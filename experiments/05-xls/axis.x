// axis.x
//
//  + make Beat parametric in width
//  + parametrize over max message size

const MAX_PAYLOAD = u32:3;
const PAYLOAD_BITS = MAX_PAYLOAD * 32;
const FRAME_BITS = PAYLOAD_BITS + 32;

pub struct Beat {
  tlast: u1,
  word: u32,
}

pub struct Header {
  payload_words: u8,
  txid: u8,
  flags: u8,
  op: u8,
}

// bridge.erl@167: {<<1,10,0,4>>,<<210,4,0,0>>}
fn header_from_bits(raw: bits[bit_count<Header>()]) -> Header {
  Header {
    payload_words: raw[0:8],
    txid: raw[8:16],
    flags: raw[16:24],
    op: raw[24:32],
  }
}

fn bits_from_header(header: Header) -> bits[bit_count<Header>()] {
  header.op ++ header.flags ++ header.txid ++ header.payload_words
}

pub struct Frame {
  header: Header,
  payload: bits[PAYLOAD_BITS],
}

fn frame_from_bits(raw: bits[bit_count<Frame>()]) -> Frame {
  Frame {
    header: header_from_bits(raw[0:32]),
    payload: raw[32:],
  }
}

fn bits_from_frame(frame: Frame) -> bits[bit_count<Frame>()] {
  frame.payload ++ bits_from_header(frame.header)
}

struct RxState {
  payload: bits[FRAME_BITS],
  words_seen: u8,
}

pub proc Rx {
  axis_in: chan<Beat> in;
  instr_out: chan<Frame> out;

  config(axis_in: chan<Beat> in, instr_out: chan<Frame> out) {
    (axis_in, instr_out)
  }

  init { zero!<RxState>() }

  next(state: RxState) {
    let (tok, beat) = recv(join(), axis_in);
    let payload = bit_slice_update(state.payload, state.words_seen * 32, beat.word);
    let words_seen = state.words_seen + u8:1;

    if beat.tlast {
      send(tok, instr_out, frame_from_bits(payload));
      zero!<RxState>()
    } else {
      RxState { payload, words_seen }
    }
  }
}

struct ReservedRxState {
  admitted: u1,
  rx: RxState,
}

// Receives one admission credit in its own activation before accepting the
// first beat of a frame. The consumer retains that credit until the assembled
// Frame is delivered, so a bounded mailbox reserves capacity before assembly.
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
      let payload = bit_slice_update(
        state.rx.payload, state.rx.words_seen * 32, beat.word);
      let words_seen = state.rx.words_seen + u8:1;

      if beat.tlast {
        send(tok, instr_out, frame_from_bits(payload));
        zero!<ReservedRxState>()
      } else {
        let rx = RxState { payload, words_seen };
        ReservedRxState { rx, ..state }
      }
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
// and lets the other input go first on the next activation. This keeps one
// non-blocking receive operation per channel, as required by XLS lowering.
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

pub proc Tx {
  resp_in: chan<Frame> in;
  axis_out: chan<Beat> out;

  config(resp_in: chan<Frame> in, axis_out: chan<Beat> out) {
    (resp_in, axis_out)
  }

  init { zero!<TxState>() }

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
      word: state2.payload[32 * state2.beats_sent +: u32],
    });

    if last {
      zero!<TxState>()
    } else {
      let beats_sent = state2.beats_sent + u8:1;
      TxState { beats_sent, ..state2 }
    }
  }
}

pub fn pack<N: u32>(op: u8, payload: bits[N]) -> Frame {
  let payload_words = (N / 32) as u8;
  Frame {
    header: Header { op, payload_words, ..zero!<Header>() },
    payload: payload as bits[PAYLOAD_BITS]
  }
}
