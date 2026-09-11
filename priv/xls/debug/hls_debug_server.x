// Request validation and serialization for the debug endpoint.

import hls_debug_trace as trace;
import hls_debug_types as debug;

struct TraceReplyHeader {
    version: u32,
    record_words: u32,
    count: u32,
    dropped: u32,
    observation_drops: u32,
}

const COUNTER_WORDS = ((bit_count<debug::Counters>() / u32:32) as u8) + u8:1;
const TRACE_RECORD_WORDS = (debug::TRACE_EVENT_BITS / u32:32) as u8;
const TRACE_HEADER_WORDS = (bit_count<TraceReplyHeader>() / u32:32) as u8;

struct DebugState {
    active: u1,
    draining: u1,
    reply_tag: debug::ReplyTag,
    response_words: u8,
    response_index: u8,
    txid: u8,
    snapshot: debug::MonitorState,
    trace_event: u64,
}

fn valid_empty_request(request: debug::Beat) -> u1 {
    request.keep == u4:0xf && request.tlast &&
    request.word[0:8] == u8:0 && request.word[16:24] == u8:0
}

fn reply_tag_for_request(request: debug::Beat) -> debug::ReplyTag {
    if !valid_empty_request(request) {
        debug::ReplyTag::ERROR
    } else {
        match request.word[24:32] as debug::RequestTag {
            debug::RequestTag::GET_COUNTERS => debug::ReplyTag::COUNTERS,
            debug::RequestTag::GET_TRACE => debug::ReplyTag::TRACE,
            _ => debug::ReplyTag::ERROR,
        }
    }
}

// Only TLAST ends a rejected packet: payload words may resemble headers, and
// the declared length may itself be wrong. Reset aborts an unterminated packet.
fn accept_request(state: DebugState, request: debug::Beat) -> DebugState {
    DebugState {
        active: request.tlast,
        draining: !request.tlast,
        reply_tag: if state.draining { debug::ReplyTag::ERROR }
                   else { reply_tag_for_request(request) },
        txid: if state.draining { state.txid } else { request.word[8:16] },
        ..zero!<DebugState>()
    }
}

fn snapshot_request_for_reply(reply_tag: debug::ReplyTag)
    -> debug::RequestTag {
    match reply_tag {
        debug::ReplyTag::TRACE => debug::RequestTag::GET_TRACE,
        _ => debug::RequestTag::NONE,
    }
}

fn response_words(reply_tag: debug::ReplyTag,
                  snapshot: debug::MonitorState) -> u8 {
    match reply_tag {
        debug::ReplyTag::COUNTERS => COUNTER_WORDS,
        debug::ReplyTag::TRACE =>
            TRACE_HEADER_WORDS +
            ((snapshot.trace.count as u8) * TRACE_RECORD_WORDS),
        _ => u8:1,
    }
}

fn trace_word_index(state: DebugState) -> u8 {
    state.response_index - (TRACE_HEADER_WORDS + u8:1)
}

fn trace_event_index(state: DebugState) -> debug::TraceCount {
    (trace_word_index(state) >> u8:1) as debug::TraceCount
}

fn trace_event_is_pending(state: DebugState) -> u1 {
    state.snapshot.trace.pending_valid &&
    trace_event_index(state) ==
        state.snapshot.trace.count - debug::TraceCount:1
}

fn trace_event_read_needed(state: DebugState) -> u1 {
    state.active && state.reply_tag == debug::ReplyTag::TRACE &&
    state.response_index > TRACE_HEADER_WORDS &&
    trace_word_index(state)[0:1] == u1:0 &&
    !trace_event_is_pending(state)
}

fn trace_read(state: DebugState) -> debug::TraceRead {
    let event_index = trace_event_index(state);
    debug::TraceRead {
        address: trace::address(state.snapshot.trace.bank, event_index),
        high: event_index[0:1],
    }
}

