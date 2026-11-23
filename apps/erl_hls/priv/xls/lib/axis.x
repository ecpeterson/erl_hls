// axis.x
//
// Beats remain 32 bits. The per-build configuration selects ordinary actor
// capacity; FrameN remains available for independent boundary formats.

import frame_config;

pub const MAX_PAYLOAD = frame_config::PAYLOAD_WORDS;
pub const PAYLOAD_BITS = frame_config::PAYLOAD_BITS;
pub const FRAME_BITS = frame_config::FRAME_BITS;

// One complete transport beat; adapters require all four bytes to be valid.
pub struct Beat {
  tlast: u1,
  word: u32,
}

// Header shape and byte positions share the generated canonical schema.
pub type Header = frame_config::Header;

// Decodes exactly one canonical header word.
pub fn header_from_bits(raw: bits[frame_config::HEADER_BITS]) -> Header {
  frame_config::header_from_bits(raw)
}

// Encodes the canonical numeric header word.
pub fn bits_from_header(header: Header) -> bits[frame_config::HEADER_BITS] {
  frame_config::bits_from_header(header)
}

// A frame with an independently selected payload capacity in complete words.
pub struct FrameN<PAYLOAD_WORDS: u32> {
  header: Header,
  payload: bits[PAYLOAD_WORDS * u32:32],
}

// The wire header carries an eight-bit payload length, so RxN and TxN can
// transfer at most 255 payload words even when PAYLOAD_WORDS is larger.

// Ordinary actor frames use the checked capacity selected for this build.
pub type Frame = FrameN<MAX_PAYLOAD>;

// Decodes the fixed-width ordinary frame selected for this build.
pub fn frame_from_bits(raw: bits[bit_count<Frame>()]) -> Frame {
  Frame {
    header: header_from_bits(raw[0+:bits[frame_config::HEADER_BITS]]),
    payload: raw[frame_config::HEADER_BITS+:bits[PAYLOAD_BITS]],
  }
}

pub fn bits_from_frame(frame: Frame) -> bits[bit_count<Frame>()] {
  frame.payload ++ bits_from_header(frame.header)
}

struct RxStateN<PAYLOAD_WORDS: u32> {
  active: u1,
  header: Header,
  payload: bits[PAYLOAD_WORDS * u32:32],
  payload_words_seen: u8,
  rejected: u1,
}

// All raw receivers share this transition. Rejected packets drain to the real
// TLAST, even if their contents resemble a new header. Without termination,
// recovery requires a link reset; no finite length counter can infer a boundary.
// Beat carries complete words only: physical adapters must require TKEEP=0xf.
fn receive_step<PAYLOAD_WORDS: u32>(
    state: RxStateN<PAYLOAD_WORDS>, beat: Beat
) -> (FrameN<PAYLOAD_WORDS>, bool, RxStateN<PAYLOAD_WORDS>) {
  let (frame, valid, next_state) = if !state.active {
    let header = header_from_bits(beat.word);
    let frame = FrameN<PAYLOAD_WORDS> {
      header,
      payload: zero!<bits[PAYLOAD_WORDS * u32:32]>(),
    };
    let valid = beat.tlast && header.payload_words == u8:0;
    let rejected = header.payload_words == u8:0 ||
      header.payload_words as u32 > PAYLOAD_WORDS;
    (frame, valid, RxStateN<PAYLOAD_WORDS> {
      active: u1:1,
      header,
      rejected,
      ..zero!<RxStateN<PAYLOAD_WORDS>>()
    })
  } else {
    // Only accepted lengths enter assembly. Once rejected, both the count and
    // payload stop advancing, so arbitrarily long packets cannot wrap valid.
    let accept_word = !state.rejected &&
      state.payload_words_seen < state.header.payload_words;
    let payload = if accept_word {
      bit_slice_update(state.payload,
        state.payload_words_seen as u32 * u32:32, beat.word)
    } else { state.payload };
    let payload_words_seen = state.payload_words_seen + accept_word as u8;
    let complete = payload_words_seen == state.header.payload_words;
    let rejected = !accept_word || beat.tlast != complete;
    (FrameN<PAYLOAD_WORDS> { header: state.header, payload },
      beat.tlast && !rejected,
      RxStateN<PAYLOAD_WORDS> {
        payload, payload_words_seen, rejected, ..state
      })
  };
  let next_state = if beat.tlast {
    zero!<RxStateN<PAYLOAD_WORDS>>()
  } else { next_state };
  (frame, valid, next_state)
}

