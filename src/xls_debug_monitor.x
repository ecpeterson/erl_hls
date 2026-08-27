// Transport-neutral debug monitor prototype written in DSLX.
//
// A small RTL tap supplies one observation per cycle without feeding ready
// back into the application datapath. Observer and DebugServer are lowered
// separately, so slower debug response serialization does not reduce the
// observer's one-sample-per-cycle schedule.

import std;

// Requests and replies occupy separate wire namespaces and travel on opposite
// channels. Keeping their types distinct catches accidental direction swaps;
// it does not assume any particular future fan-in or fan-out topology.
enum RequestTag : u8 {
    NONE = 0x00,
    GET_COUNTERS = 0x01,
    GET_STATE = 0x02,
    GET_TRACE = 0x03,
}

enum ReplyTag : u8 {
    // Allows zero!<DebugState>(); an active response never emits this value.
    NONE = 0x00,
    COUNTERS = 0x81,
    STATE = 0x82,
    TRACE = 0x83,
    ERROR = 0xff,
}

enum TraceKind : u8 {
    NONE = 0,
    APPLICATION_RX = 1,
    APPLICATION_TX = 2,
}

const DEBUG_VERSION = u32:3;
const STATE_VERSION = u32:1;
const TRACE_VERSION = u32:1;
const APPLICATION_STATE_BITS = u32:512;
const TRACE_DEPTH = u32:8;
const TRACE_COUNT_BITS = std::clog2(TRACE_DEPTH + u32:1);

type TraceCount = uN[TRACE_COUNT_BITS];

struct Beat { keep: u4, tlast: u1, word: u32 }

struct StreamObservation { data: u32, tlast: u1, ready: u1, valid: u1 }

struct Observation {
    committed_state: bits[APPLICATION_STATE_BITS],
    tap_drops: u32,
    tx: StreamObservation,
    rx: StreamObservation,
    state_valid: u1,
}

// This is deliberately a small, versioned event envelope, not an attempt to
// encode the ERTS trace protocol. Later versions can add trace-token and
// distribution context without changing how the buffer is drained.
struct TraceMetadata { kind: TraceKind, flags: u8, txid: u8, op: u8 }

struct TraceEvent { cycle: u32, metadata: TraceMetadata }

struct TraceBuffer { events: TraceEvent[TRACE_DEPTH], count: TraceCount, drops: u32 }

struct Counters {
    cycles: u32,
    app_rx_beats: u32,
    app_rx_frames: u32,
    app_rx_stall_cycles: u32,
    app_tx_beats: u32,
    app_tx_frames: u32,
    app_tx_stall_cycles: u32,
}

struct TraceReplyHeader {
    version: u32,
    record_words: u32,
    count: u32,
    dropped: u32,
    observation_drops: u32,
}

struct MonitorState {
    counters: Counters,
    tap_drops: u32,
    committed_state: bits[APPLICATION_STATE_BITS],
    app_rx_in_frame: u1,
    app_tx_in_frame: u1,
    trace: TraceBuffer,
}

const COUNTER_WORDS = ((bit_count<Counters>() / u32:32) as u8) + u8:1;
const STATE_WORDS = (APPLICATION_STATE_BITS / u32:32) as u8;
const STATE_REPLY_WORDS = STATE_WORDS + u8:1;
const TRACE_RECORD_WORDS = (bit_count<TraceEvent>() / u32:32) as u8;
const TRACE_HEADER_WORDS = (bit_count<TraceReplyHeader>() / u32:32) as u8;
const MONITOR_STATE_BITS = bit_count<MonitorState>();

fn trace_event_metadata(event: TraceEvent) -> u32 {
    ((event.metadata.kind as u32) << u32:24) | ((event.metadata.flags as u32) << u32:16) |
    ((event.metadata.txid as u32) << u32:8) | event.metadata.op as u32
}

fn append_trace(trace: TraceBuffer, event: TraceEvent, enabled: u1) -> TraceBuffer {
    if !enabled {
        trace
    } else if trace.count == TRACE_DEPTH as TraceCount {
        TraceBuffer { drops: trace.drops + u32:1, ..trace }
    } else {
        TraceBuffer {
            events: update(trace.events, trace.count, event),
            count: trace.count + TraceCount:1,
            ..trace
        }
    }
}

