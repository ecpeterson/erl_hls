// Ordered, lossless, full-duplex ready/valid transport between two devices.
// Both ends must reset together. A physical transport must preserve complete
// words and their TLAST exactly once; this layer supplies no CRC or replay.
import axis;
import std;

// Full packets serialize the ordinary header plus every configured payload word.
const FRAME_WORDS = axis::MAX_PAYLOAD + u32:1;
// Include zero (idle) and the last full-frame stage without fixed-width overflow.
type Stage = uN[std::clog2(FRAME_WORDS + u32:1)];

const CREDIT_BIT = u32:0x8000;
const LANE_MASK = u32:0x7fff;

// One complete frame is assembled after its unchanged tag/lane prefix.
struct ReceiveState {
  stage: Stage,
  lane: u32,
  payload: bits[axis::FRAME_BITS],
  failed: bool,
}

// Fault codes describe the first detected violation. A faulted receiver
// stops accepting input until reset; it never guesses a new packet boundary.
pub proc Receive<TX: u32, RX: u32, TAG: u16> {
  link_in: chan<axis::Beat> in;
  frames_out: chan<axis::Frame>[RX] out;
  credits_out: chan<u1>[TX] out;
  fault_out: chan<u32> out;

  // The tag/lane prefix is independent of ordinary frame capacity.
  config(link_in: chan<axis::Beat> in,
         frames_out: chan<axis::Frame>[RX] out,
         credits_out: chan<u1>[TX] out, fault_out: chan<u32> out) {
    const_assert!(TX > u32:0 && TX <= u32:32768);
    const_assert!(RX > u32:0 && RX <= u32:32768);
    (link_in, frames_out, credits_out, fault_out)
  }
  // Common reset cancels partial input and the sticky fault.
  init { zero!<ReceiveState>() }
  // Accept exactly FRAME_WORDS after a data prefix; credits terminate at their prefix.
  next(state: ReceiveState) {
    let (tok, beat) = recv_if(join(), link_in, !state.failed, zero!<axis::Beat>());
    let first = state.stage == Stage:0;
    let credit = (beat.word & CREDIT_BIT) != u32:0;
    let lane = beat.word & LANE_MASK;
    let tag_ok = (beat.word >> u32:16) as u16 == TAG;
    let lane_ok = lane < if credit { TX } else { RX };
    let last_ok = if first { beat.tlast == credit } else { beat.tlast == (state.stage == (FRAME_WORDS as Stage)) };
    let fault = if state.failed { u32:0 }
      else if first && !tag_ok { u32:1 }
      else if first && !lane_ok { u32:2 }
      else if !last_ok { u32:3 }
      else { u32:0 };
    let valid = !state.failed && fault == u32:0;
    let tok = unroll_for! (i, tok): (u32, token) in u32:0..TX {
      send_if(tok, credits_out[i], valid && first && credit && lane == i, u1:1)
    }(tok);
    // Words follow the public axis::bits_from_frame encoding, least first.
    let shift = ((state.stage as u32) - u32:1) * u32:32;
    let payload = state.payload | ((beat.word as bits[axis::FRAME_BITS]) << shift);
    let tok = unroll_for! (i, tok): (u32, token) in u32:0..RX {
      send_if(tok, frames_out[i], valid && state.stage == (FRAME_WORDS as Stage) && state.lane == i,
        axis::frame_from_bits(payload))
    }(tok);
    let _done = send_if(tok, fault_out, fault != u32:0, fault);
    if !valid {
      ReceiveState { failed: true, ..state }
    } else if beat.tlast {
      zero!<ReceiveState>()
    } else if first {
      ReceiveState { stage: Stage:1, lane, ..zero!<ReceiveState>() }
    } else {
      ReceiveState { stage: state.stage + Stage:1, payload, ..state }
    }
  }
}

// Each receiver lane owns an independent one-frame FIFO. Return its credit only
// after dequeuing that frame into the ordinary bounded topology lane. Each
// return channel also has its own slot, so another blocked lane cannot stop
// receipt generation or delivery on this lane.
proc Deliver {
  frame_in: chan<axis::Frame> in;
  frame_out: chan<axis::Frame> out;
  returned_out: chan<u1> out;
  // Connect one buffered incoming lane, its consumer, and its independent return-credit slot.
  config(frame_in: chan<axis::Frame> in, frame_out: chan<axis::Frame> out,
         returned_out: chan<u1> out) {
    (frame_in, frame_out, returned_out)
  }
  // No local state is retained beyond the channel buffers.
  init { () }
  // Return one credit only after the ordinary topology lane accepts the complete frame.
  next(state: ()) {
    let (tok, frame) = recv(join(), frame_in);
    let tok = send(tok, frame_out, frame);
    let _done = send(tok, returned_out, u1:1);
    state
  }
}

