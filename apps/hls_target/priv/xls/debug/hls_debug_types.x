// Shared data model for the transport-neutral debug endpoint.
//
// Observer and DebugServer are separate top-level procs, but their channel and
// snapshot types must remain identical. Keeping those declarations here makes
// the interface explicit without coupling either proc to the other's logic.

import std;

// One-beat debug requests; zero means no nonblocking observer request.
pub enum RequestTag : u8 {
    NONE = 0x00,
    GET_COUNTERS = 0x01,
    // 0x02 is reserved for a future request.
    GET_TRACE = 0x03,
}

// Response tags preserve request/reply separation and reserve ERROR for malformed requests.
pub enum ReplyTag : u8 {
    // Allows zero-initialized server state; an active response never emits it.
    NONE = 0x00,
    COUNTERS = 0x81,
    // 0x82 is reserved for a future reply.
    TRACE = 0x83,
    ERROR = 0xff,
}

// Direction recorded for an accepted application header; zero initializes empty events.
pub enum TraceKind : u8 {
    NONE = 0,
    APPLICATION_RX = 1,
    APPLICATION_TX = 2,
}

pub const DEBUG_VERSION = u32:5;
pub const TRACE_VERSION = u32:2;
pub const TRACE_DEPTH = u32:64;
pub const TRACE_COUNT_BITS = std::clog2(TRACE_DEPTH + u32:1);
pub const TRACE_ROW_COUNT = TRACE_DEPTH / u32:2;
pub const TRACE_ROW_BITS = std::clog2(TRACE_ROW_COUNT);
pub const TRACE_ADDRESS_BITS = TRACE_ROW_BITS + u32:1;

// Count of retained events including one possible unpaired event; range is zero through TRACE_DEPTH.
pub type TraceCount = uN[TRACE_COUNT_BITS];
// Row address across both trace banks.
pub type TraceAddress = uN[TRACE_ADDRESS_BITS];

// One 32-bit transport beat; keep must be full for requests and TLAST terminates a packet.
pub struct Beat { keep: u4, tlast: u1, word: u32 }

// Passive stream sample; data/TLAST count only when valid and ready are both asserted.
pub struct StreamObservation { data: u32, tlast: u1, ready: u1, valid: u1 }

// One cycle of routed/local RX and TX samples plus tap loss state.
pub struct Observation {
    routed: u1,
    gap: u1,
    tap_drops: u32,
    tx: StreamObservation,
    rx: StreamObservation,
}

// This is deliberately a small, versioned event envelope, not an attempt to
// encode the ERTS trace protocol. Later versions can add trace-token and
// distribution context without changing how the buffer is drained.
pub struct TraceMetadata { kind: TraceKind, flags: u8, txid: u8, op: u8 }

// One accepted application header with its cycle, retained route and packed metadata fields.
pub struct TraceEvent { cycle: u32, route: u32, metadata: TraceMetadata }

pub const TRACE_EVENT_BITS = bit_count<TraceEvent>();
// Packed form of one trace event.
pub type TraceBits = bits[TRACE_EVENT_BITS];
// Packed low/high pair stored in one external RAM row.
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

// Optional completed-row write emitted by the pure append function.
pub struct TraceWrite { valid: u1, address: TraceAddress, data: TraceRow }
// Mandatory row write sent to the external RAM proc.
pub struct TraceRowWrite { address: TraceAddress, data: TraceRow }
// External RAM row read plus selection of the low or high event.
pub struct TraceRead { address: TraceAddress, high: u1 }

// Wrapping cycle, traffic and stall counters reported by GET_COUNTERS.
pub struct Counters {
    cycles: u32,
    app_rx_beats: u32,
    app_rx_frames: u32,
    app_rx_stall_cycles: u32,
    app_tx_beats: u32,
    app_tx_frames: u32,
    app_tx_stall_cycles: u32,
}

// Passive framing state; UNSYNC persists after a gap until an accepted TLAST.
pub enum FramePhase : u2 { BOUNDARY = 0, HEADER = 1, PAYLOAD = 2, UNSYNC = 3 }
// Per-direction route/framing state and whether an unreported observation gap remains.
pub struct FrameState { phase: FramePhase, route: u32, gap_pending: u1 }

// Coherent observer snapshot containing counters, framing and one double-buffered trace bank.
pub struct MonitorState {
    counters: Counters,
    tap_drops: u32,
    rx: FrameState,
    tx: FrameState,
    trace: TraceBuffer,
}
