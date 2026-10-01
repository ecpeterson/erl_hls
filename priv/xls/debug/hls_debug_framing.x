// Passive header recognition for endpoint-local and routed application streams.
// A gap loses framing in both directions. Only an observed accepted TLAST can
// recover the boundary; idle cycles and header-looking payloads cannot do so.
import hls_debug_types as debug;

pub fn observe(state: debug::FrameState, beat: debug::StreamObservation,
               routed: u1, gap: u1, cycle: u32, kind: debug::TraceKind)
    -> (debug::FrameState, debug::TraceEvent, u1) {
    let accepted = beat.valid && beat.ready;
    let phase = if gap { debug::FramePhase::UNSYNC } else { state.phase };
    let header = accepted && (phase == debug::FramePhase::HEADER ||
        (phase == debug::FramePhase::BOUNDARY && !routed));
    let route_beat = accepted && routed && phase == debug::FramePhase::BOUNDARY;
    let route = if route_beat { beat.data } else if gap { u32:0 } else { state.route };
    let pending = state.gap_pending || gap;
    let next_phase = if !accepted { phase } else if beat.tlast {
        debug::FramePhase::BOUNDARY
    } else {
        match phase {
            debug::FramePhase::BOUNDARY => if routed {
                debug::FramePhase::HEADER
            } else { debug::FramePhase::PAYLOAD },
            debug::FramePhase::HEADER => debug::FramePhase::PAYLOAD,
            _ => phase,
        }
    };
    let event = debug::TraceEvent {
        cycle,
        route: if routed { route } else { u32:0 },
        metadata: debug::TraceMetadata {
            kind,
            flags: (beat.tlast as u8) | ((routed as u8) << u32:1) |
                ((pending as u8) << u32:2),
            txid: beat.data[8:16],
            op: beat.data[24:32],
        },
    };
    (debug::FrameState { phase: next_phase, route, gap_pending: pending }, event, header)
}

// Clear the pending gap only when a header is retained, so buffer overflow
// cannot erase that information before the next trace bank becomes available.
pub fn retained(state: debug::FrameState, kept: u1) -> debug::FrameState {
    debug::FrameState { gap_pending: state.gap_pending && !kept, ..state }
}

pub fn status(rx: debug::FrameState, tx: debug::FrameState) -> u32 {
    (rx.phase as u32) | ((tx.phase as u32) << u32:2) |
        ((rx.gap_pending as u32) << u32:4) | ((tx.gap_pending as u32) << u32:5)
}

fn beat(data: u32, last: u1) -> debug::StreamObservation {
    debug::StreamObservation { data, tlast: last, valid: u1:1, ready: u1:1 }
}

#[test]
fn routed_and_local_headers_test() {
    let (routed, _, header) = observe(zero!<debug::FrameState>(),
        beat(u32:0x12345678, u1:0), u1:1, u1:0, u32:5, debug::TraceKind::APPLICATION_RX);
    assert_eq(header, u1:0);
    let (done, event, header) = observe(routed, beat(u32:0x07002200, u1:1),
        u1:1, u1:0, u32:6, debug::TraceKind::APPLICATION_RX);
    assert_eq(header, u1:1);
    assert_eq(done.phase, debug::FramePhase::BOUNDARY);
    assert_eq(event.route, u32:0x12345678);
    assert_eq(event.metadata.txid, u8:0x22);
    assert_eq(event.metadata.op, u8:7);
    assert_eq(event.metadata.flags, u8:3);
    let (_, local_event, local_header) = observe(zero!<debug::FrameState>(),
        beat(u32:0x05004400, u1:1), u1:0, u1:0, u32:7, debug::TraceKind::APPLICATION_TX);
    assert_eq(local_header, u1:1);
    assert_eq(local_event.route, u32:0);
    assert_eq(local_event.metadata.flags, u8:1);
}

#[test]
fn gap_at_every_frame_phase_requires_accepted_last_test() {
    for (phase, ()): (u2, ()) in u2:0..u2:3 {
        let state = debug::FrameState { phase: phase as debug::FramePhase,
            ..zero!<debug::FrameState>() };
        let (lost, _, header) = observe(state, beat(u32:0xff00ee00, u1:0),
            u1:1, u1:1, u32:10, debug::TraceKind::APPLICATION_RX);
        assert_eq(header, u1:0);
        assert_eq(lost.phase, debug::FramePhase::UNSYNC);
        let stalled_last = debug::StreamObservation { ready: u1:0, ..beat(u32:0, u1:1) };
        let (still_lost, _, header) = observe(lost, stalled_last,
            u1:1, u1:0, u32:11, debug::TraceKind::APPLICATION_RX);
        assert_eq(header, u1:0);
        assert_eq(still_lost.phase, debug::FramePhase::UNSYNC);
        let (boundary, _, header) = observe(still_lost, beat(u32:0xff00ee00, u1:1),
            u1:1, u1:0, u32:12, debug::TraceKind::APPLICATION_RX);
        assert_eq(header, u1:0);
        assert_eq(boundary.phase, debug::FramePhase::BOUNDARY);
        let (route, _, _) = observe(boundary, beat(u32:0x12340002, u1:0),
            u1:1, u1:0, u32:13, debug::TraceKind::APPLICATION_RX);
        let (framed, event, header) = observe(route, beat(u32:0x07005500, u1:1),
            u1:1, u1:0, u32:14, debug::TraceKind::APPLICATION_RX);
        assert_eq(header, u1:1);
        assert_eq(event.route, u32:0x12340002);
        assert_eq(event.metadata.flags, u8:7);
        assert_eq(retained(framed, u1:0).gap_pending, u1:1);
        assert_eq(retained(framed, u1:1).gap_pending, u1:0);
    }(())
}
