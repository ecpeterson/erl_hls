#!/usr/bin/env python3
"""Check cascade timing dependencies against the primitive behavior and C++ filter."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class DspCascadeTest(unittest.TestCase):
    """Reject cross-bus/cross-bit arcs while preserving every selected cascade bit."""

    @unittest.skipUnless(shutil.which('c++'), 'C++ compiler is not installed')
    def test_dependency_filter(self) -> None:
        """Exhaust both cascade buses and all direct/cascade parameter combinations."""
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'check'
            subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                            str(HERE / 'test_dsp_cascade.cc'), '-o', str(executable)],
                           check=True, capture_output=True, timeout=60)
            subprocess.run([str(executable)], check=True, capture_output=True, timeout=10)

    @unittest.skipUnless(os.environ.get('YOSYS') or shutil.which('yosys'), 'Yosys is not installed')
    def test_symbolic_primitive_cascades(self) -> None:
        """Prove the identities with arbitrary data/control inputs in Yosys's DSP model."""
        yosys = os.environ.get('YOSYS') or shutil.which('yosys')
        script = ('read_verilog -sv +/xilinx/cells_sim.v "' + str(HERE / 'dsp_cascade_miter.v') + '"\n'
                  'hierarchy -check -top dsp_cascade_miter\nproc\nflatten\nopt\n'
                  'sat -verify -prove bad 0 -show-inputs\n')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'proof.ys'
            path.write_text(script)
            result = subprocess.run([yosys, '-Q', '-T', '-s', str(path)],
                                    check=True, capture_output=True, text=True, timeout=180)
            self.assertIn('SAT proof finished - no model found: SUCCESS!', result.stdout)


if __name__ == '__main__':
    unittest.main()
