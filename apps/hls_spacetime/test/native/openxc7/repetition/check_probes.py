"""Run bounded XC7 witnesses for reconvergent STA, carry timing and the four-Phi BRAM mode."""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[5]


def capture(name: str, rtl: Path, args: argparse.Namespace) -> Path:
    """Route one small circuit with the two observed pins and a 100 MHz setup request."""
    out = args.output / name
    subprocess.run(
        [
            sys.executable,
            ROOT / "apps/hls_target/priv/tools/export_openxc7.py",
            "--rtl",
            rtl,
            "--xdc",
            ROOT / "platforms/xc7/xc7z030sbg485.xdc",
            "--apio-home",
            args.apio,
            "--chipdb",
            args.chipdb,
            "--timing-tools",
            args.tools,
            "--freq",
            "100",
            "--sta",
            "--route-sta",
            "--allow-timing-fail",
            "--source-id",
            hashlib.sha256(rtl.read_bytes()).hexdigest(),
            "--observation-id",
            "g44-primitive",
            out,
        ],
        check=True,
    )
    return out


def check_carry(out: Path, db: Path) -> dict:
    """Check all connected DI pairs against the matching Project X-Ray SDF variant envelope."""
    t = json.loads((out / "timing.json").read_bytes())
    cell = t["cells"]["chain"]
    packed = json.loads((out / "routed.json").read_bytes())["modules"]["top"]["cells"][
        "chain"
    ]
    loc = json.loads((out / "locations.json").read_bytes())[
        packed["attributes"]["NEXTPNR_BEL"].split("/")[0]
    ]
    site_type = json.loads((db.parent / "xc7z030/tilegrid.json").read_bytes())[
        loc["tile"]
    ]["sites"][loc["site"]].lower()
    # Both physical SLICEL and SLICEM input tables are checked; the placement determines the applicable site.
    tables = {}
    for site in ("slicel", "slicem"):
        text = (db / f"{site}.sdf").read_text()
        table = defaultdict(list)
        for variant, body in re.findall(
            r'\(CELLTYPE "(CARRY4_[^"]+)"\)(.*?)(?=\(CELLTYPE|\Z)', text, re.S
        ):
            for pin, to, values in re.findall(
                r"\(IOPATH (DI[0-3]) (\w+) ([^\n]+)", body
            ):
                table[pin, to].extend(
                    round(float(ns) * 1000)
                    for ns in re.findall(r"::([\d.]+)\)", values)
                )
        tables[site] = {k: max(v) for k, v in table.items()}
    rows = [
        a
        for a in cell["arcs"]
        if a["from"].startswith("DI") and a["delay_ps"] is not None
    ]
    assert rows and all(
        abs(tables[site_type].get((a["from"], a["to"]), -1000) - a["delay_ps"]) <= 1
        for a in rows
    )
    # The same-output XOR uses the incoming carry, so DI[i] cannot affect O[i].
    assert not any(a["to"] == "O" + a["from"][-1] for a in rows)
    return {"checked_di_arcs": len(rows), "site": loc}


