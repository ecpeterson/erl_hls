// Transport-neutral debug monitor prototype written in DSLX.
//
// A small RTL tap supplies one observation per cycle without feeding ready
// back into the application datapath. Observer and DebugServer are lowered
// separately, so slower debug response serialization does not reduce the
// observer's one-sample-per-cycle schedule.

const DEBUG_GET_COUNTERS = u8:0x01;
const DEBUG_GET_STATE = u8:0x02;
const DEBUG_GET_TRACE = u8:0x03;
const DEBUG_COUNTERS = u8:0x81;
const DEBUG_STATE = u8:0x82;
const DEBUG_TRACE = u8:0x83;
const DEBUG_ERROR = u8:0xff;

const DEBUG_VERSION = u32:3;
const STATE_VERSION = u32:1;
const TRACE_VERSION = u32:1;
const COUNTER_WORDS = u8:8;
const STATE_WORDS = u8:16;
const STATE_REPLY_WORDS = STATE_WORDS + u8:1;
const TRACE_RECORD_WORDS = u8:2;
const TRACE_METADATA_WORDS = u8:5;
const TRACE_CAPACITY = u4:8;

const TRACE_APP_RX = u8:1;
const TRACE_APP_TX = u8:2;

const RESPONSE_COUNTERS = u2:0;
const RESPONSE_STATE = u2:1;
const RESPONSE_TRACE = u2:2;
const RESPONSE_ERROR = u2:3;

// Observation layout, least-significant bit first:
//   RX valid/ready/last, TX valid/ready/last, committed-state valid,
//   RX data, TX data, tap drop count, committed-state data.
const OBSERVATION_BITS = u32:615;

struct Beat {
  keep: u4,
  tlast: u1,
  word: u32,
}

// This is deliberately a small, versioned event envelope, not an attempt to
// encode the ERTS trace protocol. Later versions can add trace-token and
// distribution context without changing how the buffer is drained.
struct TraceEvent {
  cycle: u32,
  kind: u8,
  flags: u8,
  txid: u8,
  op: u8,
}

struct TraceBuffer {
  data: bits[512],
  count: u4,
  drops: u32,
}

fn trace_event_metadata(event: TraceEvent) -> u32 {
  ((event.kind as u32) << u32:24) |
  ((event.flags as u32) << u32:16) |
  ((event.txid as u32) << u32:8) |
  event.op as u32
}

struct MonitorState {
  cycles: u32,
  app_rx_beats: u32,
  app_rx_frames: u32,
  app_rx_stall_cycles: u32,
  app_tx_beats: u32,
  app_tx_frames: u32,
  app_tx_stall_cycles: u32,
  tap_drops: u32,
  committed_state: bits[512],
  app_rx_in_frame: u1,
  app_tx_in_frame: u1,
  trace: TraceBuffer,
}

fn append_trace(trace: TraceBuffer, event: TraceEvent, enabled: u1)
    -> TraceBuffer {
  if !enabled {
    trace
  } else if trace.count == TRACE_CAPACITY {
    TraceBuffer { drops: trace.drops + u32:1, ..trace }
  } else {
    let event_bits = ((trace_event_metadata(event) as u64) << u64:32) |
      event.cycle as u64;
    TraceBuffer {
      data: bit_slice_update(
        trace.data, (trace.count as u32) * u32:64, event_bits
      ),
      count: trace.count + u4:1,
      ..trace
    }
  }
}

fn next_in_frame(in_frame: u1, valid: u1, ready: u1, tlast: u1) -> u1 {
  if valid && ready { !tlast } else { in_frame }
}

