// phi_noise_topology.x
// Auto-generated from compact Erlang topology and scheduler rules.
// Manual changes will be overwritten.
//
// Actor state and mailbox frames use separate RAMs. Requests and
// scheduler effect batches carry dense RAM slots; each group router
// maps its slot to a narrow family and coordinate address, then
// drains the effects in source order.

import axis;
import frame_transport;
import effect_window;
import frame_queue;
import arbitration;
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

struct Phi_xReductionBatch {
  source: u32,
  frames: axis::Frame[u32:4],
}

// Fragment 0 (north) uses inverse fragment 3 at offset [0, 1].
// Fragment 1 (east) uses inverse fragment 2 at offset [-1, 0].
// Fragment 2 (west) uses inverse fragment 1 at offset [1, 0].
// Fragment 3 (south) uses inverse fragment 0 at offset [0, -1].
struct Phi_xReductionPlaneState {
  input_cursor: u1,
  output_cursor: u4,
  open_tokens: u1[u32:9],
  bank_0: frame_queue::Queue[u32:9],
  bank_1: frame_queue::Queue[u32:9],
  bank_2: frame_queue::Queue[u32:9],
  bank_3: frame_queue::Queue[u32:9],
  pending_valid: u1,
  pending_batch: Phi_xReductionBatch,
}

proc Phi_xReductionPlane {
  batch_in: chan<Phi_xReductionBatch>[u32:1] in;
  aggregate_out_0: chan<phi_halo_cell::ReductionAggregateRequest> out;

  config(
    batch_in: chan<Phi_xReductionBatch>[u32:1] in,
    aggregate_out_0: chan<phi_halo_cell::ReductionAggregateRequest> out
  ) {
    (batch_in, aggregate_out_0)
  }

  init { zero!<Phi_xReductionPlaneState>() }

  next(state: Phi_xReductionPlaneState) {
    let ready_slots = [
      state.open_tokens[u32:0] && state.bank_0[u32:1].current_valid && state.bank_1[u32:6].current_valid && state.bank_2[u32:3].current_valid && state.bank_3[u32:2].current_valid,
      state.open_tokens[u32:1] && state.bank_0[u32:2].current_valid && state.bank_1[u32:7].current_valid && state.bank_2[u32:4].current_valid && state.bank_3[u32:0].current_valid,
      state.open_tokens[u32:2] && state.bank_0[u32:0].current_valid && state.bank_1[u32:8].current_valid && state.bank_2[u32:5].current_valid && state.bank_3[u32:1].current_valid,
      state.open_tokens[u32:3] && state.bank_0[u32:4].current_valid && state.bank_1[u32:0].current_valid && state.bank_2[u32:6].current_valid && state.bank_3[u32:5].current_valid,
      state.open_tokens[u32:4] && state.bank_0[u32:5].current_valid && state.bank_1[u32:1].current_valid && state.bank_2[u32:7].current_valid && state.bank_3[u32:3].current_valid,
      state.open_tokens[u32:5] && state.bank_0[u32:3].current_valid && state.bank_1[u32:2].current_valid && state.bank_2[u32:8].current_valid && state.bank_3[u32:4].current_valid,
      state.open_tokens[u32:6] && state.bank_0[u32:7].current_valid && state.bank_1[u32:3].current_valid && state.bank_2[u32:0].current_valid && state.bank_3[u32:8].current_valid,
      state.open_tokens[u32:7] && state.bank_0[u32:8].current_valid && state.bank_1[u32:4].current_valid && state.bank_2[u32:1].current_valid && state.bank_3[u32:6].current_valid,
      state.open_tokens[u32:8] && state.bank_0[u32:6].current_valid && state.bank_1[u32:5].current_valid && state.bank_2[u32:2].current_valid && state.bank_3[u32:7].current_valid
    ];
    let (output_ready, output_index) = arbitration::select(
      ready_slots, state.output_cursor);
    let output_slot = output_index as u32;
    let pop_sources = match output_slot {
      u32:0 => [u32:1, u32:6, u32:3, u32:2],
      u32:1 => [u32:2, u32:7, u32:4, u32:0],
      u32:2 => [u32:0, u32:8, u32:5, u32:1],
      u32:3 => [u32:4, u32:0, u32:6, u32:5],
      u32:4 => [u32:5, u32:1, u32:7, u32:3],
      u32:5 => [u32:3, u32:2, u32:8, u32:4],
      u32:6 => [u32:7, u32:3, u32:0, u32:8],
      u32:7 => [u32:8, u32:4, u32:1, u32:6],
      u32:8 => [u32:6, u32:5, u32:2, u32:7],
      _ => zero!<u32[u32:4]>(),
    };
    let frames = match output_slot {
      u32:0 => [state.bank_0[u32:1].current, state.bank_1[u32:6].current, state.bank_2[u32:3].current, state.bank_3[u32:2].current],
      u32:1 => [state.bank_0[u32:2].current, state.bank_1[u32:7].current, state.bank_2[u32:4].current, state.bank_3[u32:0].current],
      u32:2 => [state.bank_0[u32:0].current, state.bank_1[u32:8].current, state.bank_2[u32:5].current, state.bank_3[u32:1].current],
      u32:3 => [state.bank_0[u32:4].current, state.bank_1[u32:0].current, state.bank_2[u32:6].current, state.bank_3[u32:5].current],
      u32:4 => [state.bank_0[u32:5].current, state.bank_1[u32:1].current, state.bank_2[u32:7].current, state.bank_3[u32:3].current],
      u32:5 => [state.bank_0[u32:3].current, state.bank_1[u32:2].current, state.bank_2[u32:8].current, state.bank_3[u32:4].current],
      u32:6 => [state.bank_0[u32:7].current, state.bank_1[u32:3].current, state.bank_2[u32:0].current, state.bank_3[u32:8].current],
      u32:7 => [state.bank_0[u32:8].current, state.bank_1[u32:4].current, state.bank_2[u32:1].current, state.bank_3[u32:6].current],
      u32:8 => [state.bank_0[u32:6].current, state.bank_1[u32:5].current, state.bank_2[u32:2].current, state.bank_3[u32:7].current],
      _ => zero!<axis::Frame[u32:4]>(),
    };
    let aggregate = phi_halo_cell::reduction_aggregate_batch<u32:4>(frames);
    let output_tok = if output_ready {
      match output_slot {
        u32:0 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:0,
            aggregate,
          }),
        u32:1 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:1,
            aggregate,
          }),
        u32:2 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:2,
            aggregate,
          }),
        u32:3 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:3,
            aggregate,
          }),
        u32:4 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:4,
            aggregate,
          }),
        u32:5 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:5,
            aggregate,
          }),
        u32:6 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:6,
            aggregate,
          }),
        u32:7 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:7,
            aggregate,
          }),
        u32:8 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:8,
            aggregate,
          }),
        _ => join(),
      }
    } else { join() };
    // Input and output handshakes are independent. The scalar
    // pending batch makes all fragment-bank insertion atomic.
    let (input_tok, received, incoming) =
      unroll_for! (candidate, acc):
          (u32, (token, u1, Phi_xReductionBatch)) in u32:0..u32:1 {
        let (next_tok, next_batch, valid) =
          recv_if_non_blocking(
            acc.0, batch_in[candidate],
            !state.pending_valid &&
              state.input_cursor as u32 == candidate,
            zero!<Phi_xReductionBatch>());
        (next_tok, acc.1 || valid,
          if valid { next_batch } else { acc.2 })
      }((join(), u1:0, zero!<Phi_xReductionBatch>()));
    let work_valid = state.pending_valid || received;
    let work = if state.pending_valid {
      state.pending_batch
    } else { incoming };
    let source_valid = work.source < u32:9;
    let push_source = if source_valid { work.source
      } else { u32:0 };
    // An actor cannot reopen before its current aggregate retires,
    // so one token bit is sufficient. Clear before set keeps the
    // conservative same-cycle update well-defined.
    let open_tokens_after_output = if output_ready {
      update(state.open_tokens, output_slot, u1:0)
    } else { state.open_tokens };
    let incoming_source_valid = received &&
      incoming.source < u32:9;
    let open_tokens = if incoming_source_valid {
      update(open_tokens_after_output, incoming.source, u1:1)
    } else { open_tokens_after_output };
    let queue_0 = state.bank_0[push_source];
    let after_pop_0 = frame_queue::after_pop(
      queue_0, output_ready &&
        pop_sources[u32:0] == push_source);
    let capacity_0 = !after_pop_0.lookahead_valid;
    let queue_1 = state.bank_1[push_source];
    let after_pop_1 = frame_queue::after_pop(
      queue_1, output_ready &&
        pop_sources[u32:1] == push_source);
    let capacity_1 = !after_pop_1.lookahead_valid;
    let queue_2 = state.bank_2[push_source];
    let after_pop_2 = frame_queue::after_pop(
      queue_2, output_ready &&
        pop_sources[u32:2] == push_source);
    let capacity_2 = !after_pop_2.lookahead_valid;
    let queue_3 = state.bank_3[push_source];
    let after_pop_3 = frame_queue::after_pop(
      queue_3, output_ready &&
        pop_sources[u32:3] == push_source);
    let capacity_3 = !after_pop_3.lookahead_valid;
    let can_insert = work_valid && source_valid && capacity_0 && capacity_1 && capacity_2 && capacity_3;
    let bank_0 = frame_queue::update_bank(
      state.bank_0, output_ready,
      pop_sources[u32:0], can_insert, push_source,
      work.frames[u32:0]);
    let bank_1 = frame_queue::update_bank(
      state.bank_1, output_ready,
      pop_sources[u32:1], can_insert, push_source,
      work.frames[u32:1]);
    let bank_2 = frame_queue::update_bank(
      state.bank_2, output_ready,
      pop_sources[u32:2], can_insert, push_source,
      work.frames[u32:2]);
    let bank_3 = frame_queue::update_bank(
      state.bank_3, output_ready,
      pop_sources[u32:3], can_insert, push_source,
      work.frames[u32:3]);
    let _done = join(output_tok, input_tok);
    Phi_xReductionPlaneState {
      input_cursor: if state.pending_valid { state.input_cursor
      } else { arbitration::successor<u32:1>(state.input_cursor) },
      output_cursor: if !output_ready { state.output_cursor
      } else { arbitration::successor<u32:9>(output_index) },
      open_tokens,
      bank_0,
      bank_1,
      bank_2,
      bank_3,
      pending_valid: work_valid && !can_insert,
      pending_batch: if work_valid && !can_insert { work
        } else { state.pending_batch },
    }
  }
}

