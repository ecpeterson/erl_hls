"""Publish two normal Spacetime recordings of the same checked four-Phi transaction."""

import argparse
import hashlib
import json
import mmap
import os
from pathlib import Path
import subprocess
import sys

import openxc7
import vivado
from capture import (
    ARCHIVE,
    HERE,
    INPUT,
    ROOT,
    RTL,
    SHARED_FILES,
    VENDOR,
    XDC,
    digest,
    native_files,
)
from replay import SELECTED_BIT, replay, require

sys.path.insert(0, str(ROOT / "apps/hls_target/priv/tools"))
from openxc7_chipdb import ChipGrid

MEMORY = "scheduler_2_state"
MULTIPLY = "umul_164656/DSP partial products"
SCRIPTS = ROOT / "apps/hls_spacetime/scripts"


def identity(data: dict) -> str:
    """Hash canonical JSON for a derived identity binding multiple evidence files."""
    return hashlib.sha256(
        json.dumps(data, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def logical(record: dict, build: dict) -> dict:
    """Project the selected transaction and accepted multiply without inferring a causal DSP edge."""
    t = record["transaction"]
    w, r, q, address = (
        t[k] for k in ("writeCycle", "readCycle", "resultCycle", "address")
    )
    state = {"resource": MEMORY, "address": address}
    word = dict(incarnation="run", storage=state)
    versions = [
        dict(
            word,
            id="prior",
            producer="root",
            origin="carry_in",
            evidence="Word before the selected write.",
        ),
        dict(
            word,
            id="written",
            producer="write",
            origin="event",
            evidence="Enabled full-row replacement.",
        ),
        dict(
            id="returned",
            incarnation="run",
            storage=None,
            producer="response",
            origin="event",
            evidence="Pre-edge read bus equals the selected word at the next edge.",
        ),
    ]
    access = dict(state, port="r", version="written")
    events = []
    for eid, cycle, operation, inputs, outputs, details in [
        (
            "write",
            w,
            "Write scheduler state",
            [],
            ["written"],
            f"Write enabled for all 540 bits. Value 0x{t['value']}.",
        ),
        (
            "read",
            r,
            "Read scheduler state",
            ["written"],
            [],
            f"Read enabled at address {address}.",
        ),
        (
            "response",
            q,
            "Return scheduler state",
            ["written"],
            ["returned"],
            f"State bit {SELECTED_BIT} changed. Both the registered read bus and the executor request state contain 0x{t['value']}.",
        ),
        (
            "multiply",
            q,
            "Accept executor request",
            [],
            [],
            f"On valid and ready, rounded__3 = 0x{t['operand']}. Multiplication by {record['factor']} gives "
            f"0x{t['product']}. The enabled result register captured 0x{t['capturedResult']} after slicing and sign selection.",
        ),
    ]:
        events.append(
            dict(
                id=eid,
                cycle=cycle,
                observer="ports",
                sequence=len(events),
                actor=("Phi executor" if eid == "multiply" else MEMORY),
                task="four-Phi",
                activation=("read" if eid == "response" else eid),
                incarnation="run",
                operation=operation,
                inputs=inputs,
                outputs=outputs,
                evidence=details,
            )
        )
    events[0]["access"] = dict(
        state,
        kind="write",
        port="w",
        before="prior",
        after_version="written",
        mask=hex((1 << 540) - 1),
    )
    events[1]["access"] = dict(access, kind="read_request")
    events[2]["access"] = dict(access, kind="read_result", request="read")
    events[3]["resources"] = [MULTIPLY]
    bounds = dict(first_cycle=w, end_cycle=q + 1)
    return dict(
        format="spacetime",
        schema=1,
        unit="cycle",
        evidence="simulation_witness",
        build=build,
        capture=dict(
            bounds,
            device="xc7z030sbg485-1",
            clock="workload",
            complete=True,
            evidence="Four-state RTL replay. Selected transaction and executor request only.",
            incarnations=[dict(bounds, id="run")],
            observers=[
                dict(
                    id="ports",
                    first_sequence=0,
                    next_sequence=4,
                    gaps=[],
                    scope="One selected RAM write, request, result and executor acceptance.",
                )
            ],
        ),
        events=events,
        versions=versions,
        relations=[],
        activity=[],
        resources=[
            dict(
                id=MULTIPLY,
                kind="logic",
                evidence="Identified DSP partial products of the observed 38-bit multiplication.",
            ),
            dict(
                id=MEMORY,
                kind="bram",
                width=540,
                depth=2,
                ports={"r": "read", "w": "write"},
                read_latency=1,
                collision="read_first",
                reset="retained",
                evidence="Two whole scheduler-state rows with one full-word write enable.",
            ),
        ],
    )


def publication(
    record: dict, physical: dict, grid: ChipGrid, build: dict, checkpoint: str
) -> tuple[dict, dict]:
    """Bind each measured path to the common grid and one selected output lane, preserving unknown lanes."""
    steps = physical["path"]
    cells = {}
    nets = {}
    for s in [*physical["productDsps"], *steps]:
        name = s["cell"]
        cells[name] = dict(
            id=name,
            kind=s["kind"],
            bel=s.get("bel"),
            **grid.location(s["site"]),
            properties={k: str(v) for k, v in s.get("stages", {}).items()},
        )
    for left, right in zip(steps, steps[1:]):
        net = nets.setdefault(right["net"], dict(id=right["net"], pins=[]))
        for step, field, direction in [
            (left, "output", "output"),
            (right, "input", "input"),
        ]:
            pin = dict(cell=step["cell"], pin=step[field], direction=direction)
            if pin not in net["pins"]:
                net["pins"].append(pin)
    ram = steps[0]
    bits = [
        dict(bit=i, status="unknown", evidence="Outside selected pin scope.")
        for i in range(540)
    ]
    bits[SELECTED_BIT] = dict(
        bit=SELECTED_BIT,
        status="supported",
        cell=ram["cell"],
        pin=ram["output"],
        evidence="Logical read bus and primitive output pin agree in this implementation.",
    )
    bundle = logical(record, build)
    bundle["physical"] = dict(
        build=build,
        checkpoint=checkpoint,
        evidence="native_measurement",
        coordinate_unit="tile_grid",
        cells=list(cells.values()),
        nets=list(nets.values()),
        generated=[
            dict(id="ram", source="decoder.scheduler_2_state.rd_data[84]"),
            dict(
                id="mul", source="Phi executor umul_164656 = rounded__3 * 0x2AAAAAAAAB"
            ),
        ],
        bindings=[
            dict(
                resource=MULTIPLY,
                disposition="distributed",
                generated=["mul"],
                cells=[s["cell"] for s in physical["productDsps"]],
                evidence="Placed partial products of the accepted multiply. AREG, BREG, MREG and PREG are bypassed.",
            ),
            dict(
                resource=MEMORY,
                generated=["ram"],
                cells=[ram["cell"]],
                disposition="ambiguous",
                bits=bits,
                evidence=f"Bit {SELECTED_BIT} maps to {ram['site']}/{ram['output']}. "
                f"{physical['ramMode']}. Other bits are outside this selection.",
            ),
        ],
    )
    targets = [s for s in steps if "stages" in s]
    stages = ". ".join(
        f"{s['site']} "
        + ", ".join(f"{k}={v}" for k, v in s["stages"].items())
        + f", clock {s['clock']}"
        for s in targets
    )
    desc = (
        f"{physical['ramMode']}. {stages}. The selected multiply has "
        f"{len(physical['productDsps'])} identified DSP partial products with AREG, BREG, MREG and PREG bypassed. "
    )

    if "slackNs" in physical:
        desc += f"The full setup path has {physical['fullDataDelayNs']} ns data delay and {physical['slackNs']} ns slack. "
    else:
        desc += "Delay along this selected path is unmeasured. "
    desc += "Execution and placement are joined by RTL identity. Path sensitization is unmeasured."
    ids = [e["id"] for e in bundle["events"]]
    examples = [
        dict(id=i, title=t, event=e, events=ids)
        for i, t, e in (
            ("memory", "Scheduler state write and readback", "response"),
            ("dsp", "Accepted multiply and DSP stages", "multiply"),
        )
    ]
    metadata = dict(
        title=f"Four-Phi scheduler · {physical['backend']}",
        examples=examples,
        scope=[
            "Four-Phi simulation witness on matched 20 ns constraints, compile-only pins Y14 and V13.",
            f"The physical selection follows scheduler state bit {SELECTED_BIT} into multiplication.",
        ],
        hardwarePath=dict(
            basis=physical["basis"],
            checkpoint=checkpoint,
            events=ids,
            description=desc,
            steps=[
                {k: s[k] for k in ("cell", "input", "output", "net") if k in s}
                for s in steps
            ],
        ),
    )
    return bundle, metadata


def publish(run: Path, chipdb: Path, output: Path) -> None:
    """Verify the receipt before deriving the recordings and build the ordinary served viewer index."""
    receipt = json.loads((run / "capture.json").read_text())
    require(
        receipt["archive"] == ARCHIVE
        and receipt["tools"]["chipdb"] == digest(chipdb)
        and receipt["constraints"] == digest(XDC)
        and receipt["periodNs"] == 20
        and receipt["seed"] == 1
        and receipt["pins"] == {"clock": "Y14", "activity": "V13"}
        and receipt["testbench"] == digest(HERE / "transaction_tb.sv"),
        "capture provenance",
    )
    files = receipt["files"]
    mode = receipt["nativeStage"]
    native = native_files(mode)
    require(
        set(files) == {str(p) for p in SHARED_FILES + native},
        "capture inventory mismatch",
    )
    for name, sha in files.items():
        require(digest(run / name) == sha, f"capture input changed: {name}")
    source = identity({n: files[str(INPUT / n)] for n in RTL})
    observation = identity(
        {n: files[n] for n in ("replay.vvp", "trace.txt")}
        | {
            "monitor": receipt["testbench"],
            "iverilog": receipt["tools"]["iverilog"],
            "vvp": receipt["tools"]["vvp"],
        }
    )
    record = replay(run / "trace.txt")
    output.mkdir()
    (output / "selection.json").write_text(json.dumps(record, indent=2) + "\n")
    entries = []
    env = dict(os.environ, ERL_LIBS=str(ROOT / "_build/spacetime/lib"))
    with (
        chipdb.open("rb") as stream,
        mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as db,
    ):
        grid = ChipGrid(db)
        require(
            grid.part == receipt["part"] == "xc7z030sbg485-1", "chipdb part mismatch"
        )
        for backend, physical, path in (
            (
                "vivado",
                vivado.placed_path(run / VENDOR, run / INPUT / "phi_decoder_profile.v"),
                VENDOR / "routed.dcp",
            ),
            (
                "openxc7",
                openxc7.placed_path(run / "native", mode),
                native[0],
            ),
        ):
            checkpoint = files[str(path)]
            build = dict(
                source=source,
                rtl=source,
                observation=observation,
                implementation=checkpoint,
            )
            bundle, metadata = publication(record, physical, grid, build, checkpoint)
            prefix = output / backend
            prefix.mkdir()
            for name, data in [
                ("raw", bundle),
                ("metadata", metadata),
                ("path", physical),
            ]:
                (prefix / f"{name}.json").write_text(json.dumps(data) + "\n")
            subprocess.run(
                [
                    "escript",
                    HERE / "validate.escript",
                    prefix / "raw.json",
                    prefix / "bundle",
                ],
                check=True,
                env=env,
            )
            view = prefix / "viewer"
            subprocess.run(
                [
                    "node",
                    SCRIPTS / "prepare-view.mjs",
                    "--bundle",
                    prefix / "bundle/bundle.json",
                    "--metadata",
                    prefix / "metadata.json",
                    "--output",
                    view,
                ],
                check=True,
            )
            (entry,) = json.loads((view / "index.json").read_text())["examples"]
            # Publish both selectable captures in the same portable gallery.
            dest = output / f"{backend}.json"
            dest.write_bytes((view / entry["file"]).read_bytes())
            entries.append(dict(entry, file=dest.name))
    require(sum(e["bytes"] for e in entries) <= 16 << 20, "publication byte limit")
    (output / "index.json").write_text(
        json.dumps(dict(format="spacetime-view-index", schema=1, examples=entries))
        + "\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for item in ("run", "chipdb", "output"):
        parser.add_argument(item, type=Path)
    args = parser.parse_args()
    publish(args.run, args.chipdb, args.output)
