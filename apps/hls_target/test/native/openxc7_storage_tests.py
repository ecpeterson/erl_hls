"""Check erased slice controls and ordered synthesis input qualification independently of CAD tools."""

import tempfile
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "priv/tools"))
from export_openxc7 import check_source_reads
from openxc7_storage import fdre


def local_ff() -> tuple[dict, dict, dict]:
    """Build one connected rising-edge FDRE with a slice-local CE and a routed reset."""
    source = {
        "type": "FDRE",
        "parameters": {"INIT": "x"},
        "connections": {"C": [1], "Q": [2], "D": [3], "R": [4], "CE": ["1"]},
    }
    attrs = {"X_ORIG_TYPE": "FDRE", "X_FFSYNC": "1", "NEXTPNR_BEL": "s/AFF"}
    packed = {
        "type": "SLICE_FFX",
        "attributes": attrs,
        "connections": {"CE": []},
        "parameters": {"INIT": "x"},
    }
    ports = {}
    for pin, original, kind in [
        ("CK", "C", "clock_input"),
        ("D", "D", "register_input"),
        ("Q", "Q", "register_output"),
        ("SR", "R", "register_input"),
        ("CE", "CE", "register_input"),
    ]:
        attrs["X_ORIG_PORT_" + pin] = original
        attrs["SPACETIME_PORT_" + original] = "original/" + original
        if pin != "CE":
            ports[pin] = {
                "net_origin": "original/" + original,
                "wire": pin,
                "bound": True,
                "bel_pin": pin,
                "class": kind,
                "clocks": [{"port": "CK", "edge": "rising"}],
            }
    return source, packed, {"type": "SLICE_FFX", "ports": ports}


class Qualification(unittest.TestCase):
    def test_local_control(self) -> None:
        """Only the exact original literal and uncontested packed site admit the missing CE wire."""
        source, packed, native = local_ff()
        bit = fdre(source, packed, native, {}, set())
        self.assertEqual(bit["local_controls"], {"CE": 1})
        self.assertIsNone(bit["initial"])
        self.assertIsNone(fdre(source, packed, native, {}, {("s", "CE")}))
        for mutate in (
            lambda s, p, n: s["connections"].update(CE=["0"]),
            lambda s, p, n: p["attributes"].pop("SPACETIME_PORT_CE"),
            lambda s, p, n: p["attributes"].pop("NEXTPNR_BEL"),
            lambda s, p, n: p["parameters"].update(INIT="1"),
            lambda s, p, n: n["ports"]["Q"]["clocks"][0].update(edge="falling"),
        ):
            source, packed, native = local_ff()
            mutate(source, packed, native)
            self.assertIsNone(fdre(source, packed, native, {}, set()))

    def test_staged_dependencies(self) -> None:
        """Reject missing or undeclared members while allowing Yosys technology mapping inputs."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            deps = root / "sources.d"
            deps.write_text("synth.json: input-00.sv input-01.sv library/techmap.v\n")
            files = ("input-00.sv", "input-01.sv")
            check_source_reads(root, files, root / "library")
            for reads in ("input-00.sv", "input-00.sv input-01.sv support.vh"):
                deps.write_text("synth.json: " + reads + "\n")
                with self.assertRaises(ValueError):
                    check_source_reads(root, files, root / "library")


if __name__ == "__main__":
    unittest.main()
