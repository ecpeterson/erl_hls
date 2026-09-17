// phi_phenom_topology.x
// Materialized logical graph; placement does not change actor identity.
import axis;
import frame_transport;
import effect_window;
import phenom_data_cell;
import phenom_syndrome_cell;
import phi_halo_cell;

const CHANNEL_DEPTH = u32:1;

proc ActorIngress0 {
  frame_in: chan<axis::Frame>[u32:1] in;
  frame_out: chan<axis::Frame> out;
  admission_in: chan<u1> in;
  config(
    frame_in: chan<axis::Frame>[u32:1] in,
    frame_out: chan<axis::Frame> out,
    admission_in: chan<u1> in
  ) {
    (frame_in, frame_out, admission_in)
  }
  init { (u32:0, false, u32:0) }
  next(state: (u32, u1, u32)) {
    if !state.1 {
      let (_tok, _credit) = recv(join(), admission_in);
      (state.0, true, state.2)
    } else if state.2 < u32:1 {
      let frame = match state.2 {
        u32:0 => axis::pack(u8:6, uN[96]:0x00000000800000009E3779B9),
        _ => zero!<axis::Frame>(),
      };
      let _tok = send(join(), frame_out, frame);
      (state.0, false, state.2 + u32:1)
    } else {
      let (tok, valid, frame) = unroll_for! (candidate, acc):
          (u32, (token, u1, axis::Frame)) in u32:0..u32:1 {
        let (tok, frame, valid) = recv_if_non_blocking(
          acc.0, frame_in[candidate], state.0 == candidate, zero!<axis::Frame>());
        (tok, acc.1 || valid, if valid { frame } else { acc.2 })
      }((join(), false, zero!<axis::Frame>()));
      let _done = send_if(tok, frame_out, valid, frame);
      (if state.0 + u32:1 == u32:1 { u32:0 } else { state.0 + u32:1 },
        !valid, state.2)
    }
  }
}

proc ActorIngress1 {
  frame_in: chan<axis::Frame>[u32:2] in;
  frame_out: chan<axis::Frame> out;
  admission_in: chan<u1> in;
  config(
    frame_in: chan<axis::Frame>[u32:2] in,
    frame_out: chan<axis::Frame> out,
    admission_in: chan<u1> in
  ) {
    (frame_in, frame_out, admission_in)
  }
  init { (u32:0, false, u32:0) }
  next(state: (u32, u1, u32)) {
    if !state.1 {
      let (_tok, _credit) = recv(join(), admission_in);
      (state.0, true, state.2)
    } else if state.2 < u32:1 {
      let frame = match state.2 {
        u32:0 => axis::pack(u8:12, u32:0x6D2B79F5),
        _ => zero!<axis::Frame>(),
      };
      let _tok = send(join(), frame_out, frame);
      (state.0, false, state.2 + u32:1)
    } else {
      let (tok, valid, frame) = unroll_for! (candidate, acc):
          (u32, (token, u1, axis::Frame)) in u32:0..u32:2 {
        let (tok, frame, valid) = recv_if_non_blocking(
          acc.0, frame_in[candidate], state.0 == candidate, zero!<axis::Frame>());
        (tok, acc.1 || valid, if valid { frame } else { acc.2 })
      }((join(), false, zero!<axis::Frame>()));
      let _done = send_if(tok, frame_out, valid, frame);
      (if state.0 + u32:1 == u32:2 { u32:0 } else { state.0 + u32:1 },
        !valid, state.2)
    }
  }
}

proc ActorIngress2 {
  frame_in: chan<axis::Frame>[u32:2] in;
  frame_out: chan<axis::Frame> out;
  admission_in: chan<u1> in;
  config(
    frame_in: chan<axis::Frame>[u32:2] in,
    frame_out: chan<axis::Frame> out,
    admission_in: chan<u1> in
  ) {
    (frame_in, frame_out, admission_in)
  }
  init { (u32:0, false, u32:0) }
  next(state: (u32, u1, u32)) {
    if !state.1 {
      let (_tok, _credit) = recv(join(), admission_in);
      (state.0, true, state.2)
    } else if state.2 < u32:1 {
      let frame = match state.2 {
        u32:0 => axis::pack(u8:6, uN[96]:0x000000008000000085EBCA6B),
        _ => zero!<axis::Frame>(),
      };
      let _tok = send(join(), frame_out, frame);
      (state.0, false, state.2 + u32:1)
    } else {
      let (tok, valid, frame) = unroll_for! (candidate, acc):
          (u32, (token, u1, axis::Frame)) in u32:0..u32:2 {
        let (tok, frame, valid) = recv_if_non_blocking(
          acc.0, frame_in[candidate], state.0 == candidate, zero!<axis::Frame>());
        (tok, acc.1 || valid, if valid { frame } else { acc.2 })
      }((join(), false, zero!<axis::Frame>()));
      let _done = send_if(tok, frame_out, valid, frame);
      (if state.0 + u32:1 == u32:2 { u32:0 } else { state.0 + u32:1 },
        !valid, state.2)
    }
  }
}