def check_sta(out: Path) -> dict:
    """Enumerate the short fixture's register-launched paths and compare the native maximizing chain."""
    t = json.loads((out / "timing.json").read_bytes())
    report = json.loads((out / "sta.json").read_bytes())["paths"]
    assert len(report) == 1
    path = report[0]
    incoming = defaultdict(list)
    for cell, c in t["cells"].items():
        for arc in c["arcs"]:
            if arc["delay_ps"] is not None:
                incoming[cell, arc["to"]].append(((cell, arc["from"]), arc["delay_ps"]))
    for row in t["sinks"]:
        if row["delay_ps"] is not None and row["source"] is not None:
            incoming[row["sink"], row["input"]].append(
                ((row["source"], row["output"]), row["delay_ps"])
            )

    def paths(node: tuple, seen: tuple) -> list[tuple]:
        """Enumerate only exact connected register launches; feedback stops at Q."""
        cell, pin = node
        if node in seen:
            raise ValueError("unexpected combinational cycle")
        p = t["cells"][cell]["ports"][pin]
        if p["class"] == "register_output":
            return [(p["clocks"][0]["clock_to_q_ps"], (node,))]
        return [
            (d + cost, chain + (node,))
            for source, cost in incoming[node]
            for d, chain in paths(source, seen + (node,))
        ]

    candidates = []
    for cell, row in t["cells"].items():
        for pin, p in row["ports"].items():
            if p["class"] == "register_input":
                candidates.extend(
                    (v + p["clocks"][0]["setup_ps"], chain)
                    for v, chain in paths((cell, pin), ())
                )
    points = path["points"]
    assert len({d for d, _ in candidates}) >= 2
    assert (
        max(d for d, _ in candidates)
        == path["path_delay_ps"]
        == points[-1]["arrival_ps"]
    )
    chain = tuple((p["cell"], p["port"]) for p in points[:-1])
    assert (path["path_delay_ps"], chain) in candidates
    printed = (
        (out / "nextpnr.log")
        .read_text()
        .rsplit("Critical path report for clock ", 1)[-1]
    )
    assert printed.startswith(f"'{path['launch_clock']}' (posedge -> posedge):")
    pins = re.findall(
        r"^Info:\s+(?:[\d.]+\s+[\d.]+\s+Source|Sink) (\S+)$", printed, re.M
    )
    assert pins == [f"{cell}.{port}" for cell, port in chain]
    totals = re.findall(
        r"^Info:\s+([\d.]+)\s+([\d.]+)\s+(?:Source|Net|Setup) ", printed, re.M
    )
    assert len(totals) == len(points)
    assert all(
        abs(float(ns) * 1000 - p[key]) <= 50.001
        for p, values in zip(points, totals)
        for key, ns in zip(("delay_ps", "arrival_ps"), values)
    )
    assert {"short_lut", "long_lut"} <= {
        c for _, candidate in candidates for c, p in candidate
    }
    assert all(
        p["arrival_ps"] == sum(x["delay_ps"] for x in points[: i + 1])
        for i, p in enumerate(points)
    )
    assert (
        path["required_ps"] == 10000
        and path["slack_ps"] == 10000 - path["path_delay_ps"]
    )
    return {
        "eligible_chains": len(candidates),
        "distinct_delays": len(set(d for d, _ in candidates)),
        "delay_ps": path["path_delay_ps"],
        "slack_ps": path["slack_ps"],
        "pins": chain,
    }


def probes(args: argparse.Namespace) -> dict:
    """Exercise the exact SDP72 read-first clock, both read latencies and an unsupported write mode."""
    args.output.mkdir()
    run = capture("reconvergent", HERE / "reconvergent.v", args)
    vendor = json.loads(args.calibration.read_bytes())
    assert vendor["part"] == "xc7z030sbg485-1"
    result = {"sta": check_sta(run), "carry": check_carry(run, args.db), "bram": {}}
    result["sta"]["branches"] = json.loads(
        subprocess.check_output(["node", HERE / "probe_route.mjs", run], text=True)
    )
    for name, reg, mode in [
        ("bram", 0, "READ_FIRST"),
        ("bramreg", 1, "READ_FIRST"),
        ("bramneg", 0, "WRITE_FIRST"),
    ]:
        rtl = args.output / (name + ".v")
        rtl.write_text(
            (HERE / "bram_launch.v")
            .read_text()
            .replace("OUTPUT_REG=0", f"OUTPUT_REG={reg}")
            .replace('MODE="READ_FIRST"', f'MODE="{mode}"')
        )
        out = capture(name, rtl, args)
        timing = json.loads((out / "timing.json").read_bytes())
        ports = timing["cells"]["memory"]["ports"]
        checks = Counter(p["class"] for p in ports.values())
        sta = json.loads((out / "sta.json").read_bytes())["paths"][0]
        if mode == "READ_FIRST":
            q = [p for p in ports.values() if p["class"] == "register_output"]
            reference = next(
                r
                for r in vendor["primitive_arcs"]
                if r["probe"] == f"ram_0_RAMB36E1_reg{reg}"
            )
            model = reference["mode"]
            assert (
                model["RAM_MODE"] == "SDP"
                and model["WRITE_MODE_A"] == model["WRITE_MODE_B"] == mode
            )
            assert int(model["READ_WIDTH_A"], 2) == int(model["WRITE_WIDTH_B"], 2) == 72
            assert reference["worst_ps"]["propagation"] == (748 if reg else 2080)
            assert len(q) == 32 and all(
                len(p["clocks"]) == 1
                and p["clocks"][0]["clock_to_q_ps"] == (748 if reg else 2080)
                and p["clocks"][0]["edge"] == "rising"
                for p in q
            )
            assert sta["points"][0]["cell"] == "memory" and checks["register_input"] > 0
        else:
            assert set(checks) == {"ignore"} and sta["points"][0]["cell"] != "memory"
        result["bram"][name] = {
            "ports": checks,
            "launch": sta["points"][0],
            "setup_path_ps": sta["path_delay_ps"],
        }
    result["calibration_sha256"] = hashlib.sha256(
        args.calibration.read_bytes()
    ).hexdigest()
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("apio", "chipdb", "tools", "db", "calibration", "output"):
        parser.add_argument(key, type=Path)
    args = parser.parse_args()
    (args.output / "measurements.json").write_text(
        json.dumps(probes(args), indent=2) + "\n"
    )
