// Bounded-trace packing and external-memory addressing.

import hls_debug_types as debug;

// Packs trace kind, flags, transaction ID and operation into the stable metadata word.
pub fn event_metadata(event: debug::TraceEvent) -> u32 {
    ((event.metadata.kind as u32) << u32:24) |
    ((event.metadata.flags as u32) << u32:16) |
    ((event.metadata.txid as u32) << u32:8) |
    event.metadata.op as u32
}

// Packs metadata, route and cycle in descending 32-bit words for storage and replies.
pub fn event_bits(event: debug::TraceEvent) -> bits[debug::TRACE_EVENT_BITS] {
    ((event_metadata(event) as debug::TraceBits) << u32:64) |
        ((event.route as debug::TraceBits) << u32:32) | event.cycle as debug::TraceBits
}

// Maps an event index to one shared RAM row; adjacent events share a row and banks occupy disjoint halves.
pub fn address(bank: u1, event_index: debug::TraceCount)
    -> debug::TraceAddress {
    ((bank as debug::TraceAddress) << debug::TRACE_ROW_BITS) |
    ((event_index as debug::TraceAddress) >> debug::TraceAddress:1)
}

// Appends an enabled event to the bounded double-buffered trace. The first event waits in-register;
// the second completes one row write; full buffers count drops without overwriting retained data.
pub fn append(trace: debug::TraceBuffer, event: debug::TraceEvent, enabled: u1,
              write: debug::TraceWrite)
    -> (debug::TraceBuffer, debug::TraceWrite) {
    if !enabled {
        (trace, write)
    } else if trace.count == debug::TRACE_DEPTH as debug::TraceCount {
        (
            debug::TraceBuffer {
                drops: trace.drops + u32:1,
                ..trace
            },
            write,
        )
    } else if trace.pending_valid {
        let row = ((event_bits(event) as debug::TraceRow) << debug::TRACE_EVENT_BITS) |
            event_bits(trace.pending_event) as debug::TraceRow;
        (
            debug::TraceBuffer {
                count: trace.count + debug::TraceCount:1,
                pending_valid: u1:0,
                pending_event: zero!<debug::TraceEvent>(),
                ..trace
            },
            debug::TraceWrite {
                valid: u1:1,
                address: address(trace.bank, trace.count),
                data: row,
            },
        )
    } else {
        (
            debug::TraceBuffer {
                count: trace.count + debug::TraceCount:1,
                pending_valid: u1:1,
                pending_event: event,
                ..trace
            },
            write,
        )
    }
}

// Checks two consecutive events pack low/high into one row and clear the pending register.
#[test]
fn event_pair_shares_one_row_test() {
    let first = debug::TraceEvent {
        cycle: u32:7,
        route: u32:0,
        metadata: debug::TraceMetadata {
            kind: debug::TraceKind::APPLICATION_RX,
            flags: u8:0,
            txid: u8:0x12,
            op: u8:5,
        },
    };
    let second = debug::TraceEvent {
        cycle: u32:7,
        route: u32:0,
        metadata: debug::TraceMetadata {
            kind: debug::TraceKind::APPLICATION_TX,
            flags: u8:1,
            txid: u8:0x12,
            op: u8:7,
        },
    };
    let (after_first, no_write) = append(
        zero!<debug::TraceBuffer>(),
        first,
        u1:1,
        zero!<debug::TraceWrite>());
    let (after_second, write) = append(
        after_first,
        second,
        u1:1,
        no_write);

    assert_eq(after_second.count, debug::TraceCount:2);
    assert_eq(after_second.pending_valid, u1:0);
    assert_eq(write.valid, u1:1);
    assert_eq(write.address, debug::TraceAddress:0);
    assert_eq(
        write.data,
        ((event_bits(second) as debug::TraceRow) << debug::TRACE_EVENT_BITS) |
        event_bits(first) as debug::TraceRow);
}

// Checks 64 events map to 32 rows per bank within one 64-row physical address space.
#[test]
fn banks_share_one_physical_address_space_test() {
    assert_eq(
        address(u1:0, debug::TraceCount:0),
        debug::TraceAddress:0);
    assert_eq(
        address(u1:0, debug::TraceCount:63),
        debug::TraceAddress:31);
    assert_eq(
        address(u1:1, debug::TraceCount:0),
        debug::TraceAddress:32);
    assert_eq(
        address(u1:1, debug::TraceCount:63),
        debug::TraceAddress:63);
}
