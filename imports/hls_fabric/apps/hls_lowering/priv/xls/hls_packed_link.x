// Independently credited lanes over a packed, lossless, full-duplex word stream.
// Subword i occupies bits [34*i+:34]: valid, TLAST, data[31:0]. Valid subwords
// form a nonempty prefix, in wire order. Both endpoints and storage reset together.
import axis;
import std;

// Full packets serialize the ordinary header plus every configured payload word.
const FRAME_WORDS = axis::MAX_PAYLOAD + u32:1;
// Include zero (idle) and the last full-frame stage without fixed-width overflow.
type Stage = uN[std::clog2(FRAME_WORDS + u32:1)];

const CREDIT_BIT = u32:0x8000;
const LANE_MASK = u32:0x7fff;

// Select an unserved eligible lane, restarting an exhausted round without a bubble.
fn choose<N: u32>(eligible: bool[N], served: bool[N]) -> (bool, u32, bool[N]) {
  let pending = for (i, any): (u32, bool) in u32:0..N {
    any || (eligible[i] && !served[i])
  }(false);
  let mask = if pending { served } else { zero!<bool[N]>() };
  let (valid, lane) = for (i, found): (u32, (bool, u32)) in u32:0..N {
    let take = eligible[i] && !mask[i] && !found.0;
    (found.0 || take, if take { i } else { found.1 })
  }((false, u32:0));
  (valid, lane, if valid { update(mask, lane, true) } else { mask })
}

// Two private staging frames per lane decouple input capture from transfer grants.
struct TxState<TX: u32, RX: u32> {
  credits: u32[TX],
  // Incoming credits affect the following activation, breaking reciprocal link
  // feedback without putting a register in the outgoing data path.
  pending_credits: u32[TX],
  frames: bits[axis::FRAME_BITS][2][TX],
  head: bool[TX],
  count: u32[TX],
  returns: u32[RX],
  data_served: bool[TX],
  return_served: bool[RX],
  prefer_return: bool,
  stage: Stage,
  last_stage: Stage,
  payload: bits[axis::FRAME_BITS],
  failed: bool,
}

// Produce one protocol word from captured work, with fair fallback between classes.
fn transmit_word<TX: u32, RX: u32, TAG: u16, COMPACT: bool>(state: TxState<TX, RX>) -> (TxState<TX, RX>, bits[34]) {
  let data_eligible = for (i, flags): (u32, bool[TX]) in u32:0..TX {
    update(flags, i, state.count[i] != u32:0 && state.credits[i] != u32:0)
  }(zero!<bool[TX]>());
  let return_eligible = for (i, flags): (u32, bool[RX]) in u32:0..RX {
    update(flags, i, state.returns[i] != u32:0)
  }(zero!<bool[RX]>());
  let (dv, dl, dm) = choose<TX>(data_eligible, state.data_served);
  let (rv, rl, rm) = choose<RX>(return_eligible, state.return_served);
  let returning = rv && (state.prefer_return || !dv);
  let frame = state.frames[dl][state.head[dl] as u32];
  let length = frame[0+:u8];
  let compact = COMPACT && dl < u32:32 && length <= u8:7 && (length as u32) <= axis::MAX_PAYLOAD
    && frame[8+:u16] == u16:0 && (frame >> (u32:32 + (length as u32)*u32:32)) == bits[axis::FRAME_BITS]:0;
  let data_header = if compact {
    (((TAG ^ u16:1) as u32) << u32:16) | ((frame[24+:u8] as u32) << u32:8)
      | ((length as u32) << u32:5) | dl
  } else { ((TAG as u32) << u32:16) | dl };
  let return_header = ((TAG as u32) << u32:16) | CREDIT_BIT | rl;
  if state.failed {
    (state, bits[34]:0)
  } else if state.stage != Stage:0 {
    let last = state.stage == state.last_stage;
    (TxState<TX, RX> { payload: state.payload >> u32:32,
       stage: if last { Stage:0 } else { state.stage + Stage:1 }, ..state },
     u1:1 ++ last ++ state.payload[0+:u32])
  } else if returning {
    (TxState<TX, RX> { returns: update(state.returns, rl, state.returns[rl] - u32:1),
       return_served: rm, prefer_return: false, ..state },
     u1:1 ++ u1:1 ++ return_header)
  } else if dv {
    (TxState<TX, RX> { credits: update(state.credits, dl, state.credits[dl] - u32:1),
       payload: if compact { frame >> u32:32 } else { frame },
       stage: if compact && length == u8:0 { Stage:0 } else { Stage:1 },
       last_stage: if compact { length as Stage } else { (FRAME_WORDS as Stage) },
       head: update(state.head, dl, !state.head[dl]),
       count: update(state.count, dl, state.count[dl] - u32:1),
       data_served: dm, prefer_return: true, ..state },
     u1:1 ++ (compact && length == u8:0) ++ data_header)
  } else {
    (state, bits[34]:0)
  }
}

