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
const TRACE_DEPTH = u32:64;
const TRACE_COUNT_BITS = std::clog2(TRACE_DEPTH + u32:1);
const TRACE_ROW_COUNT = TRACE_DEPTH / u32:2;
const TRACE_ROW_BITS = std::clog2(TRACE_ROW_COUNT);
const TRACE_ADDRESS_BITS = TRACE_ROW_BITS + u32:1;

type TraceCount = uN[TRACE_COUNT_BITS];
type TraceAddress = uN[TRACE_ADDRESS_BITS];

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

const TRACE_EVENT_BITS = bit_count<TraceEvent>();

// Complete event pairs live in an external 1R1W RAM. A possible odd final
// event remains here so the observer never needs more than one write per
// cycle, even when RX and TX frame headers are accepted together.
struct TraceBuffer {
    bank: u1,
    count: TraceCount,
    drops: u32,
    pending_valid: u1,
    pending_event: TraceEvent,
}

struct TraceWrite { valid: u1, address: TraceAddress, data: u128 }

// These shapes are consumed by codegen's external 1R1W RAM rewrite. Unit
// masks mean every write replaces one complete 128-bit row.
struct RamReadRequest { address: TraceAddress, mask: () }
struct RamReadResponse { data: u128 }
struct RamWriteRequest { address: TraceAddress, data: u128, mask: () }

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
const TRACE_RECORD_WORDS = (TRACE_EVENT_BITS / u32:32) as u8;
const TRACE_HEADER_WORDS = (bit_count<TraceReplyHeader>() / u32:32) as u8;
const MONITOR_STATE_BITS = bit_count<MonitorState>();

fn trace_event_metadata(event: TraceEvent) -> u32 {
    ((event.metadata.kind as u32) << u32:24) | ((event.metadata.flags as u32) << u32:16) |
    ((event.metadata.txid as u32) << u32:8) | event.metadata.op as u32
}

fn trace_event_bits(event: TraceEvent) -> bits[TRACE_EVENT_BITS] {
    ((trace_event_metadata(event) as u64) << u64:32) | event.cycle as u64
}

fn trace_address(bank: u1, event_index: TraceCount) -> TraceAddress {
    ((bank as TraceAddress) << TRACE_ROW_BITS) |
    ((event_index as TraceAddress) >> TraceAddress:1)
}

fn append_trace(trace: TraceBuffer, event: TraceEvent, enabled: u1,
                write: TraceWrite) -> (TraceBuffer, TraceWrite) {
    if !enabled {
        (trace, write)
    } else if trace.count == TRACE_DEPTH as TraceCount {
        (TraceBuffer { drops: trace.drops + u32:1, ..trace }, write)
    } else if trace.pending_valid {
        let row = ((trace_event_bits(event) as u128) << u128:64) |
            trace_event_bits(trace.pending_event) as u128;
        (
            TraceBuffer {
                count: trace.count + TraceCount:1,
                pending_valid: u1:0,
                pending_event: zero!<TraceEvent>(),
                ..trace
            },
            TraceWrite {
                valid: u1:1,
                address: trace_address(trace.bank, trace.count),
                data: row,
            },
        )
    } else {
        (
            TraceBuffer {
                count: trace.count + TraceCount:1,
                pending_valid: u1:1,
                pending_event: event,
                ..trace
            },
            write,
        )
    }
}

fn next_in_frame(in_frame: u1, valid: u1, ready: u1, tlast: u1) -> u1 {
    if valid && ready { !tlast } else { in_frame }
}

fn apply_observation(state: MonitorState, observation: Observation)
    -> (MonitorState, TraceWrite) {
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
    let (after_rx, rx_write) = append_trace(
        state.trace,
        rx_event,
        app_rx_accepted && !state.app_rx_in_frame,
        zero!<TraceWrite>());
    let (after_tx, trace_write) = append_trace(
        after_rx,
        tx_event,
        app_tx_accepted && !state.app_tx_in_frame,
        rx_write);

    (
        MonitorState {
            counters: Counters {
                cycles: cycle,
                app_rx_beats: state.counters.app_rx_beats + app_rx_accepted as u32,
                app_rx_frames:
                    state.counters.app_rx_frames +
                    (app_rx_accepted && observation.rx.tlast) as u32,
                app_rx_stall_cycles:
                    state.counters.app_rx_stall_cycles +
                    (observation.rx.valid && !observation.rx.ready) as u32,
                app_tx_beats: state.counters.app_tx_beats + app_tx_accepted as u32,
                app_tx_frames:
                    state.counters.app_tx_frames +
                    (app_tx_accepted && observation.tx.tlast) as u32,
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
                state.app_rx_in_frame,
                observation.rx.valid,
                observation.rx.ready,
                observation.rx.tlast),
            app_tx_in_frame: next_in_frame(
                state.app_tx_in_frame,
                observation.tx.valid,
                observation.tx.ready,
                observation.tx.tlast),
            trace: after_tx,
        },
        trace_write,
    )
}

