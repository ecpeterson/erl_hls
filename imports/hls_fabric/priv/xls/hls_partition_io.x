// Word-aligned routed application boundary. Four u64 identity parameters
// avoid the pinned XLS converter's u64 limit for each parametric value.
// Attach is single-use until coordinated reset. Invalid traffic poisons control and reports one fault;
// neither a write receipt nor attachment acknowledges actor execution.
import axis;
import hls_spatial_router;

// Fixed external-event endpoint allocation shared with hls_partition_wire.
const FIRST_EVENT_ENDPOINT = u16:8;

// Partial routed input, plus the gateway's single-use attachment/fault state.
pub struct ReceiveState {
  stage: u2,
  header: axis::Header,
  payload: bits[256],
  seen: u4,
  bad: bool,
  attached: bool,
  start_requested: bool,
  poisoned: bool,
}

// Read the explicit word ABI, independent of DSLX's aggregate bit ordering.
fn spatial(payload: bits[256]) -> hls_spatial_router::SpatialFrame {
  hls_spatial_router::SpatialFrame {
    rectangle: hls_spatial_router::Rectangle {
      x0: payload[0+:u16], y0: payload[16+:u16],
      x1: payload[32+:u16], y1: payload[48+:u16],
    },
    target: payload[64+:u2],
    frame: axis::Frame {
      header: axis::header_from_bits(payload[96+:u32]),
      payload: payload[128+:bits[96]],
    },
  }
}

// Accept only complete frames from this binding. Rejection drains to TLAST,
// including overlong packets; saturating assembly cannot wrap back to valid.
pub fn receive_ordered_step(
    state: ReceiveState, beat: axis::Beat, identity: bits[256], host: u16, service: u16,
    explicit_start: bool
) -> (ReceiveState, bool, bool, bool, bool, hls_spatial_router::SpatialFrame) {
  let next = match state.stage {
    u2:0 => ReceiveState { stage: u2:1,
      bad: beat.word != (host ++ service), ..state },
    u2:1 => {
      let header = axis::header_from_bits(beat.word);
      ReceiveState { stage: u2:2, header,
        bad: state.bad || header.payload_words == u8:0 || header.payload_words > u8:8 ||
          header.flags != u8:0 || header.txid != u8:0,
        ..state }
    },
    _ => {
      let accept = !state.bad && state.seen < u4:8;
      let payload = if accept {
        bit_slice_update(state.payload, state.seen as u32 * u32:32, beat.word)
      } else { state.payload };
      let seen = state.seen + accept as u4;
      ReceiveState { payload, seen,
        bad: state.bad || !accept || beat.tlast != (seen as u8 == state.header.payload_words),
        ..state }
    },
  };
  let frame = spatial(next.payload);
  let complete = beat.tlast && state.stage == u2:2 && !next.bad && !state.poisoned;
  let attach = complete && !state.attached && state.header.op == u8:1 &&
    state.header.payload_words == u8:8 && next.payload == identity;
  let words = frame.frame.header.payload_words;
  let control = complete && state.attached && state.header.op == u8:2 &&
    state.header.payload_words >= u8:4 && state.header.payload_words <= u8:7 &&
    words == state.header.payload_words - u8:4 &&
    frame.frame.header.flags == u8:0 && frame.frame.header.txid == u8:0 &&
    next.payload[66+:bits[30]] == bits[30]:0 &&
    frame.rectangle.x0 <= frame.rectangle.x1 && frame.rectangle.y0 <= frame.rectangle.y1;
  let start = complete && explicit_start && state.attached && !state.start_requested &&
    state.header.op == u8:3 && state.header.payload_words == u8:1 && next.payload == bits[256]:0;
  let fault = beat.tlast && !state.poisoned && !(attach || control || start);
  let next = if beat.tlast {
    ReceiveState { attached: state.attached || attach,
      start_requested: state.start_requested || start,
      poisoned: state.poisoned || fault, ..zero!<ReceiveState>() }
  } else { next };
  (next, attach, control, start, fault, frame)
}

// Automatic-activation gateways reject start; their existing command ABI is unchanged.
pub fn receive_step(
    state: ReceiveState, beat: axis::Beat, identity: bits[256], host: u16, service: u16
) -> (ReceiveState, bool, bool, bool, hls_spatial_router::SpatialFrame) {
  let (next, attach, control, _, fault, frame) = receive_ordered_step(state, beat, identity, host, service, false);
  (next, attach, control, fault, frame)
}

