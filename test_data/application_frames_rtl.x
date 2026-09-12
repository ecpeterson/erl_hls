import axis;
import hls_fabric_router;

pub proc RawTop {
  config(beat_in: chan<axis::Beat> in, frame_out: chan<axis::Frame> out) {
    spawn axis::Rx(beat_in, frame_out);
  }
  init { () }
  next(state: ()) { state }
}

pub proc ReservedTop {
  config(beat_in: chan<axis::Beat> in, frame_out: chan<axis::Frame> out,
      admission_in: chan<u1> in) {
    spawn axis::ReservedRx(beat_in, frame_out, admission_in);
  }
  init { () }
  next(state: ()) { state }
}

pub proc PairTop {
  config(beat_in: chan<axis::Beat> in, frame_out: chan<axis::Frame> out) {
    let (one_p, one_c) = chan<axis::Beat, u32:1>("one");
    let (two_p, two_c) = chan<axis::Beat, u32:1>("two");
    let (frame_one_p, frame_one_c) = chan<axis::Frame, u32:1>("frame_one");
    let (frame_two_p, frame_two_c) = chan<axis::Frame, u32:1>("frame_two");
    spawn hls_fabric_router::PairIngress(beat_in, one_p, two_p);
    spawn axis::Rx(one_c, frame_one_p);
    spawn axis::Rx(two_c, frame_two_p);
    spawn axis::FrameMux2(frame_one_c, frame_two_c, frame_out);
  }
  init { () }
  next(state: ()) { state }
}

pub proc EndpointTop {
  config(beat_in: chan<axis::Beat> in, frame_out: chan<axis::Frame> out) {
    let (routed_p, routed_c) = chan<axis::Beat, u32:1>("routed");
    spawn hls_fabric_router::EndpointIngress<u16:7, u16:1>(beat_in, routed_p);
    spawn axis::Rx(routed_c, frame_out);
  }
  init { () }
  next(state: ()) { state }
}

// A self-driving admission path for host-side inspection under backpressure.
// Each group contains an early TLAST, a late TLAST and one valid frame.
proc Producer {
  beat_out: chan<axis::Beat> out;
  config(beat_out: chan<axis::Beat> out) { (beat_out,) }
  init { u32:0 }
  next(index: u32) {
    let beats = axis::Beat[8]:[
      axis::Beat { word: u32:0x03000102, tlast: false },
      axis::Beat { word: u32:99, tlast: true },
      axis::Beat { word: u32:0x03000201, tlast: false },
      axis::Beat { word: u32:88, tlast: false },
      axis::Beat { word: u32:0x03009900, tlast: true },
      axis::Beat { word: u32:0x03000302, tlast: false },
      axis::Beat { word: u32:42, tlast: false },
      axis::Beat { word: u32:43, tlast: true },
    ];
    send(join(), beat_out, beats[index]);
    if index == u32:7 { u32:0 } else { index + u32:1 }
  }
}

proc CreditSink {
  frame_in: chan<axis::Frame> in;
  frame_out: chan<axis::Frame> out;
  credit_out: chan<u1> out;
  config(frame_in: chan<axis::Frame> in, frame_out: chan<axis::Frame> out,
      credit_out: chan<u1> out) { (frame_in, frame_out, credit_out) }
  init { false }
  next(admitted: bool) {
    // Credit validity depends only on the registered ownership snapshot.
    // A blocking receive here would couple it to the receiver's frame valid
    // through XLS's activation predicate, closing a bypass-FIFO handshake loop.
    let (tok, frame, received) = recv_if_non_blocking(
      join(), frame_in, admitted, zero!<axis::Frame>());
    let sent = send_if(tok, frame_out, received, frame);
    send_if(sent, credit_out, !admitted, u1:1);
    !received
  }
}

pub proc DebugTop {
  config(frame_out: chan<axis::Frame> out) {
    let (beat_p, beat_c) = chan<axis::Beat, u32:1>("ingress");
    let (frame_p, frame_c) = chan<axis::Frame, u32:1>("mailbox");
    let (credit_p, credit_c) = chan<u1, u32:1>("admission");
    spawn Producer(beat_p);
    spawn axis::ReservedRx(beat_c, frame_p, credit_c);
    spawn CreditSink(frame_c, frame_out, credit_p);
  }
  init { () }
  next(state: ()) { state }
}