struct Phi_zReductionBatch {
  source: u32,
  frames: axis::Frame[u32:4],
}

// Fragment 0 (north) uses inverse fragment 3 at offset [0, 1].
// Fragment 1 (east) uses inverse fragment 2 at offset [-1, 0].
// Fragment 2 (west) uses inverse fragment 1 at offset [1, 0].
// Fragment 3 (south) uses inverse fragment 0 at offset [0, -1].
struct Phi_zReductionPlaneState {
  input_cursor: u1,
  output_cursor: u4,
  open_tokens: u1[u32:9],
  bank_0: frame_queue::Queue[u32:9],
  bank_1: frame_queue::Queue[u32:9],
  bank_2: frame_queue::Queue[u32:9],
  bank_3: frame_queue::Queue[u32:9],
  pending_valid: u1,
  pending_batch: Phi_zReductionBatch,
}

proc Phi_zReductionPlane {
  batch_in: chan<Phi_zReductionBatch>[u32:1] in;
  aggregate_out_0: chan<phi_halo_cell::ReductionAggregateRequest> out;

  config(
    batch_in: chan<Phi_zReductionBatch>[u32:1] in,
    aggregate_out_0: chan<phi_halo_cell::ReductionAggregateRequest> out
  ) {
    (batch_in, aggregate_out_0)
  }

  init { zero!<Phi_zReductionPlaneState>() }

  next(state: Phi_zReductionPlaneState) {
    let ready_slots = [
      state.open_tokens[u32:0] && state.bank_0[u32:1].current_valid && state.bank_1[u32:6].current_valid && state.bank_2[u32:3].current_valid && state.bank_3[u32:2].current_valid,
      state.open_tokens[u32:1] && state.bank_0[u32:2].current_valid && state.bank_1[u32:7].current_valid && state.bank_2[u32:4].current_valid && state.bank_3[u32:0].current_valid,
      state.open_tokens[u32:2] && state.bank_0[u32:0].current_valid && state.bank_1[u32:8].current_valid && state.bank_2[u32:5].current_valid && state.bank_3[u32:1].current_valid,
      state.open_tokens[u32:3] && state.bank_0[u32:4].current_valid && state.bank_1[u32:0].current_valid && state.bank_2[u32:6].current_valid && state.bank_3[u32:5].current_valid,
      state.open_tokens[u32:4] && state.bank_0[u32:5].current_valid && state.bank_1[u32:1].current_valid && state.bank_2[u32:7].current_valid && state.bank_3[u32:3].current_valid,
      state.open_tokens[u32:5] && state.bank_0[u32:3].current_valid && state.bank_1[u32:2].current_valid && state.bank_2[u32:8].current_valid && state.bank_3[u32:4].current_valid,
      state.open_tokens[u32:6] && state.bank_0[u32:7].current_valid && state.bank_1[u32:3].current_valid && state.bank_2[u32:0].current_valid && state.bank_3[u32:8].current_valid,
      state.open_tokens[u32:7] && state.bank_0[u32:8].current_valid && state.bank_1[u32:4].current_valid && state.bank_2[u32:1].current_valid && state.bank_3[u32:6].current_valid,
      state.open_tokens[u32:8] && state.bank_0[u32:6].current_valid && state.bank_1[u32:5].current_valid && state.bank_2[u32:2].current_valid && state.bank_3[u32:7].current_valid
    ];
    let (output_ready, output_index) = arbitration::select(
      ready_slots, state.output_cursor);
    let output_slot = output_index as u32;
    let pop_sources = match output_slot {
      u32:0 => [u32:1, u32:6, u32:3, u32:2],
      u32:1 => [u32:2, u32:7, u32:4, u32:0],
      u32:2 => [u32:0, u32:8, u32:5, u32:1],
      u32:3 => [u32:4, u32:0, u32:6, u32:5],
      u32:4 => [u32:5, u32:1, u32:7, u32:3],
      u32:5 => [u32:3, u32:2, u32:8, u32:4],
      u32:6 => [u32:7, u32:3, u32:0, u32:8],
      u32:7 => [u32:8, u32:4, u32:1, u32:6],
      u32:8 => [u32:6, u32:5, u32:2, u32:7],
      _ => zero!<u32[u32:4]>(),
    };
    let frames = match output_slot {
      u32:0 => [state.bank_0[u32:1].current, state.bank_1[u32:6].current, state.bank_2[u32:3].current, state.bank_3[u32:2].current],
      u32:1 => [state.bank_0[u32:2].current, state.bank_1[u32:7].current, state.bank_2[u32:4].current, state.bank_3[u32:0].current],
      u32:2 => [state.bank_0[u32:0].current, state.bank_1[u32:8].current, state.bank_2[u32:5].current, state.bank_3[u32:1].current],
      u32:3 => [state.bank_0[u32:4].current, state.bank_1[u32:0].current, state.bank_2[u32:6].current, state.bank_3[u32:5].current],
      u32:4 => [state.bank_0[u32:5].current, state.bank_1[u32:1].current, state.bank_2[u32:7].current, state.bank_3[u32:3].current],
      u32:5 => [state.bank_0[u32:3].current, state.bank_1[u32:2].current, state.bank_2[u32:8].current, state.bank_3[u32:4].current],
      u32:6 => [state.bank_0[u32:7].current, state.bank_1[u32:3].current, state.bank_2[u32:0].current, state.bank_3[u32:8].current],
      u32:7 => [state.bank_0[u32:8].current, state.bank_1[u32:4].current, state.bank_2[u32:1].current, state.bank_3[u32:6].current],
      u32:8 => [state.bank_0[u32:6].current, state.bank_1[u32:5].current, state.bank_2[u32:2].current, state.bank_3[u32:7].current],
      _ => zero!<axis::Frame[u32:4]>(),
    };
    let aggregate = phi_halo_cell::reduction_aggregate_batch<u32:4>(frames);
    let output_tok = if output_ready {
      match output_slot {
        u32:0 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:0,
            aggregate,
          }),
        u32:1 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:1,
            aggregate,
          }),
        u32:2 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:2,
            aggregate,
          }),
        u32:3 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:3,
            aggregate,
          }),
        u32:4 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:4,
            aggregate,
          }),
        u32:5 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:5,
            aggregate,
          }),
        u32:6 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:6,
            aggregate,
          }),
        u32:7 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:7,
            aggregate,
          }),
        u32:8 => send(
          join(), aggregate_out_0, phi_halo_cell::ReductionAggregateRequest {
            slot: u32:8,
            aggregate,
          }),
        _ => join(),
      }
    } else { join() };
    // Input and output handshakes are independent. The scalar
    // pending batch makes all fragment-bank insertion atomic.
    let (input_tok, received, incoming) =
      unroll_for! (candidate, acc):
          (u32, (token, u1, Phi_zReductionBatch)) in u32:0..u32:1 {
        let (next_tok, next_batch, valid) =
          recv_if_non_blocking(
            acc.0, batch_in[candidate],
            !state.pending_valid &&
              state.input_cursor as u32 == candidate,
            zero!<Phi_zReductionBatch>());
        (next_tok, acc.1 || valid,
          if valid { next_batch } else { acc.2 })
      }((join(), u1:0, zero!<Phi_zReductionBatch>()));
    let work_valid = state.pending_valid || received;
    let work = if state.pending_valid {
      state.pending_batch
    } else { incoming };
    let source_valid = work.source < u32:9;
    let push_source = if source_valid { work.source
      } else { u32:0 };
    // An actor cannot reopen before its current aggregate retires,
    // so one token bit is sufficient. Clear before set keeps the
    // conservative same-cycle update well-defined.
    let open_tokens_after_output = if output_ready {
      update(state.open_tokens, output_slot, u1:0)
    } else { state.open_tokens };
    let incoming_source_valid = received &&
      incoming.source < u32:9;
    let open_tokens = if incoming_source_valid {
      update(open_tokens_after_output, incoming.source, u1:1)
    } else { open_tokens_after_output };
    let queue_0 = state.bank_0[push_source];
    let after_pop_0 = frame_queue::after_pop(
      queue_0, output_ready &&
        pop_sources[u32:0] == push_source);
    let capacity_0 = !after_pop_0.lookahead_valid;
    let queue_1 = state.bank_1[push_source];
    let after_pop_1 = frame_queue::after_pop(
      queue_1, output_ready &&
        pop_sources[u32:1] == push_source);
    let capacity_1 = !after_pop_1.lookahead_valid;
    let queue_2 = state.bank_2[push_source];
    let after_pop_2 = frame_queue::after_pop(
      queue_2, output_ready &&
        pop_sources[u32:2] == push_source);
    let capacity_2 = !after_pop_2.lookahead_valid;
    let queue_3 = state.bank_3[push_source];
    let after_pop_3 = frame_queue::after_pop(
      queue_3, output_ready &&
        pop_sources[u32:3] == push_source);
    let capacity_3 = !after_pop_3.lookahead_valid;
    let can_insert = work_valid && source_valid && capacity_0 && capacity_1 && capacity_2 && capacity_3;
    let bank_0 = frame_queue::update_bank(
      state.bank_0, output_ready,
      pop_sources[u32:0], can_insert, push_source,
      work.frames[u32:0]);
    let bank_1 = frame_queue::update_bank(
      state.bank_1, output_ready,
      pop_sources[u32:1], can_insert, push_source,
      work.frames[u32:1]);
    let bank_2 = frame_queue::update_bank(
      state.bank_2, output_ready,
      pop_sources[u32:2], can_insert, push_source,
      work.frames[u32:2]);
    let bank_3 = frame_queue::update_bank(
      state.bank_3, output_ready,
      pop_sources[u32:3], can_insert, push_source,
      work.frames[u32:3]);
    let _done = join(output_tok, input_tok);
    Phi_zReductionPlaneState {
      input_cursor: if state.pending_valid { state.input_cursor
      } else { arbitration::successor<u32:1>(state.input_cursor) },
      output_cursor: if !output_ready { state.output_cursor
      } else { arbitration::successor<u32:9>(output_index) },
      open_tokens,
      bank_0,
      bank_1,
      bank_2,
      bank_3,
      pending_valid: work_valid && !can_insert,
      pending_batch: if work_valid && !can_insert { work
        } else { state.pending_batch },
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
          uN[96]:0x00000000800000009E3779B9),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:1 => phenom_data_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00020000800000003C6EF372),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:2 => phenom_data_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0004000080000000DAA66D2B),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:3 => phenom_data_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x000000018000000078DDE6E4),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:4 => phenom_data_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00020001800000001715609D),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:5 => phenom_data_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0004000180000000B54CDA56),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:6 => phenom_data_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00000002800000005384540F),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:7 => phenom_data_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0002000280000000F1BBCDC8),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:8 => phenom_data_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00040002800000008FF34781),
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
          uN[96]:0x00010000800000002E2AC13A),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:1 => phenom_data_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0003000080000000CC623AF3),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:2 => phenom_data_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00050000800000006A99B4AC),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:3 => phenom_data_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x000100018000000008D12E65),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:4 => phenom_data_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0003000180000000A708A81E),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:5 => phenom_data_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0005000180000000454021D7),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:6 => phenom_data_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0001000280000000E3779B90),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:7 => phenom_data_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x000300028000000081AF1549),
        ..zero!<phenom_data_cell::ScheduledRequest>()
      },
      u32:8 => phenom_data_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phenom_data_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00050002800000001FE68F02),
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
          u32:0xDE0497BD),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:1 => phi_halo_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x7C3C1176),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:2 => phi_halo_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x1A738B2F),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:3 => phi_halo_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0xB8AB04E8),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:4 => phi_halo_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x56E27EA1),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:5 => phi_halo_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0xF519F85A),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:6 => phi_halo_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x93517213),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:7 => phi_halo_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x3188EBCC),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:8 => phi_halo_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0xCFC06585),
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
          u32:0x6DF7DF3E),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:1 => phi_halo_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x0C2F58F7),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:2 => phi_halo_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0xAA66D2B0),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:3 => phi_halo_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x489E4C69),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:4 => phi_halo_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0xE6D5C622),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:5 => phi_halo_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x850D3FDB),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:6 => phi_halo_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x2344B994),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:7 => phi_halo_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0xC17C334D),
        ..zero!<phi_halo_cell::ScheduledRequest>()
      },
      u32:8 => phi_halo_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phi_halo_cell::Tag::PHI_CONFIG as u8,
          u32:0x5FB3AD06),
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
          uN[96]:0x0000000080000000BE1E08BB),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:1 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00010000800000005C558274),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:2 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0002000080000000FA8CFC2D),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:3 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x000000018000000098C475E6),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:4 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x000100018000000036FBEF9F),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:5 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0002000180000000D5336958),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:6 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0000000280000000736AE311),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:7 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x000100028000000011A25CCA),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:8 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0002000280000000AFD9D683),
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
          uN[96]:0x00000000800000004E11503C),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:1 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:1,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0001000080000000EC48C9F5),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:2 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:2,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00020000800000008A8043AE),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:3 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:3,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x000000018000000028B7BD67),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:4 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:4,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0001000180000000C6EF3720),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:5 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:5,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00020001800000006526B0D9),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:6 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:6,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0000000280000000035E2A92),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:7 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:7,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x0001000280000000A195A44B),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      u32:8 => phenom_syndrome_cell::ScheduledRequest {
        slot: u32:8,
        frame: axis::pack(
          phenom_syndrome_cell::Tag::PHENOM_CONFIG as u8,
          uN[96]:0x00020002800000003FCD1E04),
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      },
      _ => zero!<phenom_syndrome_cell::ScheduledRequest>(),
    };
    let active = index < u32:9;
    let _done = send_if(join(), request_out, active, request);
    if active { index + u32:1 } else { index }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter0State {
  control: effect_window::ClientState,
  scheduled: phenom_data_cell::ScheduledEffects,
  index: u8,
}