// Per-class service rounds admit each lane once before starting the next round.
struct TransmitState<TX: u32, RX: u32> {
  credits: bool[TX],
  stage: Stage,
  payload: bits[axis::FRAME_BITS],
  data_served: bool[TX],
  return_served: bool[RX],
  prefer_return: bool,
  failed: bool,
}

// Select credited frames and returns into bounded shared beat storage. Each
// continuously eligible lane receives one grant per service round. Its output
// selection is combinational until accepted, so it must feed the elastic queue below.
proc Packetize<TX: u32, RX: u32, TAG: u16> {
  frames_in: chan<axis::Frame>[TX] in;
  credits_in: chan<u1>[TX] in;
  returned_in: chan<u1>[RX] in;
  link_out: chan<axis::Beat> out;
  fault_out: chan<u32> out;
  // Connect positive lane counts fitting the 15-bit wire identifier.
  config(frames_in: chan<axis::Frame>[TX] in, credits_in: chan<u1>[TX] in,
         returned_in: chan<u1>[RX] in, link_out: chan<axis::Beat> out,
         fault_out: chan<u32> out) {
    (frames_in, credits_in, returned_in, link_out, fault_out)
  }
  // Every peer receiver starts empty under the common reset. There is one
  // advertised credit per lane, irrespective of downstream topology storage.
  init { TransmitState<TX, RX> { credits: [true, ...], ..zero!<TransmitState<TX, RX>>() } }
  // Select one eligible lane or continue its packet; accept credits throughout.
  next(state: TransmitState<TX, RX>) {
    let (tok, credits, excess) = unroll_for! (i, acc):
        (u32, (token, bool[TX], bool)) in u32:0..TX {
      let (tok, _, returned) = recv_if_non_blocking(acc.0, credits_in[i],
        !state.failed, u1:0);
      (tok, update(acc.1, i, acc.1[i] || returned), acc.2 || (returned && acc.1[i]))
    }((join(), state.credits, false));
    let active = !state.failed && !excess;
    let idle = state.stage == Stage:0 && active;
    // Check every unserved lane, granting only the first available one.
    // XLS permits one nonblocking receive per channel, so an empty scan
    // clears that class's round rather than rescanning it in the same step.
    let (tok, returning, return_lane) = unroll_for! (i, acc):
        (u32, (token, bool, u32)) in u32:0..RX {
      let (tok, _, valid) = recv_if_non_blocking(acc.0, returned_in[i],
        idle && state.prefer_return && !state.return_served[i] && !acc.1, u1:0);
      (tok, acc.1 || valid, if valid { i } else { acc.2 })
    }((tok, false, u32:0));
    // An empty return turn can carry data instead. Return turns retain
    // priority when occupied; continuous data cannot starve credit traffic.
    let (tok, taking, data_lane, frame) = unroll_for! (i, acc):
        (u32, (token, bool, u32, axis::Frame)) in u32:0..TX {
      let (tok, frame, valid) = recv_if_non_blocking(acc.0, frames_in[i],
        idle && !returning && !state.data_served[i] && !acc.1 && credits[i],
        zero!<axis::Frame>());
      (tok, acc.1 || valid, if valid { i } else { acc.2 }, if valid { frame } else { acc.3 })
    }((tok, false, u32:0, zero!<axis::Frame>()));
    let data_served = if taking { update(state.data_served, data_lane, true) }
      else if idle && !returning { zero!<bool[TX]>() } else { state.data_served };
    let return_served = if returning { update(state.return_served, return_lane, true) }
      else if idle && state.prefer_return { zero!<bool[RX]>() } else { state.return_served };
    let data_header = ((TAG as u32) << u32:16) | data_lane;
    let return_header = ((TAG as u32) << u32:16) | CREDIT_BIT | return_lane;
    let beat = if returning {
      axis::Beat { tlast: true, word: return_header }
    } else if taking {
      axis::Beat { tlast: false, word: data_header }
    } else {
      axis::Beat { tlast: state.stage == (FRAME_WORDS as Stage), word: state.payload as u32 }
    };
    let tok = send_if(tok, link_out, active && (returning || taking || !idle), beat);
    let _done = send_if(tok, fault_out, excess && !state.failed, u32:4);
    let state = TransmitState<TX, RX> {
      data_served: if and_reduce(data_served as uN[TX]) { zero!<bool[TX]>() } else { data_served },
      return_served: if and_reduce(return_served as uN[RX]) { zero!<bool[RX]>() } else { return_served },
      ..state
    };
    if !active {
      TransmitState<TX, RX> { failed: true, ..state }
    } else if taking {
      TransmitState<TX, RX> { credits: update(credits, data_lane, false),
        stage: Stage:1, payload: axis::bits_from_frame(frame),
        prefer_return: true, ..state }
    } else if idle {
      TransmitState<TX, RX> { credits, prefer_return: !state.prefer_return, ..state }
    } else {
      TransmitState<TX, RX> { credits, payload: state.payload >> u32:32,
        stage: if state.stage == (FRAME_WORDS as Stage) { Stage:0 } else { state.stage + Stage:1 }, ..state }
    }
  }
}