proc ActorRouter0 {
  egress_in: chan<phenom_data_cell::Egress> in;
  lane_0_out: chan<axis::Frame> out;
  lane_1_out: chan<axis::Frame> out;
  config(
    egress_in: chan<phenom_data_cell::Egress> in,
    lane_0_out: chan<axis::Frame> out,
    lane_1_out: chan<axis::Frame> out
  ) {
    (egress_in, lane_0_out, lane_1_out)
  }
  init { () }
  next(state: ()) {
    let (tok, effect) = recv(join(), egress_in);
    let lane_0_tok = send_if(
      tok, lane_0_out, true && (effect.port == phenom_data_cell::OutputPort::NORTH || effect.port == phenom_data_cell::OutputPort::EAST || effect.port == phenom_data_cell::OutputPort::WEST || effect.port == phenom_data_cell::OutputPort::SOUTH), effect.frame);
    let lane_1_tok = send_if(
      tok, lane_1_out, true && (effect.port == phenom_data_cell::OutputPort::MEASUREMENT), effect.frame);
    let routed_tok = join(tok, lane_0_tok, lane_1_tok);
    state
  }
}

proc ActorRouter1 {
  egress_in: chan<phi_halo_cell::Egress> in;
  lane_2_out: chan<axis::Frame> out;
  lane_3_out: chan<axis::Frame> out;
  lane_4_out: chan<axis::Frame> out;
  config(
    egress_in: chan<phi_halo_cell::Egress> in,
    lane_2_out: chan<axis::Frame> out,
    lane_3_out: chan<axis::Frame> out,
    lane_4_out: chan<axis::Frame> out
  ) {
    (egress_in, lane_2_out, lane_3_out, lane_4_out)
  }
  init { () }
  next(state: ()) {
    let (tok, effect) = recv(join(), egress_in);
    let lane_2_tok = send_if(
      tok, lane_2_out, true && (effect.port == phi_halo_cell::OutputPort::NORTH || effect.port == phi_halo_cell::OutputPort::EAST || effect.port == phi_halo_cell::OutputPort::WEST || effect.port == phi_halo_cell::OutputPort::SOUTH), effect.frame);
    let lane_3_tok = send_if(
      tok, lane_3_out, true && (effect.port == phi_halo_cell::OutputPort::SYNDROME), effect.frame);
    let lane_4_tok = send_if(
      tok, lane_4_out, true && (effect.port == phi_halo_cell::OutputPort::CORRECTION || effect.port == phi_halo_cell::OutputPort::STATUS), effect.frame);
    let routed_tok = join(tok, lane_2_tok, lane_3_tok, lane_4_tok);
    state
  }
}

proc ActorRouter2 {
  egress_in: chan<phenom_syndrome_cell::Egress> in;
  lane_5_out: chan<axis::Frame> out;
  lane_6_out: chan<axis::Frame> out;
  lane_7_out: chan<axis::Frame> out;
  config(
    egress_in: chan<phenom_syndrome_cell::Egress> in,
    lane_5_out: chan<axis::Frame> out,
    lane_6_out: chan<axis::Frame> out,
    lane_7_out: chan<axis::Frame> out
  ) {
    (egress_in, lane_5_out, lane_6_out, lane_7_out)
  }
  init { () }
  next(state: ()) {
    let (tok, effect) = recv(join(), egress_in);
    let lane_5_tok = send_if(
      tok, lane_5_out, true && (effect.port == phenom_syndrome_cell::OutputPort::NORTH || effect.port == phenom_syndrome_cell::OutputPort::EAST || effect.port == phenom_syndrome_cell::OutputPort::WEST || effect.port == phenom_syndrome_cell::OutputPort::SOUTH), effect.frame);
    let lane_6_tok = send_if(
      tok, lane_6_out, true && (effect.port == phenom_syndrome_cell::OutputPort::PHI), effect.frame);
    let lane_7_tok = send_if(
      tok, lane_7_out, true && (effect.port == phenom_syndrome_cell::OutputPort::PHI), effect.frame);
    let routed_tok = join(tok, lane_5_tok, lane_6_tok, lane_7_tok);
    state
  }
}

