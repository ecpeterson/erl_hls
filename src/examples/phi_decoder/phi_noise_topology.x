// phi_noise_topology.x
// Auto-generated from compact Erlang topology and scheduler rules.
// Manual changes will be overwritten.
//
// Actor state and mailbox frames use separate RAMs. Requests and
// scheduler egress carry dense RAM slots; each group router maps its
// egress slot to a narrow family and coordinate address.

import axis;
import hls_spatial_router;
import phenom_data_cell;
import phenom_syndrome_cell;
import phi_halo_cell;

const CHANNEL_DEPTH = u32:1;
const WIDTH = u16:3;
const HEIGHT = u16:3;

enum FamilyId : u8 {
  DATA_EVEN = u8:0,
  DATA_ODD = u8:1,
  PHI_X = u8:2,
  PHI_Z = u8:3,
  SYNDROME_X = u8:4,
  SYNDROME_Z = u8:5,
}

struct ScheduledAddress {
  family: u8,
  x: u16,
  y: u16,
}

fn scheduler_0_address(slot: u32) -> ScheduledAddress {
  match slot {
    u32:0 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:0, y: u16:0 },
    u32:1 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:0, y: u16:1 },
    u32:2 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:0, y: u16:2 },
    u32:3 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:1, y: u16:0 },
    u32:4 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:1, y: u16:1 },
    u32:5 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:1, y: u16:2 },
    u32:6 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:2, y: u16:0 },
    u32:7 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:2, y: u16:1 },
    u32:8 => ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: u16:2, y: u16:2 },
    _ => zero!<ScheduledAddress>(),
  }
}

fn scheduler_0_slot(address: ScheduledAddress) -> u32 {
  match (address.family as FamilyId, address.x, address.y) {
    (FamilyId::DATA_EVEN, u16:0, u16:0) => u32:0,
    (FamilyId::DATA_EVEN, u16:0, u16:1) => u32:1,
    (FamilyId::DATA_EVEN, u16:0, u16:2) => u32:2,
    (FamilyId::DATA_EVEN, u16:1, u16:0) => u32:3,
    (FamilyId::DATA_EVEN, u16:1, u16:1) => u32:4,
    (FamilyId::DATA_EVEN, u16:1, u16:2) => u32:5,
    (FamilyId::DATA_EVEN, u16:2, u16:0) => u32:6,
    (FamilyId::DATA_EVEN, u16:2, u16:1) => u32:7,
    (FamilyId::DATA_EVEN, u16:2, u16:2) => u32:8,
    _ => u32:9,
  }
}

fn scheduler_1_address(slot: u32) -> ScheduledAddress {
  match slot {
    u32:0 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:0, y: u16:0 },
    u32:1 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:0, y: u16:1 },
    u32:2 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:0, y: u16:2 },
    u32:3 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:1, y: u16:0 },
    u32:4 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:1, y: u16:1 },
    u32:5 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:1, y: u16:2 },
    u32:6 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:2, y: u16:0 },
    u32:7 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:2, y: u16:1 },
    u32:8 => ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: u16:2, y: u16:2 },
    _ => zero!<ScheduledAddress>(),
  }
}

fn scheduler_1_slot(address: ScheduledAddress) -> u32 {
  match (address.family as FamilyId, address.x, address.y) {
    (FamilyId::DATA_ODD, u16:0, u16:0) => u32:0,
    (FamilyId::DATA_ODD, u16:0, u16:1) => u32:1,
    (FamilyId::DATA_ODD, u16:0, u16:2) => u32:2,
    (FamilyId::DATA_ODD, u16:1, u16:0) => u32:3,
    (FamilyId::DATA_ODD, u16:1, u16:1) => u32:4,
    (FamilyId::DATA_ODD, u16:1, u16:2) => u32:5,
    (FamilyId::DATA_ODD, u16:2, u16:0) => u32:6,
    (FamilyId::DATA_ODD, u16:2, u16:1) => u32:7,
    (FamilyId::DATA_ODD, u16:2, u16:2) => u32:8,
    _ => u32:9,
  }
}

fn scheduler_2_address(slot: u32) -> ScheduledAddress {
  match slot {
    u32:0 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:0, y: u16:0 },
    u32:1 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:0, y: u16:1 },
    u32:2 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:0, y: u16:2 },
    u32:3 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:1, y: u16:0 },
    u32:4 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:1, y: u16:1 },
    u32:5 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:1, y: u16:2 },
    u32:6 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:2, y: u16:0 },
    u32:7 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:2, y: u16:1 },
    u32:8 => ScheduledAddress { family: FamilyId::PHI_X as u8, x: u16:2, y: u16:2 },
    _ => zero!<ScheduledAddress>(),
  }
}

fn scheduler_2_slot(address: ScheduledAddress) -> u32 {
  match (address.family as FamilyId, address.x, address.y) {
    (FamilyId::PHI_X, u16:0, u16:0) => u32:0,
    (FamilyId::PHI_X, u16:0, u16:1) => u32:1,
    (FamilyId::PHI_X, u16:0, u16:2) => u32:2,
    (FamilyId::PHI_X, u16:1, u16:0) => u32:3,
    (FamilyId::PHI_X, u16:1, u16:1) => u32:4,
    (FamilyId::PHI_X, u16:1, u16:2) => u32:5,
    (FamilyId::PHI_X, u16:2, u16:0) => u32:6,
    (FamilyId::PHI_X, u16:2, u16:1) => u32:7,
    (FamilyId::PHI_X, u16:2, u16:2) => u32:8,
    _ => u32:9,
  }
}