// Assembles a frame with a statically selected payload capacity, checking that
// TLAST agrees with the declared length. Rejected packets emit no Frame.
//
// TODO: Report rejection on a typed protocol-fault sideband. Its connection
// owner should close or advance the session; a distribution adapter may then
// translate that session failure for the semantic relationships it owns.
pub proc RxN<PAYLOAD_WORDS: u32> {
  axis_in: chan<Beat> in;
  instr_out: chan<FrameN<PAYLOAD_WORDS>> out;

  config(
      axis_in: chan<Beat> in,
      instr_out: chan<FrameN<PAYLOAD_WORDS>> out
  ) {
    (axis_in, instr_out)
  }

  init { zero!<RxStateN<PAYLOAD_WORDS>>() }

  next(state: RxStateN<PAYLOAD_WORDS>) {
    let (tok, beat) = recv(join(), axis_in);
    let (frame, valid, next_state) = receive_step(state, beat);
    let _done = send_if(tok, instr_out, valid, frame);
    next_state
  }
}

pub proc Rx {
  config(axis_in: chan<Beat> in, instr_out: chan<Frame> out) {
    spawn RxN<MAX_PAYLOAD>(axis_in, instr_out);
  }

  init { () }
  next(state: ()) { state }
}

struct ReservedRxState {
  admitted: u1,
  rx: RxStateN<MAX_PAYLOAD>,
}

// Receives one admission credit in its own activation before accepting the
// first beat of a frame. The consumer retains that credit until the assembled
// Frame is delivered, so a bounded mailbox reserves capacity before assembly.
// Rejected packets retain that reservation for the next valid frame; they
// neither deliver a message nor consume another credit. Reset the link and
// credit owner together when abandoning an unterminated packet.
pub proc ReservedRx {
  axis_in: chan<Beat> in;
  instr_out: chan<Frame> out;
  admission_in: chan<u1> in;

  config(axis_in: chan<Beat> in,
         instr_out: chan<Frame> out,
         admission_in: chan<u1> in) {
    (axis_in, instr_out, admission_in)
  }

  init { zero!<ReservedRxState>() }

  next(state: ReservedRxState) {
    if !state.admitted {
      let (_tok, _credit) = recv(join(), admission_in);
      ReservedRxState { admitted: u1:1, ..state }
    } else {
      let (tok, beat) = recv(join(), axis_in);
      let (frame, valid, rx) = receive_step(state.rx, beat);
      send_if(tok, instr_out, valid, frame);
      ReservedRxState { admitted: !valid, rx }
    }
  }
}

// Applies the same admission-credit contract as ReservedRx to an already
// assembled Frame. This is the natural boundary for links between generated
// actors: the receiver reserves bounded-mailbox capacity before this adapter
// transfers one complete message into the actor. Upstream Frame FIFOs may
// still form explicit bounded network or egress queues before that admission
// point.
pub proc ReservedFrame {
  frame_in: chan<Frame> in;
  frame_out: chan<Frame> out;
  admission_in: chan<u1> in;

  config(frame_in: chan<Frame> in,
         frame_out: chan<Frame> out,
         admission_in: chan<u1> in) {
    (frame_in, frame_out, admission_in)
  }

  init { u1:0 }

  next(admitted: u1) {
    if admitted {
      let (tok, frame) = recv(join(), frame_in);
      send(tok, frame_out, frame);
      u1:0
    } else {
      let (_tok, _credit) = recv(join(), admission_in);
      u1:1
    }
  }
}

