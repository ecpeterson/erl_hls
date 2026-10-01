#!/usr/bin/env python3
"""Fail closed when the component linker sees changed wiring or unsupported generated syntax."""
import unittest

from phi_mesh_components import modules, namespace, ports, widen


class ComponentSyntaxTest(unittest.TestCase):
    """The build accelerator changes only named module types and link declarations."""

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