fn scheduler_3_address(slot: u32) -> ScheduledAddress {
  match slot {
    u32:0 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:0, y: u16:0 },
    u32:1 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:0, y: u16:1 },
    u32:2 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:0, y: u16:2 },
    u32:3 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:1, y: u16:0 },
    u32:4 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:1, y: u16:1 },
    u32:5 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:1, y: u16:2 },
    u32:6 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:2, y: u16:0 },
    u32:7 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:2, y: u16:1 },
    u32:8 => ScheduledAddress { family: FamilyId::PHI_Z as u8, x: u16:2, y: u16:2 },
    _ => zero!<ScheduledAddress>(),
  }
}

fn scheduler_3_slot(address: ScheduledAddress) -> u32 {
  match (address.family as FamilyId, address.x, address.y) {
    (FamilyId::PHI_Z, u16:0, u16:0) => u32:0,
    (FamilyId::PHI_Z, u16:0, u16:1) => u32:1,
    (FamilyId::PHI_Z, u16:0, u16:2) => u32:2,
    (FamilyId::PHI_Z, u16:1, u16:0) => u32:3,
    (FamilyId::PHI_Z, u16:1, u16:1) => u32:4,
    (FamilyId::PHI_Z, u16:1, u16:2) => u32:5,
    (FamilyId::PHI_Z, u16:2, u16:0) => u32:6,
    (FamilyId::PHI_Z, u16:2, u16:1) => u32:7,
    (FamilyId::PHI_Z, u16:2, u16:2) => u32:8,
    _ => u32:9,
  }
}

fn scheduler_4_address(slot: u32) -> ScheduledAddress {
  match slot {
    u32:0 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:0, y: u16:0 },
    u32:1 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:0, y: u16:1 },
    u32:2 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:0, y: u16:2 },
    u32:3 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:1, y: u16:0 },
    u32:4 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:1, y: u16:1 },
    u32:5 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:1, y: u16:2 },
    u32:6 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:2, y: u16:0 },
    u32:7 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:2, y: u16:1 },
    u32:8 => ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: u16:2, y: u16:2 },
    _ => zero!<ScheduledAddress>(),
  }
}

fn scheduler_4_slot(address: ScheduledAddress) -> u32 {
  match (address.family as FamilyId, address.x, address.y) {
    (FamilyId::SYNDROME_X, u16:0, u16:0) => u32:0,
    (FamilyId::SYNDROME_X, u16:0, u16:1) => u32:1,
    (FamilyId::SYNDROME_X, u16:0, u16:2) => u32:2,
    (FamilyId::SYNDROME_X, u16:1, u16:0) => u32:3,
    (FamilyId::SYNDROME_X, u16:1, u16:1) => u32:4,
    (FamilyId::SYNDROME_X, u16:1, u16:2) => u32:5,
    (FamilyId::SYNDROME_X, u16:2, u16:0) => u32:6,
    (FamilyId::SYNDROME_X, u16:2, u16:1) => u32:7,
    (FamilyId::SYNDROME_X, u16:2, u16:2) => u32:8,
    _ => u32:9,
  }
}

fn scheduler_5_address(slot: u32) -> ScheduledAddress {
  match slot {
    u32:0 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:0, y: u16:0 },
    u32:1 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:0, y: u16:1 },
    u32:2 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:0, y: u16:2 },
    u32:3 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:1, y: u16:0 },
    u32:4 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:1, y: u16:1 },
    u32:5 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:1, y: u16:2 },
    u32:6 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:2, y: u16:0 },
    u32:7 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:2, y: u16:1 },
    u32:8 => ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: u16:2, y: u16:2 },
    _ => zero!<ScheduledAddress>(),
  }
}

fn scheduler_5_slot(address: ScheduledAddress) -> u32 {
  match (address.family as FamilyId, address.x, address.y) {
    (FamilyId::SYNDROME_Z, u16:0, u16:0) => u32:0,
    (FamilyId::SYNDROME_Z, u16:0, u16:1) => u32:1,
    (FamilyId::SYNDROME_Z, u16:0, u16:2) => u32:2,
    (FamilyId::SYNDROME_Z, u16:1, u16:0) => u32:3,
    (FamilyId::SYNDROME_Z, u16:1, u16:1) => u32:4,
    (FamilyId::SYNDROME_Z, u16:1, u16:2) => u32:5,
    (FamilyId::SYNDROME_Z, u16:2, u16:0) => u32:6,
    (FamilyId::SYNDROME_Z, u16:2, u16:1) => u32:7,
    (FamilyId::SYNDROME_Z, u16:2, u16:2) => u32:8,
    _ => u32:9,
  }
}

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
proc FrameArrayMux<INPUT_COUNT: u32> {
  frame_in: chan<axis::Frame>[INPUT_COUNT] in;
  frame_out: chan<axis::Frame> out;

  config(
      frame_in: chan<axis::Frame>[INPUT_COUNT] in,
      frame_out: chan<axis::Frame> out
  ) {
    (frame_in, frame_out)
  }

  init { u32:0 }

  next(cursor: u32) {
    let (tok, received, frame) =
      unroll_for! (candidate, acc):
          (u32, (token, u1, axis::Frame)) in u32:0..INPUT_COUNT {
        let selected = cursor == candidate;
        let (next_tok, next_frame, valid) = recv_if_non_blocking(
          acc.0, frame_in[candidate], selected, zero!<axis::Frame>());
        (
          next_tok,
          acc.1 | valid,
          if valid { next_frame } else { acc.2 }
        )
      }((join(), u1:0, zero!<axis::Frame>()));
    let _done = send_if(tok, frame_out, received, frame);
    if cursor + u32:1 == INPUT_COUNT {
      u32:0
    } else {
      cursor + u32:1
    }
  }
}
enum ControlFamily : u8 {
  DATA_EVEN = u8:0,
  DATA_ODD = u8:1,
  SYNDROME_X = u8:2,
  SYNDROME_Z = u8:3,
}

struct ControlState {
  active: u1,
  packet: hls_spatial_router::SpatialFrame,
  family: u8,
  x: u16,
  y: u16,
}