// Capture each input at most once per clock; the pure word loop can cross packets.
proc Packetize<TX: u32, RX: u32, TAG: u16, WORDS: u32, CREDITS: u32, COMPACT: bool> {
  frames_in: chan<axis::Frame>[TX] in;
  credits_in: chan<u32>[TX] in;
  returns_in: chan<u1>[RX] in;
  packed_out: chan<bits[WORDS * u32:34]> out;
  fault_out: chan<u32> out;
  // Credits count actual reserved receive slots; pending returns have separate storage.
  config(frames_in: chan<axis::Frame>[TX] in, credits_in: chan<u32>[TX] in,
         returns_in: chan<u1>[RX] in, packed_out: chan<bits[WORDS * u32:34]> out,
         fault_out: chan<u32> out) {
    (frames_in, credits_in, returns_in, packed_out, fault_out)
  }
  // Common reset reserves CREDITS empty receiver slots independently for every lane.
  init { TxState<TX, RX> { credits: [CREDITS, ...], ..zero!<TxState<TX, RX>>() } }
  // Frame staging is bounded and independent even while a lane has no peer credit.
  next(state: TxState<TX, RX>) {
    let (tok, incoming_credits, incoming_frames, offered) = unroll_for! (i, acc):
        (u32, (token, u32[TX], bits[axis::FRAME_BITS][TX], bool[TX])) in u32:0..TX {
      let (tok, credit, valid) = recv_if_non_blocking(acc.0, credits_in[i], !state.failed, u32:0);
      let (tok, frame, offered) = recv_if_non_blocking(tok, frames_in[i],
        !state.failed && state.count[i] < u32:2, zero!<axis::Frame>());
      (tok, update(acc.1, i, if valid { credit } else { u32:0 }),
       update(acc.2, i, axis::bits_from_frame(frame)), update(acc.3, i, offered))
    }((join(), zero!<u32[TX]>(), zero!<bits[axis::FRAME_BITS][TX]>(), zero!<bool[TX]>()));
    let (captured, fault) = for (i, acc): (u32, (TxState<TX, RX>, bool)) in u32:0..TX {
      let credit = state.pending_credits[i];
      let balance = state.credits[i] + credit;
      let excess = credit > CREDITS || balance > CREDITS;
      let tail = state.head[i] ^ (state.count[i] == u32:1);
      let frames = if offered[i] { update(acc.0.frames, i,
        update(acc.0.frames[i], tail as u32, incoming_frames[i])) } else { acc.0.frames };
      (TxState<TX, RX> { credits: update(acc.0.credits, i, balance), frames,
        count: update(acc.0.count, i, state.count[i] + offered[i] as u32), ..acc.0 }, acc.1 || excess)
    }((state, false));
    let (tok, incoming_returns) = unroll_for! (i, acc):
        (u32, (token, bool[RX])) in u32:0..RX {
      let (tok, _, valid) = recv_if_non_blocking(acc.0, returns_in[i], !state.failed, u1:0);
      (tok, update(acc.1, i, valid))
    }((tok, zero!<bool[RX]>()));
    let (captured, fault) = for (i, acc): (u32, (TxState<TX, RX>, bool)) in u32:0..RX {
      let pending = state.returns[i] + incoming_returns[i] as u32;
      (TxState<TX, RX> { returns: update(acc.0.returns, i, pending), ..acc.0 },
       acc.1 || pending > CREDITS)
    }((captured, fault));
    let captured = TxState<TX, RX> { failed: state.failed || fault, pending_credits: incoming_credits, ..captured };
    let (next_state, transfer) = for (i, acc):
        (u32, (TxState<TX, RX>, bits[WORDS * u32:34])) in u32:0..WORDS {
      let (next_state, word) = transmit_word<TX, RX, TAG, COMPACT>(acc.0);
      (next_state, bit_slice_update(acc.1, i * u32:34, word))
    }((captured, bits[WORDS * u32:34]:0));
    let tok = send_if(tok, packed_out, transfer != bits[WORDS * u32:34]:0, transfer);
    let _sent = send_if(tok, fault_out, fault && !state.failed, u32:4);
    next_state
  }
}

