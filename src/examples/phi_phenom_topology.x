// phi_phenom_topology.x
//
// A closed, deliberately small hardware experiment containing one phi cell,
// one phenomenological syndrome cell, and one phenomenological data cell.
// Four logical edges share each actor instance but remain distinct channels
// and carry distinct source labels. The topology connects generated services
// with complete axis::Frames, avoiding Beat serialization between actors.

import axis;
import phenom_data_cell;
import phenom_syndrome_cell;
import phi_halo_cell;

const DATA_PRNG_SEED = u32:0x9e3779b9;
const SYNDROME_PRNG_SEED = u32:0x85ebca6b;
const HALF_THRESHOLD = u32:0x80000000;

// TODO: Have actor lowering export record packers so topology sources do not
// repeat the wire layout of their statically injected messages.
fn config_frame(tag: u8, seed: u32, threshold: u32) -> axis::Frame {
  axis::pack(tag, threshold ++ seed)
}

proc DataConfig {
  frame_out: chan<axis::Frame> out;

  config(frame_out: chan<axis::Frame> out) { (frame_out,) }

  init { u1:0 }

  next(sent: u1) {
    send_if(
      join(), frame_out, !sent,
      config_frame(
        phenom_data_cell::Tag::PHENOM_CONFIG as u8,
        DATA_PRNG_SEED,
        HALF_THRESHOLD));
    u1:1
  }
}

proc SyndromeConfig {
  frame_out: chan<axis::Frame> out;

  config(frame_out: chan<axis::Frame> out) { (frame_out,) }

  init { u1:0 }

  next(sent: u1) {
    send_if(
      join(), frame_out, !sent,
      config_frame(
        phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
        SYNDROME_PRNG_SEED,
        HALF_THRESHOLD));
    u1:1
  }
}

// Duplicates each completed syndrome announcement: one copy continues to the
// phi cell and the other is the experiment's observation port. Both copies
// must be accepted, so probe backpressure propagates through the real network.
proc AnnouncementTap {
  frame_in: chan<axis::Frame> in;
  phi_out: chan<axis::Frame> out;
  probe_out: chan<axis::Frame> out;

  config(frame_in: chan<axis::Frame> in,
         phi_out: chan<axis::Frame> out,
         probe_out: chan<axis::Frame> out) {
    (frame_in, phi_out, probe_out)
  }

  init { () }

  next(state: ()) {
    let (tok, frame) = recv(join(), frame_in);
    let phi_tok = send(tok, phi_out, frame);
    let probe_tok = send(tok, probe_out, frame);
    let _done = join(phi_tok, probe_tok);
    state
  }
}

