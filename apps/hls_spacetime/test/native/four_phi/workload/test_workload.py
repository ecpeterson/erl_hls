"""Regression witnesses for startup configuration, scoped nets and four-state primitive sampling."""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from init_bits import configured
from scopes import links

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from capture import check_mapping_log


class WorkloadTest(unittest.TestCase):
    """Run small witnesses independently of the archived decoder and device databases."""

    def test_effective_map(self) -> None:
        """Reject a run whose executable opened a different installation's technology map."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            library = root / "qualified/share/brams_xc6v_map.v"
            log = root / "map.log"
            log.write_text(
                "1.2. Executing Verilog-2005 frontend: " + str(library) + "\n"
            )
            check_mapping_log(log, library)
            with self.assertRaises(ValueError):
                check_mapping_log(log, root / "stock/share/brams_xc6v_map.v")

    def test_configuration(self) -> None:
        """Keep defined startup bits and reject a new class of unqualified unknowns."""
        cells = {
            "ff": {"type": "FDRE", "parameters": {"INIT": "x"}},
            "mem": {
                "type": "RAMB18E1",
                "parameters": {"INIT_01": "10xz", "WRITE_MODE_A": "READ_FIRST"},
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            s = d / "source.json"

            def write() -> None:
                """Write the current set of test primitives as a fresh input."""
                s.write_text(
                    json.dumps({"modules": {"phi_timing_harness": {"cells": cells}}})
                )

            write()
            configured(s, d / "view", d / "receipt")
            found = json.loads((d / "view").read_text())["modules"][
                "phi_timing_harness"
            ]["cells"]
            self.assertEqual(
                found["mem"]["parameters"],
                {"INIT_01": "1000", "WRITE_MODE_A": "READ_FIRST"},
            )
            self.assertEqual(found["ff"]["parameters"]["INIT"], "0")
            self.assertEqual(
                json.loads((d / "receipt").read_text())["RAMB18E1.INIT_nn"], 2
            )
            cells["mem"]["parameters"]["INIT_A"] = "1x"
            write()
            with self.assertRaisesRegex(ValueError, "nonzero BRAM"):
                configured(s, d / "bad", d / "receipt")
            del cells["mem"]["parameters"]["INIT_A"]
            cells["ff"]["type"] = "LUT1"
            write()
            with self.assertRaisesRegex(ValueError, "unqualified"):
                configured(s, d / "bad", d / "receipt")

    def test_scopes(self) -> None:
        """Use exact hierarchy or named output bits, leaving shared and unnamed nets unassigned."""
        units = [{"path": "decoder.a"}, {"path": "decoder.b"}]
        cell = lambda bit: {
            "connections": {"O": [bit]},
            "port_directions": {"O": "output"},
        }
        module = {
            "netnames": {"decoder.a.q": {"bits": [4, 5]}, "decoder.b.q": {"bits": [5]}},
            "cells": {
                "direct": cell(4),
                "shared": cell(5),
                "unnamed": cell(6),
                r"$flatten\decoder.\a.$mul": cell(6),
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "native").mkdir()
            (root / "native/synth.json").write_text(
                json.dumps({"modules": {"phi_timing_harness": module}})
            )
            self.assertEqual(
                links("openxc7", root, units, []),
                {"direct": 0, r"$flatten\decoder.\a.$mul": 0},
            )
            self.assertEqual(
                links(
                    "vivado",
                    root,
                    units,
                    [("decoder/b/gate", "LUT"), ("decoder/bb/gate", "LUT")],
                ),
                {"decoder/b/gate": 1},
            )

    @unittest.skipUnless(
        all(shutil.which(t) for t in ("iverilog", "iverilog-vpi", "vvp")),
        "Icarus VPI toolchain",
    )
    def test_transition_masks(self) -> None:
        """Check a known toggle alongside an unknown bit, a stable edge and a 33-bit output."""
        bench = """`timescale 1ns/1ps
module FDRE(output Q); assign Q=1'b1; endmodule
module primitive_model(output reg [32:0] q);
initial begin q=33'b0; #14; q[32]=1; q[2]=1'bx; #15; q[2]=1; end
endmodule
module holder; wire [32:0] q; wire qb; primitive_model m(q); FDRE z(qb); endmodule
module functional_tb; reg clock=0; holder dut(); initial begin repeat(5) begin #5;clock=1;#5;clock=0;end #1;$finish;end endmodule
"""
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            (d / "cells.v").write_text(bench)
            (d / "primitive-types.txt").write_text("FDRE\nprimitive_model\n")
            for cmd in (
                ["iverilog-vpi", HERE / "transitions.cpp"],
                ["iverilog", "-o", "design", "cells.v"],
                ["vvp", "-M.", "-mtransitions", "design"],
            ):
                subprocess.run(cmd, cwd=d, check=True, capture_output=True)
            self.assertEqual(
                (d / "cells.tsv").read_text(), "m\tprimitive_model\nz\tFDRE\n"
            )
            self.assertEqual((d / "initial-q.txt").read_text(), "-1")
            self.assertEqual(
                (d / "changes.bin").read_bytes(), bytes([0, 3, 1, 1, 0, 1, 0, 0, 0, 0])
            )


if __name__ == "__main__":
    unittest.main()
