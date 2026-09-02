// phi_noise_topology.x
// Auto-generated from compact Erlang topology and scheduler rules.
// Manual changes will be overwritten.
//
// Actor state and mailbox frames use separate RAMs. Group routers
// carry scheduled {slot, frame} requests without coordinate-level
// request, admission, or egress channel arrays.

import axis;
import hls_spatial_router;
import phenom_data_cell;
import phenom_syndrome_cell;
import phi_halo_cell;

const CHANNEL_DEPTH = u32:1;
const WIDTH = u32:3;
const HEIGHT = u32:3;

proc FrameRelay {
  frame_in: chan<axis::Frame> in;
  frame_out: chan<axis::Frame> out;

  config(
      frame_in: chan<axis::Frame> in,
      frame_out: chan<axis::Frame> out
  ) {
    (frame_in, frame_out)
  }

  init { () }

  next(state: ()) {
    let (tok, frame) = recv(join(), frame_in);
    let _done = send(tok, frame_out, frame);
    state
  }
}
struct ControlState {
  active: u1,
  packet: hls_spatial_router::SpatialFrame,
  family: u32,
  x: u32,
  y: u32,
}

proc ControlDispatcher {
  spatial_in: chan<hls_spatial_router::SpatialFrame> in;
  scheduler_0_control_out: chan<phenom_data_cell::ScheduledRequest> out;
  scheduler_2_control_out: chan<phenom_syndrome_cell::ScheduledRequest> out;

  config(
    spatial_in: chan<hls_spatial_router::SpatialFrame> in,
    scheduler_0_control_out: chan<phenom_data_cell::ScheduledRequest> out,
    scheduler_2_control_out: chan<phenom_syndrome_cell::ScheduledRequest> out
  ) {
    (spatial_in, scheduler_0_control_out, scheduler_2_control_out)
  }

  init { zero!<ControlState>() }

  next(state: ControlState) {
    if !state.active {
      let (_tok, packet) = recv(join(), spatial_in);
      ControlState { active: u1:1, packet,
        ..zero!<ControlState>() }
    } else {
      let _done = match state.family {
        u32:0 => {
          let address_x = (state.x * u32:1 + u32:0) as u16;
          let address_y = (state.y * u32:2 + u32:0) as u16;
          let selected = ((state.packet.target == u2:0 && (state.packet.frame.header.op == u8:13 || state.packet.frame.header.op == u8:16)) || (state.packet.target == u2:1 && (state.packet.frame.header.op == u8:15))) && hls_spatial_router::contains(
            state.packet.rectangle, address_x, address_y);
          let request = phenom_data_cell::ScheduledRequest {
            slot: u32:0 + state.x * HEIGHT + state.y,
            frame: state.packet.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          };
          send_if(join(), scheduler_0_control_out, selected, request)
        },
        u32:1 => {
          let address_x = (state.x * u32:1 + u32:0) as u16;
          let address_y = (state.y * u32:2 + u32:1) as u16;
          let selected = ((state.packet.target == u2:0 && (state.packet.frame.header.op == u8:13 || state.packet.frame.header.op == u8:16)) || (state.packet.target == u2:1 && (state.packet.frame.header.op == u8:15))) && hls_spatial_router::contains(
            state.packet.rectangle, address_x, address_y);
          let request = phenom_data_cell::ScheduledRequest {
            slot: u32:9 + state.x * HEIGHT + state.y,
            frame: state.packet.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          };
          send_if(join(), scheduler_0_control_out, selected, request)
        },
        u32:2 => {
          let address_x = (state.x * u32:1 + u32:0) as u16;
          let address_y = (state.y * u32:2 + u32:0) as u16;
          let selected = ((state.packet.target == u2:1 && (state.packet.frame.header.op == u8:15))) && hls_spatial_router::contains(
            state.packet.rectangle, address_x, address_y);
          let request = phenom_syndrome_cell::ScheduledRequest {
            slot: u32:0 + state.x * HEIGHT + state.y,
            frame: state.packet.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          };
          send_if(join(), scheduler_2_control_out, selected, request)
        },
        u32:3 => {
          let address_x = (state.x * u32:1 + u32:0) as u16;
          let address_y = (state.y * u32:2 + u32:0) as u16;
          let selected = ((state.packet.target == u2:1 && (state.packet.frame.header.op == u8:15))) && hls_spatial_router::contains(
            state.packet.rectangle, address_x, address_y);
          let request = phenom_syndrome_cell::ScheduledRequest {
            slot: u32:9 + state.x * HEIGHT + state.y,
            frame: state.packet.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          };
          send_if(join(), scheduler_2_control_out, selected, request)
        },
        _ => join(),
      };
      let last_y = state.y + u32:1 == HEIGHT;
      let last_x = state.x + u32:1 == WIDTH;
      let last_family = state.family + u32:1 == u32:4;
      let family_done = last_y && last_x;
      let all_done = family_done && last_family;
      ControlState {
        active: !all_done,
        family: if family_done { state.family + u32:1 }
          else { state.family },
        x: if last_y {
          if last_x { u32:0 } else { state.x + u32:1 }
        } else { state.x },
        y: if last_y { u32:0 } else { state.y + u32:1 },
        ..state
      }
    }
  }
}

