// Focused shared-executor harness for the reduction re-open invariant.
//
// The input machine is deliberately assembled in its public MachineBits ABI:
// it is entering COLLECTING_MEMBERS while the COUNTING reduction is still
// OPEN.  The entry must fail, but failure must preserve both the ordinary
// actor data and original open reduction so diagnostics describe the
// operation that was interrupted.

import axis;
import hls_statem_reduction_rtl_fixture as actor;

// Test-only diagnostic ABI: the independently stored reduction row occupies
// the high bits and the ordinary machine row occupies the low bits.
type ResultBits = bits[263];

fn open_counting_reduction() -> actor::ReductionBits {
  // ReductionState is packed low-to-high as status, site, key, remaining,
  // seen, accumulator. Sum is packed as value followed by contributions.
  (u32:1 as bits[32]) ++
    (u32:0x11223344 as bits[32]) ++
    (uN[3]:0 as bits[3]) ++
    (u8:1 as bits[8]) ++
    (u32:0xa5a51234 as bits[32]) ++
    (u8:0 as bits[8]) ++
    (u2:1 as bits[2])
}

fn pending_reopen_machine() -> actor::MachineBits {
  // MachineBits excludes the sidecar reduction row. SharedMachine's remaining
  // fields are packed low-to-high as phase, entered_from, data,
  // enter_pending, and failed. Phase 1 is COLLECTING_MEMBERS and phase 0 is
  // COUNTING in this fixture.
  u1:0 ++
    u1:1 ++
    (u32:0x44444444 as bits[32]) ++
    (u32:0x33333333 as bits[32]) ++
    (u32:0x22222222 as bits[32]) ++
    (u32:0x11111111 as bits[32]) ++
    (u8:0 as bits[8]) ++
    (u8:1 as bits[8])
}

pub proc Top {
  result_out: chan<ResultBits> out;

  config(result_out: chan<ResultBits> out) { (result_out,) }

  init { u1:0 }

  next(sent: u1) {
    let result = actor::shared_execute(actor::SharedExecutorRequest {
      machine: pending_reopen_machine(),
      reduction: open_counting_reduction(),
      egress_ready: u1:1,
      ..zero!<actor::SharedExecutorRequest>()
    });
    let diagnostic = result.reduction ++ result.machine;
    let _done = send_if(join(), result_out, !sent, diagnostic);
    u1:1
  }
}