// A single assembly state spans packed transfers; all complete packets retain order.
struct RxState {
  stage: Stage,
  last_stage: Stage,
  compact: bool,
  lane: u32,
  payload: bits[axis::FRAME_BITS],
  failed: bool,
}

// Decode a common header or an opaque extended frame without inferring application metadata.
fn receive_word<TX: u32, RX: u32, TAG: u16, COMPACT: bool>(state: RxState, word: bits[33])
    -> (RxState, u32, bool, u32, bits[axis::FRAME_BITS], bool, u32) {
  let data = word[0+:u32];
  let last = word[32+:u1];
  let first = state.stage == Stage:0;
  let common = COMPACT && data[16+:u16] == (TAG ^ u16:1);
  let length = data[5+:u3];
  let credit = !common && (data & CREDIT_BIT) != u32:0;
  let lane = if common { data & u32:31 } else { data & LANE_MASK };
  let expected_last = if first { credit || (common && length == u3:0) }
    else { state.stage == state.last_stage };
  let fault = if state.failed { u32:0 }
    else if first && data[16+:u16] != TAG && !common { u32:1 }
    else if first && lane >= if credit { TX } else { RX } { u32:2 }
    else if last != expected_last || (first && common && (length as u32) > axis::MAX_PAYLOAD) { u32:3 }
    else { u32:0 };
  let valid = !state.failed && fault == u32:0;
  let shift = (state.stage as u32 - u32:1 + state.compact as u32) * u32:32;
  let header = (data[8+:u8] as u32 << u32:24) | length as u32;
  let payload = if first { header as bits[axis::FRAME_BITS] }
    else { state.payload | ((data as bits[axis::FRAME_BITS]) << shift) };
  let next_state = if !valid { RxState { failed: true, ..state } }
    else if last { zero!<RxState>() }
    else if first { RxState { stage: Stage:1, lane, compact: common,
      last_stage: if common { length as Stage } else { (FRAME_WORDS as Stage) },
      payload: if common { payload } else { bits[axis::FRAME_BITS]:0 }, failed: false } }
    else { RxState { stage: state.stage + Stage:1, payload, ..state } };
  (next_state, fault, valid && first && credit, lane, payload,
   valid && last && (!first || !credit), if first { lane } else { state.lane })
}

// An accepted transfer may complete several frames for one lane. Retain its tail
// while draining at most one frame per lane per activation; wire grouping is free.
struct RxBuffer<WORDS: u32> {
  assembly: RxState,
  held: bits[WORDS * u32:34],
}