// Fairly merges two atomic Frame streams. Since a Frame is transferred in one
// channel operation, arbitration has no packet lock or TLAST state. Preference
// alternates after every attempt. An empty preferred input yields the cycle
// and lets the other input go first on the next activation.
//
// XLS requires a non-blocking receive to be the only receive operation on its
// channel, even when two receive sites are in mutually exclusive branches.
// Trying the preferred input and then the other one would therefore need to
// poll both channels and retain an unselected Frame. Keep this small symmetric
// mux stateless apart from its preference bit; a generated N-way ingress can
// choose a different throughput/storage tradeoff.
pub proc FrameMux2 {
  left_in: chan<Frame> in;
  right_in: chan<Frame> in;
  frame_out: chan<Frame> out;

  config(left_in: chan<Frame> in,
         right_in: chan<Frame> in,
         frame_out: chan<Frame> out) {
    (left_in, right_in, frame_out)
  }

  init { u1:0 }

  next(prefer_right: u1) {
    let (left_tok, left, left_valid) = recv_if_non_blocking(
      join(), left_in, !prefer_right, zero!<Frame>());
    let (tok, right, right_valid) = recv_if_non_blocking(
      left_tok, right_in, prefer_right, zero!<Frame>());
    let valid = left_valid || right_valid;
    let frame = if left_valid { left } else { right };
    send_if(tok, frame_out, valid, frame);
    !prefer_right
  }
}

struct TxState {
  active: u1,
  header: Header,
  payload: bits[FRAME_BITS],
  beats_sent: u8,
}

// Serializes a checked ordinary frame as its header followed by declared payload words.
pub proc Tx {
  resp_in: chan<Frame> in;
  axis_out: chan<Beat> out;

  // The caller supplies frames whose declared payload length fits the selected capacity.
  config(resp_in: chan<Frame> in, axis_out: chan<Beat> out) {
    (resp_in, axis_out)
  }

  // Starts idle and accepts a complete frame before emitting its first beat.
  init { zero!<TxState>() }

  // Emits the header then each declared payload word; widen the bit offset before multiplication.
  next(state: TxState) {
    let (tok, state2) = if state.active {
      (join(), state)
    } else {
      let (tok1, frame) = recv(join(), resp_in);
      let payload = bits_from_frame(frame);
      let header = frame.header;
      (tok1, TxState { active: u1:1, header, payload, ..zero!<TxState>() })
    };

    let last = state2.beats_sent == state2.header.payload_words;
    send(tok, axis_out, Beat {
      tlast: last,
      word: state2.payload[u32:32 * (state2.beats_sent as u32) +: u32],
    });

    if last {
      zero!<TxState>()
    } else {
      let beats_sent = state2.beats_sent + u8:1;
      TxState { beats_sent, ..state2 }
    }
  }
}

struct TxStateN<PAYLOAD_WORDS: u32> {
  active: u1,
  frame: FrameN<PAYLOAD_WORDS>,
  beats_sent: u32,
}

// Serializes the statically selected FrameN width. Callers are responsible for
// ensuring payload_words does not exceed PAYLOAD_WORDS.
pub proc TxN<PAYLOAD_WORDS: u32> {
  resp_in: chan<FrameN<PAYLOAD_WORDS>> in;
  axis_out: chan<Beat> out;

  config(
      resp_in: chan<FrameN<PAYLOAD_WORDS>> in,
      axis_out: chan<Beat> out
  ) {
    (resp_in, axis_out)
  }

  init { zero!<TxStateN<PAYLOAD_WORDS>>() }

  next(state: TxStateN<PAYLOAD_WORDS>) {
    let (tok, state2) = if state.active {
      (join(), state)
    } else {
      let (tok1, frame) = recv(join(), resp_in);
      (tok1, TxStateN<PAYLOAD_WORDS> {
        active: u1:1,
        frame,
        ..zero!<TxStateN<PAYLOAD_WORDS>>()
      })
    };
    let last =
      state2.beats_sent == state2.frame.header.payload_words as u32;
    let word = if state2.beats_sent == u32:0 {
      bits_from_header(state2.frame.header) as u32
    } else {
      state2.frame.payload[
        u32:32 * (state2.beats_sent - u32:1) +: u32]
    };
    send(tok, axis_out, Beat { tlast: last, word });
    if last {
      zero!<TxStateN<PAYLOAD_WORDS>>()
    } else {
      let beats_sent = state2.beats_sent + u32:1;
      TxStateN<PAYLOAD_WORDS> { beats_sent, ..state2 }
    }
  }
}

