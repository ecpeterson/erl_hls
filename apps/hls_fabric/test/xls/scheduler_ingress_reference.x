// Reference for the former final merger plus separate scheduled-request wrapper.
import axis;
import ingress_types;

proc Wrap<SLOT: u32> {
  frame_in: chan<axis::Frame> in;
  request_out: chan<ingress_types::ScheduledRequest> out;
  // Preserve the original slot/credit envelope.
  config(frame_in: chan<axis::Frame> in, request_out: chan<ingress_types::ScheduledRequest> out) {
    (frame_in, request_out)
  }
  // Frame storage belongs to the channel and generated output registers.
  init { () }
  // Every accepted frame becomes exactly one ordinary request.
  next(state: ()) {
    let (tok, frame) = recv(join(), frame_in);
    send(tok, request_out, ingress_types::ScheduledRequest { slot: SLOT, frame, credit: u1:0 });
    state
  }
}

pub proc Reference<SLOT: u32> {
  // Match the former CHANNEL_DEPTH=1 root and its alternating input service.
  config(left: chan<axis::Frame> in, right: chan<axis::Frame> in,
         output: chan<ingress_types::ScheduledRequest> out) {
    let (merged_p, merged_c) = chan<axis::Frame, u32:1>("merged");
    spawn axis::FrameMux2(left, right, merged_p);
    spawn Wrap<SLOT>(merged_c, output);
    ()
  }
  // The children own all state.
  init { () }
  // This proc provides connectivity only.
  next(state: ()) { state }
}
