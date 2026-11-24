"""Compare the small observer fixture with nextpnr's independent SDF writer and packing records."""
import copy
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "apps/hls_target/priv/tools"))
from openxc7_storage import qualify_words


def check(capture: Path, reference: Path) -> None:
    """Require an identical route and timing capture, observed fracturing, and both negative cases."""
    def read(name: str) -> dict:
        return json.loads((capture / name).read_bytes())

    for name in ("routed.json", "timing.json"):
        assert (capture / name).read_bytes() == (reference / name).read_bytes(), name
    timing = read("timing.json")
    packed = read("routed.json")["modules"]["top"]["cells"]
    synth = read("synth.json")["modules"]["top"]
    words = read("storage.json")
    assert [(b["cell"], b["initial"]) for b in words[0]["bits"]] == [("low", 0), ("high", 1)]
    halves = {c["attributes"]["SPACETIME_OUTPUT"]: (n, c) for n, c in packed.items()
              if c["attributes"].get("SPACETIME_CELL") == "functions"}
    assert set(halves) == {"O5", "O6"}
    bel5, bel6 = [halves[o][1]["attributes"]["NEXTPNR_BEL"] for o in ("O5", "O6")]
    assert bel5.endswith("5LUT") and bel6.endswith("6LUT") and bel5[:-4] == bel6[:-4]
    permuted = False
    for out, (name, cell) in halves.items():
        ports = timing["cells"][name]["ports"]
        assert ports[out]["net_origin"] == cell["attributes"]["SPACETIME_PORT_" + out]
        for pin, row in ports.items():
            if row["net_origin"] in ("q[0]", "q[1]"):
                original = cell["attributes"]["X_ORIG_PORT_" + pin]
                assert cell["attributes"]["SPACETIME_PORT_" + original] == row["net_origin"]
                permuted |= int(pin[1:]) != int(original[1:]) + 1
    assert permuted
    # This fixture has scalar ports. nextpnr's SDF writer formats integer picoseconds.
    interconnect, logic = {}, {}
    instance = None
    for line in (reference / "oracle.sdf").read_text().replace("\\", "").splitlines():
        if match := re.search(r"\(INSTANCE ([^ )]+)\)", line):
            instance = match[1]
        if match := re.search(r"\((INTERCONNECT|IOPATH) ([^ ]+) ([^ ]+) \((\d+):(\d+):(\d+)\)", line):
            kind, start, end, _, _, ps = match.groups()
            if kind == "INTERCONNECT":
                interconnect[start, end] = int(ps)
            else:
                logic[instance, start, end] = int(ps)
    count = 0
    for row in timing["sinks"]:
        if row["delay_ps"] is not None:
            pair = (row["source"] + "/" + row["output"], row["sink"] + "/" + row["input"])
            # The SDF writer converts through floating-point ns before formatting ps.
            assert abs(row["delay_ps"] - interconnect[pair]) <= 1, pair
            count += 1
    for name, cell in timing["cells"].items():
        for arc in cell["arcs"]:
            if arc["delay_ps"] is not None:
                assert abs(arc["delay_ps"] - logic[name, arc["from"], arc["to"]]) <= 1
                count += 1
    damaged = copy.deepcopy(packed)
    del damaged["high"]["attributes"]["SPACETIME_PORT_D"]
    bits = qualify_words(["q=q"], synth, damaged, timing, 4096)[0]["bits"]
    assert [bit["status"] for bit in bits] == ["supported", "unknown"] and "cell" not in bits[1]
    print(f"Compared {count} modeled delay queries; fractured BELs {bel5} and {bel6}")


if __name__ == "__main__":
    check(Path(sys.argv[1]), Path(sys.argv[2]))
