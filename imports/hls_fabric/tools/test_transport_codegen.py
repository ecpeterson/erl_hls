"""Reject unsupported adapter IR and accidental changes outside its module boundary."""
import unittest

from transport_codegen import adapter_procs, replace_module


class AdapterCodegenTest(unittest.TestCase):
    """Specialization changes schedules, never interfaces or neighboring modules."""

    def test_self_contained_proc(self) -> None:
        """Only stateless adapters made from the expected channel primitives qualify."""
        proc = '''proc __hls_packed_link__Wire_0_next<_wire_queue: bits[8] in>() {
  tok: token = after_all(id=1)
}'''
        self.assertEqual(adapter_procs(proc), [('__hls_packed_link__Wire_0_next', 'Wire', proc)])
        for bad in [proc.replace('>() {', '>(state: bits[1], init={0}) {'),
                    proc.replace('after_all', 'invoke')]:
            with self.assertRaises(ValueError):
                adapter_procs(bad)
        with self.assertRaisesRegex(ValueError, 'lacks'):
            adapter_procs(proc+'\nproc __hls_packed_link__Bridge_0() {}')

    def test_reduction_frame_adapter(self) -> None:
        """The typed port extractor is combinational and obeys the same statelessness check."""
        proc = """proc __graph__phi_ParallelActorOutboxDrainB2S0_ReductionFrame_0_next<_fragment: bits[136] in>() {
  tok: token = after_all(id=1)
}"""
        self.assertEqual(adapter_procs(proc)[0][1], 'Wire')
        with self.assertRaisesRegex(ValueError, 'state'):
            adapter_procs(proc.replace('>() {', '>(state: bits[1], init={0}) {'))

    def test_aggregate_mux_cursor(self) -> None:
        """Only the reset-zero polling cursor may survive queue-mux extraction."""
        proc = """proc __graph__actor_ReductionMux_0__2_next<_incoming__0: bits[8] in>(__state: bits[1], init={0}) {
  cursor: bits[1] = state_read(state_element=__state, id=1)
}"""
        self.assertEqual(adapter_procs(proc)[0][1], 'ReductionMux')
        for bad in [proc.replace('init={0}', 'init={1}'), proc.replace('state_read', 'invoke'),
                    proc.replace('__state: bits[1]', '__state: (bits[1], bits[8])')]:
            with self.assertRaises(ValueError): adapter_procs(bad)

    def test_module_boundary(self) -> None:
        """Only the selected module body may change, even when neighbors share text."""
        old = 'module adapter(\n  input wire a\n);\n  wire x;\nendmodule'
        new = old.replace('wire x;', 'wire y;')
        rtl = '// retained\n'+old+'\n'+old.replace('adapter(', 'neighbor(')+'\n'
        self.assertEqual(replace_module(rtl, 'adapter', new), rtl.replace(old, new, 1))
        with self.assertRaisesRegex(ValueError, 'interface'):
            replace_module(rtl, 'adapter', new.replace('input wire a', 'input wire b'))
        with self.assertRaises(ValueError):
            replace_module(rtl, 'adapter', new+'\nmodule surprise();\nendmodule')
        with self.assertRaises(ValueError):
            replace_module(rtl+'\n'+old, 'adapter', new)


if __name__ == '__main__':
    unittest.main()