// Drain stable queued words in order; wire backpressure retains the queue head.
proc Wire {
  queued: chan<axis::Beat> in;
  wire_out: chan<axis::Beat> out;
  // The input must provide elastic storage for a pending word.
  config(queued: chan<axis::Beat> in, wire_out: chan<axis::Beat> out) {
    (queued, wire_out)
  }
  // The FIFO owns all buffered words.
  init { () }
  // A word is retired only when its output send can complete.
  next(state: ()) {
    let (tok, beat) = recv(join(), queued);
    let _done = send(tok, wire_out, beat);
    state
  }
}

// Fairly serialize independently credited lanes, retaining each offered word
// through arbitrary wire stalls. Frames remain contiguous and lane order is
// preserved. Duplicate credits fault until the common reset.
pub proc Transmit<TX: u32, RX: u32, TAG: u16> {
  // Two shared beat slots preserve word-rate service when one head is blocked.
  config(frames_in: chan<axis::Frame>[TX] in, credits_in: chan<u1>[TX] in,
         returned_in: chan<u1>[RX] in, link_out: chan<axis::Beat> out,
         fault_out: chan<u32> out) {
    const_assert!(TX > u32:0 && TX <= u32:32768);
    const_assert!(RX > u32:0 && RX <= u32:32768);
    let (queued_p, queued_c) = chan<axis::Beat, u32:2>("transmit_words");
    spawn Packetize<TX, RX, TAG>(frames_in, credits_in, returned_in, queued_p, fault_out);
    spawn Wire(queued_c, link_out);
    ()
  }
  // Packetizer state and the empty elastic queue share the same reset.
  init { () }
  // Child procs perform all transfers.
  next(state: ()) { state }
}

// Alternate fault-source polling; reporting blocks until the fault consumer accepts the selected code.
proc FaultMux {
  receive_in: chan<u32> in;
  transmit_in: chan<u32> in;
  fault_out: chan<u32> out;
  // Connect independent receive/transmit fault sources to the common report channel.
  config(receive_in: chan<u32> in, transmit_in: chan<u32> in, fault_out: chan<u32> out) {
    (receive_in, transmit_in, fault_out)
  }
  // Poll the receive side first after reset.
  init { false }
  // Poll the selected side without waiting for a fault, then alternate after any report is accepted.
  next(prefer_transmit: bool) {
    let (tok, rx, rx_valid) = recv_if_non_blocking(join(), receive_in, !prefer_transmit, u32:0);
    let (tok, tx, tx_valid) = recv_if_non_blocking(tok, transmit_in, prefer_transmit, u32:0);
    let _done = send_if(tok, fault_out, rx_valid || tx_valid, if rx_valid { rx } else { tx });
    !prefer_transmit
  }
}

// Compose a bidirectional credited link with independent lane slots and common reset. Lane counts must be positive and fit the 15-bit identifiers; peers must use the same tag and frame capacity.
pub proc Bridge<TX: u32, RX: u32, TAG: u16> {
  // The tag/lane prefix is independent of ordinary frame capacity.
  config(link_in: chan<axis::Beat> in, link_out: chan<axis::Beat> out,
         frames_in: chan<axis::Frame>[TX] in, frames_out: chan<axis::Frame>[RX] out,
         fault_out: chan<u32> out) {
    // A registered producer output is shared with that proc's progress. It
    // cannot replace these independent per-lane slots: otherwise one blocked
    // output would also stop unrelated packets and incoming credit updates.
    let (received_p, received_c) = chan<axis::Frame, u32:1>[RX]("link_received");
    let (credit_p, credit_c) = chan<u1, u32:1>[TX]("link_credit");
    let (returned_p, returned_c) = chan<u1, u32:1>[RX]("link_returned");
    let (rx_fault_p, rx_fault_c) = chan<u32, u32:0>("link_rx_fault");
    let (tx_fault_p, tx_fault_c) = chan<u32, u32:0>("link_tx_fault");
    spawn Receive<TX, RX, TAG>(link_in, received_p, credit_p, rx_fault_p);
    unroll_for! (i, _): (u32, ()) in u32:0..RX {
      spawn Deliver(received_c[i], frames_out[i], returned_p[i]);
    }(());
    spawn Transmit<TX, RX, TAG>(frames_in, credit_c, returned_c, link_out, tx_fault_p);
    spawn FaultMux(rx_fault_c, tx_fault_c, fault_out);
    ()
  }
  // The children and lane buffers own all mutable packet and credit state.
  init { () }
  // The structural wrapper has no independent transfer or progress state.
  next(state: ()) { state }
}
