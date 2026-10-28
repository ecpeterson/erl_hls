"""Check tuple/array accounting and state-read deduplication in the diagnostic census."""
from pathlib import Path
import tempfile
import unittest

from erl_hls_tools.xls_ir_census import bit_width, census


class CensusTests(unittest.TestCase):
    """Keep structural counts exact while rejecting unsupported input shapes."""

    def test_type_widths(self) -> None:
        """Count nested compound state, including zero-width tokens and empty tuples."""
        for kind, expected in [("bits[0]", 0), ("token", 0), ("()", 0),
                               ("(bits[3], bits[5][2])[6]", 78),
                               ("((bits[4], bits[1]), token)[2][3]", 30)]:
            self.assertEqual(bit_width(kind), expected)

    def test_unknown_types_fail(self) -> None:
        """Do not silently undercount new or malformed IR types."""
        for kind in ["bits[x]", "bits[3]oops", "(bits[8],)", "bool", "bits[2][-1]"]:
            with self.assertRaises(ValueError):
                bit_width(kind)

    def test_state_reads_and_proc_filter(self) -> None:
        """Repeated state reads count once; unrelated functions/procs stay excluded."""
        text = '''package probe
proc selected(s: bits[4][6], init={[0, 0, 0, 0, 0, 0]}) {
  a: bits[4][6] = state_read(state_element=s, id=1)
  b: bits[4][6] = state_read(state_element=s, id=2)
  i: bits[3] = literal(value=1, id=3)
  v: bits[4] = array_index(a, indices=[i], id=4)
  n: () = next_value(param=a, value=b, id=5)
}
fn ignored(x: bits[8]) -> bits[8] {
  ret v: bits[8] = add(x, x, id=6)
}
proc other(s: bits[99], init={0}) {
  s: bits[99] = state_read(state_element=s, id=7)
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "probe.ir"
            path.write_text(text)
            result = census(path, "^selected$")
            self.assertEqual(result["state_bits"], 24)
            self.assertEqual(result["nodes"], 5)
            self.assertEqual(result["procs"][0]["access_result_bits"], {"array_index": 4})
            with self.assertRaises(ValueError):
                census(path, "missing")


if __name__ == "__main__":
    unittest.main()