// Pack the one management response emitted at attach or protocol failure.
pub fn response(attach: bool, identity: bits[256]) -> axis::FrameN<u32:8> {
  axis::FrameN<u32:8> {
    header: axis::Header { op: if attach { u8:0x81 } else { u8:0xff },
      payload_words: if attach { u8:8 } else { u8:1 }, ..zero!<axis::Header>() },
    payload: if attach { identity } else { bits[256]:1 },
  }
}

// The graph receives one ordered SpatialFrame stream for every control target.
pub proc Receive<ID0: u64, ID1: u64, ID2: u64, ID3: u64, HOST: u16, SERVICE: u16> {
  input: chan<axis::Beat> in;
  control: chan<hls_spatial_router::SpatialFrame> out;
  management: chan<axis::FrameN<u32:8>> out;
  config(input: chan<axis::Beat> in,
      control: chan<hls_spatial_router::SpatialFrame> out,
      management: chan<axis::FrameN<u32:8>> out) { (input, control, management) }
  init { zero!<ReceiveState>() }
  next(state: ReceiveState) {
    let (tok, beat) = recv(join(), input);
    let (state, attach, valid, fault, command) = receive_step(state, beat, ID3 ++ ID2 ++ ID1 ++ ID0, HOST, SERVICE);
    let tok = send_if(tok, control, valid, command);
    let _done = send_if(tok, management, attach || fault, response(attach, ID3 ++ ID2 ++ ID1 ++ ID0));
    state
  }
}

// One selected output packet and the fair external-stream polling cursor.
pub struct TransmitState {
  started: bool,
  sending: bool,
  cursor: u32,
  source: u16,
  frame: axis::FrameN<u32:8>,
  index: u4,
}

// Select a word from the retained frame without changing its wire ABI.
pub fn transmit_beat(state: TransmitState, host: u16) -> axis::Beat {
  let word = match state.index {
    u4:0 => state.source ++ host,
    u4:1 => axis::bits_from_header(state.frame.header),
    _ => state.frame.payload[(state.index as u32 - u32:2)*u32:32+:u32],
  };
  axis::Beat { word, tlast: state.index as u8 == state.frame.header.payload_words + u8:1 }
}

// Advance only after the current word is accepted; attach releases ordinary events.
pub fn transmitted(state: TransmitState, service: u16) -> TransmitState {
  let last = state.index as u8 == state.frame.header.payload_words + u8:1;
  let started = if last && state.source == service {
    match state.frame.header.op {
      u8:0x81 => true,
      u8:0xff => false,
      _ => state.started,
    }
  } else { state.started };
  TransmitState { started, sending: !last, index: state.index + u4:1, ..state }
}

// Fair frame arbitration retains a packet through its accepted final beat.
// The attachment acknowledgment precedes all external packets on the wire.
pub proc Transmit<N: u32, HOST: u16, SERVICE: u16> {
  management: chan<axis::FrameN<u32:8>> in;
  events: chan<axis::Frame>[N] in;
  output: chan<axis::Beat> out;
  config(management: chan<axis::FrameN<u32:8>> in,
      events: chan<axis::Frame>[N] in, output: chan<axis::Beat> out) {
    (management, events, output)
  }
  init { zero!<TransmitState>() }
  next(state: TransmitState) {
    if !state.sending {
      let (tok, reply, reply_valid) = recv_if_non_blocking(join(), management,
        !state.started || state.cursor == N, zero!<axis::FrameN<u32:8>>());
      let (_, frame, source, valid) = unroll_for! (i, acc):
          (u32, (token, axis::FrameN<u32:8>, u16, bool)) in u32:0..N {
        let (tok, event, valid) = recv_if_non_blocking(acc.0, events[i],
          state.started && state.cursor == i, zero!<axis::Frame>());
        (tok, if valid { axis::FrameN<u32:8> {
          header: event.header, payload: event.payload as bits[256],
        } } else { acc.1 }, if valid { FIRST_EVENT_ENDPOINT + i as u16 } else { acc.2 }, valid || acc.3)
      }((tok, reply, SERVICE, reply_valid));
      TransmitState { frame, source, sending: valid, index: u4:0,
        cursor: if state.cursor == N { u32:0 } else { state.cursor + u32:1 }, ..state }
    } else {
      let _done = send(join(), output, transmit_beat(state, HOST));
      transmitted(state, SERVICE)
    }
  }
}

