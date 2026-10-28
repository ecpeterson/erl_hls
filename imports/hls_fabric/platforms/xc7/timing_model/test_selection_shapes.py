"""Exercise shape inventory against composite types and scoped selector names."""
import unittest
from selection_shapes import flat_width, inventory, table_bounds


class SelectionShapesTests(unittest.TestCase):
    """Guard dimension counts and explicit failure on unsupported input formats."""

    def test_composite_widths(self) -> None:
        """Flatten nested tuple/array data while treating tokens as zero bits."""
        for text, expected in [('bits[65]', 65), ('token', 0), ('()', 0),
                               ('bits[8][5]', 40), ('(token, bits[4])[3][2]', 24),
                               ('((bits[8], bits[8], bits[8], bits[8]), bits[96])[4]', 512)]:
            with self.subTest(text=text):
                self.assertEqual(flat_width(text), expected)

    def test_bad_types_fail(self) -> None:
        """Do not turn malformed or new type syntax into a plausible width."""
        for text in ['', 'bits[', 'bits[x]', 'bits[8]extra', '(bits[3],)', 'bits[2][3']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                flat_width(text)

    def test_bounds_validate_rows(self) -> None:
        """Reject duplicate widths and invalid delays while ignoring comments."""
        self.assertEqual(table_bounds('# fixture\nsel 4 2 1 2\nsel 64 2 3 4\n'), {('sel', 2): 64})
        for text in ['', 'sel 4 2 3 2', 'sel 0 2 1 2', 'sel 4 2 1 2\nsel 4 2 1 2']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                table_bounds(text)

    def test_scopes_and_dimensions(self) -> None:
        """Distinguish data width, fan-in and overwide selectors across reused names."""
        source = '''package example
fn first(selector: bits[1], a: bits[65], b: bits[65]) -> bits[65] {
  ret chosen: bits[65] = sel(selector, cases=[a, b], id=3)
}
fn second(selector: bits[8], a: bits[8], b: bits[8]) -> bits[8] {
  ret chosen: bits[8] = sel(selector, cases=[a, b], default=a, id=6)
}
fn third(selector: bits[3], a: bits[8][5]) -> bits[8][5] {
  ret chosen: bits[8][5] = priority_sel(selector, cases=[a, a, a], default=a, id=8)
}
'''
        rows = inventory(source, {('sel', 2): 64})
        self.assertEqual(sum(row['occurrences'] for row in rows), 3)
        wide = next(row for row in rows if row['result_bits'] == 65)
        self.assertEqual(wide['selector_bits'], 1)
        self.assertEqual(wide['review_reasons'], ['wider_than_table'])
        narrow = next(row for row in rows if row['result_bits'] == 8)
        self.assertEqual(narrow['selector_bits'], 8)
        self.assertEqual(narrow['review_reasons'], ['unmeasured_selector_width'])
        array = next(row for row in rows if row['op'] == 'priority_sel')
        self.assertEqual((array['result_bits'], array['case_count']), (40, 3))
        self.assertEqual(array['review_reasons'], ['unmeasured_case_count'])

    def test_comments_preserve_locations(self) -> None:
        """Skip comments without losing source line numbers or shadowing symbols."""
        rows = inventory('''// fn ignored(s: bits[99]) {
fn f(s: bits[1], a: bits[8]) -> bits[8] {
  // out: bits[8] = sel(s, cases=[a, a], id=2)
  // s: bits[99]
  ret out: bits[8] = sel(s, cases=[a, a], id=2)
}
''', {('sel', 2): 64})
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['selector_bits'], 1)
        self.assertEqual(rows[0]['review_reasons'], [])
        self.assertEqual(rows[0]['examples'][0]['line'], 5)

    def test_message_text_is_not_a_declaration(self) -> None:
        """Diagnostic string contents must not shadow selector definitions."""
        source = '''fn f(t: token, s: bits[1], a: bits[8]) -> bits[8] {
  guard: token = assert(t, s, message="s: bits[99]; x: bits[8] = sel(", id=4)
  ret out: bits[8] = sel(s, cases=[a, a], id=5)
}
'''
        rows = inventory(source, {('sel', 2): 64})
        self.assertEqual(rows[0]['selector_bits'], 1)
        self.assertEqual(rows[0]['review_reasons'], [])

    def test_unresolved_or_multiline_selection_fails(self) -> None:
        """An unrecognized canonical dump must not silently omit selections."""
        for expression in ['sel(missing, cases=[a, a], id=2)', 'sel(s,\n cases=[a, a], id=2)']:
            with self.subTest(expression=expression), self.assertRaises(ValueError):
                inventory('fn f(s: bits[1], a: bits[8]) -> bits[8] {\n  ret out: bits[8] = ' + expression + '\n}', {})


if __name__ == '__main__':
    unittest.main()
