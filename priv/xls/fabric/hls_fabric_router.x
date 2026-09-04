// Routed AXI-stream packet building blocks.
//
// A fabric packet begins with one routing beat. Its low 16 bits are the
// destination endpoint and its high 16 bits are the source endpoint. The
// remaining beats are an unchanged application or debug frame. Neither this
// envelope nor the fixed endpoint numbers are Erlang PID representations.
//
// PairIngress and PairEgress implement the first two-endpoint fixture.
// EndpointIngress and RoutedTx are the corresponding one-route boundary
// components used by generated gateways. EgressGate holds unsolicited output
// until its owner explicitly activates the connection.

import axis;

const HOST_ENDPOINT = u16:0;
const ENDPOINT_ONE = u16:1;
const ENDPOINT_TWO = u16:2;

enum IngressRoute : u2 {
    HEADER = 0,
    ENDPOINT_ONE = 1,
    ENDPOINT_TWO = 2,
    DROP = 3,
}

enum EgressGrant : u2 {
    NONE = 0,
    ENDPOINT_ONE = 1,
    ENDPOINT_TWO = 2,
}

struct RouteHeader { source: u16, destination: u16 }

fn route_from_word(word: u32) -> RouteHeader {
    RouteHeader { source: word[16:32], destination: word[0:16] }
}

fn route_word(source: u16, destination: u16) -> u32 {
    ((source as u32) << u32:16) | destination as u32
}

fn routing_beat(source: u16) -> axis::Beat {
    axis::Beat { tlast: u1:0, word: route_word(source, HOST_ENDPOINT) }
}

fn ingress_route(beat: axis::Beat) -> IngressRoute {
    let route = route_from_word(beat.word);
    if beat.tlast {
        IngressRoute::HEADER
    } else {
        match route.destination {
            ENDPOINT_ONE => IngressRoute::ENDPOINT_ONE,
            ENDPOINT_TWO => IngressRoute::ENDPOINT_TWO,
            _ => IngressRoute::DROP,
        }
    }
}

// Ingress consumes the routing beat and locks the selected endpoint until
// TLAST. An invalid destination is drained as one complete packet so that it
// cannot desynchronize the following packet. A bounded error reply will be
// added once the fabric error/exit semantics are chosen.
pub proc PairIngress {
    shared_in: chan<axis::Beat> in;
    endpoint_one_out: chan<axis::Beat> out;
    endpoint_two_out: chan<axis::Beat> out;

    config(shared_in: chan<axis::Beat> in, endpoint_one_out: chan<axis::Beat> out,
           endpoint_two_out: chan<axis::Beat> out) {
        (shared_in, endpoint_one_out, endpoint_two_out)
    }

    init { IngressRoute::HEADER }

    next(route: IngressRoute) {
        let (tok, beat) = recv(join(), shared_in);
        match route {
            IngressRoute::HEADER => ingress_route(beat),
            IngressRoute::ENDPOINT_ONE => {
                send(tok, endpoint_one_out, beat);
                if beat.tlast { IngressRoute::HEADER } else { IngressRoute::ENDPOINT_ONE }
            },
            IngressRoute::ENDPOINT_TWO => {
                send(tok, endpoint_two_out, beat);
                if beat.tlast { IngressRoute::HEADER } else { IngressRoute::ENDPOINT_TWO }
            },
            IngressRoute::DROP => if beat.tlast { IngressRoute::HEADER } else { IngressRoute::DROP },
        }
    }
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

struct EgressState { grant: EgressGrant, first_pending: u1, first: axis::Beat, prefer_two: u1 }

fn begin_packet(beat: axis::Beat, grant: EgressGrant, prefer_two: u1) -> EgressState {
    EgressState { grant, first_pending: u1:1, first: beat, prefer_two }
}

fn after_beat(state: EgressState, beat: axis::Beat) -> EgressState {
    if beat.tlast {
        EgressState { prefer_two: state.grant == EgressGrant::ENDPOINT_ONE, ..zero!<EgressState>() }
    } else {
        EgressState { first_pending: u1:0, ..state }
    }
}

// Egress arbitrates only between packets. Once selected, an endpoint owns the
// shared output until an accepted TLAST even if it pauses TVALID. Selection
// alternates after each packet, so two continuously ready endpoints cannot
// starve one another.
pub proc PairEgress {
    endpoint_one_in: chan<axis::Beat> in;
    endpoint_two_in: chan<axis::Beat> in;
    shared_out: chan<axis::Beat> out;

    config(endpoint_one_in: chan<axis::Beat> in, endpoint_two_in: chan<axis::Beat> in,
           shared_out: chan<axis::Beat> out) {
        (endpoint_one_in, endpoint_two_in, shared_out)
    }

    init { zero!<EgressState>() }

    next(state: EgressState) {
        let poll_one = !state.first_pending &&
                       (state.grant == EgressGrant::ENDPOINT_ONE ||
                       (state.grant == EgressGrant::NONE && !state.prefer_two));
        let poll_two = !state.first_pending &&
                       (state.grant == EgressGrant::ENDPOINT_TWO ||
                       (state.grant == EgressGrant::NONE && state.prefer_two));
        let (tok_one, beat_one, valid_one) =
            recv_if_non_blocking(join(), endpoint_one_in, poll_one, zero!<axis::Beat>());
        let (tok_two, beat_two, valid_two) =
            recv_if_non_blocking(tok_one, endpoint_two_in, poll_two, zero!<axis::Beat>());

        if state.first_pending {
            send(tok_two, shared_out, state.first);
            after_beat(state, state.first)
        } else {
            match state.grant {
                EgressGrant::ENDPOINT_ONE => {
                    send_if(tok_two, shared_out, valid_one, beat_one);
                    if valid_one { after_beat(state, beat_one) } else { state }
                },
                EgressGrant::ENDPOINT_TWO => {
                    send_if(tok_two, shared_out, valid_two, beat_two);
                    if valid_two { after_beat(state, beat_two) } else { state }
                },
                EgressGrant::NONE => if valid_one {
                    send(tok_two, shared_out, routing_beat(ENDPOINT_ONE));
                    begin_packet(beat_one, EgressGrant::ENDPOINT_ONE, state.prefer_two)
                } else if valid_two {
                    send(tok_two, shared_out, routing_beat(ENDPOINT_TWO));
                    begin_packet(beat_two, EgressGrant::ENDPOINT_TWO, state.prefer_two)
                } else {
                    EgressState { prefer_two: !state.prefer_two, ..state }
                },
            }
        }
    }
}