// Exercises the ordinary alias at the selected capacity, including word offsets above u8.
#[test_proc]
proc OrdinaryCapacityRoundTripTest {
  terminator: chan<bool> out;
  frame_out: chan<Frame> out;
  frame_in: chan<Frame> in;

  // Connects the ordinary transmitter and receiver through a bounded beat channel.
  config(terminator: chan<bool> out) {
    let (frame_p, frame_c) = chan<Frame, u32:1>("ordinary_capacity_frame");
    let (beat_p, beat_c) = chan<Beat, u32:1>("ordinary_capacity_beat");
    let (received_p, received_c) = chan<Frame, u32:1>("ordinary_capacity_received");
    spawn Tx(frame_c, beat_p);
    spawn Rx(beat_c, received_p);
    (terminator, frame_p, received_c)
  }

  // One complete round trip supplies the termination witness.
  init { () }

  // Distinct word values expose any truncation or wrapping in the selected-width path.
  next(state: ()) {
    let payload = for (i, payload): (u32, bits[PAYLOAD_BITS]) in u32:0..MAX_PAYLOAD {
      bit_slice_update(payload, i * u32:32, i + u32:1)
    } (zero!<bits[PAYLOAD_BITS]>());
    let expected = Frame {
      header: Header { payload_words: MAX_PAYLOAD as u8, txid: u8:23,
        flags: u8:42, op: u8:99 }, payload,
    };
    let sent_tok = send(join(), frame_out, expected);
    let (received_tok, actual) = recv(sent_tok, frame_in);
    assert_eq(actual, expected);
    let _done = send(received_tok, terminator, true);
    state
  }
}

#[test_proc]
proc FrameN9RoundTripTest {
  terminator: chan<bool> out;
  frame_out: chan<FrameN<u32:9>> out;
  frame_in: chan<FrameN<u32:9>> in;

  config(terminator: chan<bool> out) {
    let (frame_p, frame_c) =
      chan<FrameN<u32:9>, u32:1>("frame_nine_test_frame");
    let (beat_p, beat_c) =
      chan<Beat, u32:1>("frame_nine_test_beat");
    let (received_p, received_c) =
      chan<FrameN<u32:9>, u32:1>("frame_nine_test_received");
    spawn TxN<u32:9>(frame_c, beat_p);
    spawn RxN<u32:9>(beat_c, received_p);
    (terminator, frame_p, received_c)
  }

  init { () }

  next(state: ()) {
    let expected = FrameN<u32:9> {
      header: Header {
        payload_words: u8:9,
        txid: u8:23,
        flags: u8:42,
        op: u8:99,
      },
      payload:
        u32:9 ++ u32:8 ++ u32:7 ++ u32:6 ++ u32:5 ++
        u32:4 ++ u32:3 ++ u32:2 ++ u32:1,
    };
    let sent_tok = send(join(), frame_out, expected);
    let (received_tok, actual) = recv(sent_tok, frame_in);
    assert_eq(actual, expected);
    let _done = send(received_tok, terminator, true);
    state
  }
}

#[test_proc]
proc RxNRejectsMalformedAndResynchronizesTest {
  terminator: chan<bool> out;
  beat_out: chan<Beat> out;
  frame_in: chan<FrameN<u32:2>> in;

  config(terminator: chan<bool> out) {
    let (beat_p, beat_c) =
      chan<Beat, u32:1>("rx_n_reject_test_beat");
    let (frame_p, frame_c) =
      chan<FrameN<u32:2>, u32:1>("rx_n_reject_test_frame");
    spawn RxN<u32:2>(beat_c, frame_p);
    (terminator, beat_p, frame_c)
  }

  init { () }

  next(state: ()) {
    let malformed_header = Header {
      payload_words: u8:2,
      op: u8:17,
      ..zero!<Header>()
    };
    let valid_header = Header {
      payload_words: u8:1,
      op: u8:23,
      ..zero!<Header>()
    };
    let tok_0 = send(join(), beat_out, Beat {
      tlast: u1:0,
      word: bits_from_header(malformed_header) as u32,
    });
    let tok_1 = send(tok_0, beat_out, Beat {
      tlast: u1:1,
      word: u32:0xaaaaaaaa,
    });
    let tok_2 = send(tok_1, beat_out, Beat {
      tlast: u1:0,
      word: bits_from_header(valid_header) as u32,
    });
    let tok_3 = send(tok_2, beat_out, Beat {
      tlast: u1:1,
      word: u32:0x12345678,
    });
    let (received_tok, actual) = recv(tok_3, frame_in);
    let expected = FrameN<u32:2> {
      header: valid_header,
      payload: u32:0 ++ u32:0x12345678,
    };
    assert_eq(actual, expected);
    let _done = send(received_tok, terminator, true);
    state
  }
}

