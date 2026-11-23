"""Check routed DMA mappings and packaging support without images or native tools."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from typing import Any

from dma import debug_device_tree as debug
import packaging_commands
import prepare_ps_probe as probes
from test_sfp_probe import regenerate_reference

ROOT = Path(__file__).resolve().parent
APPLICATION = "/amba_pl/dma-mailbox@40000000"
DEBUG = "/amba_pl/dma-mailbox@40004000"


def pair_fields() -> dict[tuple[str, str], str]:
    """Describe the documented banks using asymmetric controller/clock phandles."""
    return {
        ("/axi/slcr@f8000000/clkc@100", "phandle"): "17",
        ("/axi/slcr@f8000000/clkc@100", "fclk-enable"): "1",
        ("/axi/dma-controller@f8003000", "phandle"): "2a",
        ("/axi/interrupt-controller@f8f01000", "phandle"): "39",
        ("/aliases", "hlsdma0"): APPLICATION, ("/aliases", "hlsdma1"): DEBUG,
        (APPLICATION, "compatible"): "erl-hls,dma-mailbox-v1",
        (APPLICATION, "reg"): "40000000 3000", (APPLICATION, "interrupt-parent"): "39",
        (APPLICATION, "interrupts"): "0 1d 4", (APPLICATION, "dmas"): "2a 0 2a 1",
        (APPLICATION, "dma-names"): "tx rx", (APPLICATION, "clocks"): "17 f",
        (APPLICATION, "clock-names"): "s_axi_aclk",
        (DEBUG, "compatible"): "erl-hls,dma-mailbox-v1",
        (DEBUG, "reg"): "40004000 3000", (DEBUG, "interrupt-parent"): "39",
        (DEBUG, "interrupts"): "0 1e 4", (DEBUG, "dmas"): "2a 2 2a 3",
        (DEBUG, "dma-names"): "tx rx", (DEBUG, "clocks"): "17 f",
        (DEBUG, "clock-names"): "s_axi_aclk",
    }


class PairMappingTests(unittest.TestCase):
    """Both bank identities and independent resources must match the documented boundary."""

    def check(self, fields: dict[tuple[str, str], str]) -> None:
        """Read mocked properties through both the shared application and pair validators."""
        def read(tree: Path, node: str, name: str, kind: str) -> str:
            """Model fdtget's property lookup and missing-property failure."""
            try:
                return fields[node, name]
            except KeyError as error:
                raise subprocess.CalledProcessError(1, ["fdtget", str(tree), node, name]) from error
        with patch.object(probes, "fdt", side_effect=read), patch.object(debug, "fdt", side_effect=read):
            debug.check_pair_tree(Path("unused.dtb"))

    def test_independent_pair(self) -> None:
        """Accept aliases 0/1, distinct SPI IDs, DMA channels 0/1 versus 2/3, and one clock."""
        self.check(pair_fields())

    def test_invalid_application_or_debug_binding(self) -> None:
        """Reject misplaced banks, shared resources and swapped providers or directions."""
        mutations = [
            (("/aliases", "hlsdma0"), DEBUG), (("/aliases", "hlsdma1"), APPLICATION),
            ((APPLICATION, "reg"), "40000000 1000"),
            ((APPLICATION, "interrupts"), "0 1e 4"),
            ((APPLICATION, "dmas"), "2a 2 2a 3"),
            ((APPLICATION, "clocks"), "17 e"),
            ((APPLICATION, "clock-names"), "other"),
            ((DEBUG, "compatible"), "generic-uio"),
            ((DEBUG, "reg"), "40000000 3000"),
            ((DEBUG, "interrupt-parent"), "2a"),
            ((DEBUG, "interrupts"), "0 1d 4"),
            ((DEBUG, "dmas"), "2a 0 2a 1"),
            ((DEBUG, "dmas"), "39 2 39 3"),
            ((DEBUG, "dmas"), "2a 3 2a 2"),
            ((DEBUG, "dma-names"), "rx tx"),
            ((DEBUG, "clocks"), "39 f"),
            ((DEBUG, "clock-names"), "other"),
        ]
        for key, value in mutations:
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, "mapping differs"):
                self.check({**pair_fields(), key: value})
        missing = pair_fields()
        del missing["/aliases", "hlsdma1"]
        with self.assertRaises(subprocess.CalledProcessError):
            self.check(missing)