// Restore opaque frames and independently queued credit counts from packed words.
proc Receive<TX: u32, RX: u32, TAG: u16, WORDS: u32, COMPACT: bool> {
  packed_in: chan<bits[WORDS * u32:34]> in;
  frames_out: chan<axis::Frame>[RX] out;
  credits_out: chan<u32>[TX] out;
  fault_out: chan<u32> out;
  // Each frame output owns advertised storage; credit outputs have independent capacity.
  config(packed_in: chan<bits[WORDS * u32:34]> in, frames_out: chan<axis::Frame>[RX] out,
         credits_out: chan<u32>[TX] out, fault_out: chan<u32> out) {
    (packed_in, frames_out, credits_out, fault_out)
  }
  // Reset excludes every unfinished packet and transfer from the next activation.
  init { zero!<RxBuffer<WORDS>>() }
  // Advertised frame slots also cover held words. A tail drains in at most WORDS
  // activations, even if all its frames target one lane; other lanes keep their slots.
  next(buffer: RxBuffer<WORDS>) {
    let state = buffer.assembly;
    let (tok, incoming) = recv_if(join(), packed_in,
      !state.failed && buffer.held == bits[WORDS * u32:34]:0, bits[WORDS * u32:34]:0);
    let transfer = if buffer.held != bits[WORDS * u32:34]:0 { buffer.held } else { incoming };
    let (next_state, fault, _, counts, complete, payload, held) = for (i, acc):
        (u32, (RxState, u32, bool, u32[TX], bool[RX], bits[axis::FRAME_BITS][RX], bits[WORDS * u32:34])) in u32:0..WORDS {
      if acc.6 != bits[WORDS * u32:34]:0 { acc } else {
        let word = (transfer >> (i * u32:34)) as bits[34];
        let valid = word[33+:u1];
        let bad_prefix = (valid && !acc.2) || (!valid && i == u32:0);
        let (next_state, code, returned, lane, frame, done, recipient) =
          receive_word<TX, RX, TAG, COMPACT>(acc.0, word as bits[33]);
        let fail = !acc.0.failed && (bad_prefix || (valid && code != u32:0));
        if valid && done && acc.4[recipient] && !fail {
          (acc.0, acc.1, acc.2, acc.3, acc.4, acc.5, transfer >> (i * u32:34))
        } else {
          let counts = if valid && !bad_prefix && returned {
            update(acc.3, lane, acc.3[lane] + u32:1)
          } else { acc.3 };
          (if fail { RxState { failed: true, ..acc.0 } } else if valid { next_state } else { acc.0 },
           if acc.1 != u32:0 { acc.1 } else if fail { if bad_prefix { u32:5 } else { code } } else { u32:0 },
           acc.2 && valid, counts,
           if valid && !fail && done { update(acc.4, recipient, true) } else { acc.4 },
           if valid && !fail && done { update(acc.5, recipient, frame) } else { acc.5 }, acc.6)
        }
      }
    }((state, u32:0, true, zero!<u32[TX]>(), zero!<bool[RX]>(), zero!<bits[axis::FRAME_BITS][RX]>(), bits[WORDS * u32:34]:0));
    let tok = unroll_for! (i, tok): (u32, token) in u32:0..TX {
      send_if(tok, credits_out[i], counts[i] != u32:0, counts[i])
    }(tok);
    let tok = unroll_for! (i, tok): (u32, token) in u32:0..RX {
      send_if(tok, frames_out[i], complete[i], axis::frame_from_bits(payload[i]))
    }(tok);
    let _sent = send_if(tok, fault_out, fault != u32:0, fault);
    RxBuffer<WORDS> { assembly: next_state, held }
  }
}