// Observer is its own top-level proc so XLS schedules it for one observation
// every cycle. Coupling it to the variable-length response loop would impose
// DebugServer's slower recurrence on passive sampling and manufacture drops.
proc Observer {
    observation_in: chan<Observation> in;
    snapshot_request_in: chan<RequestTag> in;
    snapshot_out: chan<MonitorState> out;
    trace_read_request_in: chan<TraceAddress> in;
    trace_read_response_out: chan<u128> out;
    trace_rd_req: chan<RamReadRequest> out;
    trace_rd_resp: chan<RamReadResponse> in;
    trace_wr_req: chan<RamWriteRequest> out;
    trace_wr_comp: chan<()> in;

    config(observation_in: chan<Observation> in, snapshot_request_in: chan<RequestTag> in,
           snapshot_out: chan<MonitorState> out,
           trace_read_request_in: chan<TraceAddress> in,
           trace_read_response_out: chan<u128> out,
           trace_rd_req: chan<RamReadRequest> out,
           trace_rd_resp: chan<RamReadResponse> in,
           trace_wr_req: chan<RamWriteRequest> out,
           trace_wr_comp: chan<()> in) {
        (
            observation_in,
            snapshot_request_in,
            snapshot_out,
            trace_read_request_in,
            trace_read_response_out,
            trace_rd_req,
            trace_rd_resp,
            trace_wr_req,
            trace_wr_comp,
        )
    }

    init { zero!<MonitorState>() }

    next(state: MonitorState) {
        let (tok_observation, observation) = recv(join(), observation_in);
        let (observed, trace_write) = apply_observation(state, observation);

        let write_request = RamWriteRequest {
            address: trace_write.address,
            data: trace_write.data,
            mask: (),
        };
        let tok_write_request = send_if(
            tok_observation, trace_wr_req, trace_write.valid, write_request);
        let (tok_write_complete, _) = recv_if(
            tok_write_request, trace_wr_comp, trace_write.valid, ());

        let (tok_read_input, read_address, read_requested) = recv_non_blocking(
            tok_observation, trace_read_request_in, TraceAddress:0);
        let read_request = RamReadRequest { address: read_address, mask: () };
        let tok_read_request = send_if(
            tok_read_input, trace_rd_req, read_requested, read_request);
        let (tok_read_complete, read_response) = recv_if(
            tok_read_request,
            trace_rd_resp,
            read_requested,
            zero!<RamReadResponse>());
        let tok_read_response = send_if(
            tok_read_complete,
            trace_read_response_out,
            read_requested,
            read_response.data);

        let (tok_snapshot_request, request, requested) = recv_non_blocking(
            tok_observation, snapshot_request_in, RequestTag::NONE);
        let tok_snapshot = join(
            tok_write_complete, tok_read_response, tok_snapshot_request);
        send_if(tok_snapshot, snapshot_out, requested, observed);

        if requested && request == RequestTag::GET_TRACE {
            let next_trace = TraceBuffer {
                bank: !observed.trace.bank,
                ..zero!<TraceBuffer>()
            };
            MonitorState { trace: next_trace, ..observed }
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
    trace_row: u128,
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

fn trace_word_index(state: DebugState) -> u8 {
    state.response_index - (TRACE_HEADER_WORDS + u8:1)
}

fn trace_event_index(state: DebugState) -> TraceCount {
    (trace_word_index(state) >> u8:1) as TraceCount
}

fn trace_event_is_pending(state: DebugState) -> u1 {
    state.snapshot.trace.pending_valid &&
    trace_event_index(state) == state.snapshot.trace.count - TraceCount:1
}

fn trace_row_read_needed(state: DebugState) -> u1 {
    state.reply_tag == ReplyTag::TRACE &&
    state.response_index > TRACE_HEADER_WORDS &&
    trace_word_index(state)[0:2] == u2:0 &&
    !trace_event_is_pending(state)
}

fn trace_read_address(state: DebugState) -> TraceAddress {
    trace_address(state.snapshot.trace.bank, trace_event_index(state))
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
            let word_index = trace_word_index(state);
            if trace_event_is_pending(state) {
                trace_event_bits(state.snapshot.trace.pending_event)[
                    (word_index[0:1] as u32) * u32:32+:u32]
            } else {
                state.trace_row[(word_index[0:2] as u32) * u32:32+:u32]
            }
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
    trace_read_request_out: chan<TraceAddress> out;
    trace_read_response_in: chan<u128> in;

    config(request_in: chan<Beat> in, response_out: chan<Beat> out,
           snapshot_request_out: chan<RequestTag> out, snapshot_in: chan<MonitorState> in,
           trace_read_request_out: chan<TraceAddress> out,
           trace_read_response_in: chan<u128> in) {
        (
            request_in,
            response_out,
            snapshot_request_out,
            snapshot_in,
            trace_read_request_out,
            trace_read_response_in,
        )
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
                    trace_row: u128:0,
                },
            )
        };

        let read_needed = trace_row_read_needed(response);
        let tok_read_request = send_if(
            tok1,
            trace_read_request_out,
            read_needed,
            trace_read_address(response));
        let (tok_read_response, trace_row) = recv_if(
            tok_read_request, trace_read_response_in, read_needed, u128:0);
        let response_with_row = if read_needed {
            DebugState { trace_row, ..response }
        } else {
            response
        };

        let beat = response_beat(response_with_row);
        send(tok_read_response, response_out, beat);

        if beat.tlast {
            zero!<DebugState>()
        } else {
            DebugState {
                response_index: response_with_row.response_index + u8:1,
                ..response_with_row
            }
        }
    }
}