class CommandTests(unittest.TestCase):
    """The extracted command runner preserves output, environment, and bounded failure behavior."""

    def test_append_and_time_limits(self) -> None:
        """Packaging defaults to 180 seconds; compiler calls explicitly retain 1200 seconds."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            log = stage / "commands.log"
            log.write_text("earlier\n")
            environment = {"PATH": "selected-tools"}
            for timeout, options in ((180, {}), (1200, {"timeout": 1200})):
                def completed(arguments: list[str], **kwargs: Any) -> subprocess.CompletedProcess:
                    """Capture the child contract without executing any external program."""
                    self.assertEqual(arguments, ["tool", "argument with spaces"])
                    self.assertEqual(kwargs["cwd"], stage)
                    self.assertIs(kwargs["env"], environment)
                    self.assertEqual(kwargs["stderr"], subprocess.STDOUT)
                    self.assertEqual(kwargs["timeout"], timeout)
                    kwargs["stdout"].write(f"child {timeout}\n")
                    return subprocess.CompletedProcess(arguments, 0)
                with patch.object(packaging_commands.subprocess, "run", side_effect=completed):
                    packaging_commands.execute(["tool", Path("argument with spaces")], stage, log,
                                               environment, **options)
            self.assertEqual(log.read_text(), "earlier\nchild 180\nchild 1200\n")

    def test_failure_and_timeout(self) -> None:
        """Nonzero exit names the retained log; timeout remains the original subprocess error."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            log = stage / "commands.log"
            with patch.object(packaging_commands.subprocess, "run",
                              return_value=subprocess.CompletedProcess(["tool"], 7)):
                with self.assertRaisesRegex(RuntimeError, r"tool failed \(7\); see"):
                    packaging_commands.execute(["tool"], stage, log)
            failure = subprocess.TimeoutExpired(["tool"], 180)
            with patch.object(packaging_commands.subprocess, "run", side_effect=failure):
                with self.assertRaises(subprocess.TimeoutExpired) as raised:
                    packaging_commands.execute(["tool"], stage, log)
                self.assertIs(raised.exception, failure)


class ReferencePathTests(unittest.TestCase):
    """Platform relocation preserves byte-exact vendor regeneration and its recorded source name."""

    def test_reference_input_is_staged_under_recorded_name(self) -> None:
        """GHDL receives the current VHDL bytes with the historical relative name, not a stale checkout path."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            source = stage / "current.vhd"
            source.write_bytes(b"current vendor source\n")
            expected = b"translated reference\n"

            def translated(arguments: list[str], *, cwd: Path) -> bytes:
                """Inspect the staged input at the external-tool boundary without launching GHDL."""
                self.assertEqual(cwd, stage)
                self.assertEqual(arguments, ["ghdl", "synth", "--std=08", "--out=verilog",
                    "experiments/07-openxc7/sfp/vendor/ddsrpi_slave.vhd", "-e", "ddsrpi_slave"])
                self.assertEqual((cwd / arguments[4]).read_bytes(), source.read_bytes())
                return expected

            with patch("test_sfp_probe.subprocess.check_output", side_effect=translated):
                self.assertEqual(regenerate_reference(source, stage, Path("ghdl")), expected)
            self.assertEqual(source.read_bytes(), b"current vendor source\n")


class EntrypointTests(unittest.TestCase):
    """The packager imports and explains its CLI without any tool or test-module dependency."""

    def test_partition_import_and_help_without_external_commands(self) -> None:
        """A fresh interpreter rejects test imports and subprocesses during import and --help."""
        script = r"""
import importlib.abc
from pathlib import Path
import runpy
import subprocess
import sys
sys.path.insert(0, sys.argv[1])
class RejectTests(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if any(part.startswith('test_') for part in fullname.split('.')):
            raise AssertionError('production imported test helper: ' + fullname)
sys.meta_path.insert(0, RejectTests())
def blocked(*args, **kwargs):
    raise AssertionError('entrypoint launched an external command')
subprocess.Popen = blocked
import prepare_partition_link
assert prepare_partition_link.check_pair_tree.__module__ == 'dma.debug_device_tree'
assert prepare_partition_link.execute.__module__ == 'packaging_commands'
sys.argv = [str(Path(sys.argv[1]) / 'prepare_partition_link.py'), '--help']
try:
    runpy.run_path(sys.argv[0], run_name='__main__')
except SystemExit as error:
    assert error.code == 0
else:
    raise AssertionError('--help did not exit')
"""
        completed = subprocess.run([sys.executable, "-c", script, str(ROOT)],
                                   text=True, capture_output=True, timeout=20)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("--application", completed.stdout)


if __name__ == "__main__":
    unittest.main()
