// Routed AXI-stream packet building blocks.
//
// A fabric packet begins with one routing beat. Its low 16 bits are the
// destination endpoint and its high 16 bits are the source endpoint. The
// remaining beats are an unchanged application or debug frame. Neither this
// envelope nor the fixed endpoint numbers are Erlang PID representations.
//
// EndpointIngress and RoutedTx are the one-route boundary components used by
// generated gateways. EgressGate holds output until connection activation.
// Configurable physical multiplexing lives in priv/rtl/fabric.

import axis;

const HOST_ENDPOINT = u16:0;
fn route_word(source: u16, destination: u16) -> u32 {
    ((source as u32) << u32:16) | destination as u32
}

enum EndpointIngressState : u2 {
    HEADER = 0,
    FORWARD = 1,
    DROP = 2,
}

// Accepts one exact source/destination route and removes its routing beat.
// Any other complete packet is drained, preserving packet synchronization.
pub proc EndpointIngress<EXPECTED_SOURCE: u16, ENDPOINT: u16> {
    routed_in: chan<axis::Beat> in;
    boundary_out: chan<axis::Beat> out;

    config(routed_in: chan<axis::Beat> in,
           boundary_out: chan<axis::Beat> out) {
        (routed_in, boundary_out)
    }

    init { EndpointIngressState::HEADER }

    next(state: EndpointIngressState) {
        let (tok, beat) = recv(join(), routed_in);
        match state {
            EndpointIngressState::HEADER => if beat.tlast {
                EndpointIngressState::HEADER
            } else if beat.word == route_word(EXPECTED_SOURCE, ENDPOINT) {
                EndpointIngressState::FORWARD
            } else {
                EndpointIngressState::DROP
            },
            EndpointIngressState::FORWARD => {
                let _done = send(tok, boundary_out, beat);
                if beat.tlast {
                    EndpointIngressState::HEADER
                } else {
                    EndpointIngressState::FORWARD
                }
            },
            EndpointIngressState::DROP => if beat.tlast {
                EndpointIngressState::HEADER
            } else {
                EndpointIngressState::DROP
            },
        }
    }
}

pub struct RoutedFrame {
    source: u16,
    frame: axis::Frame,
}

// Blocks output until its connection owner sends one credit. Storage and
// lifecycle ownership belong to the bounded channels around this proc.
pub proc EgressGate {
    frame_in: chan<RoutedFrame> in;
    frame_out: chan<RoutedFrame> out;
    arm_in: chan<u1> in;

    config(frame_in: chan<RoutedFrame> in,
           frame_out: chan<RoutedFrame> out,
           arm_in: chan<u1> in) {
        (frame_in, frame_out, arm_in)
    }

    init { u1:0 }

    next(armed: u1) {
        if armed {
            let (tok, frame) = recv(join(), frame_in);
            let _done = send(tok, frame_out, frame);
            armed
        } else {
            let (_tok, arm) = recv(join(), arm_in);
            arm
        }
    }
}

fn header_word(header: axis::Header) -> u32 {
    ((header.op as u32) << u32:24) |
        ((header.flags as u32) << u32:16) |
        ((header.txid as u32) << u32:8) |
        header.payload_words as u32
}

struct RoutedTxState {
    active: u1,
    route_pending: u1,
    source: u16,
    frame: axis::Frame,
    beats_sent: u8,
}

// Prefixes each compact Frame with its route and serializes it into Beats.
// payload_words must fit axis::Frame. Frame flags and transaction identity
// remain application boundary policy.
pub proc RoutedTx<DESTINATION: u16> {
    frame_in: chan<RoutedFrame> in;
    routed_out: chan<axis::Beat> out;

    config(frame_in: chan<RoutedFrame> in,
           routed_out: chan<axis::Beat> out) {
        (frame_in, routed_out)
    }

    init { zero!<RoutedTxState>() }

    next(state: RoutedTxState) {
        let (tok, routed) = recv_if(
            join(), frame_in, !state.active, zero!<RoutedFrame>());
        let state2 = if state.active {
            state
        } else {
            RoutedTxState {
                active: u1:1,
                route_pending: u1:1,
                source: routed.source,
                frame: routed.frame,
                ..zero!<RoutedTxState>()
            }
        };
        let (beat, next_state) = if state2.route_pending {
            let beat = axis::Beat {
                tlast: u1:0,
                word: route_word(state2.source, DESTINATION),
            };
            (beat, RoutedTxState { route_pending: u1:0, ..state2 })
        } else {
            let last = state2.beats_sent == state2.frame.header.payload_words;
            let word = if state2.beats_sent == u8:0 {
                header_word(state2.frame.header)
            } else {
                state2.frame.payload[
                    u8:32 * (state2.beats_sent - u8:1) +: u32]
            };
            let beat = axis::Beat { tlast: last, word };
            let next_state = if last {
                zero!<RoutedTxState>()
            } else {
                let beats_sent = state2.beats_sent + u8:1;
                RoutedTxState { beats_sent, ..state2 }
            };
            (beat, next_state)
        };
        let _done = send(tok, routed_out, beat);
        next_state
    }
}

// Concrete host-bound serializer entry point. Gateways expose RoutedFrame at
// their scheduling boundary so this proc can be compiled independently at the
// one-beat-per-clock rate required by the physical stream.
pub proc HostRoutedTx {
    frame_in: chan<RoutedFrame> in;
    routed_out: chan<axis::Beat> out;

    config(frame_in: chan<RoutedFrame> in,
           routed_out: chan<axis::Beat> out) {
        spawn RoutedTx<HOST_ENDPOINT>(frame_in, routed_out);
        (frame_in, routed_out)
    }

    init { () }
    next(state: ()) { state }
}