// Packs a numeric payload only when its width fits the selected ordinary capacity.
pub fn pack<N: u32>(op: u8, payload: bits[N]) -> Frame {
  const_assert!(N <= PAYLOAD_BITS);
  let payload_words = ((N + u32:31) / u32:32) as u8;
  Frame {
    header: Header { op, payload_words, ..zero!<Header>() },
    payload: payload as bits[PAYLOAD_BITS]
  }
}

// A sub-word payload retains its exact low bits and receives a complete word length.
#[test]
fn densely_packed_payload() {
  let frame = pack(u8:7, uN[13]:0x1abc);
  assert_eq(frame.header.payload_words, u8:1);
  assert_eq(frame.payload, bits[PAYLOAD_BITS]:0x1abc);
  assert_eq(pack(u8:7, bits[0]:0).header.payload_words, u8:0);
}

#[test]
fn receive_length_matrix() {
  // All early, exact, late, empty and oversized combinations near capacity.
  for (declared, ()): (u32, ()) in u32:0..u32:6 {
    for (actual, ()): (u32, ()) in u32:0..u32:6 {
      let header = Header {
        payload_words: declared as u8, txid: u8:19,
        flags: u8:42, op: u8:7,
      };
      let (frame, valid, state) = receive_step(zero!<RxStateN<u32:3>>(),
        Beat { tlast: actual == u32:0, word: bits_from_header(header) });
      assert_eq(valid, actual == u32:0 && declared == u32:0);
      let (frame, valid, state) = for (i, acc):
          (u32, (FrameN<u32:3>, bool, RxStateN<u32:3>)) in u32:0..u32:5 {
        if i < actual {
          let next = receive_step(acc.2,
            Beat { tlast: i + u32:1 == actual, word: i + u32:1 });
          assert_eq(next.1,
            i + u32:1 == actual && actual == declared && actual <= u32:3);
          next
        } else { acc }
      }((frame, valid, state));
      assert_eq(valid, actual == declared && actual <= u32:3);
      assert_eq(state, zero!<RxStateN<u32:3>>());
      if valid {
        assert_eq(frame.header, header);
        let expected = match actual {
          u32:0 => bits[96]:0,
          u32:1 => u32:0 ++ u32:0 ++ u32:1,
          u32:2 => u32:0 ++ u32:2 ++ u32:1,
          _ => u32:3 ++ u32:2 ++ u32:1,
        };
        assert_eq(frame.payload, expected);
      } else { () }
    }(())
  }(())
}

#[test]
fn receive_wire_limit_and_empty_capacity() {
  let header = Header { payload_words: u8:255, ..zero!<Header>() };
  let (_, valid, state) = receive_step(zero!<RxStateN<u32:255>>(),
    Beat { tlast: false, word: bits_from_header(header) });
  assert_eq(valid, false);
  let (frame, valid, state) = for (i, (_, _, state)):
      (u32, (FrameN<u32:255>, bool, RxStateN<u32:255>)) in u32:0..u32:255 {
    receive_step(state, Beat { tlast: i == u32:254, word: i + u32:1 })
  }((zero!<FrameN<u32:255>>(), false, state));
  assert_eq(valid, true);
  assert_eq(state, zero!<RxStateN<u32:255>>());
  for (i, ()): (u32, ()) in u32:0..u32:255 {
    assert_eq(frame.payload[i * u32:32 +: u32], i + u32:1)
  }(());
  let (frame, valid, state) = receive_step(zero!<RxStateN<u32:0>>(),
    Beat { tlast: true, word: u32:0 });
  assert_eq(valid, true);
  assert_eq(frame, zero!<FrameN<u32:0>>());
  assert_eq(state, zero!<RxStateN<u32:0>>());
}
