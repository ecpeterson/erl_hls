// Exercise asymmetric lane populations without a receiver pacing the stimulus.
import axis;
import hls_credit_link;

// Twelve data lanes and three independent credit-return lanes share one wire.
pub proc Top {
  // Test sources explicitly return data credits after each accepted packet.
  config(frames_in: chan<axis::Frame>[12] in, credits_in: chan<u1>[12] in,
         returned_in: chan<u1>[3] in, link_out: chan<axis::Beat> out,
         fault_out: chan<u32> out) {
    spawn hls_credit_link::Transmit<u32:12, u32:3, u16:0x4850>(
      frames_in, credits_in, returned_in, link_out, fault_out);
    ()
  }
  // The wrapper owns no state or buffering.
  init { () }
  // All service belongs to the transmitter under test.
  next(state: ()) { state }
}