proc ControlDispatcher {
  spatial_in: chan<hls_spatial_router::SpatialFrame> in;
  scheduler_0_control_out: chan<phenom_data_cell::ScheduledRequest> out;
  scheduler_1_control_out: chan<phenom_data_cell::ScheduledRequest> out;
  scheduler_4_control_out: chan<phenom_syndrome_cell::ScheduledRequest> out;
  scheduler_5_control_out: chan<phenom_syndrome_cell::ScheduledRequest> out;

  config(
    spatial_in: chan<hls_spatial_router::SpatialFrame> in,
    scheduler_0_control_out: chan<phenom_data_cell::ScheduledRequest> out,
    scheduler_1_control_out: chan<phenom_data_cell::ScheduledRequest> out,
    scheduler_4_control_out: chan<phenom_syndrome_cell::ScheduledRequest> out,
    scheduler_5_control_out: chan<phenom_syndrome_cell::ScheduledRequest> out
  ) {
    (spatial_in, scheduler_0_control_out, scheduler_1_control_out, scheduler_4_control_out, scheduler_5_control_out)
  }

  init { zero!<ControlState>() }

  next(state: ControlState) {
    if !state.active {
      let (_tok, packet) = recv(join(), spatial_in);
      ControlState { active: u1:1, packet,
        ..zero!<ControlState>() }
    } else {
      let _done = match state.family as ControlFamily {
        ControlFamily::DATA_EVEN => {
          let address_x = state.x * u16:1 + u16:0;
          let address_y = state.y * u16:2 + u16:0;
          let selected = ((state.packet.target == u2:0 && (state.packet.frame.header.op == u8:13 || state.packet.frame.header.op == u8:16)) || (state.packet.target == u2:1 && (state.packet.frame.header.op == u8:15))) && hls_spatial_router::contains(
            state.packet.rectangle, address_x, address_y);
          let request = phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: state.x, y: state.y }),
            frame: state.packet.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          };
          send_if(join(), scheduler_0_control_out, selected, request)
        },
        ControlFamily::DATA_ODD => {
          let address_x = state.x * u16:1 + u16:0;
          let address_y = state.y * u16:2 + u16:1;
          let selected = ((state.packet.target == u2:0 && (state.packet.frame.header.op == u8:13 || state.packet.frame.header.op == u8:16)) || (state.packet.target == u2:1 && (state.packet.frame.header.op == u8:15))) && hls_spatial_router::contains(
            state.packet.rectangle, address_x, address_y);
          let request = phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: state.x, y: state.y }),
            frame: state.packet.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          };
          send_if(join(), scheduler_1_control_out, selected, request)
        },
        ControlFamily::SYNDROME_X => {
          let address_x = state.x * u16:1 + u16:0;
          let address_y = state.y * u16:2 + u16:0;
          let selected = ((state.packet.target == u2:1 && (state.packet.frame.header.op == u8:15))) && hls_spatial_router::contains(
            state.packet.rectangle, address_x, address_y);
          let request = phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: state.x, y: state.y }),
            frame: state.packet.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          };
          send_if(join(), scheduler_4_control_out, selected, request)
        },
        ControlFamily::SYNDROME_Z => {
          let address_x = state.x * u16:1 + u16:0;
          let address_y = state.y * u16:2 + u16:0;
          let selected = ((state.packet.target == u2:1 && (state.packet.frame.header.op == u8:15))) && hls_spatial_router::contains(
            state.packet.rectangle, address_x, address_y);
          let request = phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: state.x, y: state.y }),
            frame: state.packet.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          };
          send_if(join(), scheduler_5_control_out, selected, request)
        },
        _ => join(),
      };
      let last_y = state.y + u16:1 == u16:3;
      let last_x = state.x + u16:1 == u16:3;
      let last_family = state.family + u8:1 == u8:4;
      let family_done = last_y && last_x;
      let all_done = family_done && last_family;
      ControlState {
        active: !all_done,
        family: if family_done { state.family + u8:1 }
          else { state.family },
        x: if last_y {
          if last_x { u16:0 } else { state.x + u16:1 }
        } else { state.x },
        y: if last_y { u16:0 } else { state.y + u16:1 },
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
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:2654435769,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:0,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:1 => phenom_data_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:1013904242,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:2,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:2 => phenom_data_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:3668340011,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:4,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:3 => phenom_data_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:2027808484,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:0,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:4 => phenom_data_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:387276957,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:2,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:5 => phenom_data_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:3041712726,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:4,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:6 => phenom_data_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:1401181199,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:0,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:7 => phenom_data_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:4055616968,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:2,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:8 => phenom_data_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:2415085441,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:4,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      _ => zero!<phenom_data_cell::ScheduledRequest>(),
    };
    let active = index < u32:9;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerStartup1 {
  request_out: chan<phenom_data_cell::ScheduledRequest> out;

  config(request_out: chan<phenom_data_cell::ScheduledRequest> out) { (request_out,) }

  init { u32:0 }

  next(index: u32) {
    let request = match index {
      u32:0 => phenom_data_cell::ScheduledRequest {
        slot: u32:0,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:774553914,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:1,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:1 => phenom_data_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:3428989683,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:3,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:2 => phenom_data_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:1788458156,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:5,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:3 => phenom_data_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:147926629,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:1,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:4 => phenom_data_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:2802362398,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:3,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:5 => phenom_data_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:1161830871,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:5,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:6 => phenom_data_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:3816266640,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:1,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:7 => phenom_data_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:2175735113,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:3,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:8 => phenom_data_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          phenom_data_cell::bits_from_phenomconfig(
            phenom_data_cell::Phenomconfig {
              seed: u32:535203586,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:5,
            })),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      _ => zero!<phenom_data_cell::ScheduledRequest>(),
    };
    let active = index < u32:9;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerStartup2 {
  request_out: chan<phi_halo_cell::ScheduledRequest> out;

  config(request_out: chan<phi_halo_cell::ScheduledRequest> out) { (request_out,) }

  init { u32:0 }

  next(index: u32) {
    let request = match index {
      u32:0 => phi_halo_cell::ScheduledRequest {
        slot: u32:0,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:3724842941,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:1 => phi_halo_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:2084311414,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:2 => phi_halo_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:443779887,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:3 => phi_halo_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:3098215656,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:4 => phi_halo_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:1457684129,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:5 => phi_halo_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:4112119898,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:6 => phi_halo_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:2471588371,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:7 => phi_halo_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:831056844,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:8 => phi_halo_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:3485492613,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      _ => zero!<phi_halo_cell::ScheduledRequest>(),
    };
    let active = index < u32:9;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerStartup3 {
  request_out: chan<phi_halo_cell::ScheduledRequest> out;

  config(request_out: chan<phi_halo_cell::ScheduledRequest> out) { (request_out,) }

  init { u32:0 }

  next(index: u32) {
    let request = match index {
      u32:0 => phi_halo_cell::ScheduledRequest {
        slot: u32:0,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:1844961086,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:1 => phi_halo_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:204429559,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:2 => phi_halo_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:2858865328,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:3 => phi_halo_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:1218333801,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:4 => phi_halo_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:3872769570,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:5 => phi_halo_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:2232238043,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:6 => phi_halo_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:591706516,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:7 => phi_halo_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:3246142285,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:8 => phi_halo_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          phi_halo_cell::bits_from_phiconfig(
            phi_halo_cell::Phiconfig {
              seed: u32:1605610758,
            })),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      _ => zero!<phi_halo_cell::ScheduledRequest>(),
    };
    let active = index < u32:9;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerStartup4 {
  request_out: chan<phenom_syndrome_cell::ScheduledRequest> out;

  config(request_out: chan<phenom_syndrome_cell::ScheduledRequest> out) { (request_out,) }

  init { u32:0 }

  next(index: u32) {
    let request = match index {
      u32:0 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:0,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:3189639355,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:0,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:1 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:1549107828,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:1,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:2 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:4203543597,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:2,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:3 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:2563012070,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:0,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:4 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:922480543,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:1,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:5 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:3576916312,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:2,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:6 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:1936384785,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:0,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:7 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:295853258,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:1,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:8 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:2950289027,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:2,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      _ => zero!<phenom_syndrome_cell::ScheduledRequest>(),
    };
    let active = index < u32:9;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerStartup5 {
  request_out: chan<phenom_syndrome_cell::ScheduledRequest> out;

  config(request_out: chan<phenom_syndrome_cell::ScheduledRequest> out) { (request_out,) }

  init { u32:0 }

  next(index: u32) {
    let request = match index {
      u32:0 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:0,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:1309757500,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:0,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:1 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:3964193269,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:1,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:2 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:2323661742,
              threshold: u32:2147483648,
              x: u16:0,
              y: u16:2,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:3 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:683130215,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:0,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:4 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:3337565984,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:1,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:5 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:1697034457,
              threshold: u32:2147483648,
              x: u16:1,
              y: u16:2,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:6 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:56502930,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:0,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:7 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:2710938699,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:1,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:8 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          phenom_syndrome_cell::bits_from_phenomconfig(
            phenom_syndrome_cell::Phenomconfig {
              seed: u32:1070407172,
              threshold: u32:2147483648,
              x: u16:2,
              y: u16:2,
            })),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      _ => zero!<phenom_syndrome_cell::ScheduledRequest>(),
    };
    let active = index < u32:9;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

proc SchedulerRouter0 {
  scheduled_in: chan<phenom_data_cell::ScheduledEgress> in;
  credit_out: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out;
  data_measurements_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phenom_data_cell::ScheduledEgress> in,
    credit_out: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out,
    data_measurements_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_4, to_scheduler_5, data_measurements_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let address = scheduler_0_address(scheduled.slot);
    let routed_tok = match address.family as FamilyId {
      FamilyId::DATA_EVEN => {
        let x = address.x;
        let y = address.y;
        match scheduled.egress.port {
        phenom_data_cell::OutputPort::NORTH => send(tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: (if y >= u16:1 { y - u16:1 } else { y + u16:2 }) }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::EAST => send(tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::WEST => send(tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::SOUTH => send(tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::MEASUREMENT => send(tok, data_measurements_out, scheduled.egress.frame),
        }
      },
      _ => tok,
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
  scheduled_in: chan<phenom_data_cell::ScheduledEgress> in;
  credit_out: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out;
  data_measurements_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phenom_data_cell::ScheduledEgress> in,
    credit_out: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out,
    data_measurements_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_4, to_scheduler_5, data_measurements_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let address = scheduler_1_address(scheduled.slot);
    let routed_tok = match address.family as FamilyId {
      FamilyId::DATA_ODD => {
        let x = address.x;
        let y = address.y;
        match scheduled.egress.port {
        phenom_data_cell::OutputPort::NORTH => send(tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::EAST => send(tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::WEST => send(tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::SOUTH => send(tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: x, y: (if y >= u16:2 { y - u16:2 } else { y + u16:1 }) }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::MEASUREMENT => send(tok, data_measurements_out, scheduled.egress.frame),
        }
      },
      _ => tok,
    };
    let _done = send(
      routed_tok, credit_out, phenom_data_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_data_cell::ScheduledRequest>()
      });
    state
  }
}

proc SchedulerRouter2 {
  scheduled_in: chan<phi_halo_cell::ScheduledEgress> in;
  credit_out: chan<phi_halo_cell::ScheduledRequest> out;
  to_scheduler_2: chan<phi_halo_cell::ScheduledRequest> out;
  to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out;
  x_decoder_events_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phi_halo_cell::ScheduledEgress> in,
    credit_out: chan<phi_halo_cell::ScheduledRequest> out,
    to_scheduler_2: chan<phi_halo_cell::ScheduledRequest> out,
    to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out,
    x_decoder_events_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_2, to_scheduler_4, x_decoder_events_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let address = scheduler_2_address(scheduled.slot);
    let routed_tok = match address.family as FamilyId {
      FamilyId::PHI_X => {
        let x = address.x;
        let y = address.y;
        match scheduled.egress.port {
        phi_halo_cell::OutputPort::NORTH => send(tok, to_scheduler_2, phi_halo_cell::ScheduledRequest {
            slot: scheduler_2_slot(ScheduledAddress { family: FamilyId::PHI_X as u8, x: x, y: (if y >= u16:1 { y - u16:1 } else { y + u16:2 }) }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::EAST => send(tok, to_scheduler_2, phi_halo_cell::ScheduledRequest {
            slot: scheduler_2_slot(ScheduledAddress { family: FamilyId::PHI_X as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::WEST => send(tok, to_scheduler_2, phi_halo_cell::ScheduledRequest {
            slot: scheduler_2_slot(ScheduledAddress { family: FamilyId::PHI_X as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::SOUTH => send(tok, to_scheduler_2, phi_halo_cell::ScheduledRequest {
            slot: scheduler_2_slot(ScheduledAddress { family: FamilyId::PHI_X as u8, x: x, y: (if y >= u16:2 { y - u16:2 } else { y + u16:1 }) }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::SYNDROME => send(tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::CORRECTION => send(tok, x_decoder_events_out, scheduled.egress.frame),
        phi_halo_cell::OutputPort::STATUS => send(tok, x_decoder_events_out, scheduled.egress.frame),
        }
      },
      _ => tok,
    };
    let _done = send(
      routed_tok, credit_out, phi_halo_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phi_halo_cell::ScheduledRequest>()
      });
    state
  }
}

proc SchedulerRouter3 {
  scheduled_in: chan<phi_halo_cell::ScheduledEgress> in;
  credit_out: chan<phi_halo_cell::ScheduledRequest> out;
  to_scheduler_3: chan<phi_halo_cell::ScheduledRequest> out;
  to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out;
  z_decoder_events_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phi_halo_cell::ScheduledEgress> in,
    credit_out: chan<phi_halo_cell::ScheduledRequest> out,
    to_scheduler_3: chan<phi_halo_cell::ScheduledRequest> out,
    to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out,
    z_decoder_events_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_3, to_scheduler_5, z_decoder_events_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let address = scheduler_3_address(scheduled.slot);
    let routed_tok = match address.family as FamilyId {
      FamilyId::PHI_Z => {
        let x = address.x;
        let y = address.y;
        match scheduled.egress.port {
        phi_halo_cell::OutputPort::NORTH => send(tok, to_scheduler_3, phi_halo_cell::ScheduledRequest {
            slot: scheduler_3_slot(ScheduledAddress { family: FamilyId::PHI_Z as u8, x: x, y: (if y >= u16:1 { y - u16:1 } else { y + u16:2 }) }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::EAST => send(tok, to_scheduler_3, phi_halo_cell::ScheduledRequest {
            slot: scheduler_3_slot(ScheduledAddress { family: FamilyId::PHI_Z as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::WEST => send(tok, to_scheduler_3, phi_halo_cell::ScheduledRequest {
            slot: scheduler_3_slot(ScheduledAddress { family: FamilyId::PHI_Z as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::SOUTH => send(tok, to_scheduler_3, phi_halo_cell::ScheduledRequest {
            slot: scheduler_3_slot(ScheduledAddress { family: FamilyId::PHI_Z as u8, x: x, y: (if y >= u16:2 { y - u16:2 } else { y + u16:1 }) }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::SYNDROME => send(tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::CORRECTION => send(tok, z_decoder_events_out, scheduled.egress.frame),
        phi_halo_cell::OutputPort::STATUS => send(tok, z_decoder_events_out, scheduled.egress.frame),
        }
      },
      _ => tok,
    };
    let _done = send(
      routed_tok, credit_out, phi_halo_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phi_halo_cell::ScheduledRequest>()
      });
    state
  }
}

proc SchedulerRouter4 {
  scheduled_in: chan<phenom_syndrome_cell::ScheduledEgress> in;
  credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_1: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_2: chan<phi_halo_cell::ScheduledRequest> out;
  x_announcements_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phenom_syndrome_cell::ScheduledEgress> in,
    credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_1: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_2: chan<phi_halo_cell::ScheduledRequest> out,
    x_announcements_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_0, to_scheduler_1, to_scheduler_2, x_announcements_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let address = scheduler_4_address(scheduled.slot);
    let routed_tok = match address.family as FamilyId {
      FamilyId::SYNDROME_X => {
        let x = address.x;
        let y = address.y;
        match scheduled.egress.port {
        phenom_syndrome_cell::OutputPort::NORTH => send(tok, to_scheduler_1, phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: x, y: (if y >= u16:1 { y - u16:1 } else { y + u16:2 }) }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::EAST => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::WEST => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::SOUTH => send(tok, to_scheduler_1, phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::PHI => {
          let left_tok = send(tok, x_announcements_out, scheduled.egress.frame);
          let right_tok = send(tok, to_scheduler_2, phi_halo_cell::ScheduledRequest {
            slot: scheduler_2_slot(ScheduledAddress { family: FamilyId::PHI_X as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          });
          join(left_tok, right_tok)
        },
        }
      },
      _ => tok,
    };
    let _done = send(
      routed_tok, credit_out, phenom_syndrome_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      });
    state
  }
}

proc SchedulerRouter5 {
  scheduled_in: chan<phenom_syndrome_cell::ScheduledEgress> in;
  credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_1: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_3: chan<phi_halo_cell::ScheduledRequest> out;
  z_announcements_out: chan<axis::Frame> out;

  config(
    scheduled_in: chan<phenom_syndrome_cell::ScheduledEgress> in,
    credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_1: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_3: chan<phi_halo_cell::ScheduledRequest> out,
    z_announcements_out: chan<axis::Frame> out
  ) {
    (scheduled_in, credit_out, to_scheduler_0, to_scheduler_1, to_scheduler_3, z_announcements_out)
  }

  init { () }

  next(state: ()) {
    let (tok, scheduled) = recv(join(), scheduled_in);
    let address = scheduler_5_address(scheduled.slot);
    let routed_tok = match address.family as FamilyId {
      FamilyId::SYNDROME_Z => {
        let x = address.x;
        let y = address.y;
        match scheduled.egress.port {
        phenom_syndrome_cell::OutputPort::NORTH => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::EAST => send(tok, to_scheduler_1, phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::WEST => send(tok, to_scheduler_1, phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::SOUTH => send(tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: (if y >= u16:2 { y - u16:2 } else { y + u16:1 }) }),
            frame: scheduled.egress.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::PHI => {
          let left_tok = send(tok, z_announcements_out, scheduled.egress.frame);
          let right_tok = send(tok, to_scheduler_3, phi_halo_cell::ScheduledRequest {
            slot: scheduler_3_slot(ScheduledAddress { family: FamilyId::PHI_Z as u8, x: x, y: y }),
            frame: scheduled.egress.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          });
          join(left_tok, right_tok)
        },
        }
      },
      _ => tok,
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
    scheduler_1_ram_req_out: chan<phenom_data_cell::MachineRamReq> out,
    scheduler_1_ram_resp_in: chan<phenom_data_cell::MachineRamResp> in,
    scheduler_1_ram_wr_comp_in: chan<()> in,
    scheduler_1_mailbox_req_out: chan<phenom_data_cell::MailboxRamReq> out,
    scheduler_1_mailbox_resp_in: chan<phenom_data_cell::MailboxRamResp> in,
    scheduler_1_mailbox_wr_comp_in: chan<()> in,
    scheduler_2_ram_req_out: chan<phi_halo_cell::MachineRamReq> out,
    scheduler_2_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in,
    scheduler_2_ram_wr_comp_in: chan<()> in,
    scheduler_2_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out,
    scheduler_2_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in,
    scheduler_2_mailbox_wr_comp_in: chan<()> in,
    scheduler_3_ram_req_out: chan<phi_halo_cell::MachineRamReq> out,
    scheduler_3_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in,
    scheduler_3_ram_wr_comp_in: chan<()> in,
    scheduler_3_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out,
    scheduler_3_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in,
    scheduler_3_mailbox_wr_comp_in: chan<()> in,
    scheduler_4_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out,
    scheduler_4_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in,
    scheduler_4_ram_wr_comp_in: chan<()> in,
    scheduler_4_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out,
    scheduler_4_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in,
    scheduler_4_mailbox_wr_comp_in: chan<()> in,
    scheduler_5_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out,
    scheduler_5_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in,
    scheduler_5_ram_wr_comp_in: chan<()> in,
    scheduler_5_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out,
    scheduler_5_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in,
    scheduler_5_mailbox_wr_comp_in: chan<()> in,
    control_router_in: chan<hls_spatial_router::SpatialFrame> in,
    data_measurements_out: chan<axis::Frame> out,
    x_announcements_out: chan<axis::Frame> out,
    x_decoder_events_out: chan<axis::Frame> out,
    z_announcements_out: chan<axis::Frame> out,
    z_decoder_events_out: chan<axis::Frame> out
  ) {
    let (external_0_buffer_p, external_0_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>[u32:2]("external_0_buffer");
    let (external_1_buffer_p, external_1_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_1_buffer");
    let (external_2_buffer_p, external_2_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_2_buffer");
    let (external_3_buffer_p, external_3_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_3_buffer");
    let (external_4_buffer_p, external_4_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_4_buffer");
    let (scheduler_0_requests_p, scheduler_0_requests_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:4]("scheduler_0_requests");
    let (scheduler_0_startup_p, scheduler_0_startup_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_0_startup");
    let (scheduler_0_egress_p, scheduler_0_egress_c) =
      chan<phenom_data_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_0_egress");
    spawn SchedulerStartup0(scheduler_0_startup_p);
    let (scheduler_1_requests_p, scheduler_1_requests_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:4]("scheduler_1_requests");
    let (scheduler_1_startup_p, scheduler_1_startup_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_1_startup");
    let (scheduler_1_egress_p, scheduler_1_egress_c) =
      chan<phenom_data_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_1_egress");
    spawn SchedulerStartup1(scheduler_1_startup_p);
    let (scheduler_2_requests_p, scheduler_2_requests_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:3]("scheduler_2_requests");
    let (scheduler_2_startup_p, scheduler_2_startup_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_2_startup");
    let (scheduler_2_egress_p, scheduler_2_egress_c) =
      chan<phi_halo_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_2_egress");
    spawn SchedulerStartup2(scheduler_2_startup_p);
    let (scheduler_3_requests_p, scheduler_3_requests_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:3]("scheduler_3_requests");
    let (scheduler_3_startup_p, scheduler_3_startup_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_3_startup");
    let (scheduler_3_egress_p, scheduler_3_egress_c) =
      chan<phi_halo_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_3_egress");
    spawn SchedulerStartup3(scheduler_3_startup_p);
    let (scheduler_4_requests_p, scheduler_4_requests_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:5]("scheduler_4_requests");
    let (scheduler_4_startup_p, scheduler_4_startup_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_4_startup");
    let (scheduler_4_egress_p, scheduler_4_egress_c) =
      chan<phenom_syndrome_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_4_egress");
    spawn SchedulerStartup4(scheduler_4_startup_p);
    let (scheduler_5_requests_p, scheduler_5_requests_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:5]("scheduler_5_requests");
    let (scheduler_5_startup_p, scheduler_5_startup_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_5_startup");
    let (scheduler_5_egress_p, scheduler_5_egress_c) =
      chan<phenom_syndrome_cell::ScheduledEgress, CHANNEL_DEPTH>("scheduler_5_egress");
    spawn SchedulerStartup5(scheduler_5_startup_p);
    spawn phenom_data_cell::SharedService<
      u32:9, u32:4, u32:9, u32:0>(
      scheduler_0_requests_c, scheduler_0_startup_c,
      scheduler_0_egress_p,
      scheduler_0_ram_req_out, scheduler_0_ram_resp_in,
      scheduler_0_ram_wr_comp_in,
      scheduler_0_mailbox_req_out, scheduler_0_mailbox_resp_in,
      scheduler_0_mailbox_wr_comp_in);
    spawn phenom_data_cell::SharedService<
      u32:9, u32:4, u32:9, u32:1>(
      scheduler_1_requests_c, scheduler_1_startup_c,
      scheduler_1_egress_p,
      scheduler_1_ram_req_out, scheduler_1_ram_resp_in,
      scheduler_1_ram_wr_comp_in,
      scheduler_1_mailbox_req_out, scheduler_1_mailbox_resp_in,
      scheduler_1_mailbox_wr_comp_in);
    spawn phi_halo_cell::SharedService<
      u32:9, u32:3, u32:9, u32:2>(
      scheduler_2_requests_c, scheduler_2_startup_c,
      scheduler_2_egress_p,
      scheduler_2_ram_req_out, scheduler_2_ram_resp_in,
      scheduler_2_ram_wr_comp_in,
      scheduler_2_mailbox_req_out, scheduler_2_mailbox_resp_in,
      scheduler_2_mailbox_wr_comp_in);
    spawn phi_halo_cell::SharedService<
      u32:9, u32:3, u32:9, u32:3>(
      scheduler_3_requests_c, scheduler_3_startup_c,
      scheduler_3_egress_p,
      scheduler_3_ram_req_out, scheduler_3_ram_resp_in,
      scheduler_3_ram_wr_comp_in,
      scheduler_3_mailbox_req_out, scheduler_3_mailbox_resp_in,
      scheduler_3_mailbox_wr_comp_in);
    spawn phenom_syndrome_cell::SharedService<
      u32:9, u32:5, u32:9, u32:4>(
      scheduler_4_requests_c, scheduler_4_startup_c,
      scheduler_4_egress_p,
      scheduler_4_ram_req_out, scheduler_4_ram_resp_in,
      scheduler_4_ram_wr_comp_in,
      scheduler_4_mailbox_req_out, scheduler_4_mailbox_resp_in,
      scheduler_4_mailbox_wr_comp_in);
    spawn phenom_syndrome_cell::SharedService<
      u32:9, u32:5, u32:9, u32:5>(
      scheduler_5_requests_c, scheduler_5_startup_c,
      scheduler_5_egress_p,
      scheduler_5_ram_req_out, scheduler_5_ram_resp_in,
      scheduler_5_ram_wr_comp_in,
      scheduler_5_mailbox_req_out, scheduler_5_mailbox_resp_in,
      scheduler_5_mailbox_wr_comp_in);
    spawn SchedulerRouter0(
      scheduler_0_egress_c, scheduler_0_requests_p[u32:3],
      scheduler_4_requests_p[u32:0],
      scheduler_5_requests_p[u32:0],
      external_0_buffer_p[u32:0]);
    spawn SchedulerRouter1(
      scheduler_1_egress_c, scheduler_1_requests_p[u32:3],
      scheduler_4_requests_p[u32:1],
      scheduler_5_requests_p[u32:1],
      external_0_buffer_p[u32:1]);
    spawn SchedulerRouter2(
      scheduler_2_egress_c, scheduler_2_requests_p[u32:2],
      scheduler_2_requests_p[u32:0],
      scheduler_4_requests_p[u32:2],
      external_2_buffer_p);
    spawn SchedulerRouter3(
      scheduler_3_egress_c, scheduler_3_requests_p[u32:2],
      scheduler_3_requests_p[u32:0],
      scheduler_5_requests_p[u32:2],
      external_4_buffer_p);
    spawn SchedulerRouter4(
      scheduler_4_egress_c, scheduler_4_requests_p[u32:4],
      scheduler_0_requests_p[u32:0],
      scheduler_1_requests_p[u32:0],
      scheduler_2_requests_p[u32:1],
      external_1_buffer_p);
    spawn SchedulerRouter5(
      scheduler_5_egress_c, scheduler_5_requests_p[u32:4],
      scheduler_0_requests_p[u32:1],
      scheduler_1_requests_p[u32:1],
      scheduler_3_requests_p[u32:1],
      external_3_buffer_p);
    spawn ControlDispatcher(control_router_in, scheduler_0_requests_p[u32:2], scheduler_1_requests_p[u32:2], scheduler_4_requests_p[u32:3], scheduler_5_requests_p[u32:3]);
    spawn FrameArrayMux<u32:2>(external_0_buffer_c, data_measurements_out);
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
  scheduler_1_ram_req_out: chan<phenom_data_cell::MachineRamReq> out;
  scheduler_1_ram_resp_in: chan<phenom_data_cell::MachineRamResp> in;
  scheduler_1_ram_wr_comp_in: chan<()> in;
  scheduler_1_mailbox_req_out: chan<phenom_data_cell::MailboxRamReq> out;
  scheduler_1_mailbox_resp_in: chan<phenom_data_cell::MailboxRamResp> in;
  scheduler_1_mailbox_wr_comp_in: chan<()> in;
  scheduler_2_ram_req_out: chan<phi_halo_cell::MachineRamReq> out;
  scheduler_2_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in;
  scheduler_2_ram_wr_comp_in: chan<()> in;
  scheduler_2_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out;
  scheduler_2_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in;
  scheduler_2_mailbox_wr_comp_in: chan<()> in;
  scheduler_3_ram_req_out: chan<phi_halo_cell::MachineRamReq> out;
  scheduler_3_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in;
  scheduler_3_ram_wr_comp_in: chan<()> in;
  scheduler_3_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out;
  scheduler_3_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in;
  scheduler_3_mailbox_wr_comp_in: chan<()> in;
  scheduler_4_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out;
  scheduler_4_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in;
  scheduler_4_ram_wr_comp_in: chan<()> in;
  scheduler_4_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out;
  scheduler_4_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in;
  scheduler_4_mailbox_wr_comp_in: chan<()> in;
  scheduler_5_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out;
  scheduler_5_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in;
  scheduler_5_ram_wr_comp_in: chan<()> in;
  scheduler_5_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out;
  scheduler_5_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in;
  scheduler_5_mailbox_wr_comp_in: chan<()> in;
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
    scheduler_1_ram_req_out: chan<phenom_data_cell::MachineRamReq> out,
    scheduler_1_ram_resp_in: chan<phenom_data_cell::MachineRamResp> in,
    scheduler_1_ram_wr_comp_in: chan<()> in,
    scheduler_1_mailbox_req_out: chan<phenom_data_cell::MailboxRamReq> out,
    scheduler_1_mailbox_resp_in: chan<phenom_data_cell::MailboxRamResp> in,
    scheduler_1_mailbox_wr_comp_in: chan<()> in,
    scheduler_2_ram_req_out: chan<phi_halo_cell::MachineRamReq> out,
    scheduler_2_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in,
    scheduler_2_ram_wr_comp_in: chan<()> in,
    scheduler_2_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out,
    scheduler_2_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in,
    scheduler_2_mailbox_wr_comp_in: chan<()> in,
    scheduler_3_ram_req_out: chan<phi_halo_cell::MachineRamReq> out,
    scheduler_3_ram_resp_in: chan<phi_halo_cell::MachineRamResp> in,
    scheduler_3_ram_wr_comp_in: chan<()> in,
    scheduler_3_mailbox_req_out: chan<phi_halo_cell::MailboxRamReq> out,
    scheduler_3_mailbox_resp_in: chan<phi_halo_cell::MailboxRamResp> in,
    scheduler_3_mailbox_wr_comp_in: chan<()> in,
    scheduler_4_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out,
    scheduler_4_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in,
    scheduler_4_ram_wr_comp_in: chan<()> in,
    scheduler_4_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out,
    scheduler_4_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in,
    scheduler_4_mailbox_wr_comp_in: chan<()> in,
    scheduler_5_ram_req_out: chan<phenom_syndrome_cell::MachineRamReq> out,
    scheduler_5_ram_resp_in: chan<phenom_syndrome_cell::MachineRamResp> in,
    scheduler_5_ram_wr_comp_in: chan<()> in,
    scheduler_5_mailbox_req_out: chan<phenom_syndrome_cell::MailboxRamReq> out,
    scheduler_5_mailbox_resp_in: chan<phenom_syndrome_cell::MailboxRamResp> in,
    scheduler_5_mailbox_wr_comp_in: chan<()> in,
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
      scheduler_3_ram_req_out,
      scheduler_3_ram_resp_in,
      scheduler_3_ram_wr_comp_in,
      scheduler_3_mailbox_req_out,
      scheduler_3_mailbox_resp_in,
      scheduler_3_mailbox_wr_comp_in,
      scheduler_4_ram_req_out,
      scheduler_4_ram_resp_in,
      scheduler_4_ram_wr_comp_in,
      scheduler_4_mailbox_req_out,
      scheduler_4_mailbox_resp_in,
      scheduler_4_mailbox_wr_comp_in,
      scheduler_5_ram_req_out,
      scheduler_5_ram_resp_in,
      scheduler_5_ram_wr_comp_in,
      scheduler_5_mailbox_req_out,
      scheduler_5_mailbox_resp_in,
      scheduler_5_mailbox_wr_comp_in,
      control_router_in,
      data_measurements_out,
      x_announcements_out,
      x_decoder_events_out,
      z_announcements_out,
      z_decoder_events_out
    );
    (scheduler_0_ram_req_out, scheduler_0_ram_resp_in, scheduler_0_ram_wr_comp_in, scheduler_0_mailbox_req_out, scheduler_0_mailbox_resp_in, scheduler_0_mailbox_wr_comp_in, scheduler_1_ram_req_out, scheduler_1_ram_resp_in, scheduler_1_ram_wr_comp_in, scheduler_1_mailbox_req_out, scheduler_1_mailbox_resp_in, scheduler_1_mailbox_wr_comp_in, scheduler_2_ram_req_out, scheduler_2_ram_resp_in, scheduler_2_ram_wr_comp_in, scheduler_2_mailbox_req_out, scheduler_2_mailbox_resp_in, scheduler_2_mailbox_wr_comp_in, scheduler_3_ram_req_out, scheduler_3_ram_resp_in, scheduler_3_ram_wr_comp_in, scheduler_3_mailbox_req_out, scheduler_3_mailbox_resp_in, scheduler_3_mailbox_wr_comp_in, scheduler_4_ram_req_out, scheduler_4_ram_resp_in, scheduler_4_ram_wr_comp_in, scheduler_4_mailbox_req_out, scheduler_4_mailbox_resp_in, scheduler_4_mailbox_wr_comp_in, scheduler_5_ram_req_out, scheduler_5_ram_resp_in, scheduler_5_ram_wr_comp_in, scheduler_5_mailbox_req_out, scheduler_5_mailbox_resp_in, scheduler_5_mailbox_wr_comp_in, control_router_in, data_measurements_out, x_announcements_out, x_decoder_events_out, z_announcements_out, z_decoder_events_out)
  }

  init { () }
  next(state: ()) { state }
}