proc SchedulerStartup0 {
  request_out: chan<phenom_data_cell::ScheduledRequest> out;

  config(request_out: chan<phenom_data_cell::ScheduledRequest> out) { (request_out,) }

  init { u32:0 }

  next(index: u32) {
    let request = match index {
      u32:0 => phenom_data_cell::ScheduledRequest {
        slot: u32:0,
        frame: axis::pack(u8:6, uN[96]:0x00000000800000009E3779B9),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:1 => phenom_data_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(u8:6, uN[96]:0x00020000800000003C6EF372),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:2 => phenom_data_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(u8:6, uN[96]:0x0004000080000000DAA66D2B),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:3 => phenom_data_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(u8:6, uN[96]:0x000000018000000078DDE6E4),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:4 => phenom_data_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(u8:6, uN[96]:0x00020001800000001715609D),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:5 => phenom_data_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(u8:6, uN[96]:0x0004000180000000B54CDA56),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:6 => phenom_data_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(u8:6, uN[96]:0x00000002800000005384540F),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:7 => phenom_data_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(u8:6, uN[96]:0x0002000280000000F1BBCDC8),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:8 => phenom_data_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(u8:6, uN[96]:0x00040002800000008FF34781),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:9 => phenom_data_cell::ScheduledRequest {
        slot: u32:9,
        frame: axis::pack(u8:6, uN[96]:0x00010000800000002E2AC13A),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:10 => phenom_data_cell::ScheduledRequest {
        slot: u32:10,
        frame: axis::pack(u8:6, uN[96]:0x0003000080000000CC623AF3),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:11 => phenom_data_cell::ScheduledRequest {
        slot: u32:11,
        frame: axis::pack(u8:6, uN[96]:0x00050000800000006A99B4AC),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:12 => phenom_data_cell::ScheduledRequest {
        slot: u32:12,
        frame: axis::pack(u8:6, uN[96]:0x000100018000000008D12E65),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:13 => phenom_data_cell::ScheduledRequest {
        slot: u32:13,
        frame: axis::pack(u8:6, uN[96]:0x0003000180000000A708A81E),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:14 => phenom_data_cell::ScheduledRequest {
        slot: u32:14,
        frame: axis::pack(u8:6, uN[96]:0x0005000180000000454021D7),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:15 => phenom_data_cell::ScheduledRequest {
        slot: u32:15,
        frame: axis::pack(u8:6, uN[96]:0x0001000280000000E3779B90),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:16 => phenom_data_cell::ScheduledRequest {
        slot: u32:16,
        frame: axis::pack(u8:6, uN[96]:0x000300028000000081AF1549),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:17 => phenom_data_cell::ScheduledRequest {
        slot: u32:17,
        frame: axis::pack(u8:6, uN[96]:0x00050002800000001FE68F02),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      _ => zero!<phenom_data_cell::ScheduledRequest>(),
    };
    let active = index < u32:18;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerStartup1 {
  request_out: chan<phi_halo_cell::ScheduledRequest> out;

  config(request_out: chan<phi_halo_cell::ScheduledRequest> out) { (request_out,) }

  init { u32:0 }

  next(index: u32) {
    let request = match index {
      u32:0 => phi_halo_cell::ScheduledRequest {
        slot: u32:0,
        frame: axis::pack(u8:12, u32:0xDE0497BD),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:1 => phi_halo_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(u8:12, u32:0x7C3C1176),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:2 => phi_halo_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(u8:12, u32:0x1A738B2F),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:3 => phi_halo_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(u8:12, u32:0xB8AB04E8),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:4 => phi_halo_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(u8:12, u32:0x56E27EA1),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:5 => phi_halo_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(u8:12, u32:0xF519F85A),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:6 => phi_halo_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(u8:12, u32:0x93517213),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:7 => phi_halo_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(u8:12, u32:0x3188EBCC),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:8 => phi_halo_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(u8:12, u32:0xCFC06585),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:9 => phi_halo_cell::ScheduledRequest {
        slot: u32:9,
        frame: axis::pack(u8:12, u32:0x6DF7DF3E),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:10 => phi_halo_cell::ScheduledRequest {
        slot: u32:10,
        frame: axis::pack(u8:12, u32:0x0C2F58F7),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:11 => phi_halo_cell::ScheduledRequest {
        slot: u32:11,
        frame: axis::pack(u8:12, u32:0xAA66D2B0),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:12 => phi_halo_cell::ScheduledRequest {
        slot: u32:12,
        frame: axis::pack(u8:12, u32:0x489E4C69),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:13 => phi_halo_cell::ScheduledRequest {
        slot: u32:13,
        frame: axis::pack(u8:12, u32:0xE6D5C622),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:14 => phi_halo_cell::ScheduledRequest {
        slot: u32:14,
        frame: axis::pack(u8:12, u32:0x850D3FDB),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:15 => phi_halo_cell::ScheduledRequest {
        slot: u32:15,
        frame: axis::pack(u8:12, u32:0x2344B994),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:16 => phi_halo_cell::ScheduledRequest {
        slot: u32:16,
        frame: axis::pack(u8:12, u32:0xC17C334D),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:17 => phi_halo_cell::ScheduledRequest {
        slot: u32:17,
        frame: axis::pack(u8:12, u32:0x5FB3AD06),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      _ => zero!<phi_halo_cell::ScheduledRequest>(),
    };
    let active = index < u32:18;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerStartup2 {
  request_out: chan<phenom_syndrome_cell::ScheduledRequest> out;

  config(request_out: chan<phenom_syndrome_cell::ScheduledRequest> out) { (request_out,) }

  init { u32:0 }

  next(index: u32) {
    let request = match index {
      u32:0 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:0,
        frame: axis::pack(u8:6, uN[96]:0x0000000080000000BE1E08BB),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:1 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(u8:6, uN[96]:0x00010000800000005C558274),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:2 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(u8:6, uN[96]:0x0002000080000000FA8CFC2D),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:3 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(u8:6, uN[96]:0x000000018000000098C475E6),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:4 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(u8:6, uN[96]:0x000100018000000036FBEF9F),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:5 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(u8:6, uN[96]:0x0002000180000000D5336958),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:6 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(u8:6, uN[96]:0x0000000280000000736AE311),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:7 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(u8:6, uN[96]:0x000100028000000011A25CCA),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:8 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(u8:6, uN[96]:0x0002000280000000AFD9D683),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:9 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:9,
        frame: axis::pack(u8:6, uN[96]:0x00000000800000004E11503C),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:10 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:10,
        frame: axis::pack(u8:6, uN[96]:0x0001000080000000EC48C9F5),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:11 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:11,
        frame: axis::pack(u8:6, uN[96]:0x00020000800000008A8043AE),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:12 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:12,
        frame: axis::pack(u8:6, uN[96]:0x000000018000000028B7BD67),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:13 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:13,
        frame: axis::pack(u8:6, uN[96]:0x0001000180000000C6EF3720),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:14 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:14,
        frame: axis::pack(u8:6, uN[96]:0x00020001800000006526B0D9),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:15 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:15,
        frame: axis::pack(u8:6, uN[96]:0x0000000280000000035E2A92),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:16 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:16,
        frame: axis::pack(u8:6, uN[96]:0x0001000280000000A195A44B),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:17 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:17,
        frame: axis::pack(u8:6, uN[96]:0x00020002800000003FCD1E04),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      _ => zero!<phenom_syndrome_cell::ScheduledRequest>(),
    };
    let active = index < u32:18;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerRouter0 {
  scheduled_in: chan<phenom_data_cell::ScheduledEgress> in;
  credit_out: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_2: chan<phenom_syndrome_cell::ScheduledRequest> out;
  data_measurements_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phenom_data_cell::ScheduledEgress> in,
    credit_out: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_2: chan<phenom_syndrome_cell::ScheduledRequest> out,
    data_measurements_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_2, data_measurements_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let routed_tok = if scheduled.slot < u32:9 {
      let local = scheduled.slot - u32:0;
      let x = local / HEIGHT;
      let y = local % HEIGHT;
      match scheduled.egress.port {
        phenom_data_cell::OutputPort::NORTH => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:9 + (x + WIDTH - u32:1) % WIDTH * HEIGHT + (y + HEIGHT - u32:1) % HEIGHT,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::EAST => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:0 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::WEST => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:0 + (x + WIDTH - u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::SOUTH => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:9 + (x + WIDTH - u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::MEASUREMENT => send(tok, data_measurements_out, scheduled.egress.frame),
      }
    } else {
      if scheduled.slot < u32:18 {
      let local = scheduled.slot - u32:9;
      let x = local / HEIGHT;
      let y = local % HEIGHT;
      match scheduled.egress.port {
        phenom_data_cell::OutputPort::NORTH => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:0 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::EAST => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:9 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::WEST => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:9 + (x + WIDTH - u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::SOUTH => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:0 + x * HEIGHT + (y + u32:1) % HEIGHT,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::MEASUREMENT => send(tok, data_measurements_out, scheduled.egress.frame),
      }
    } else {
      tok
    }
    };
    let _done = send(
      routed_tok, credit_out, phenom_data_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_data_cell::ScheduledRequest>()
      });
    state
  }
}

proc SchedulerRouter1 {
  scheduled_in: chan<phi_halo_cell::ScheduledEgress> in;
  credit_out: chan<phi_halo_cell::ScheduledRequest> out;
  to_scheduler_1: chan<phi_halo_cell::ScheduledRequest> out;
  to_scheduler_2: chan<phenom_syndrome_cell::ScheduledRequest> out;
  x_decoder_events_out: chan<axis::Frame> out;
  z_decoder_events_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phi_halo_cell::ScheduledEgress> in,
    credit_out: chan<phi_halo_cell::ScheduledRequest> out,
    to_scheduler_1: chan<phi_halo_cell::ScheduledRequest> out,
    to_scheduler_2: chan<phenom_syndrome_cell::ScheduledRequest> out,
    x_decoder_events_out: chan<axis::Frame> out,
    z_decoder_events_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_1, to_scheduler_2, x_decoder_events_out, z_decoder_events_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let routed_tok = if scheduled.slot < u32:9 {
      let local = scheduled.slot - u32:0;
      let x = local / HEIGHT;
      let y = local % HEIGHT;
      match scheduled.egress.port {
        phi_halo_cell::OutputPort::NORTH => send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:0 + x * HEIGHT + (y + HEIGHT - u32:1) % HEIGHT,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::EAST => send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:0 + (x + u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::WEST => send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:0 + (x + WIDTH - u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::SOUTH => send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:0 + x * HEIGHT + (y + u32:1) % HEIGHT,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::SYNDROME => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:0 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::CORRECTION => send(tok, x_decoder_events_out, scheduled.egress.frame),
        phi_halo_cell::OutputPort::STATUS => send(tok, x_decoder_events_out, scheduled.egress.frame),
      }
    } else {
      if scheduled.slot < u32:18 {
      let local = scheduled.slot - u32:9;
      let x = local / HEIGHT;
      let y = local % HEIGHT;
      match scheduled.egress.port {
        phi_halo_cell::OutputPort::NORTH => send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:9 + x * HEIGHT + (y + HEIGHT - u32:1) % HEIGHT,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::EAST => send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:9 + (x + u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::WEST => send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:9 + (x + WIDTH - u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::SOUTH => send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:9 + x * HEIGHT + (y + u32:1) % HEIGHT,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::SYNDROME => send(tok, to_scheduler_2, phenom_syndrome_cell::ScheduledRequest {
            slot: u32:9 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::CORRECTION => send(tok, z_decoder_events_out, scheduled.egress.frame),
        phi_halo_cell::OutputPort::STATUS => send(tok, z_decoder_events_out, scheduled.egress.frame),
      }
    } else {
      tok
    }
    };
    let _done = send(
      routed_tok, credit_out, phi_halo_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phi_halo_cell::ScheduledRequest>()
      });
    state
  }
}

proc SchedulerRouter2 {
  scheduled_in: chan<phenom_syndrome_cell::ScheduledEgress> in;
  credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_1: chan<phi_halo_cell::ScheduledRequest> out;
  x_announcements_out: chan<axis::Frame> out;
  z_announcements_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phenom_syndrome_cell::ScheduledEgress> in,
    credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_1: chan<phi_halo_cell::ScheduledRequest> out,
    x_announcements_out: chan<axis::Frame> out,
    z_announcements_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_0, to_scheduler_1, x_announcements_out, z_announcements_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let routed_tok = if scheduled.slot < u32:9 {
      let local = scheduled.slot - u32:0;
      let x = local / HEIGHT;
      let y = local % HEIGHT;
      match scheduled.egress.port {
        phenom_syndrome_cell::OutputPort::NORTH => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: u32:9 + x * HEIGHT + (y + HEIGHT - u32:1) % HEIGHT,
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::EAST => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: u32:0 + (x + u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::WEST => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: u32:0 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::SOUTH => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: u32:9 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::PHI => {
          let left_tok = send(tok, x_announcements_out, scheduled.egress.frame);
          let right_tok = send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:0 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          });
          join(left_tok, right_tok)
        },
      }
    } else {
      if scheduled.slot < u32:18 {
      let local = scheduled.slot - u32:9;
      let x = local / HEIGHT;
      let y = local % HEIGHT;
      match scheduled.egress.port {
        phenom_syndrome_cell::OutputPort::NORTH => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: u32:0 + (x + u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::EAST => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: u32:9 + (x + u32:1) % WIDTH * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::WEST => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: u32:9 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::SOUTH => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: u32:0 + (x + u32:1) % WIDTH * HEIGHT + (y + u32:1) % HEIGHT,
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::PHI => {
          let left_tok = send(tok, z_announcements_out, scheduled.egress.frame);
          let right_tok = send(tok, to_scheduler_1, phi_halo_cell::ScheduledRequest {
            slot: u32:9 + x * HEIGHT + y,
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          });
          join(left_tok, right_tok)
        },
      }
    } else {
      tok
    }
    };
    let _done = send(
      routed_tok, credit_out, phenom_syndrome_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      });
    state
  }
}

proc SchedulerGrid {
  config(
    scheduler_0_ram_req_out: chan<phenom_data_cell::MachineRamReq> out,
    scheduler_0_ram_resp_in: chan<phenom_data_cell::MachineRamResp> in,
    scheduler_0_ram_wr_comp_in: chan<()> in,
    scheduler_0_mailbox_req_out: chan<phenom_data_cell::MailboxRamReq> out,
    scheduler_0_mailbox_resp_in: chan<phenom_data_cell::MailboxRamResp> in,
    scheduler_0_mailbox_wr_comp_in: chan<()> in,
    scheduler_1_ram_req_out: chan<phi_halo_cell::MachineRamReq> out,
    scheduler_1_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in,
    scheduler_1_ram_wr_comp_in: chan<()> in,
    scheduler_1_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out,
    scheduler_1_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in,
    scheduler_1_mailbox_wr_comp_in: chan<()> in,
    scheduler_2_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out,
    scheduler_2_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in,
    scheduler_2_ram_wr_comp_in: chan<()> in,
    scheduler_2_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out,
    scheduler_2_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in,
    scheduler_2_mailbox_wr_comp_in: chan<()> in,
    control_router_in: chan<hls_spatial_router::SpatialFrame> in,
    data_measurements_out: chan<axis::Frame> out,
    x_announcements_out: chan<axis::Frame> out,
    x_decoder_events_out: chan<axis::Frame> out,
    z_announcements_out: chan<axis::Frame> out,
    z_decoder_events_out: chan<axis::Frame> out
  ) {
    let (external_0_buffer_p, external_0_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_0_buffer");
    let (external_1_buffer_p, external_1_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_1_buffer");
    let (external_2_buffer_p, external_2_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_2_buffer");
    let (external_3_buffer_p, external_3_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_3_buffer");
    let (external_4_buffer_p, external_4_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_4_buffer");
    let (scheduler_0_requests_p, scheduler_0_requests_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:3]("scheduler_0_requests");
    let (scheduler_0_startup_p, scheduler_0_startup_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_0_startup");
    let (scheduler_0_egress_p, scheduler_0_egress_c) =
      chan<phenom_data_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_0_egress");
    spawn SchedulerStartup0(scheduler_0_startup_p);
    let (scheduler_1_requests_p, scheduler_1_requests_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:3]("scheduler_1_requests");
    let (scheduler_1_startup_p, scheduler_1_startup_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_1_startup");
    let (scheduler_1_egress_p, scheduler_1_egress_c) =
      chan<phi_halo_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_1_egress");
    spawn SchedulerStartup1(scheduler_1_startup_p);
    let (scheduler_2_requests_p, scheduler_2_requests_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:4]("scheduler_2_requests");
    let (scheduler_2_startup_p, scheduler_2_startup_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_2_startup");
    let (scheduler_2_egress_p, scheduler_2_egress_c) =
      chan<phenom_syndrome_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_2_egress");
    spawn SchedulerStartup2(scheduler_2_startup_p);
    spawn phenom_data_cell::SharedService<
      u32:18, u32:3, u32:18>(
      scheduler_0_requests_c, scheduler_0_startup_c,
      scheduler_0_egress_p,
      scheduler_0_ram_req_out, scheduler_0_ram_resp_in,
      scheduler_0_ram_wr_comp_in,
      scheduler_0_mailbox_req_out, scheduler_0_mailbox_resp_in,
      scheduler_0_mailbox_wr_comp_in);
    spawn phi_halo_cell::SharedService<
      u32:18, u32:3, u32:18>(
      scheduler_1_requests_c, scheduler_1_startup_c,
      scheduler_1_egress_p,
      scheduler_1_ram_req_out, scheduler_1_ram_resp_in,
      scheduler_1_ram_wr_comp_in,
      scheduler_1_mailbox_req_out, scheduler_1_mailbox_resp_in,
      scheduler_1_mailbox_wr_comp_in);
    spawn phenom_syndrome_cell::SharedService<
      u32:18, u32:4, u32:18>(
      scheduler_2_requests_c, scheduler_2_startup_c,
      scheduler_2_egress_p,
      scheduler_2_ram_req_out, scheduler_2_ram_resp_in,
      scheduler_2_ram_wr_comp_in,
      scheduler_2_mailbox_req_out, scheduler_2_mailbox_resp_in,
      scheduler_2_mailbox_wr_comp_in);
    spawn SchedulerRouter0(
      scheduler_0_egress_c, scheduler_0_requests_p[u32:2],
      scheduler_2_requests_p[u32:0],
      external_0_buffer_p);
    spawn SchedulerRouter1(
      scheduler_1_egress_c, scheduler_1_requests_p[u32:2],
      scheduler_1_requests_p[u32:0],
      scheduler_2_requests_p[u32:1],
      external_2_buffer_p,
      external_4_buffer_p);
    spawn SchedulerRouter2(
      scheduler_2_egress_c, scheduler_2_requests_p[u32:3],
      scheduler_0_requests_p[u32:0],
      scheduler_1_requests_p[u32:1],
      external_1_buffer_p,
      external_3_buffer_p);
    spawn ControlDispatcher(control_router_in, scheduler_0_requests_p[u32:1], scheduler_2_requests_p[u32:2]);
    spawn FrameRelay(external_0_buffer_c, data_measurements_out);
    spawn FrameRelay(external_1_buffer_c, x_announcements_out);
    spawn FrameRelay(external_2_buffer_c, x_decoder_events_out);
    spawn FrameRelay(external_3_buffer_c, z_announcements_out);
    spawn FrameRelay(external_4_buffer_c, z_decoder_events_out);
    ()
  }

  init { () }
  next(state: ()) { state }
}

pub proc Top {
  scheduler_0_ram_req_out: chan<phenom_data_cell::MachineRamReq> out;
  scheduler_0_ram_resp_in: chan<phenom_data_cell::MachineRamResp> in;
  scheduler_0_ram_wr_comp_in: chan<()> in;
  scheduler_0_mailbox_req_out: chan<phenom_data_cell::MailboxRamReq> out;
  scheduler_0_mailbox_resp_in: chan<phenom_data_cell::MailboxRamResp> in;
  scheduler_0_mailbox_wr_comp_in: chan<()> in;
  scheduler_1_ram_req_out: chan<phi_halo_cell::MachineRamReq> out;
  scheduler_1_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in;
  scheduler_1_ram_wr_comp_in: chan<()> in;
  scheduler_1_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out;
  scheduler_1_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in;
  scheduler_1_mailbox_wr_comp_in: chan<()> in;
  scheduler_2_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out;
  scheduler_2_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in;
  scheduler_2_ram_wr_comp_in: chan<()> in;
  scheduler_2_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out;
  scheduler_2_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in;
  scheduler_2_mailbox_wr_comp_in: chan<()> in;
  control_router_in: chan<hls_spatial_router::SpatialFrame> in;
  data_measurements_out: chan<axis::Frame> out;
  x_announcements_out: chan<axis::Frame> out;
  x_decoder_events_out: chan<axis::Frame> out;
  z_announcements_out: chan<axis::Frame> out;
  z_decoder_events_out: chan<axis::Frame> out;

  config(
    scheduler_0_ram_req_out: chan<phenom_data_cell::MachineRamReq> out,
    scheduler_0_ram_resp_in: chan<phenom_data_cell::MachineRamResp> in,
    scheduler_0_ram_wr_comp_in: chan<()> in,
    scheduler_0_mailbox_req_out: chan<phenom_data_cell::MailboxRamReq> out,
    scheduler_0_mailbox_resp_in: chan<phenom_data_cell::MailboxRamResp> in,
    scheduler_0_mailbox_wr_comp_in: chan<()> in,
    scheduler_1_ram_req_out: chan<phi_halo_cell::MachineRamReq> out,
    scheduler_1_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in,
    scheduler_1_ram_wr_comp_in: chan<()> in,
    scheduler_1_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out,
    scheduler_1_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in,
    scheduler_1_mailbox_wr_comp_in: chan<()> in,
    scheduler_2_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out,
    scheduler_2_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in,
    scheduler_2_ram_wr_comp_in: chan<()> in,
    scheduler_2_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out,
    scheduler_2_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in,
    scheduler_2_mailbox_wr_comp_in: chan<()> in,
    control_router_in: chan<hls_spatial_router::SpatialFrame> in,
    data_measurements_out: chan<axis::Frame> out,
    x_announcements_out: chan<axis::Frame> out,
    x_decoder_events_out: chan<axis::Frame> out,
    z_announcements_out: chan<axis::Frame> out,
    z_decoder_events_out: chan<axis::Frame> out
  ) {
    spawn SchedulerGrid(
      scheduler_0_ram_req_out,
      scheduler_0_ram_resp_in,
      scheduler_0_ram_wr_comp_in,
      scheduler_0_mailbox_req_out,
      scheduler_0_mailbox_resp_in,
      scheduler_0_mailbox_wr_comp_in,
      scheduler_1_ram_req_out,
      scheduler_1_ram_resp_in,
      scheduler_1_ram_wr_comp_in,
      scheduler_1_mailbox_req_out,
      scheduler_1_mailbox_resp_in,
      scheduler_1_mailbox_wr_comp_in,
      scheduler_2_ram_req_out,
      scheduler_2_ram_resp_in,
      scheduler_2_ram_wr_comp_in,
      scheduler_2_mailbox_req_out,
      scheduler_2_mailbox_resp_in,
      scheduler_2_mailbox_wr_comp_in,
      control_router_in,
      data_measurements_out,
      x_announcements_out,
      x_decoder_events_out,
      z_announcements_out,
      z_decoder_events_out
    );
    (scheduler_0_ram_req_out, scheduler_0_ram_resp_in, scheduler_0_ram_wr_comp_in, scheduler_0_mailbox_req_out, scheduler_0_mailbox_resp_in, scheduler_0_mailbox_wr_comp_in, scheduler_1_ram_req_out, scheduler_1_ram_resp_in, scheduler_1_ram_wr_comp_in, scheduler_1_mailbox_req_out, scheduler_1_mailbox_resp_in, scheduler_1_mailbox_wr_comp_in, scheduler_2_ram_req_out, scheduler_2_ram_resp_in, scheduler_2_ram_wr_comp_in, scheduler_2_mailbox_req_out, scheduler_2_mailbox_resp_in, scheduler_2_mailbox_wr_comp_in, control_router_in, data_measurements_out, x_announcements_out, x_decoder_events_out, z_announcements_out, z_decoder_events_out)
  }

  init { () }
  next(state: ()) { state }
}