fn next_in_frame(in_frame: u1, valid: u1, ready: u1, tlast: u1) -> u1 {
    if valid && ready { !tlast } else { in_frame }
}

fn apply_observation(state: MonitorState, observation: Observation) -> MonitorState {
    let app_rx_accepted = observation.rx.valid && observation.rx.ready;
    let app_tx_accepted = observation.tx.valid && observation.tx.ready;
    let cycle = state.counters.cycles + u32:1;
    let rx_event = TraceEvent {
        cycle,
        metadata: TraceMetadata {
            kind: TraceKind::APPLICATION_RX,
            flags: observation.rx.tlast as u8,
            txid: observation.rx.data[8:16],
            op: observation.rx.data[24:32],
        },
    };
    let tx_event = TraceEvent {
        cycle,
        metadata: TraceMetadata {
            kind: TraceKind::APPLICATION_TX,
            flags: observation.tx.tlast as u8,
            txid: observation.tx.data[8:16],
            op: observation.tx.data[24:32],
        },
    };
    let after_rx = append_trace(state.trace, rx_event, app_rx_accepted && !state.app_rx_in_frame);
    let after_tx = append_trace(after_rx, tx_event, app_tx_accepted && !state.app_tx_in_frame);

    MonitorState {
        counters: Counters {
            cycles: cycle,
            app_rx_beats: state.counters.app_rx_beats + app_rx_accepted as u32,
            app_rx_frames:
                state.counters.app_rx_frames + (app_rx_accepted && observation.rx.tlast) as u32,
            app_rx_stall_cycles:
                state.counters.app_rx_stall_cycles +
                (observation.rx.valid && !observation.rx.ready) as u32,
            app_tx_beats: state.counters.app_tx_beats + app_tx_accepted as u32,
            app_tx_frames:
                state.counters.app_tx_frames + (app_tx_accepted && observation.tx.tlast) as u32,
            app_tx_stall_cycles:
                state.counters.app_tx_stall_cycles +
                (observation.tx.valid && !observation.tx.ready) as u32,
        },
        tap_drops: observation.tap_drops,
        committed_state: if observation.state_valid {
            observation.committed_state
        } else {
            state.committed_state
        },
        app_rx_in_frame: next_in_frame(
            state.app_rx_in_frame, observation.rx.valid, observation.rx.ready, observation.rx.tlast),
        app_tx_in_frame: next_in_frame(
            state.app_tx_in_frame, observation.tx.valid, observation.tx.ready, observation.tx.tlast),
        trace: after_tx,
    }
}

// Observer is its own top-level proc so XLS schedules it for one observation
// every cycle. Coupling it to the variable-length response loop would impose
// DebugServer's slower recurrence on passive sampling and manufacture drops.
proc Observer {
    observation_in: chan<Observation> in;
    snapshot_request_in: chan<RequestTag> in;
    snapshot_out: chan<MonitorState> out;

    config(observation_in: chan<Observation> in, snapshot_request_in: chan<RequestTag> in,
           snapshot_out: chan<MonitorState> out) {
        (observation_in, snapshot_request_in, snapshot_out)
    }

    init { zero!<MonitorState>() }

    next(state: MonitorState) {
        let (tok1, observation) = recv(join(), observation_in);
        let observed = apply_observation(state, observation);
        let (tok2, request, requested) =
            recv_non_blocking(tok1, snapshot_request_in, RequestTag::NONE);
        send_if(tok2, snapshot_out, requested, observed);
        if requested && request == RequestTag::GET_TRACE {
            MonitorState { trace: zero!<TraceBuffer>(), ..observed }
        } else {
            observed
        }
    }
}

struct DebugState {
    active: u1,
    reply_tag: ReplyTag,
    response_words: u8,
    response_index: u8,
    txid: u8,
    snapshot: MonitorState,
}

fn valid_empty_request(request: Beat) -> u1 {
    request.keep == u4:0xf && request.tlast && request.word[0:8] == u8:0
}