proc SchedulerRouter0 {
  scheduled_in: chan<phenom_data_cell::ScheduledEffects> in;
  credit_out: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out;
  data_measurements_out: chan<axis::Frame> out;
  window_request_out: chan<u1> out;
  window_grant_in: chan<u1> in;
  window_release_out: chan<u1> out;

  config(
    scheduled_in: chan<phenom_data_cell::ScheduledEffects> in,
    credit_out: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out,
    data_measurements_out: chan<axis::Frame> out,
    window_request_out: chan<u1> out,
    window_grant_in: chan<u1> in,
    window_release_out: chan<u1> out
  ) {
    (scheduled_in, credit_out, to_scheduler_4, to_scheduler_5, data_measurements_out, window_request_out, window_grant_in, window_release_out)
  }

  init { zero!<SchedulerRouter0State>() }

  next(state: SchedulerRouter0State) {
    let state_effect_info = phenom_data_cell::scheduled_effect(state.scheduled, state.index);
    let state_last = state.control.active && state_effect_info.2;
    let can_receive = effect_window::can_receive(
      state.control, state_last);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phenom_data_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.control.window_requested &&
          !state.control.window_granted, u1:0);
    let batch_valid = state.control.active || incoming_valid;
    let scheduled = if state.control.active {
      state.scheduled
    } else { incoming };
    let index = if state.control.active { state.index } else { u8:0 };
    let effect_info = phenom_data_cell::scheduled_effect(scheduled, index);
    let effect = effect_info.0;
    let emit = batch_valid && effect_info.1;
    let address = scheduler_0_address(scheduled.slot);
    let routed_tok = if emit {
      match address.family as FamilyId {
      FamilyId::DATA_EVEN => {
        let x = address.x;
        let y = address.y;
        match effect.port {
        phenom_data_cell::OutputPort::NORTH => send(grant_tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: (if y >= u16:1 { y - u16:1 } else { y + u16:2 }) }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::EAST => send(grant_tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::WEST => send(grant_tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: y }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::SOUTH => send(grant_tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: y }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::MEASUREMENT => send(grant_tok, data_measurements_out, effect.frame),
        }
      },
        _ => grant_tok,
      }
    } else { grant_tok };
    let last = batch_valid && effect_info.2;
    let transition = effect_window::advance_client(
      state.control, incoming_valid, grant_valid, last);
    let forward_credit = transition.forward_credit;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phenom_data_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_data_cell::ScheduledRequest>()
      });
    let release = transition.release;
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let _request_tok = send_if(
      release_tok, window_request_out, transition.request, u1:1);
    let updated = SchedulerRouter0State {
      control: transition.state,
      ..zero!<SchedulerRouter0State>()
    };
    if transition.carry_lookahead {
      SchedulerRouter0State { scheduled: incoming, ..updated }
    } else if transition.batch_continues {
      SchedulerRouter0State {
        scheduled,
        index: index + u8:1,
        ..updated
      }
    } else { updated }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter1State {
  control: effect_window::ClientState,
  scheduled: phenom_data_cell::ScheduledEffects,
  index: u8,
}