fn response_trace_payload(state: DebugState) -> u32 {
    let payload_index = state.response_index - u8:1;
    match payload_index {
        u8:0 => debug::TRACE_VERSION,
        u8:1 => TRACE_RECORD_WORDS as u32,
        u8:2 => state.snapshot.trace.count as u32,
        u8:3 => state.snapshot.trace.drops,
        u8:4 => state.snapshot.tap_drops,
        _ => {
            let word_index = trace_word_index(state);
            if trace_event_is_pending(state) {
                trace::event_bits(state.snapshot.trace.pending_event)[
                    (word_index[0:1] as u32) * u32:32+:u32]
            } else {
                state.trace_event[
                    (word_index[0:1] as u32) * u32:32+:u32]
            }
        },
    }
}

fn response_payload(state: DebugState) -> u32 {
    match state.reply_tag {
        debug::ReplyTag::COUNTERS => match state.response_index {
            u8:1 => debug::DEBUG_VERSION,
            u8:2 => state.snapshot.counters.cycles,
            u8:3 => state.snapshot.counters.app_rx_beats,
            u8:4 => state.snapshot.counters.app_rx_frames,
            u8:5 => state.snapshot.counters.app_rx_stall_cycles,
            u8:6 => state.snapshot.counters.app_tx_beats,
            u8:7 => state.snapshot.counters.app_tx_frames,
            u8:8 => state.snapshot.counters.app_tx_stall_cycles,
            _ => u32:0,
        },
        debug::ReplyTag::TRACE => response_trace_payload(state),
        _ => u32:1,
    }
}

fn response_beat(state: DebugState) -> debug::Beat {
    let word = if state.response_index == u8:0 {
        ((state.reply_tag as u32) << u32:24) |
        ((state.txid as u32) << u32:8) |
        state.response_words as u32
    } else {
        response_payload(state)
    };
    debug::Beat {
        keep: u4:0xf,
        tlast: state.response_index == state.response_words,
        word,
    }
}

// DebugServer is lowered separately with a relaxed throughput target. Debug
// serialization may take multiple cycles per beat without affecting Observer
// or feeding back into the application datapath.
pub proc DebugServer {
    request_in: chan<debug::Beat> in;
    response_out: chan<debug::Beat> out;
    snapshot_request_out: chan<debug::RequestTag> out;
    snapshot_in: chan<debug::MonitorState> in;
    trace_read_request_out: chan<debug::TraceRead> out;
    trace_read_response_in: chan<u64> in;

    config(request_in: chan<debug::Beat> in,
           response_out: chan<debug::Beat> out,
           snapshot_request_out: chan<debug::RequestTag> out,
           snapshot_in: chan<debug::MonitorState> in,
           trace_read_request_out: chan<debug::TraceRead> out,
           trace_read_response_in: chan<u64> in) {
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
        if !state.active {
            let (tok_request, request) = recv(join(), request_in);
            let response = accept_request(state, request);
            // Invalid requests neither query Observer nor release a trace bank.
            let needs_snapshot = response.active &&
                response.reply_tag != debug::ReplyTag::ERROR;
            let tok_snapshot_request = send_if(
                tok_request,
                snapshot_request_out,
                needs_snapshot,
                snapshot_request_for_reply(response.reply_tag));
            let (_, snapshot) = recv_if(
                tok_snapshot_request,
                snapshot_in,
                needs_snapshot,
                zero!<debug::MonitorState>());
            DebugState {
                response_words: response_words(response.reply_tag, snapshot),
                snapshot,
                ..response
            }
        } else {
            let read_needed = trace_event_read_needed(state);
            let tok_read_request = send_if(
                join(),
                trace_read_request_out,
                read_needed,
                trace_read(state));
            let (tok_read_response, trace_event) = recv_if(
                tok_read_request,
                trace_read_response_in,
                read_needed,
                u64:0);
            let response = if read_needed {
                DebugState { trace_event, ..state }
            } else {
                state
            };

            let beat = response_beat(response);
            send(tok_read_response, response_out, beat);
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
}
