#!/usr/bin/env python3
"""Fail closed when the component linker sees changed wiring or unsupported generated syntax."""
import phi_tool_paths  # Resolve shared tooling for this application.
import argparse
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from phi_mesh_components import compile_component, modules, namespace, ports, widen


class ComponentSyntaxTest(unittest.TestCase):
    """The build accelerator changes only named module types and link declarations."""

    def test_unsupported_policy_rejected_before_outputs(self) -> None:
        """Reject completion legalization and custom timing before any component cache is created."""
        for storage, model, error in [("lutram", "unit", "completion storage"),
                                      ("registers", "xc7_7030", "unit delay model")]:
            with self.subTest(storage=storage, model=model), tempfile.TemporaryDirectory() as directory:
                stage = Path(directory)
                policy = {"profile": {"postprocess": {"completion_storage": storage},
                                      "schedules": {"channel": {"delay_model": model}}}}
                args = argparse.Namespace(stage=stage, xls=stage / "xls")
                with patch("phi_mesh_components.read_profile", return_value=policy), \
                        patch("phi_mesh_components.execute") as execute:
                    with self.assertRaisesRegex(ValueError, error):
                        compile_component(args, "link", "pub proc Top {}")
                execute.assert_not_called()
                self.assertEqual(list(stage.iterdir()), [])

    def test_namespace_and_ports(self) -> None:
        """Renaming types retains data widths, port names, body expressions and instance wiring."""
        text = '''module child(
  input wire [32:0] a,
  output wire [32:0] b
);
  assign b = a;
endmodule
module parent(
  input wire [32:0] a,
  output wire [32:0] b
);
  child c (
    .a(a),
    .b(b)
  );
endmodule
'''
        renamed, library = namespace(text, 'p__')
        self.assertEqual(set(library), {'p__parent', 'p__child'})
        self.assertIn('  p__child c (', renamed)
        self.assertIn('  assign b = a;', renamed)
        fifo = text.split('module parent')[0].replace('child', 'fifo_for_depth_4_ty_bits_128_with_bypass_register_push')
        _, fifo_library = namespace(fifo, 'link_8_8__')
        self.assertIn('fifo_for_depth_4_ty_link_8_8__bits_128_with_bypass_register_push', fifo_library)
        self.assertEqual(ports(library['p__parent']), {'a': ('input', 33), 'b': ('output', 33)})
        self.assertEqual(ports(widen(library['p__parent'], 'a', 136)),
                         {'a': ('input', 136), 'b': ('output', 33)})
        with self.assertRaises(ValueError):
            widen(library['p__parent'], 'missing', 136)
        with self.assertRaises(ValueError):
            modules(text+text)
        with self.assertRaises(ValueError):
            modules('unexplained\n'+text)
        with self.assertRaises(ValueError):
            ports(library['p__parent'].replace('input wire', 'input wire signed'))


if __name__ == '__main__':
    unittest.main()
