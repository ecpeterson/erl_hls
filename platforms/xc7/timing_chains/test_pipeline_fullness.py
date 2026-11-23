"""Check the experiment observer refuses ambiguous bindings and conserves sampled time."""
import csv
from pathlib import Path
import tempfile
import unittest

from pipeline_fullness import instrument, summarize


def fixture(array: bool) -> str:
    """Exercise both XLS representations of two in-flight flags."""
    declaration = 'reg held[0:1];' if array else 'reg held_0; reg held_1;'
    flights = ['held[0]','held[1]'] if array else ['held_0','held_1']
    return f'''module __cell__SharedService_0__2_0_next(
      input clk, input reset);
      {declaration}
      wire ready, ready__1, selectable, selectable__1, p0_stage_done, issue_valid;
      wire qv, qr, rv, rr;
      wire _ram_read_req_out_vld, _ram_read_req_out_rdy;
      wire _ram_write_req_out_vld, _ram_write_req_out_rdy, _egress_out_vld, _egress_out_rdy;
      assign selectable = ready & ~{flights[0]};
      assign selectable__1 = ready__1 & ~{flights[1]};
      __cell__SharedExecutor_0_next executor (
        ._request_in_vld(qv), ._request_in_rdy(qr),
        ._result_out_vld(rv), ._result_out_rdy(rr)
      );
    endmodule'''


class FullnessTests(unittest.TestCase):
    """Availability, ownership and accepted work are distinct measured quantities."""

    def test_both_storage_representations(self) -> None:
        """Scalarization must preserve the count and exact predicate bindings."""
        for array in (True,False):
            rewritten, bindings = instrument(fixture(array))
            self.assertEqual(bindings[0]['actors'],2)
            self.assertIn('$fdisplay',rewritten)
            self.assertEqual(len(bindings[0]['selectors']),2)

    def test_missing_or_derived_ownership_is_rejected(self) -> None:
        """Do not report occupancy from a missing actor or a combinational next-state value."""
        with self.assertRaises(ValueError):
            instrument(fixture(True).replace('assign selectable__1','assign other'))
        with self.assertRaises(ValueError):
            instrument(fixture(False).replace('reg held_0','wire held_0'))

    def test_steady_interval_is_partitioned_once(self) -> None:
        """Count population rather than bit positions and exclude startup/drain samples."""
        fields = ['time','ready','eligible','inflight','request_valid','request_ready',
                  'result_valid','result_ready','metadata_advance','issue_valid',
                  'read_valid','read_ready','write_valid','write_ready','egress_valid','egress_ready']
        base = dict.fromkeys(fields,0)
        samples = [dict(base,time=0,request_valid=1,request_ready=1),
                   dict(base,time=10,ready=3,eligible=2,inflight=1),
                   dict(base,time=20,ready=2,eligible=0,inflight=3),
                   dict(base,time=30,request_valid=1,request_ready=1),
                   dict(base,time=40,request_valid=1,request_ready=0),
                   dict(base,time=50)]
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            with (stage/'fullness-0.csv').open('w') as stream:
                writer = csv.DictWriter(stream,fieldnames=fields)
                writer.writeheader()
                writer.writerows(samples)
            result, = summarize(stage,[{'id':0}],10,50)
        self.assertEqual(result['counts']['cycles'],4)
        self.assertEqual(result['counts']['requests'],1)
        self.assertEqual(result['histograms']['inflight'],{1:1,2:1,0:2})
        self.assertEqual(result['histograms']['executor'],{
            'no request; eligible actor exists':1,
            'no request; outstanding actors, none eligible':1,
            'accepted':1,'request blocked':1})
        self.assertTrue(all(sum(h.values())==4 for h in result['histograms'].values()))


if __name__ == '__main__':
    unittest.main()