// Forward the queue head without another frame register; return its credit after acceptance.
// tools/transport_codegen.py keeps the frame in one cycle and the credit in the next.
proc Deliver {
  delivered_queue: chan<axis::Frame> in;
  delivered_frame: chan<axis::Frame> out;
  delivered_credit: chan<u1> out;
  // A blocked destination owns only this lane's advertised slots.
  config(delivered_queue: chan<axis::Frame> in, delivered_frame: chan<axis::Frame> out,
         delivered_credit: chan<u1> out) { (delivered_queue, delivered_frame, delivered_credit) }
  // Queues own all retained frames and credits.
  init { () }
  // The return cannot overtake downstream acceptance.
  next(state: ()) {
    let (tok, frame) = recv(join(), delivered_queue);
    let tok = send(tok, delivered_frame, frame);
    let _sent = send(tok, delivered_credit, u1:1);
    state
  }
}

// The input FIFO holds every offered word stable through stalls; forwarding adds no register.
proc Wire<WORDS: u32> {
  wire_queue: chan<bits[WORDS * u32:34]> in;
  wire_transfer: chan<bits[WORDS * u32:34]> out;
  // Pair with the same-cycle constraint in tools/transport_codegen.py.
  config(wire_queue: chan<bits[WORDS * u32:34]> in, wire_transfer: chan<bits[WORDS * u32:34]> out) { (wire_queue, wire_transfer) }
  // The channel owns queued transfers.
  init { () }
  // Drain in order without changing word validity or packet boundaries.
  next(state: ()) {
    let (tok, value) = recv(join(), wire_queue);
    let _sent = send(tok, wire_transfer, value);
    state
  }
}

// Poll independent fault reports; once faulted each half emits at most one report.
proc FaultMux {
  rx: chan<u32> in;
  tx: chan<u32> in;
  output: chan<u32> out;
  // Management must consume faults even when application traffic is stopped.
  config(rx: chan<u32> in, tx: chan<u32> in, output: chan<u32> out) { (rx, tx, output) }
  // Either half can report first.
  init { false }
  // Alternate fault sources to preserve bounded service.
  next(prefer_tx: bool) {
    let (tok, r, rv) = recv_if_non_blocking(join(), rx, !prefer_tx, u32:0);
    let (tok, t, tv) = recv_if_non_blocking(tok, tx, prefer_tx, u32:0);
    let _sent = send_if(tok, output, rv || tv, if rv { r } else { t });
    !prefer_tx
  }
}

// Packed transport preserves every configured ordinary frame; only serialization and lane
// capacity change. Validity/TLAST are internal sidebands, not a physical encoding.
pub proc Bridge<TX: u32, RX: u32, TAG: u16, WORDS: u32, CREDITS: u32, COMPACT: bool = {false}> {
  // Word grouping is independent of frame boundaries; repeated lanes drain from bounded staging.
  config(link_in: chan<bits[WORDS * u32:34]> in, link_out: chan<bits[WORDS * u32:34]> out,
         frames_in: chan<axis::Frame>[TX] in, frames_out: chan<axis::Frame>[RX] out,
         fault_out: chan<u32> out) {
    const_assert!(TX > u32:0 && TX <= u32:32768 && RX > u32:0 && RX <= u32:32768);
    const_assert!(WORDS == u32:1 || WORDS == u32:2 || WORDS == u32:4);
    const_assert!(CREDITS > u32:0 && CREDITS <= u32:16);
    let (received_p, received_c) = chan<axis::Frame, CREDITS>[RX]("link_received");
    let (credit_p, credit_c) = chan<u32, CREDITS>[TX]("link_credit");
    let (return_p, return_c) = chan<u1, CREDITS>[RX]("link_returned");
    let (words_p, words_c) = chan<bits[WORDS * u32:34], u32:2>("transmit_words");
    let (rx_fault_p, rx_fault_c) = chan<u32, u32:1>("link_rx_fault");
    let (tx_fault_p, tx_fault_c) = chan<u32, u32:1>("link_tx_fault");
    spawn Receive<TX, RX, TAG, WORDS, COMPACT>(link_in, received_p, credit_p, rx_fault_p);
    unroll_for! (i, _): (u32, ()) in u32:0..RX {
      spawn Deliver(received_c[i], frames_out[i], return_p[i]);
    }(());
    spawn Packetize<TX, RX, TAG, WORDS, CREDITS, COMPACT>(frames_in, credit_c, return_c, words_p, tx_fault_p);
    spawn Wire<WORDS>(words_c, link_out);
    spawn FaultMux(rx_fault_c, tx_fault_c, fault_out);
    ()
  }
  // All child state and the advertised queues share this reset.
  init { () }
  // Child procs implement the link.
  next(state: ()) { state }
}