pub proc Top {
  announcement_out: chan<axis::Frame> out;
  data_measurements_out: chan<axis::Frame> out;
  decoder_events_out: chan<axis::Frame> out;
  config(
    announcement_out: chan<axis::Frame> out,
    data_measurements_out: chan<axis::Frame> out,
    decoder_events_out: chan<axis::Frame> out
  ) {
    let (actor_0_req_p, actor_0_req_c) = chan<axis::Frame, CHANNEL_DEPTH>("actor_0_req");
    let (actor_0_admit_p, actor_0_admit_c) = chan<u1, CHANNEL_DEPTH>("actor_0_admit");
    let (actor_0_egress_p, actor_0_egress_c) = chan<phenom_data_cell::Egress, u32:3>("actor_0_egress");
    let (actor_0_requests_p, actor_0_requests_c) = chan<axis::Frame, CHANNEL_DEPTH>[u32:1]("actor_0_requests");
    let (actor_1_req_p, actor_1_req_c) = chan<axis::Frame, CHANNEL_DEPTH>("actor_1_req");
    let (actor_1_admit_p, actor_1_admit_c) = chan<u1, CHANNEL_DEPTH>("actor_1_admit");
    let (actor_1_egress_p, actor_1_egress_c) = chan<phi_halo_cell::Egress, u32:4>("actor_1_egress");
    let (actor_1_requests_p, actor_1_requests_c) = chan<axis::Frame, CHANNEL_DEPTH>[u32:2]("actor_1_requests");
    let (actor_2_req_p, actor_2_req_c) = chan<axis::Frame, CHANNEL_DEPTH>("actor_2_req");
    let (actor_2_admit_p, actor_2_admit_c) = chan<u1, CHANNEL_DEPTH>("actor_2_admit");
    let (actor_2_egress_p, actor_2_egress_c) = chan<phenom_syndrome_cell::Egress, u32:4>("actor_2_egress");
    let (actor_2_requests_p, actor_2_requests_c) = chan<axis::Frame, CHANNEL_DEPTH>[u32:2]("actor_2_requests");
    let (announcement_lanes_p, announcement_lanes_c) = chan<axis::Frame, CHANNEL_DEPTH>[u32:1]("announcement_lanes");
    let (data_measurements_lanes_p, data_measurements_lanes_c) = chan<axis::Frame, CHANNEL_DEPTH>[u32:1]("data_measurements_lanes");
    let (decoder_events_lanes_p, decoder_events_lanes_c) = chan<axis::Frame, CHANNEL_DEPTH>[u32:1]("decoder_events_lanes");
    // Actor data uses phenom_data_cell.
    spawn phenom_data_cell::Service(actor_0_req_c, actor_0_egress_p, actor_0_admit_p);
    spawn ActorIngress0(actor_0_requests_c, actor_0_req_p, actor_0_admit_c);
    // Actor phi uses phi_halo_cell.
    spawn phi_halo_cell::Service(actor_1_req_c, actor_1_egress_p, actor_1_admit_p);
    spawn ActorIngress1(actor_1_requests_c, actor_1_req_p, actor_1_admit_c);
    // Actor syndrome uses phenom_syndrome_cell.
    spawn phenom_syndrome_cell::Service(actor_2_req_c, actor_2_egress_p, actor_2_admit_p);
    spawn ActorIngress2(actor_2_requests_c, actor_2_req_p, actor_2_admit_c);
    spawn ActorRouter0(actor_0_egress_c, actor_2_requests_p[u32:0], data_measurements_lanes_p[u32:0]);
    spawn ActorRouter1(actor_1_egress_c, actor_1_requests_p[u32:0], actor_2_requests_p[u32:1], decoder_events_lanes_p[u32:0]);
    spawn ActorRouter2(actor_2_egress_c, actor_0_requests_p[u32:0], actor_1_requests_p[u32:1], announcement_lanes_p[u32:0]);
    spawn frame_transport::FrameArrayMux<u32:1>(announcement_lanes_c, announcement_out);
    spawn frame_transport::FrameArrayMux<u32:1>(data_measurements_lanes_c, data_measurements_out);
    spawn frame_transport::FrameArrayMux<u32:1>(decoder_events_lanes_c, decoder_events_out);
    (announcement_out, data_measurements_out, decoder_events_out)
  }
  init { () }
  next(state: ()) { state }
}