fn reply_tag_for_request(request: Beat) -> ReplyTag {
    if !valid_empty_request(request) {
        ReplyTag::ERROR
    } else {
        match request.word[24:32] as RequestTag {
            RequestTag::GET_COUNTERS => ReplyTag::COUNTERS,
            RequestTag::GET_STATE => ReplyTag::STATE,
            RequestTag::GET_TRACE => ReplyTag::TRACE,
            _ => ReplyTag::ERROR,
        }
    }
}

fn snapshot_request_for_reply(reply_tag: ReplyTag) -> RequestTag {
    match reply_tag {
        ReplyTag::TRACE => RequestTag::GET_TRACE,
        _ => RequestTag::NONE,
    }
}

fn response_words(reply_tag: ReplyTag, snapshot: MonitorState) -> u8 {
    match reply_tag {
        ReplyTag::COUNTERS => COUNTER_WORDS,
        ReplyTag::STATE => STATE_REPLY_WORDS,
        ReplyTag::TRACE => TRACE_HEADER_WORDS + ((snapshot.trace.count as u8) * TRACE_RECORD_WORDS),
        _ => u8:1,
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
            let event = state.snapshot.trace.events[event_word_index >> u32:1];
            if event_word_index[0:1] == u1:0 { event.cycle } else { trace_event_metadata(event) }
        },
    }
}

fn response_payload(state: DebugState) -> u32 {
    match state.reply_tag {
        ReplyTag::COUNTERS => match state.response_index {
            u8:1 => DEBUG_VERSION,
            u8:2 => state.snapshot.counters.cycles,
            u8:3 => state.snapshot.counters.app_rx_beats,
            u8:4 => state.snapshot.counters.app_rx_frames,
            u8:5 => state.snapshot.counters.app_rx_stall_cycles,
            u8:6 => state.snapshot.counters.app_tx_beats,
            u8:7 => state.snapshot.counters.app_tx_frames,
            u8:8 => state.snapshot.counters.app_tx_stall_cycles,
            _ => u32:0,
        },
        ReplyTag::STATE => if state.response_index == u8:1 {
            STATE_VERSION
        } else {
            state.snapshot.committed_state[((state.response_index as u32) - u32:2) * u32:32+:u32]
        },
        ReplyTag::TRACE => response_trace_payload(state),
        _ => u32:1,
    }
}

fn response_beat(state: DebugState) -> Beat {
    let word = if state.response_index == u8:0 {
        ((state.reply_tag as u32) << u32:24) | ((state.txid as u32) << u32:8) |
        state.response_words as u32
    } else {
        response_payload(state)
    };
    Beat { keep: u4:0xf, tlast: state.response_index == state.response_words, word }
}

// DebugServer is lowered separately with a relaxed throughput target. Debug
// serialization may take multiple cycles per beat without affecting Observer
// or feeding back into the application datapath.
proc DebugServer {
    request_in: chan<Beat> in;
    response_out: chan<Beat> out;
    snapshot_request_out: chan<RequestTag> out;
    snapshot_in: chan<MonitorState> in;

    config(request_in: chan<Beat> in, response_out: chan<Beat> out,
           snapshot_request_out: chan<RequestTag> out, snapshot_in: chan<MonitorState> in) {
        (request_in, response_out, snapshot_request_out, snapshot_in)
    }

    init { zero!<DebugState>() }

    next(state: DebugState) {
        let (tok1, response) = if state.active {
            (join(), state)
        } else {
            let (tok_request, request) = recv(join(), request_in);
            let reply_tag = reply_tag_for_request(request);
            let tok_snapshot_request =
                send(tok_request, snapshot_request_out, snapshot_request_for_reply(reply_tag));
            let (tok_snapshot, snapshot) = recv(tok_snapshot_request, snapshot_in);
            (
                tok_snapshot,
                DebugState {
                    active: u1:1,
                    reply_tag,
                    response_words: response_words(reply_tag, snapshot),
                    response_index: u8:0,
                    txid: request.word[8:16],
                    snapshot,
                },
            )
        };

        let beat = response_beat(response);
        send(tok1, response_out, beat);

        if beat.tlast {
            zero!<DebugState>()
        } else {
            DebugState { response_index: response.response_index + u8:1, ..response }
        }
    }
}
