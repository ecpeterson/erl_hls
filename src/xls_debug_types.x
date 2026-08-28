// Shared data model for the transport-neutral debug endpoint.
//
// Observer and DebugServer are separate top-level procs, but their channel and
// snapshot types must remain identical. Keeping those declarations here makes
// the interface explicit without coupling either proc to the other's logic.

import std;

pub enum RequestTag : u8 {
    NONE = 0x00,
    GET_COUNTERS = 0x01,
    GET_STATE = 0x02,
    GET_TRACE = 0x03,
}

pub enum ReplyTag : u8 {
    // Allows zero-initialized server state; an active response never emits it.
    NONE = 0x00,
    COUNTERS = 0x81,
    STATE = 0x82,
    TRACE = 0x83,
    ERROR = 0xff,
}

pub enum TraceKind : u8 {
    NONE = 0,
    APPLICATION_RX = 1,
    APPLICATION_TX = 2,
}

pub const DEBUG_VERSION = u32:3;
pub const STATE_VERSION = u32:1;
pub const TRACE_VERSION = u32:1;
pub const APPLICATION_STATE_BITS = u32:512;
pub const TRACE_DEPTH = u32:64;
pub const TRACE_COUNT_BITS = std::clog2(TRACE_DEPTH + u32:1);
pub const TRACE_ROW_COUNT = TRACE_DEPTH / u32:2;
pub const TRACE_ROW_BITS = std::clog2(TRACE_ROW_COUNT);
pub const TRACE_ADDRESS_BITS = TRACE_ROW_BITS + u32:1;

pub type TraceCount = uN[TRACE_COUNT_BITS];
pub type TraceAddress = uN[TRACE_ADDRESS_BITS];

pub struct Beat { keep: u4, tlast: u1, word: u32 }

pub struct StreamObservation { data: u32, tlast: u1, ready: u1, valid: u1 }

pub struct Observation {
    committed_state: bits[APPLICATION_STATE_BITS],
    tap_drops: u32,
    tx: StreamObservation,
    rx: StreamObservation,
    state_valid: u1,
}

// This is deliberately a small, versioned event envelope, not an attempt to
// encode the ERTS trace protocol. Later versions can add trace-token and
// distribution context without changing how the buffer is drained.
pub struct TraceMetadata { kind: TraceKind, flags: u8, txid: u8, op: u8 }

pub struct TraceEvent { cycle: u32, metadata: TraceMetadata }

pub const TRACE_EVENT_BITS = bit_count<TraceEvent>();
pub type TraceRow = bits[TRACE_EVENT_BITS * u32:2];

// Complete event pairs live in an external 1R1W RAM. A possible odd final
// event remains here so the observer never needs more than one write per
// cycle, even when RX and TX frame headers are accepted together.
pub struct TraceBuffer {
    bank: u1,
    count: TraceCount,
    drops: u32,
    pending_valid: u1,
    pending_event: TraceEvent,
}

pub struct TraceWrite { valid: u1, address: TraceAddress, data: TraceRow }
pub struct TraceRowWrite { address: TraceAddress, data: TraceRow }
pub struct TraceRead { address: TraceAddress, high: u1 }

pub struct Counters {
    cycles: u32,
    app_rx_beats: u32,
    app_rx_frames: u32,
    app_rx_stall_cycles: u32,
    app_tx_beats: u32,
    app_tx_frames: u32,
    app_tx_stall_cycles: u32,
}

pub struct MonitorState {
    counters: Counters,
    tap_drops: u32,
    committed_state: bits[APPLICATION_STATE_BITS],
    app_rx_in_frame: u1,
    app_tx_in_frame: u1,
    trace: TraceBuffer,
}