// The extended lane format transports every configured bit, including noncanonical actor headers.
#[test]
fn configured_extended_frame_test() {
  let frame = !bits[axis::FRAME_BITS]:0;
  let source = TxState<u32:1,u32:1> {
    credits: [u32:1], count: [u32:1], frames: [[frame, bits[axis::FRAME_BITS]:0]],
    ..zero!<TxState<u32:1,u32:1>>()
  };
  let (tx, header) = transmit_word<u32:1,u32:1,u16:0x4850,true>(source);
  assert_eq(header[16+:u16], u16:0x4850);
  let (rx, fault, credit, _, _, done, _) =
    receive_word<u32:1,u32:1,u16:0x4850,true>(zero!<RxState>(), header as bits[33]);
  assert_eq((fault, credit, done), (u32:0, false, false));
  let (tx, rx) = for (i, states): (u32, (TxState<u32:1,u32:1>, RxState)) in u32:0..FRAME_WORDS {
    let (tx, beat) = transmit_word<u32:1,u32:1,u16:0x4850,true>(states.0);
    let (rx, fault, credit, _, payload, done, _) =
      receive_word<u32:1,u32:1,u16:0x4850,true>(states.1, beat as bits[33]);
    assert_eq(fault, u32:0);
    assert_eq(credit, false);
    assert_eq(done, i + u32:1 == FRAME_WORDS);
    if done { assert_eq(payload, frame) } else { () };
    (tx, rx)
  }((tx, rx));
  assert_eq((tx.stage, rx.stage), (Stage:0, Stage:0));
}

// Compact headers retain their fixed three-bit length; selected capacity only bounds admissibility.
#[test]
fn configured_compact_frame_test() {
  let frame = (bits[axis::FRAME_BITS]:0x12345678 << u32:32) | bits[axis::FRAME_BITS]:0xa5000001;
  let source = TxState<u32:1,u32:1> {
    credits: [u32:1], count: [u32:1], frames: [[frame, bits[axis::FRAME_BITS]:0]],
    ..zero!<TxState<u32:1,u32:1>>()
  };
  let (tx, header) = transmit_word<u32:1,u32:1,u16:0x4850,true>(source);
  assert_eq(header[16+:u16], u16:0x4851);
  let (rx, fault, _, _, _, done, _) =
    receive_word<u32:1,u32:1,u16:0x4850,true>(zero!<RxState>(), header as bits[33]);
  assert_eq((fault, done), (u32:0, false));
  let (_, beat) = transmit_word<u32:1,u32:1,u16:0x4850,true>(tx);
  let (rx, fault, credit, _, payload, done, _) =
    receive_word<u32:1,u32:1,u16:0x4850,true>(rx, beat as bits[33]);
  assert_eq((rx.stage, fault, credit, done, payload), (Stage:0, u32:0, false, true, frame));
  if axis::MAX_PAYLOAD < u32:7 {
    let too_long = bits[33]:0x4851a500 | (((axis::MAX_PAYLOAD + u32:1) as bits[33]) << u32:5);
    let (bad, fault, _, _, _, done, _) =
      receive_word<u32:1,u32:1,u16:0x4850,true>(zero!<RxState>(), too_long);
    assert_eq((bad.failed, fault, done), (true, u32:3, false));
  } else { () }
}