pub proc Top {
  announcement_out: chan<axis::Frame> out;

  config(announcement_out: chan<axis::Frame> out) {
    // Generated actor boundaries.
    let (phi_req_p, phi_req_c) = chan<axis::Frame, u32:1>("phi_req");
    let (phi_admit_p, phi_admit_c) = chan<u1, u32:1>("phi_admit");
    let (phi_north_p, phi_north_c) = chan<axis::Frame, u32:1>("phi_north");
    let (phi_east_p, phi_east_c) = chan<axis::Frame, u32:1>("phi_east");
    let (phi_west_p, phi_west_c) = chan<axis::Frame, u32:1>("phi_west");
    let (phi_south_p, phi_south_c) = chan<axis::Frame, u32:1>("phi_south");
    let (phi_syndrome_p, phi_syndrome_c) =
      chan<axis::Frame, u32:1>("phi_syndrome");

    let (syndrome_req_p, syndrome_req_c) =
      chan<axis::Frame, u32:1>("syndrome_req");
    let (syndrome_admit_p, syndrome_admit_c) =
      chan<u1, u32:1>("syndrome_admit");
    let (syndrome_north_p, syndrome_north_c) =
      chan<axis::Frame, u32:1>("syndrome_north");
    let (syndrome_east_p, syndrome_east_c) =
      chan<axis::Frame, u32:1>("syndrome_east");
    let (syndrome_west_p, syndrome_west_c) =
      chan<axis::Frame, u32:1>("syndrome_west");
    let (syndrome_south_p, syndrome_south_c) =
      chan<axis::Frame, u32:1>("syndrome_south");
    let (syndrome_phi_p, syndrome_phi_c) =
      chan<axis::Frame, u32:1>("syndrome_phi");

    let (data_req_p, data_req_c) = chan<axis::Frame, u32:1>("data_req");
    let (data_admit_p, data_admit_c) = chan<u1, u32:1>("data_admit");
    let (data_north_p, data_north_c) = chan<axis::Frame, u32:1>("data_north");
    let (data_east_p, data_east_c) = chan<axis::Frame, u32:1>("data_east");
    let (data_west_p, data_west_c) = chan<axis::Frame, u32:1>("data_west");
    let (data_south_p, data_south_c) = chan<axis::Frame, u32:1>("data_south");

    spawn phi_halo_cell::Service(
      phi_req_c,
      phi_north_p,
      phi_east_p,
      phi_west_p,
      phi_south_p,
      phi_syndrome_p,
      phi_admit_p);
    spawn phenom_syndrome_cell::Service(
      syndrome_req_c,
      syndrome_north_p,
      syndrome_east_p,
      syndrome_west_p,
      syndrome_south_p,
      syndrome_phi_p,
      syndrome_admit_p);
    spawn phenom_data_cell::Service(
      data_req_c,
      data_north_p,
      data_east_p,
      data_west_p,
      data_south_p,
      data_admit_p);

    // Static one-shot configuration. A production elaborator can substitute
    // per-instance constants without changing the actor callback protocol.
    let (data_config_p, data_config_c) =
      chan<axis::Frame, u32:1>("data_config");
    let (syndrome_config_p, syndrome_config_c) =
      chan<axis::Frame, u32:1>("syndrome_config");
    spawn DataConfig(data_config_p);
    spawn SyndromeConfig(syndrome_config_p);

    // TODO: Replace these pairwise mux trees with a generated, credit-aware
    // N-way ingress. This first fixture favors direct composition over FIFO
    // count; every tree edge currently contributes one 128-bit buffer.
    //
    // Four logical ports from an actor also alias one destination here. The
    // barrier protocols tolerate their interleaving, but a general topology
    // elaborator must preserve aggregate sender-to-receiver order across such
    // aliases, or reject the topology.

    // Phi ingress: four periodic mesh edges plus the syndrome announcement.
    let (announcement_phi_p, announcement_phi_c) =
      chan<axis::Frame, u32:1>("announcement_phi");
    spawn AnnouncementTap(syndrome_phi_c, announcement_phi_p, announcement_out);
    let (phi_mesh_ne_p, phi_mesh_ne_c) =
      chan<axis::Frame, u32:1>("phi_mesh_ne");
    let (phi_mesh_ws_p, phi_mesh_ws_c) =
      chan<axis::Frame, u32:1>("phi_mesh_ws");
    let (phi_mesh_p, phi_mesh_c) = chan<axis::Frame, u32:1>("phi_mesh");
    let (phi_ingress_p, phi_ingress_c) =
      chan<axis::Frame, u32:1>("phi_ingress");
    spawn axis::FrameMux2(phi_north_c, phi_east_c, phi_mesh_ne_p);
    spawn axis::FrameMux2(phi_west_c, phi_south_c, phi_mesh_ws_p);
    spawn axis::FrameMux2(phi_mesh_ne_c, phi_mesh_ws_c, phi_mesh_p);
    spawn axis::FrameMux2(phi_mesh_c, announcement_phi_c, phi_ingress_p);
    spawn axis::ReservedFrame(phi_ingress_c, phi_req_p, phi_admit_c);

    // Data ingress: four queries from the syndrome plus configuration.
    let (data_query_ne_p, data_query_ne_c) =
      chan<axis::Frame, u32:1>("data_query_ne");
    let (data_query_ws_p, data_query_ws_c) =
      chan<axis::Frame, u32:1>("data_query_ws");
    let (data_queries_p, data_queries_c) =
      chan<axis::Frame, u32:1>("data_queries");
    let (data_ingress_p, data_ingress_c) =
      chan<axis::Frame, u32:1>("data_ingress");
    spawn axis::FrameMux2(syndrome_north_c, syndrome_east_c, data_query_ne_p);
    spawn axis::FrameMux2(syndrome_west_c, syndrome_south_c, data_query_ws_p);
    spawn axis::FrameMux2(data_query_ne_c, data_query_ws_c, data_queries_p);
    spawn axis::FrameMux2(data_queries_c, data_config_c, data_ingress_p);
    spawn axis::ReservedFrame(data_ingress_c, data_req_p, data_admit_c);

    // Syndrome ingress: phi request, four data replies, and configuration.
    let (data_reply_ne_p, data_reply_ne_c) =
      chan<axis::Frame, u32:1>("data_reply_ne");
    let (data_reply_ws_p, data_reply_ws_c) =
      chan<axis::Frame, u32:1>("data_reply_ws");
    let (data_replies_p, data_replies_c) =
      chan<axis::Frame, u32:1>("data_replies");
    let (syndrome_control_p, syndrome_control_c) =
      chan<axis::Frame, u32:1>("syndrome_control");
    let (syndrome_ingress_p, syndrome_ingress_c) =
      chan<axis::Frame, u32:1>("syndrome_ingress");
    spawn axis::FrameMux2(data_north_c, data_east_c, data_reply_ne_p);
    spawn axis::FrameMux2(data_west_c, data_south_c, data_reply_ws_p);
    spawn axis::FrameMux2(data_reply_ne_c, data_reply_ws_c, data_replies_p);
    spawn axis::FrameMux2(phi_syndrome_c, syndrome_config_c, syndrome_control_p);
    spawn axis::FrameMux2(data_replies_c, syndrome_control_c, syndrome_ingress_p);
    spawn axis::ReservedFrame(
      syndrome_ingress_c, syndrome_req_p, syndrome_admit_c);

    (announcement_out,)
  }

  init { () }
  next(state: ()) { state }
}