// A deployment supplies constants and connects graph ports; all protocol
// state lives here rather than in generated source or a testbench.
pub proc Boundary<N: u32, ID0: u64, ID1: u64, ID2: u64, ID3: u64, HOST: u16, SERVICE: u16> {
  config(input: chan<axis::Beat> in, output: chan<axis::Beat> out,
      control: chan<hls_spatial_router::SpatialFrame> out, events: chan<axis::Frame>[N] in) {
    let (management_p, management_c) = chan<axis::FrameN<u32:8>, u32:1>("management");
    spawn Receive<ID0, ID1, ID2, ID3, HOST, SERVICE>(input, control, management_p);
    spawn Transmit<N, HOST, SERVICE>(management_c, events, output);
    ()
  }
  init { () }
  next(state: ()) { state }
}

// One ordered output carries setup and start, so separate channel buffering
// cannot let activation overtake an earlier rectangle command.
pub struct OrderedCommand {
  start: bool,
  frame: hls_spatial_router::SpatialFrame,
}

// Start acknowledgment follows the downstream activation handshake, not send
// admission. Reset cancels partial input, queued start and any pending reply.
pub proc ReceiveOrdered<ID0: u64, ID1: u64, ID2: u64, ID3: u64, HOST: u16, SERVICE: u16> {
  input: chan<axis::Beat> in;
  commands: chan<OrderedCommand> out;
  started: chan<bool> in;
  management: chan<axis::FrameN<u32:8>> out;
  // The started channel must acknowledge actual application activation.
  config(input: chan<axis::Beat> in, commands: chan<OrderedCommand> out,
      started: chan<bool> in, management: chan<axis::FrameN<u32:8>> out) {
    (input, commands, started, management)
  }
  // Reset requires fresh attachment and cancels a pending completion wait.
  init { (zero!<ReceiveState>(), false) }
  // Completion waits in a separate activation so output acceptance and its
  // returned acknowledgment do not form a same-activation scheduling cycle.
  next(state: (ReceiveState, bool)) {
    let identity = ID3 ++ ID2 ++ ID1 ++ ID0;
    let waiting = state.1;
    let (tok, beat) = recv_if(join(), input, !waiting, zero!<axis::Beat>());
    let (tok, accepted) = recv_if(tok, started, waiting, false);
    let (parsed, attach, valid, start, fault, frame) = receive_ordered_step(state.0, beat, identity, HOST, SERVICE, true);
    let tok = send_if(tok, commands, !waiting && (valid || start), OrderedCommand { start, frame });
    let reply = if waiting && accepted {
      axis::FrameN<u32:8> { header: axis::Header {
        op: u8:0x83, payload_words: u8:1, ..zero!<axis::Header>() }, payload: bits[256]:0 }
    } else { response(!waiting && attach, identity) };
    let _done = send_if(tok, management, waiting || attach || fault, reply);
    if waiting {
      (ReceiveState { poisoned: state.0.poisoned || !accepted, ..state.0 }, false)
    } else { (parsed, start) }
  }
}

// Reuse attachment, framing and fair event serialization for an explicitly
// activated network. The external command bridge owns the activation barrier.
pub proc OrderedBoundary<N: u32, ID0: u64, ID1: u64, ID2: u64, ID3: u64, HOST: u16, SERVICE: u16> {
  // Connect one ordered command stream and a completion channel from the network.
  config(input: chan<axis::Beat> in, output: chan<axis::Beat> out,
      commands: chan<OrderedCommand> out, started: chan<bool> in,
      events: chan<axis::Frame>[N] in) {
    let (management_p, management_c) = chan<axis::FrameN<u32:8>, u32:1>("management");
    spawn ReceiveOrdered<ID0, ID1, ID2, ID3, HOST, SERVICE>(input, commands, started, management_p);
    spawn Transmit<N, HOST, SERVICE>(management_c, events, output);
    ()
  }
  // All protocol state belongs to the shared receiver and transmitter.
  init { () }
  // The structural wrapper has no independent activation or packet state.
  next(state: ()) { state }
}