fn apply_observation(state: MonitorState, raw: bits[OBSERVATION_BITS])
    -> MonitorState {
  let app_rx_valid = raw[0:1];
  let app_rx_ready = raw[1:2];
  let app_rx_last = raw[2:3];
  let app_tx_valid = raw[3:4];
  let app_tx_ready = raw[4:5];
  let app_tx_last = raw[5:6];
  let app_state_valid = raw[6:7];
  let app_rx_data = raw[7:39];
  let app_tx_data = raw[39:71];
  let tap_drops = raw[71:103];
  let app_state_data = raw[103:615];
  let app_rx_accepted = app_rx_valid && app_rx_ready;
  let app_tx_accepted = app_tx_valid && app_tx_ready;
  let cycle = state.cycles + u32:1;
  let rx_event = TraceEvent {
    cycle,
    kind: TRACE_APP_RX,
    flags: app_rx_last as u8,
    txid: app_rx_data[8:16],
    op: app_rx_data[24:32],
  };
  let tx_event = TraceEvent {
    cycle,
    kind: TRACE_APP_TX,
    flags: app_tx_last as u8,
    txid: app_tx_data[8:16],
    op: app_tx_data[24:32],
  };
  let after_rx = append_trace(
    state.trace, rx_event, app_rx_accepted && !state.app_rx_in_frame
  );
  let after_tx = append_trace(
    after_rx, tx_event, app_tx_accepted && !state.app_tx_in_frame
  );

  MonitorState {
    cycles: cycle,
    app_rx_beats: state.app_rx_beats +
      app_rx_accepted as u32,
    app_rx_frames: state.app_rx_frames +
      (app_rx_accepted && app_rx_last) as u32,
    app_rx_stall_cycles: state.app_rx_stall_cycles +
      (app_rx_valid && !app_rx_ready) as u32,
    app_tx_beats: state.app_tx_beats +
      app_tx_accepted as u32,
    app_tx_frames: state.app_tx_frames +
      (app_tx_accepted && app_tx_last) as u32,
    app_tx_stall_cycles: state.app_tx_stall_cycles +
      (app_tx_valid && !app_tx_ready) as u32,
    tap_drops,
    committed_state: if app_state_valid {
      app_state_data
    } else {
      state.committed_state
    },
    app_rx_in_frame: next_in_frame(
      state.app_rx_in_frame, app_rx_valid, app_rx_ready, app_rx_last
    ),
    app_tx_in_frame: next_in_frame(
      state.app_tx_in_frame, app_tx_valid, app_tx_ready, app_tx_last
    ),
    trace: after_tx,
  }
}

proc Observer {
  observation_in: chan<bits[OBSERVATION_BITS]> in;
  snapshot_request_in: chan<u8> in;
  snapshot_out: chan<MonitorState> out;

  config(
      observation_in: chan<bits[OBSERVATION_BITS]> in,
      snapshot_request_in: chan<u8> in,
      snapshot_out: chan<MonitorState> out
  ) {
    (observation_in, snapshot_request_in, snapshot_out)
  }

  init { zero!<MonitorState>() }

  next(state: MonitorState) {
    let (tok1, raw) = recv(join(), observation_in);
    let observed = apply_observation(state, raw);
    let (tok2, request, requested) = recv_non_blocking(
      tok1, snapshot_request_in, u8:0
    );
    send_if(tok2, snapshot_out, requested, observed);
    if requested && request == DEBUG_GET_TRACE {
      MonitorState { trace: zero!<TraceBuffer>(), ..observed }
    } else {
      observed
    }
  }
}

struct DebugState {
  active: u1,
  response_kind: u2,
  response_words: u8,
  response_index: u8,
  txid: u8,
  snapshot: MonitorState,
}

fn response_tag(state: DebugState) -> u8 {
  match state.response_kind {
    RESPONSE_COUNTERS => DEBUG_COUNTERS,
    RESPONSE_STATE => DEBUG_STATE,
    RESPONSE_TRACE => DEBUG_TRACE,
    _ => DEBUG_ERROR,
  }
}

fn response_trace_payload(state: DebugState) -> u32 {
  let payload_index = state.response_index - u8:1;
  match payload_index {
    u8:0 => TRACE_VERSION,
    u8:1 => TRACE_RECORD_WORDS as u32,
    u8:2 => state.snapshot.trace.count as u32,
    u8:3 => state.snapshot.trace.drops,
    u8:4 => state.snapshot.tap_drops,
    _ => {
      let event_word_index = (payload_index as u32) - u32:5;
      state.snapshot.trace.data[event_word_index * u32:32 +: u32]
    },
  }
}