proc SchedulerRouter1 {
  scheduled_in: chan<phenom_data_cell::ScheduledEffects> in;
  credit_out: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out;
  data_measurements_out: chan<axis::Frame> out;
  window_request_out: chan<u1> out;
  window_grant_in: chan<u1> in;
  window_release_out: chan<u1> out;

  config(
    scheduled_in: chan<phenom_data_cell::ScheduledEffects> in,
    credit_out: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out,
    data_measurements_out: chan<axis::Frame> out,
    window_request_out: chan<u1> out,
    window_grant_in: chan<u1> in,
    window_release_out: chan<u1> out
  ) {
    (scheduled_in, credit_out, to_scheduler_4, to_scheduler_5, data_measurements_out, window_request_out, window_grant_in, window_release_out)
  }

  init { zero!<SchedulerRouter1State>() }

  next(state: SchedulerRouter1State) {
    let state_effect_info = phenom_data_cell::scheduled_effect(state.scheduled, state.index);
    let state_last = state.control.active && state_effect_info.2;
    let can_receive = effect_window::can_receive(
      state.control, state_last);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phenom_data_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.control.window_requested &&
          !state.control.window_granted, u1:0);
    let batch_valid = state.control.active || incoming_valid;
    let scheduled = if state.control.active {
      state.scheduled
    } else { incoming };
    let index = if state.control.active { state.index } else { u8:0 };
    let effect_info = phenom_data_cell::scheduled_effect(scheduled, index);
    let effect = effect_info.0;
    let emit = batch_valid && effect_info.1;
    let address = scheduler_1_address(scheduled.slot);
    let routed_tok = if emit {
      match address.family as FamilyId {
      FamilyId::DATA_ODD => {
        let x = address.x;
        let y = address.y;
        match effect.port {
        phenom_data_cell::OutputPort::NORTH => send(grant_tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::EAST => send(grant_tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::WEST => send(grant_tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: (if x >= u16:1 { x - u16:1 } else { x + u16:2 }), y: y }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::SOUTH => send(grant_tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: x, y: (if y >= u16:2 { y - u16:2 } else { y + u16:1 }) }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phenom_data_cell::OutputPort::MEASUREMENT => send(grant_tok, data_measurements_out, effect.frame),
        }
      },
        _ => grant_tok,
      }
    } else { grant_tok };
    let last = batch_valid && effect_info.2;
    let transition = effect_window::advance_client(
      state.control, incoming_valid, grant_valid, last);
    let forward_credit = transition.forward_credit;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phenom_data_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_data_cell::ScheduledRequest>()
      });
    let release = transition.release;
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let _request_tok = send_if(
      release_tok, window_request_out, transition.request, u1:1);
    let updated = SchedulerRouter1State {
      control: transition.state,
      ..zero!<SchedulerRouter1State>()
    };
    if transition.carry_lookahead {
      SchedulerRouter1State { scheduled: incoming, ..updated }
    } else if transition.batch_continues {
      SchedulerRouter1State {
        scheduled,
        index: index + u8:1,
        ..updated
      }
    } else { updated }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter2State {
  control: effect_window::ClientState,
  scheduled: phi_halo_cell::ScheduledEffects,
  index: u8,
}

proc SchedulerRouter2 {
  scheduled_in: chan<phi_halo_cell::ScheduledEffects> in;
  credit_out: chan<phi_halo_cell::ScheduledRequest> out;
  to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out;
  x_decoder_events_out: chan<axis::Frame> out;
  phi_x_reduction_out: chan<Phi_xReductionBatch> out;
  window_request_out: chan<u1> out;
  window_grant_in: chan<u1> in;
  window_release_out: chan<u1> out;

  config(
    scheduled_in: chan<phi_halo_cell::ScheduledEffects> in,
    credit_out: chan<phi_halo_cell::ScheduledRequest> out,
    to_scheduler_4: chan<phenom_syndrome_cell::ScheduledRequest> out,
    x_decoder_events_out: chan<axis::Frame> out,
    phi_x_reduction_out: chan<Phi_xReductionBatch> out,
    window_request_out: chan<u1> out,
    window_grant_in: chan<u1> in,
    window_release_out: chan<u1> out
  ) {
    (scheduled_in, credit_out, to_scheduler_4, x_decoder_events_out, phi_x_reduction_out, window_request_out, window_grant_in, window_release_out)
  }

  init { zero!<SchedulerRouter2State>() }

  next(state: SchedulerRouter2State) {
    let state_effect_info = phi_halo_cell::scheduled_effect(state.scheduled, state.index);
    let state_reduction_prefix = phi_halo_cell::scheduled_reduction_prefix(state.scheduled);
    let state_reduction_batch = state.control.active &&
      state.index == u8:0 && state_reduction_prefix.0;
    let state_last = state.control.active &&
      if state_reduction_batch { state_reduction_prefix.2
      } else { state_effect_info.2 };
    let can_receive = effect_window::can_receive(
      state.control, state_last);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phi_halo_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.control.window_requested &&
          !state.control.window_granted, u1:0);
    let batch_valid = state.control.active || incoming_valid;
    let scheduled = if state.control.active {
      state.scheduled
    } else { incoming };
    let index = if state.control.active { state.index } else { u8:0 };
    let effect_info = phi_halo_cell::scheduled_effect(scheduled, index);
    let reduction_prefix = phi_halo_cell::scheduled_reduction_prefix(scheduled);
    let reduction_batch = batch_valid && index == u8:0 &&
      reduction_prefix.0;
    let effect = effect_info.0;
    let emit = batch_valid && effect_info.1;
    let address = scheduler_2_address(scheduled.slot);
    let routed_tok = if reduction_batch {
      match address.family as FamilyId {
        FamilyId::PHI_X => {
          let effect_0 = phi_halo_cell::scheduled_effect(scheduled, u8:0).0;
          let effect_1 = phi_halo_cell::scheduled_effect(scheduled, u8:1).0;
          let effect_2 = phi_halo_cell::scheduled_effect(scheduled, u8:2).0;
          let effect_3 = phi_halo_cell::scheduled_effect(scheduled, u8:3).0;
          let batch = Phi_xReductionBatch {
            source: (address.x as u32) * u32:3 + address.y as u32,
            frames: [effect_0.frame, effect_1.frame, effect_2.frame, effect_3.frame],
          };
          send(grant_tok, phi_x_reduction_out, batch)
        },
        _ => grant_tok,
      }
    } else if emit {
      match address.family as FamilyId {
      FamilyId::PHI_X => {
        let x = address.x;
        let y = address.y;
        match effect.port {
        phi_halo_cell::OutputPort::NORTH => grant_tok,
        phi_halo_cell::OutputPort::EAST => grant_tok,
        phi_halo_cell::OutputPort::WEST => grant_tok,
        phi_halo_cell::OutputPort::SOUTH => grant_tok,
        phi_halo_cell::OutputPort::SYNDROME => send(grant_tok, to_scheduler_4, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_4_slot(ScheduledAddress { family: FamilyId::SYNDROME_X as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::CORRECTION => send(grant_tok, x_decoder_events_out, effect.frame),
        phi_halo_cell::OutputPort::STATUS => send(grant_tok, x_decoder_events_out, effect.frame),
        }
      },
        _ => grant_tok,
      }
    } else { grant_tok };
    let last = batch_valid && if reduction_batch {
      reduction_prefix.2
    } else { effect_info.2 };
    let transition = effect_window::advance_client(
      state.control, incoming_valid, grant_valid, last);
    let forward_credit = transition.forward_credit;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phi_halo_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phi_halo_cell::ScheduledRequest>()
      });
    let release = transition.release;
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let _request_tok = send_if(
      release_tok, window_request_out, transition.request, u1:1);
    let updated = SchedulerRouter2State {
      control: transition.state,
      ..zero!<SchedulerRouter2State>()
    };
    if transition.carry_lookahead {
      SchedulerRouter2State { scheduled: incoming, ..updated }
    } else if transition.batch_continues {
      SchedulerRouter2State {
        scheduled,
        index: index + if reduction_batch { u8:4 } else { u8:1 },
        ..updated
      }
    } else { updated }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter3State {
  control: effect_window::ClientState,
  scheduled: phi_halo_cell::ScheduledEffects,
  index: u8,
}

proc SchedulerRouter3 {
  scheduled_in: chan<phi_halo_cell::ScheduledEffects> in;
  credit_out: chan<phi_halo_cell::ScheduledRequest> out;
  to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out;
  z_decoder_events_out: chan<axis::Frame> out;
  phi_z_reduction_out: chan<Phi_zReductionBatch> out;
  window_request_out: chan<u1> out;
  window_grant_in: chan<u1> in;
  window_release_out: chan<u1> out;

  config(
    scheduled_in: chan<phi_halo_cell::ScheduledEffects> in,
    credit_out: chan<phi_halo_cell::ScheduledRequest> out,
    to_scheduler_5: chan<phenom_syndrome_cell::ScheduledRequest> out,
    z_decoder_events_out: chan<axis::Frame> out,
    phi_z_reduction_out: chan<Phi_zReductionBatch> out,
    window_request_out: chan<u1> out,
    window_grant_in: chan<u1> in,
    window_release_out: chan<u1> out
  ) {
    (scheduled_in, credit_out, to_scheduler_5, z_decoder_events_out, phi_z_reduction_out, window_request_out, window_grant_in, window_release_out)
  }

  init { zero!<SchedulerRouter3State>() }

  next(state: SchedulerRouter3State) {
    let state_effect_info = phi_halo_cell::scheduled_effect(state.scheduled, state.index);
    let state_reduction_prefix = phi_halo_cell::scheduled_reduction_prefix(state.scheduled);
    let state_reduction_batch = state.control.active &&
      state.index == u8:0 && state_reduction_prefix.0;
    let state_last = state.control.active &&
      if state_reduction_batch { state_reduction_prefix.2
      } else { state_effect_info.2 };
    let can_receive = effect_window::can_receive(
      state.control, state_last);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phi_halo_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.control.window_requested &&
          !state.control.window_granted, u1:0);
    let batch_valid = state.control.active || incoming_valid;
    let scheduled = if state.control.active {
      state.scheduled
    } else { incoming };
    let index = if state.control.active { state.index } else { u8:0 };
    let effect_info = phi_halo_cell::scheduled_effect(scheduled, index);
    let reduction_prefix = phi_halo_cell::scheduled_reduction_prefix(scheduled);
    let reduction_batch = batch_valid && index == u8:0 &&
      reduction_prefix.0;
    let effect = effect_info.0;
    let emit = batch_valid && effect_info.1;
    let address = scheduler_3_address(scheduled.slot);
    let routed_tok = if reduction_batch {
      match address.family as FamilyId {
        FamilyId::PHI_Z => {
          let effect_0 = phi_halo_cell::scheduled_effect(scheduled, u8:0).0;
          let effect_1 = phi_halo_cell::scheduled_effect(scheduled, u8:1).0;
          let effect_2 = phi_halo_cell::scheduled_effect(scheduled, u8:2).0;
          let effect_3 = phi_halo_cell::scheduled_effect(scheduled, u8:3).0;
          let batch = Phi_zReductionBatch {
            source: (address.x as u32) * u32:3 + address.y as u32,
            frames: [effect_0.frame, effect_1.frame, effect_2.frame, effect_3.frame],
          };
          send(grant_tok, phi_z_reduction_out, batch)
        },
        _ => grant_tok,
      }
    } else if emit {
      match address.family as FamilyId {
      FamilyId::PHI_Z => {
        let x = address.x;
        let y = address.y;
        match effect.port {
        phi_halo_cell::OutputPort::NORTH => grant_tok,
        phi_halo_cell::OutputPort::EAST => grant_tok,
        phi_halo_cell::OutputPort::WEST => grant_tok,
        phi_halo_cell::OutputPort::SOUTH => grant_tok,
        phi_halo_cell::OutputPort::SYNDROME => send(grant_tok, to_scheduler_5, phenom_syndrome_cell::ScheduledRequest {
            slot: scheduler_5_slot(ScheduledAddress { family: FamilyId::SYNDROME_Z as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phenom_syndrome_cell::ScheduledRequest>()
          }),
        phi_halo_cell::OutputPort::CORRECTION => send(grant_tok, z_decoder_events_out, effect.frame),
        phi_halo_cell::OutputPort::STATUS => send(grant_tok, z_decoder_events_out, effect.frame),
        }
      },
        _ => grant_tok,
      }
    } else { grant_tok };
    let last = batch_valid && if reduction_batch {
      reduction_prefix.2
    } else { effect_info.2 };
    let transition = effect_window::advance_client(
      state.control, incoming_valid, grant_valid, last);
    let forward_credit = transition.forward_credit;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phi_halo_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phi_halo_cell::ScheduledRequest>()
      });
    let release = transition.release;
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let _request_tok = send_if(
      release_tok, window_request_out, transition.request, u1:1);
    let updated = SchedulerRouter3State {
      control: transition.state,
      ..zero!<SchedulerRouter3State>()
    };
    if transition.carry_lookahead {
      SchedulerRouter3State { scheduled: incoming, ..updated }
    } else if transition.batch_continues {
      SchedulerRouter3State {
        scheduled,
        index: index + if reduction_batch { u8:4 } else { u8:1 },
        ..updated
      }
    } else { updated }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter4State {
  control: effect_window::ClientState,
  scheduled: phenom_syndrome_cell::ScheduledEffects,
  index: u8,
}

proc SchedulerRouter4 {
  scheduled_in: chan<phenom_syndrome_cell::ScheduledEffects> in;
  credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_1: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_2: chan<phi_halo_cell::ScheduledRequest> out;
  window_request_out: chan<u1> out;
  window_grant_in: chan<u1> in;
  window_release_out: chan<u1> out;

  config(
    scheduled_in: chan<phenom_syndrome_cell::ScheduledEffects> in,
    credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_1: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_2: chan<phi_halo_cell::ScheduledRequest> out,
    window_request_out: chan<u1> out,
    window_grant_in: chan<u1> in,
    window_release_out: chan<u1> out
  ) {
    (scheduled_in, credit_out, to_scheduler_0, to_scheduler_1, to_scheduler_2, window_request_out, window_grant_in, window_release_out)
  }

  init { zero!<SchedulerRouter4State>() }

  next(state: SchedulerRouter4State) {
    let state_effect_info = phenom_syndrome_cell::scheduled_effect(state.scheduled, state.index);
    let state_last = state.control.active && state_effect_info.2;
    let can_receive = effect_window::can_receive(
      state.control, state_last);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phenom_syndrome_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.control.window_requested &&
          !state.control.window_granted, u1:0);
    let batch_valid = state.control.active || incoming_valid;
    let scheduled = if state.control.active {
      state.scheduled
    } else { incoming };
    let index = if state.control.active { state.index } else { u8:0 };
    let effect_info = phenom_syndrome_cell::scheduled_effect(scheduled, index);
    let effect = effect_info.0;
    let emit = batch_valid && effect_info.1;
    let address = scheduler_4_address(scheduled.slot);
    let routed_tok = if emit {
      match address.family as FamilyId {
      FamilyId::SYNDROME_X => {
        let x = address.x;
        let y = address.y;
        match effect.port {
        phenom_syndrome_cell::OutputPort::NORTH => send(grant_tok, to_scheduler_1, phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: x, y: (if y >= u16:1 { y - u16:1 } else { y + u16:2 }) }),
            frame: effect.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::EAST => send(grant_tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: y }),
            frame: effect.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::WEST => send(grant_tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::SOUTH => send(grant_tok, to_scheduler_1, phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::PHI => send(grant_tok, to_scheduler_2, phi_halo_cell::ScheduledRequest {
            slot: scheduler_2_slot(ScheduledAddress { family: FamilyId::PHI_X as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        }
      },
        _ => grant_tok,
      }
    } else { grant_tok };
    let last = batch_valid && effect_info.2;
    let transition = effect_window::advance_client(
      state.control, incoming_valid, grant_valid, last);
    let forward_credit = transition.forward_credit;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phenom_syndrome_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      });
    let release = transition.release;
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let _request_tok = send_if(
      release_tok, window_request_out, transition.request, u1:1);
    let updated = SchedulerRouter4State {
      control: transition.state,
      ..zero!<SchedulerRouter4State>()
    };
    if transition.carry_lookahead {
      SchedulerRouter4State { scheduled: incoming, ..updated }
    } else if transition.batch_continues {
      SchedulerRouter4State {
        scheduled,
        index: index + u8:1,
        ..updated
      }
    } else { updated }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter5State {
  control: effect_window::ClientState,
  scheduled: phenom_syndrome_cell::ScheduledEffects,
  index: u8,
}

proc SchedulerRouter5 {
  scheduled_in: chan<phenom_syndrome_cell::ScheduledEffects> in;
  credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out;
  to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_1: chan<phenom_data_cell::ScheduledRequest> out;
  to_scheduler_3: chan<phi_halo_cell::ScheduledRequest> out;
  window_request_out: chan<u1> out;
  window_grant_in: chan<u1> in;
  window_release_out: chan<u1> out;

  config(
    scheduled_in: chan<phenom_syndrome_cell::ScheduledEffects> in,
    credit_out: chan<phenom_syndrome_cell::ScheduledRequest> out,
    to_scheduler_0: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_1: chan<phenom_data_cell::ScheduledRequest> out,
    to_scheduler_3: chan<phi_halo_cell::ScheduledRequest> out,
    window_request_out: chan<u1> out,
    window_grant_in: chan<u1> in,
    window_release_out: chan<u1> out
  ) {
    (scheduled_in, credit_out, to_scheduler_0, to_scheduler_1, to_scheduler_3, window_request_out, window_grant_in, window_release_out)
  }

  init { zero!<SchedulerRouter5State>() }

  next(state: SchedulerRouter5State) {
    let state_effect_info = phenom_syndrome_cell::scheduled_effect(state.scheduled, state.index);
    let state_last = state.control.active && state_effect_info.2;
    let can_receive = effect_window::can_receive(
      state.control, state_last);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phenom_syndrome_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.control.window_requested &&
          !state.control.window_granted, u1:0);
    let batch_valid = state.control.active || incoming_valid;
    let scheduled = if state.control.active {
      state.scheduled
    } else { incoming };
    let index = if state.control.active { state.index } else { u8:0 };
    let effect_info = phenom_syndrome_cell::scheduled_effect(scheduled, index);
    let effect = effect_info.0;
    let emit = batch_valid && effect_info.1;
    let address = scheduler_5_address(scheduled.slot);
    let routed_tok = if emit {
      match address.family as FamilyId {
      FamilyId::SYNDROME_Z => {
        let x = address.x;
        let y = address.y;
        match effect.port {
        phenom_syndrome_cell::OutputPort::NORTH => send(grant_tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: y }),
            frame: effect.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::EAST => send(grant_tok, to_scheduler_1, phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: y }),
            frame: effect.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::WEST => send(grant_tok, to_scheduler_1, phenom_data_cell::ScheduledRequest {
            slot: scheduler_1_slot(ScheduledAddress { family: FamilyId::DATA_ODD as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::SOUTH => send(grant_tok, to_scheduler_0, phenom_data_cell::ScheduledRequest {
            slot: scheduler_0_slot(ScheduledAddress { family: FamilyId::DATA_EVEN as u8, x: (if x >= u16:2 { x - u16:2 } else { x + u16:1 }), y: (if y >= u16:2 { y - u16:2 } else { y + u16:1 }) }),
            frame: effect.frame,
            ..zero!<phenom_data_cell::ScheduledRequest>()
          }),
        phenom_syndrome_cell::OutputPort::PHI => send(grant_tok, to_scheduler_3, phi_halo_cell::ScheduledRequest {
            slot: scheduler_3_slot(ScheduledAddress { family: FamilyId::PHI_Z as u8, x: x, y: y }),
            frame: effect.frame,
            ..zero!<phi_halo_cell::ScheduledRequest>()
          }),
        }
      },
        _ => grant_tok,
      }
    } else { grant_tok };
    let last = batch_valid && effect_info.2;
    let transition = effect_window::advance_client(
      state.control, incoming_valid, grant_valid, last);
    let forward_credit = transition.forward_credit;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phenom_syndrome_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      });
    let release = transition.release;
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let _request_tok = send_if(
      release_tok, window_request_out, transition.request, u1:1);
    let updated = SchedulerRouter5State {
      control: transition.state,
      ..zero!<SchedulerRouter5State>()
    };
    if transition.carry_lookahead {
      SchedulerRouter5State { scheduled: incoming, ..updated }
    } else if transition.batch_continues {
      SchedulerRouter5State {
        scheduled,
        index: index + u8:1,
        ..updated
      }
    } else { updated }
  }
}

proc SchedulerGrid {
  config(
    scheduler_0_ram_read_req_out: chan<phenom_data_cell::MachineRamReadReq> out,
    scheduler_0_ram_read_resp_in: chan<phenom_data_cell::MachineRamReadResp> in,
    scheduler_0_ram_write_req_out: chan<phenom_data_cell::MachineRamWriteReq> out,
    scheduler_0_ram_write_resp_in: chan<phenom_data_cell::MachineRamWriteResp> in,
    scheduler_0_mailbox_read_req_out: chan<phenom_data_cell::MailboxRamReadReq> out,
    scheduler_0_mailbox_read_resp_in: chan<phenom_data_cell::MailboxRamReadResp> in,
    scheduler_0_mailbox_write_req_out: chan<phenom_data_cell::MailboxRamWriteReq> out,
    scheduler_0_mailbox_write_resp_in: chan<phenom_data_cell::MailboxRamWriteResp> in,
    scheduler_1_ram_read_req_out: chan<phenom_data_cell::MachineRamReadReq> out,
    scheduler_1_ram_read_resp_in: chan<phenom_data_cell::MachineRamReadResp> in,
    scheduler_1_ram_write_req_out: chan<phenom_data_cell::MachineRamWriteReq> out,
    scheduler_1_ram_write_resp_in: chan<phenom_data_cell::MachineRamWriteResp> in,
    scheduler_1_mailbox_read_req_out: chan<phenom_data_cell::MailboxRamReadReq> out,
    scheduler_1_mailbox_read_resp_in: chan<phenom_data_cell::MailboxRamReadResp> in,
    scheduler_1_mailbox_write_req_out: chan<phenom_data_cell::MailboxRamWriteReq> out,
    scheduler_1_mailbox_write_resp_in: chan<phenom_data_cell::MailboxRamWriteResp> in,
    scheduler_2_ram_read_req_out: chan<phi_halo_cell::MachineRamReadReq> out,
    scheduler_2_ram_read_resp_in: chan<phi_halo_cell::MachineRamReadResp> in,
    scheduler_2_ram_write_req_out: chan<phi_halo_cell::MachineRamWriteReq> out,
    scheduler_2_ram_write_resp_in: chan<phi_halo_cell::MachineRamWriteResp> in,
    scheduler_2_mailbox_read_req_out: chan<phi_halo_cell::MailboxRamReadReq> out,
    scheduler_2_mailbox_read_resp_in: chan<phi_halo_cell::MailboxRamReadResp> in,
    scheduler_2_mailbox_write_req_out: chan<phi_halo_cell::MailboxRamWriteReq> out,
    scheduler_2_mailbox_write_resp_in: chan<phi_halo_cell::MailboxRamWriteResp> in,
    scheduler_3_ram_read_req_out: chan<phi_halo_cell::MachineRamReadReq> out,
    scheduler_3_ram_read_resp_in: chan<phi_halo_cell::MachineRamReadResp> in,
    scheduler_3_ram_write_req_out: chan<phi_halo_cell::MachineRamWriteReq> out,
    scheduler_3_ram_write_resp_in: chan<phi_halo_cell::MachineRamWriteResp> in,
    scheduler_3_mailbox_read_req_out: chan<phi_halo_cell::MailboxRamReadReq> out,
    scheduler_3_mailbox_read_resp_in: chan<phi_halo_cell::MailboxRamReadResp> in,
    scheduler_3_mailbox_write_req_out: chan<phi_halo_cell::MailboxRamWriteReq> out,
    scheduler_3_mailbox_write_resp_in: chan<phi_halo_cell::MailboxRamWriteResp> in,
    scheduler_4_ram_read_req_out: chan<phenom_syndrome_cell::MachineRamReadReq> out,
    scheduler_4_ram_read_resp_in: chan<phenom_syndrome_cell::MachineRamReadResp> in,
    scheduler_4_ram_write_req_out: chan<phenom_syndrome_cell::MachineRamWriteReq> out,
    scheduler_4_ram_write_resp_in: chan<phenom_syndrome_cell::MachineRamWriteResp> in,
    scheduler_4_mailbox_read_req_out: chan<phenom_syndrome_cell::MailboxRamReadReq> out,
    scheduler_4_mailbox_read_resp_in: chan<phenom_syndrome_cell::MailboxRamReadResp> in,
    scheduler_4_mailbox_write_req_out: chan<phenom_syndrome_cell::MailboxRamWriteReq> out,
    scheduler_4_mailbox_write_resp_in: chan<phenom_syndrome_cell::MailboxRamWriteResp> in,
    scheduler_5_ram_read_req_out: chan<phenom_syndrome_cell::MachineRamReadReq> out,
    scheduler_5_ram_read_resp_in: chan<phenom_syndrome_cell::MachineRamReadResp> in,
    scheduler_5_ram_write_req_out: chan<phenom_syndrome_cell::MachineRamWriteReq> out,
    scheduler_5_ram_write_resp_in: chan<phenom_syndrome_cell::MachineRamWriteResp> in,
    scheduler_5_mailbox_read_req_out: chan<phenom_syndrome_cell::MailboxRamReadReq> out,
    scheduler_5_mailbox_read_resp_in: chan<phenom_syndrome_cell::MailboxRamReadResp> in,
    scheduler_5_mailbox_write_req_out: chan<phenom_syndrome_cell::MailboxRamWriteReq> out,
    scheduler_5_mailbox_write_resp_in: chan<phenom_syndrome_cell::MailboxRamWriteResp> in,
    control_router_in: chan<hls_spatial_router::SpatialFrame> in,
    data_measurements_out: chan<axis::Frame> out,
    x_decoder_events_out: chan<axis::Frame> out,
    z_decoder_events_out: chan<axis::Frame> out
  ) {
    let (effect_window_request_p, effect_window_request_c) =
      chan<u1, CHANNEL_DEPTH>[u32:6]("effect_window_request");
    let (effect_window_grant_p, effect_window_grant_c) =
      chan<u1, CHANNEL_DEPTH>[u32:6]("effect_window_grant");
    let (effect_window_release_p, effect_window_release_c) =
      chan<u1, CHANNEL_DEPTH>[u32:6]("effect_window_release");
    let (external_0_buffer_p, external_0_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>[u32:2]("external_0_buffer");
    let (external_1_buffer_p, external_1_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_1_buffer");
    let (external_2_buffer_p, external_2_buffer_c) =
      chan<axis::Frame, CHANNEL_DEPTH>("external_2_buffer");
    let (scheduler_0_requests_p, scheduler_0_requests_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:4]("scheduler_0_requests");
    let (scheduler_0_startup_p, scheduler_0_startup_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_0_startup");
    let (scheduler_0_egress_p, scheduler_0_egress_c) =
      chan<phenom_data_cell::ScheduledEffects, CHANNEL_DEPTH>("scheduler_0_egress");
    spawn SchedulerStartup0(scheduler_0_startup_p);
    let (scheduler_1_requests_p, scheduler_1_requests_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:4]("scheduler_1_requests");
    let (scheduler_1_startup_p, scheduler_1_startup_c) =
      chan<phenom_data_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_1_startup");
    let (scheduler_1_egress_p, scheduler_1_egress_c) =
      chan<phenom_data_cell::ScheduledEffects, CHANNEL_DEPTH>("scheduler_1_egress");
    spawn SchedulerStartup1(scheduler_1_startup_p);
    let (scheduler_2_requests_p, scheduler_2_requests_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:2]("scheduler_2_requests");
    let (scheduler_2_startup_p, scheduler_2_startup_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_2_startup");
    let (scheduler_2_egress_p, scheduler_2_egress_c) =
      chan<phi_halo_cell::ScheduledEffects, CHANNEL_DEPTH>("scheduler_2_egress");
    let (scheduler_2_aggregate_p, scheduler_2_aggregate_c) =
      chan<phi_halo_cell::ReductionAggregateRequest, u32:0>("scheduler_2_aggregate");
    spawn SchedulerStartup2(scheduler_2_startup_p);
    let (scheduler_3_requests_p, scheduler_3_requests_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:2]("scheduler_3_requests");
    let (scheduler_3_startup_p, scheduler_3_startup_c) =
      chan<phi_halo_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_3_startup");
    let (scheduler_3_egress_p, scheduler_3_egress_c) =
      chan<phi_halo_cell::ScheduledEffects, CHANNEL_DEPTH>("scheduler_3_egress");
    let (scheduler_3_aggregate_p, scheduler_3_aggregate_c) =
      chan<phi_halo_cell::ReductionAggregateRequest, u32:0>("scheduler_3_aggregate");
    spawn SchedulerStartup3(scheduler_3_startup_p);
    let (scheduler_4_requests_p, scheduler_4_requests_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:5]("scheduler_4_requests");
    let (scheduler_4_startup_p, scheduler_4_startup_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_4_startup");
    let (scheduler_4_egress_p, scheduler_4_egress_c) =
      chan<phenom_syndrome_cell::ScheduledEffects, CHANNEL_DEPTH>("scheduler_4_egress");
    spawn SchedulerStartup4(scheduler_4_startup_p);
    let (scheduler_5_requests_p, scheduler_5_requests_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>[u32:5]("scheduler_5_requests");
    let (scheduler_5_startup_p, scheduler_5_startup_c) =
      chan<phenom_syndrome_cell::ScheduledRequest, CHANNEL_DEPTH>("scheduler_5_startup");
    let (scheduler_5_egress_p, scheduler_5_egress_c) =
      chan<phenom_syndrome_cell::ScheduledEffects, CHANNEL_DEPTH>("scheduler_5_egress");
    spawn SchedulerStartup5(scheduler_5_startup_p);
    let (phi_x_reduction_batch_p, phi_x_reduction_batch_c) =
      chan<Phi_xReductionBatch, CHANNEL_DEPTH>[u32:1]("phi_x_reduction_batch");
    let (phi_z_reduction_batch_p, phi_z_reduction_batch_c) =
      chan<Phi_zReductionBatch, CHANNEL_DEPTH>[u32:1]("phi_z_reduction_batch");
    spawn effect_window::Arbiter<u32:6>(
      effect_window_request_c, effect_window_grant_p,
      effect_window_release_c);
    spawn phenom_data_cell::SharedService<
      u32:9, u32:4, u32:9, u32:0>(
      scheduler_0_requests_c, scheduler_0_startup_c,
      scheduler_0_egress_p,
      scheduler_0_ram_read_req_out, scheduler_0_ram_read_resp_in,
      scheduler_0_ram_write_req_out, scheduler_0_ram_write_resp_in,
      scheduler_0_mailbox_read_req_out, scheduler_0_mailbox_read_resp_in,
      scheduler_0_mailbox_write_req_out, scheduler_0_mailbox_write_resp_in);
    spawn phenom_data_cell::SharedService<
      u32:9, u32:4, u32:9, u32:1>(
      scheduler_1_requests_c, scheduler_1_startup_c,
      scheduler_1_egress_p,
      scheduler_1_ram_read_req_out, scheduler_1_ram_read_resp_in,
      scheduler_1_ram_write_req_out, scheduler_1_ram_write_resp_in,
      scheduler_1_mailbox_read_req_out, scheduler_1_mailbox_read_resp_in,
      scheduler_1_mailbox_write_req_out, scheduler_1_mailbox_write_resp_in);
    spawn phi_halo_cell::SharedService<
      u32:9, u32:2, u32:9, u32:2>(
      scheduler_2_requests_c, scheduler_2_startup_c,
      scheduler_2_egress_p,
      scheduler_2_ram_read_req_out, scheduler_2_ram_read_resp_in,
      scheduler_2_ram_write_req_out, scheduler_2_ram_write_resp_in,
      scheduler_2_mailbox_read_req_out, scheduler_2_mailbox_read_resp_in,
      scheduler_2_mailbox_write_req_out, scheduler_2_mailbox_write_resp_in,
      scheduler_2_aggregate_c);
    spawn phi_halo_cell::SharedService<
      u32:9, u32:2, u32:9, u32:3>(
      scheduler_3_requests_c, scheduler_3_startup_c,
      scheduler_3_egress_p,
      scheduler_3_ram_read_req_out, scheduler_3_ram_read_resp_in,
      scheduler_3_ram_write_req_out, scheduler_3_ram_write_resp_in,
      scheduler_3_mailbox_read_req_out, scheduler_3_mailbox_read_resp_in,
      scheduler_3_mailbox_write_req_out, scheduler_3_mailbox_write_resp_in,
      scheduler_3_aggregate_c);
    spawn phenom_syndrome_cell::SharedService<
      u32:9, u32:5, u32:9, u32:4>(
      scheduler_4_requests_c, scheduler_4_startup_c,
      scheduler_4_egress_p,
      scheduler_4_ram_read_req_out, scheduler_4_ram_read_resp_in,
      scheduler_4_ram_write_req_out, scheduler_4_ram_write_resp_in,
      scheduler_4_mailbox_read_req_out, scheduler_4_mailbox_read_resp_in,
      scheduler_4_mailbox_write_req_out, scheduler_4_mailbox_write_resp_in);
    spawn phenom_syndrome_cell::SharedService<
      u32:9, u32:5, u32:9, u32:5>(
      scheduler_5_requests_c, scheduler_5_startup_c,
      scheduler_5_egress_p,
      scheduler_5_ram_read_req_out, scheduler_5_ram_read_resp_in,
      scheduler_5_ram_write_req_out, scheduler_5_ram_write_resp_in,
      scheduler_5_mailbox_read_req_out, scheduler_5_mailbox_read_resp_in,
      scheduler_5_mailbox_write_req_out, scheduler_5_mailbox_write_resp_in);
    spawn Phi_xReductionPlane(
      phi_x_reduction_batch_c,
      scheduler_2_aggregate_p);
    spawn Phi_zReductionPlane(
      phi_z_reduction_batch_c,
      scheduler_3_aggregate_p);
    spawn SchedulerRouter0(
      scheduler_0_egress_c, scheduler_0_requests_p[u32:3],
      scheduler_4_requests_p[u32:0],
      scheduler_5_requests_p[u32:0],
      external_0_buffer_p[u32:0],
      effect_window_request_p[u32:0],
      effect_window_grant_c[u32:0],
      effect_window_release_p[u32:0]);
    spawn SchedulerRouter1(
      scheduler_1_egress_c, scheduler_1_requests_p[u32:3],
      scheduler_4_requests_p[u32:1],
      scheduler_5_requests_p[u32:1],
      external_0_buffer_p[u32:1],
      effect_window_request_p[u32:1],
      effect_window_grant_c[u32:1],
      effect_window_release_p[u32:1]);
    spawn SchedulerRouter2(
      scheduler_2_egress_c, scheduler_2_requests_p[u32:1],
      scheduler_4_requests_p[u32:2],
      external_1_buffer_p,
      phi_x_reduction_batch_p[u32:0],
      effect_window_request_p[u32:2],
      effect_window_grant_c[u32:2],
      effect_window_release_p[u32:2]);
    spawn SchedulerRouter3(
      scheduler_3_egress_c, scheduler_3_requests_p[u32:1],
      scheduler_5_requests_p[u32:2],
      external_2_buffer_p,
      phi_z_reduction_batch_p[u32:0],
      effect_window_request_p[u32:3],
      effect_window_grant_c[u32:3],
      effect_window_release_p[u32:3]);
    spawn SchedulerRouter4(
      scheduler_4_egress_c, scheduler_4_requests_p[u32:4],
      scheduler_0_requests_p[u32:0],
      scheduler_1_requests_p[u32:0],
      scheduler_2_requests_p[u32:0],
      effect_window_request_p[u32:4],
      effect_window_grant_c[u32:4],
      effect_window_release_p[u32:4]);
    spawn SchedulerRouter5(
      scheduler_5_egress_c, scheduler_5_requests_p[u32:4],
      scheduler_0_requests_p[u32:1],
      scheduler_1_requests_p[u32:1],
      scheduler_3_requests_p[u32:0],
      effect_window_request_p[u32:5],
      effect_window_grant_c[u32:5],
      effect_window_release_p[u32:5]);
    spawn ControlDispatcher(control_router_in, scheduler_0_requests_p[u32:2], scheduler_1_requests_p[u32:2], scheduler_4_requests_p[u32:3], scheduler_5_requests_p[u32:3]);
    spawn frame_transport::FrameArrayMux<u32:2>(external_0_buffer_c, data_measurements_out);
    spawn frame_transport::FrameRelay(external_1_buffer_c, x_decoder_events_out);
    spawn frame_transport::FrameRelay(external_2_buffer_c, z_decoder_events_out);
    ()
  }

  init { () }
  next(state: ()) { state }
}

pub proc Top {
  scheduler_0_ram_read_req_out: chan<phenom_data_cell::MachineRamReadReq> out;
  scheduler_0_ram_read_resp_in: chan<phenom_data_cell::MachineRamReadResp> in;
  scheduler_0_ram_write_req_out: chan<phenom_data_cell::MachineRamWriteReq> out;
  scheduler_0_ram_write_resp_in: chan<phenom_data_cell::MachineRamWriteResp> in;
  scheduler_0_mailbox_read_req_out: chan<phenom_data_cell::MailboxRamReadReq> out;
  scheduler_0_mailbox_read_resp_in: chan<phenom_data_cell::MailboxRamReadResp> in;
  scheduler_0_mailbox_write_req_out: chan<phenom_data_cell::MailboxRamWriteReq> out;
  scheduler_0_mailbox_write_resp_in: chan<phenom_data_cell::MailboxRamWriteResp> in;
  scheduler_1_ram_read_req_out: chan<phenom_data_cell::MachineRamReadReq> out;
  scheduler_1_ram_read_resp_in: chan<phenom_data_cell::MachineRamReadResp> in;
  scheduler_1_ram_write_req_out: chan<phenom_data_cell::MachineRamWriteReq> out;
  scheduler_1_ram_write_resp_in: chan<phenom_data_cell::MachineRamWriteResp> in;
  scheduler_1_mailbox_read_req_out: chan<phenom_data_cell::MailboxRamReadReq> out;
  scheduler_1_mailbox_read_resp_in: chan<phenom_data_cell::MailboxRamReadResp> in;
  scheduler_1_mailbox_write_req_out: chan<phenom_data_cell::MailboxRamWriteReq> out;
  scheduler_1_mailbox_write_resp_in: chan<phenom_data_cell::MailboxRamWriteResp> in;
  scheduler_2_ram_read_req_out: chan<phi_halo_cell::MachineRamReadReq> out;
  scheduler_2_ram_read_resp_in: chan<phi_halo_cell::MachineRamReadResp> in;
  scheduler_2_ram_write_req_out: chan<phi_halo_cell::MachineRamWriteReq> out;
  scheduler_2_ram_write_resp_in: chan<phi_halo_cell::MachineRamWriteResp> in;
  scheduler_2_mailbox_read_req_out: chan<phi_halo_cell::MailboxRamReadReq> out;
  scheduler_2_mailbox_read_resp_in: chan<phi_halo_cell::MailboxRamReadResp> in;
  scheduler_2_mailbox_write_req_out: chan<phi_halo_cell::MailboxRamWriteReq> out;
  scheduler_2_mailbox_write_resp_in: chan<phi_halo_cell::MailboxRamWriteResp> in;
  scheduler_3_ram_read_req_out: chan<phi_halo_cell::MachineRamReadReq> out;
  scheduler_3_ram_read_resp_in: chan<phi_halo_cell::MachineRamReadResp> in;
  scheduler_3_ram_write_req_out: chan<phi_halo_cell::MachineRamWriteReq> out;
  scheduler_3_ram_write_resp_in: chan<phi_halo_cell::MachineRamWriteResp> in;
  scheduler_3_mailbox_read_req_out: chan<phi_halo_cell::MailboxRamReadReq> out;
  scheduler_3_mailbox_read_resp_in: chan<phi_halo_cell::MailboxRamReadResp> in;
  scheduler_3_mailbox_write_req_out: chan<phi_halo_cell::MailboxRamWriteReq> out;
  scheduler_3_mailbox_write_resp_in: chan<phi_halo_cell::MailboxRamWriteResp> in;
  scheduler_4_ram_read_req_out: chan<phenom_syndrome_cell::MachineRamReadReq> out;
  scheduler_4_ram_read_resp_in: chan<phenom_syndrome_cell::MachineRamReadResp> in;
  scheduler_4_ram_write_req_out: chan<phenom_syndrome_cell::MachineRamWriteReq> out;
  scheduler_4_ram_write_resp_in: chan<phenom_syndrome_cell::MachineRamWriteResp> in;
  scheduler_4_mailbox_read_req_out: chan<phenom_syndrome_cell::MailboxRamReadReq> out;
  scheduler_4_mailbox_read_resp_in: chan<phenom_syndrome_cell::MailboxRamReadResp> in;
  scheduler_4_mailbox_write_req_out: chan<phenom_syndrome_cell::MailboxRamWriteReq> out;
  scheduler_4_mailbox_write_resp_in: chan<phenom_syndrome_cell::MailboxRamWriteResp> in;
  scheduler_5_ram_read_req_out: chan<phenom_syndrome_cell::MachineRamReadReq> out;
  scheduler_5_ram_read_resp_in: chan<phenom_syndrome_cell::MachineRamReadResp> in;
  scheduler_5_ram_write_req_out: chan<phenom_syndrome_cell::MachineRamWriteReq> out;
  scheduler_5_ram_write_resp_in: chan<phenom_syndrome_cell::MachineRamWriteResp> in;
  scheduler_5_mailbox_read_req_out: chan<phenom_syndrome_cell::MailboxRamReadReq> out;
  scheduler_5_mailbox_read_resp_in: chan<phenom_syndrome_cell::MailboxRamReadResp> in;
  scheduler_5_mailbox_write_req_out: chan<phenom_syndrome_cell::MailboxRamWriteReq> out;
  scheduler_5_mailbox_write_resp_in: chan<phenom_syndrome_cell::MailboxRamWriteResp> in;
  control_router_in: chan<hls_spatial_router::SpatialFrame> in;
  data_measurements_out: chan<axis::Frame> out;
  x_decoder_events_out: chan<axis::Frame> out;
  z_decoder_events_out: chan<axis::Frame> out;

  config(
    scheduler_0_ram_read_req_out: chan<phenom_data_cell::MachineRamReadReq> out,
    scheduler_0_ram_read_resp_in: chan<phenom_data_cell::MachineRamReadResp> in,
    scheduler_0_ram_write_req_out: chan<phenom_data_cell::MachineRamWriteReq> out,
    scheduler_0_ram_write_resp_in: chan<phenom_data_cell::MachineRamWriteResp> in,
    scheduler_0_mailbox_read_req_out: chan<phenom_data_cell::MailboxRamReadReq> out,
    scheduler_0_mailbox_read_resp_in: chan<phenom_data_cell::MailboxRamReadResp> in,
    scheduler_0_mailbox_write_req_out: chan<phenom_data_cell::MailboxRamWriteReq> out,
    scheduler_0_mailbox_write_resp_in: chan<phenom_data_cell::MailboxRamWriteResp> in,
    scheduler_1_ram_read_req_out: chan<phenom_data_cell::MachineRamReadReq> out,
    scheduler_1_ram_read_resp_in: chan<phenom_data_cell::MachineRamReadResp> in,
    scheduler_1_ram_write_req_out: chan<phenom_data_cell::MachineRamWriteReq> out,
    scheduler_1_ram_write_resp_in: chan<phenom_data_cell::MachineRamWriteResp> in,
    scheduler_1_mailbox_read_req_out: chan<phenom_data_cell::MailboxRamReadReq> out,
    scheduler_1_mailbox_read_resp_in: chan<phenom_data_cell::MailboxRamReadResp> in,
    scheduler_1_mailbox_write_req_out: chan<phenom_data_cell::MailboxRamWriteReq> out,
    scheduler_1_mailbox_write_resp_in: chan<phenom_data_cell::MailboxRamWriteResp> in,
    scheduler_2_ram_read_req_out: chan<phi_halo_cell::MachineRamReadReq> out,
    scheduler_2_ram_read_resp_in: chan<phi_halo_cell::MachineRamReadResp> in,
    scheduler_2_ram_write_req_out: chan<phi_halo_cell::MachineRamWriteReq> out,
    scheduler_2_ram_write_resp_in: chan<phi_halo_cell::MachineRamWriteResp> in,
    scheduler_2_mailbox_read_req_out: chan<phi_halo_cell::MailboxRamReadReq> out,
    scheduler_2_mailbox_read_resp_in: chan<phi_halo_cell::MailboxRamReadResp> in,
    scheduler_2_mailbox_write_req_out: chan<phi_halo_cell::MailboxRamWriteReq> out,
    scheduler_2_mailbox_write_resp_in: chan<phi_halo_cell::MailboxRamWriteResp> in,
    scheduler_3_ram_read_req_out: chan<phi_halo_cell::MachineRamReadReq> out,
    scheduler_3_ram_read_resp_in: chan<phi_halo_cell::MachineRamReadResp> in,
    scheduler_3_ram_write_req_out: chan<phi_halo_cell::MachineRamWriteReq> out,
    scheduler_3_ram_write_resp_in: chan<phi_halo_cell::MachineRamWriteResp> in,
    scheduler_3_mailbox_read_req_out: chan<phi_halo_cell::MailboxRamReadReq> out,
    scheduler_3_mailbox_read_resp_in: chan<phi_halo_cell::MailboxRamReadResp> in,
    scheduler_3_mailbox_write_req_out: chan<phi_halo_cell::MailboxRamWriteReq> out,
    scheduler_3_mailbox_write_resp_in: chan<phi_halo_cell::MailboxRamWriteResp> in,
    scheduler_4_ram_read_req_out: chan<phenom_syndrome_cell::MachineRamReadReq> out,
    scheduler_4_ram_read_resp_in: chan<phenom_syndrome_cell::MachineRamReadResp> in,
    scheduler_4_ram_write_req_out: chan<phenom_syndrome_cell::MachineRamWriteReq> out,
    scheduler_4_ram_write_resp_in: chan<phenom_syndrome_cell::MachineRamWriteResp> in,
    scheduler_4_mailbox_read_req_out: chan<phenom_syndrome_cell::MailboxRamReadReq> out,
    scheduler_4_mailbox_read_resp_in: chan<phenom_syndrome_cell::MailboxRamReadResp> in,
    scheduler_4_mailbox_write_req_out: chan<phenom_syndrome_cell::MailboxRamWriteReq> out,
    scheduler_4_mailbox_write_resp_in: chan<phenom_syndrome_cell::MailboxRamWriteResp> in,
    scheduler_5_ram_read_req_out: chan<phenom_syndrome_cell::MachineRamReadReq> out,
    scheduler_5_ram_read_resp_in: chan<phenom_syndrome_cell::MachineRamReadResp> in,
    scheduler_5_ram_write_req_out: chan<phenom_syndrome_cell::MachineRamWriteReq> out,
    scheduler_5_ram_write_resp_in: chan<phenom_syndrome_cell::MachineRamWriteResp> in,
    scheduler_5_mailbox_read_req_out: chan<phenom_syndrome_cell::MailboxRamReadReq> out,
    scheduler_5_mailbox_read_resp_in: chan<phenom_syndrome_cell::MailboxRamReadResp> in,
    scheduler_5_mailbox_write_req_out: chan<phenom_syndrome_cell::MailboxRamWriteReq> out,
    scheduler_5_mailbox_write_resp_in: chan<phenom_syndrome_cell::MailboxRamWriteResp> in,
    control_router_in: chan<hls_spatial_router::SpatialFrame> in,
    data_measurements_out: chan<axis::Frame> out,
    x_decoder_events_out: chan<axis::Frame> out,
    z_decoder_events_out: chan<axis::Frame> out
  ) {
    spawn SchedulerGrid(
      scheduler_0_ram_read_req_out,
      scheduler_0_ram_read_resp_in,
      scheduler_0_ram_write_req_out,
      scheduler_0_ram_write_resp_in,
      scheduler_0_mailbox_read_req_out,
      scheduler_0_mailbox_read_resp_in,
      scheduler_0_mailbox_write_req_out,
      scheduler_0_mailbox_write_resp_in,
      scheduler_1_ram_read_req_out,
      scheduler_1_ram_read_resp_in,
      scheduler_1_ram_write_req_out,
      scheduler_1_ram_write_resp_in,
      scheduler_1_mailbox_read_req_out,
      scheduler_1_mailbox_read_resp_in,
      scheduler_1_mailbox_write_req_out,
      scheduler_1_mailbox_write_resp_in,
      scheduler_2_ram_read_req_out,
      scheduler_2_ram_read_resp_in,
      scheduler_2_ram_write_req_out,
      scheduler_2_ram_write_resp_in,
      scheduler_2_mailbox_read_req_out,
      scheduler_2_mailbox_read_resp_in,
      scheduler_2_mailbox_write_req_out,
      scheduler_2_mailbox_write_resp_in,
      scheduler_3_ram_read_req_out,
      scheduler_3_ram_read_resp_in,
      scheduler_3_ram_write_req_out,
      scheduler_3_ram_write_resp_in,
      scheduler_3_mailbox_read_req_out,
      scheduler_3_mailbox_read_resp_in,
      scheduler_3_mailbox_write_req_out,
      scheduler_3_mailbox_write_resp_in,
      scheduler_4_ram_read_req_out,
      scheduler_4_ram_read_resp_in,
      scheduler_4_ram_write_req_out,
      scheduler_4_ram_write_resp_in,
      scheduler_4_mailbox_read_req_out,
      scheduler_4_mailbox_read_resp_in,
      scheduler_4_mailbox_write_req_out,
      scheduler_4_mailbox_write_resp_in,
      scheduler_5_ram_read_req_out,
      scheduler_5_ram_read_resp_in,
      scheduler_5_ram_write_req_out,
      scheduler_5_ram_write_resp_in,
      scheduler_5_mailbox_read_req_out,
      scheduler_5_mailbox_read_resp_in,
      scheduler_5_mailbox_write_req_out,
      scheduler_5_mailbox_write_resp_in,
      control_router_in,
      data_measurements_out,
      x_decoder_events_out,
      z_decoder_events_out
    );
    (scheduler_0_ram_read_req_out, scheduler_0_ram_read_resp_in, scheduler_0_ram_write_req_out, scheduler_0_ram_write_resp_in, scheduler_0_mailbox_read_req_out, scheduler_0_mailbox_read_resp_in, scheduler_0_mailbox_write_req_out, scheduler_0_mailbox_write_resp_in, scheduler_1_ram_read_req_out, scheduler_1_ram_read_resp_in, scheduler_1_ram_write_req_out, scheduler_1_ram_write_resp_in, scheduler_1_mailbox_read_req_out, scheduler_1_mailbox_read_resp_in, scheduler_1_mailbox_write_req_out, scheduler_1_mailbox_write_resp_in, scheduler_2_ram_read_req_out, scheduler_2_ram_read_resp_in, scheduler_2_ram_write_req_out, scheduler_2_ram_write_resp_in, scheduler_2_mailbox_read_req_out, scheduler_2_mailbox_read_resp_in, scheduler_2_mailbox_write_req_out, scheduler_2_mailbox_write_resp_in, scheduler_3_ram_read_req_out, scheduler_3_ram_read_resp_in, scheduler_3_ram_write_req_out, scheduler_3_ram_write_resp_in, scheduler_3_mailbox_read_req_out, scheduler_3_mailbox_read_resp_in, scheduler_3_mailbox_write_req_out, scheduler_3_mailbox_write_resp_in, scheduler_4_ram_read_req_out, scheduler_4_ram_read_resp_in, scheduler_4_ram_write_req_out, scheduler_4_ram_write_resp_in, scheduler_4_mailbox_read_req_out, scheduler_4_mailbox_read_resp_in, scheduler_4_mailbox_write_req_out, scheduler_4_mailbox_write_resp_in, scheduler_5_ram_read_req_out, scheduler_5_ram_read_resp_in, scheduler_5_ram_write_req_out, scheduler_5_ram_write_resp_in, scheduler_5_mailbox_read_req_out, scheduler_5_mailbox_read_resp_in, scheduler_5_mailbox_write_req_out, scheduler_5_mailbox_write_resp_in, control_router_in, data_measurements_out, x_decoder_events_out, z_decoder_events_out)
  }

  init { () }
  next(state: ()) { state }
}
