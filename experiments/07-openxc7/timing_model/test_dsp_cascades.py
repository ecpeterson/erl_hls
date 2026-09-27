#!/usr/bin/env python3
"""Check that cascade timing fixtures preserve their intended pipeline behavior."""
from itertools import product
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from dsp_cascades import source


class CascadeFixtures(unittest.TestCase):
    """Exercise forwarded full-width buses and signed products in every fixture mode."""

    def test_invalid_mode(self) -> None:
        """Reject modes whose cascade selection or register latency is undefined here."""
        for args in [('unknown', 'DIRECT', 0, 0), ('DIRECT', 'DIRECT', 1, 0)]:
            with self.assertRaises(ValueError):
                source(*args)

    @unittest.skipUnless(shutil.which('iverilog') and os.environ.get('XILINX_CELLS_SIM'),
                         'Icarus and XILINX_CELLS_SIM are required')
    def test_products_and_forwarded_buses(self) -> None:
        """Match 256 input transitions against independent bus and signed-multiply rules."""
        modules, instances, checks = [], [], []
        modes = product(('DIRECT', 'CASCADE'), ('DIRECT', 'CASCADE'),
                        ((0, 0), (1, 1), (2, 1), (2, 2)))
        for i, (a, b, (registers, cascade)) in enumerate(modes):
            text = source(a, b, registers, cascade)
            for name in ('operation', 'cascade_stage'):
                text = re.sub(r'\b' + name + r'\b', name + str(i), text)
            modules.append(text)
            aa = 'a' if a == 'DIRECT' else 'acin'
            bb = 'b' if b == 'DIRECT' else 'bcin'
            product_a = ('prior_' if registers == 2 else '') + aa
            product_b = ('prior_' if registers == 2 else '') + bb
            cascade_a = ('prior_' if cascade == 2 else '') + aa
            cascade_b = ('prior_' if cascade == 2 else '') + bb
            instances.append(f'''wire [95:0] out{i};
operation{i} instance{i}(clock, a, acin, b, bcin, out{i});
wire signed [47:0] product{i} = $signed({product_a}[24:0]) * $signed({product_b});
wire [95:0] expected{i} = {{{cascade_a}, {cascade_b}, product{i}}};''')
            checks.append(f'if (out{i} !== expected{i}) $fatal(1, "mode {i}, step %0d: %h != %h", step, out{i}, expected{i});')
        bench = '''module tb;
reg clock=0;
always #5 clock=~clock;
reg [29:0] a=0, acin=0, prior_a=0, prior_acin=0;
reg [17:0] b=0, bcin=0, prior_b=0, prior_bcin=0;
integer step, seed=1234567;
''' + '\n'.join(instances) + '''
initial begin
  for (step=0; step<256; step=step+1) begin
    @(negedge clock);
    prior_a=a; prior_acin=acin; prior_b=b; prior_bcin=bcin;
    a=$random(seed); acin=$random(seed); b=$random(seed); bcin=$random(seed);
    @(posedge clock); #1;
    if (step>3) begin
''' + '\n'.join(checks) + '''
    end
  end
  $display("PASS: sixteen cascade modes"); $finish;
end
endmodule
'''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'test.v').write_text('\n'.join(modules) + '\n' + bench)
            subprocess.run(['iverilog', '-g2012', '-s', 'tb', '-o', 'test.vvp',
                            os.environ['XILINX_CELLS_SIM'], 'test.v'], cwd=root,
                           capture_output=True, check=True, timeout=60)
            result = subprocess.run(['vvp', 'test.vvp'], cwd=root, capture_output=True,
                                    text=True, check=True, timeout=60)
            self.assertIn('PASS: sixteen cascade modes', result.stdout)


if __name__ == '__main__':
    unittest.main()