fn response_payload(state: DebugState) -> u32 {
  match state.response_kind {
    RESPONSE_COUNTERS => match state.response_index {
      u8:1 => DEBUG_VERSION,
      u8:2 => state.snapshot.cycles,
      u8:3 => state.snapshot.app_rx_beats,
      u8:4 => state.snapshot.app_rx_frames,
      u8:5 => state.snapshot.app_rx_stall_cycles,
      u8:6 => state.snapshot.app_tx_beats,
      u8:7 => state.snapshot.app_tx_frames,
      u8:8 => state.snapshot.app_tx_stall_cycles,
      _ => u32:0,
    },
    RESPONSE_STATE => if state.response_index == u8:1 {
      STATE_VERSION
    } else {
      state.snapshot.committed_state[
        ((state.response_index as u32) - u32:2) * u32:32 +: u32
      ]
    },
    RESPONSE_TRACE => response_trace_payload(state),
    _ => u32:1,
  }
}

fn response_beat(state: DebugState) -> Beat {
  let word = if state.response_index == u8:0 {
    ((response_tag(state) as u32) << u32:24) |
    ((state.txid as u32) << u32:8) |
    state.response_words as u32
  } else {
    response_payload(state)
  };
  Beat {
    keep: u4:0xf,
    tlast: state.response_index == state.response_words,
    word,
  }
}

proc DebugServer {
  request_in: chan<Beat> in;
  response_out: chan<Beat> out;
  snapshot_request_out: chan<u8> out;
  snapshot_in: chan<MonitorState> in;

  config(
      request_in: chan<Beat> in,
      response_out: chan<Beat> out,
      snapshot_request_out: chan<u8> out,
      snapshot_in: chan<MonitorState> in
  ) {
    (request_in, response_out, snapshot_request_out, snapshot_in)
  }

  init { zero!<DebugState>() }

  next(state: DebugState) {
    let (tok1, response) = if state.active {
      (join(), state)
    } else {
      let (tok_request, request) = recv(join(), request_in);
      let op = request.word[24:32];
      let valid_empty_request =
        request.keep == u4:0xf &&
        request.tlast &&
        request.word[0:8] == u8:0;
      let response_kind = if valid_empty_request && op == DEBUG_GET_COUNTERS {
        RESPONSE_COUNTERS
      } else if valid_empty_request && op == DEBUG_GET_STATE {
        RESPONSE_STATE
      } else if valid_empty_request && op == DEBUG_GET_TRACE {
        RESPONSE_TRACE
      } else {
        RESPONSE_ERROR
      };
      let snapshot_op = if response_kind == RESPONSE_TRACE {
        DEBUG_GET_TRACE
      } else {
        u8:0
      };
      let tok_snapshot_request = send(
        tok_request, snapshot_request_out, snapshot_op
      );
      let (tok_snapshot, snapshot) = recv(tok_snapshot_request, snapshot_in);
      let response_words = match response_kind {
        RESPONSE_COUNTERS => COUNTER_WORDS,
        RESPONSE_STATE => STATE_REPLY_WORDS,
        RESPONSE_TRACE => TRACE_METADATA_WORDS +
          ((snapshot.trace.count as u8) * TRACE_RECORD_WORDS),
        _ => u8:1,
      };
      (tok_snapshot, DebugState {
        active: u1:1,
        response_kind,
        response_words,
        response_index: u8:0,
        txid: request.word[8:16],
        snapshot,
      })
    };

    let beat = response_beat(response);
    send(tok1, response_out, beat);

    if beat.tlast {
      zero!<DebugState>()
    } else {
      DebugState {
        response_index: response.response_index + u8:1,
        ..response
      }
    }
  }
}
