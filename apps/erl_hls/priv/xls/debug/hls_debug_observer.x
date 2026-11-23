// Passive application observation and coherent snapshot capture.

import hls_debug_trace as trace;
import hls_debug_framing as framing;
import hls_debug_types as debug;

pub fn apply_observation(state: debug::MonitorState,
                         observation: debug::Observation)
    -> (debug::MonitorState, debug::TraceWrite) {
    let app_rx_accepted = observation.rx.valid && observation.rx.ready;
    let app_tx_accepted = observation.tx.valid && observation.tx.ready;
    let dropped_observations = observation.tap_drops - state.tap_drops;
    let cycle = state.counters.cycles + u32:1 + dropped_observations;
    let gap = observation.gap;
    let (rx, rx_event, rx_header) = framing::observe(state.rx, observation.rx,
        observation.routed, gap, cycle, debug::TraceKind::APPLICATION_RX);
    let (tx, tx_event, tx_header) = framing::observe(state.tx, observation.tx,
        observation.routed, gap, cycle, debug::TraceKind::APPLICATION_TX);
    let (after_rx, rx_write) = trace::append(
        state.trace,
        rx_event,
        rx_header,
        zero!<debug::TraceWrite>());
    let (after_tx, trace_write) = trace::append(
        after_rx,
        tx_event,
        tx_header,
        rx_write);

    (
        debug::MonitorState {
            counters: debug::Counters {
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
            rx: framing::retained(rx, rx_header && state.trace.count < debug::TRACE_DEPTH as debug::TraceCount),
            tx: framing::retained(tx, tx_header && after_rx.count < debug::TRACE_DEPTH as debug::TraceCount),
            trace: after_tx,
        },
        trace_write,
    )
}

#[test]
fn simultaneous_headers_become_one_trace_row_test() {
    let rx_data = (u32:5 << u32:24) | (u32:0x12 << u32:8);
    let tx_data = (u32:7 << u32:24) | (u32:0x12 << u32:8);
    let observation = debug::Observation {
        rx: debug::StreamObservation {
            data: rx_data, tlast: u1:0, ready: u1:1, valid: u1:1,
        },
        tx: debug::StreamObservation {
            data: tx_data, tlast: u1:0, ready: u1:1, valid: u1:1,
        },
        ..zero!<debug::Observation>()
    };
    let (observed, write) = apply_observation(
        zero!<debug::MonitorState>(), observation);

    assert_eq(observed.trace.count, debug::TraceCount:2);
    assert_eq(observed.trace.pending_valid, u1:0);
    assert_eq(write.valid, u1:1);
    assert_eq(write.address, debug::TraceAddress:0);
}

#[test]
fn dropped_observations_advance_cycle_test() {
    let initial = debug::MonitorState {
        counters: debug::Counters {
            cycles: u32:10,
            ..zero!<debug::Counters>()
        },
        tap_drops: u32:7,
        ..zero!<debug::MonitorState>()
    };
    let observation = debug::Observation {
        tap_drops: u32:12,
        gap: u1:1,
        ..zero!<debug::Observation>()
    };
    let (observed, write) = apply_observation(initial, observation);

    assert_eq(observed.counters.cycles, u32:16);
    assert_eq(observed.tap_drops, u32:12);
    assert_eq(write.valid, u1:0);
}

#[test]
fn wrapping_counters_do_not_hide_observation_loss_test() {
    let initial = debug::MonitorState {
        counters: debug::Counters { cycles: u32:0xfffffffe, ..zero!<debug::Counters>() },
        tap_drops: u32:0xffffffff,
        ..zero!<debug::MonitorState>()
    };
    let observation = debug::Observation {
        gap: u1:1, tap_drops: u32:1,
        rx: debug::StreamObservation {
            data: u32:0x07004400, valid: u1:1, ready: u1:1, tlast: u1:0,
        },
        ..zero!<debug::Observation>()
    };
    let (wrapped, _) = apply_observation(initial, observation);
    assert_eq(wrapped.counters.cycles, u32:1);
    assert_eq(wrapped.trace.count, debug::TraceCount:0);
    assert_eq(wrapped.rx.phase, debug::FramePhase::UNSYNC);
    // Exactly 2^32 missed cycles produce the same drop counter, but the tap's
    // separate gap bit must still suppress the apparent local header.
    let (full_wrap, _) = apply_observation(initial,
        debug::Observation { tap_drops: initial.tap_drops, ..observation });
    assert_eq(full_wrap.counters.cycles, u32:0xffffffff);
    assert_eq(full_wrap.trace.count, debug::TraceCount:0);
    assert_eq(full_wrap.rx.gap_pending, u1:1);
    assert_eq(full_wrap.tx.phase, debug::FramePhase::UNSYNC);
}

// Observer is its own top-level proc so XLS schedules it for one observation
// every cycle. Coupling it to the variable-length response loop would impose
// DebugServer's slower recurrence on passive sampling and manufacture drops.
pub proc Observer {
    observation_in: chan<debug::Observation> in;
    snapshot_request_in: chan<debug::RequestTag> in;
    snapshot_out: chan<debug::MonitorState> out;
    trace_write_out: chan<debug::TraceRowWrite> out;

    config(observation_in: chan<debug::Observation> in,
           snapshot_request_in: chan<debug::RequestTag> in,
           snapshot_out: chan<debug::MonitorState> out,
           trace_write_out: chan<debug::TraceRowWrite> out) {
        (
            observation_in,
            snapshot_request_in,
            snapshot_out,
            trace_write_out,
        )
    }

    init { zero!<debug::MonitorState>() }

    next(state: debug::MonitorState) {
        let (tok_observation, observation) = recv(join(), observation_in);
        let (observed, trace_write) = apply_observation(state, observation);

        let write_request = debug::TraceRowWrite {
            address: trace_write.address,
            data: trace_write.data,
        };
        let tok_trace_write = send_if(
            tok_observation,
            trace_write_out,
            trace_write.valid,
            write_request);

        let (tok_snapshot_request, request, requested) = recv_non_blocking(
            tok_observation,
            snapshot_request_in,
            debug::RequestTag::NONE);
        let tok_snapshot = join(tok_trace_write, tok_snapshot_request);
        send_if(tok_snapshot, snapshot_out, requested, observed);

        if requested && request == debug::RequestTag::GET_TRACE {
            let next_trace = debug::TraceBuffer {
                bank: !observed.trace.bank,
                ..zero!<debug::TraceBuffer>()
            };
            debug::MonitorState { trace: next_trace, ..observed }
        } else {
            observed
        }
    }
}
