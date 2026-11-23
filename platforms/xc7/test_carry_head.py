"""Finite negatives for the packed carry-head repair audit; no native tool execution."""
import unittest
from gtx.check_carry_head import audit


def cell(kind: str, inputs: dict, outputs: dict, parameters: dict | None = None) -> dict:
    """Build a small packed cell with explicit input/output directions."""
    return {'type':kind,'parameters':parameters or {},'connections':inputs | outputs,
        'port_directions':{name:'input' for name in inputs} | {name:'output' for name in outputs}}


def fixture(mode: int) -> dict:
    """Represent the observed relocated head and two independent fabric consumers."""
    carry = mode + 2 if mode in (0,1) else 4
    cells = {
        'gnd':cell('PSEUDO_GND',{}, {'Y':[2]}),
        'vcc':cell('PSEUDO_VCC',{}, {'Y':[3]}),
        'target':cell('CARRY4',{'S0':[10],'CIN':[] if mode in (0,1) else [4]},
            {'O0':[20],'CO0':[21]}, {'PRECYINIT_CONST':str(mode)} if mode in (0,1) else {}),
        'head$sumLUT$1':cell('SLICE_LUTX',{'A1':[10],'A2':[carry]}, {'O6':[30]}, {'INIT':'0110'}),
        'sum_user':cell('SLICE_LUTX',{'A1':[30]}, {'O6':[40]}, {'INIT':'10'}),
        'carry_user':cell('SLICE_LUTX',{'A1':[21]}, {'O6':[41]}, {'INIT':'10'})}
    if mode == 2:
        cells['upstream'] = cell('CARRY4',{'S0':[12],'CIN':[]},{'CO3':[4]})
    return {'modules':{'carry_head_fixture':{'cells':cells}}}


class CarryHeadTests(unittest.TestCase):
    """Wrong constants, wrong truth tables and retained mux contention cannot qualify."""

    def test_both_constants_and_dynamic_spine(self) -> None:
        """All explicit carry-in kinds retain the exhaustive four-case sum identity."""
        for mode in (0,1,2):
            with self.subTest(mode=mode):
                result = audit(fixture(mode),mode)
                self.assertTrue(result['passed'])
                self.assertEqual(result['boolean_assignments'],4)

    def test_wrong_constant_or_truth_table(self) -> None:
        """A constant-one root cannot silently use zero; native LUT INIT must encode XOR."""
        packed = fixture(1)
        packed['modules']['carry_head_fixture']['cells']['head$sumLUT$1']['connections']['A2'] = [2]
        with self.assertRaisesRegex(ValueError,'head sum lacks'):
            audit(packed,1)
        packed = fixture(0)
        packed['modules']['carry_head_fixture']['cells']['head$sumLUT$1']['parameters']['INIT'] = '0000'
        with self.assertRaisesRegex(ValueError,'sum identity'):
            audit(packed,0)

    def test_residual_output_mux_conflict(self) -> None:
        """Retaining a root O0 consumer reproduces the diagnosed pre-repair failure."""
        packed = fixture(0)
        packed['modules']['carry_head_fixture']['cells']['unmoved_user'] = cell(
            'SLICE_LUTX',{'A1':[20]},{'O6':[42]},{'INIT':'10'})
        with self.assertRaisesRegex(ValueError,'O0 still has consumers'):
            audit(packed,0)


if __name__ == '__main__':
    unittest.main()
