import axis;
import hls_credit_link;

pub proc Top {
  config(link_in: chan<axis::Beat> in, link_out: chan<axis::Beat> out,
         frames_in: chan<axis::Frame>[2] in, frames_out: chan<axis::Frame>[2] out,
         fault_out: chan<u32> out) {
    spawn hls_credit_link::Bridge<u32:2, u32:2, u16:0x4850>(
      link_in, link_out, frames_in, frames_out, fault_out);
    ()
  }
  init { () }
  next(state: ()) { state }
}
