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

struct Phi_xReductionFragmentQueue {
  current_valid: u1,
  current: axis::Frame,
  lookahead_valid: u1,
  lookahead: axis::Frame,
}

// Fragment 0 (north) uses inverse fragment 3 at offset [0, 1].
// Fragment 1 (east) uses inverse fragment 2 at offset [-1, 0].
// Fragment 2 (west) uses inverse fragment 1 at offset [1, 0].
// Fragment 3 (south) uses inverse fragment 0 at offset [0, -1].
fn phi_x_reduction_fragment_pop(queue: Phi_xReductionFragmentQueue) -> Phi_xReductionFragmentQueue {
  Phi_xReductionFragmentQueue {
    current_valid: queue.lookahead_valid,
    current: if queue.lookahead_valid { queue.lookahead
      } else { queue.current },
    lookahead_valid: u1:0,
    lookahead: queue.lookahead,
  }
}

fn phi_x_reduction_fragment_push(
    queue: Phi_xReductionFragmentQueue, frame: axis::Frame) -> Phi_xReductionFragmentQueue {
  if !queue.current_valid {
    Phi_xReductionFragmentQueue { current_valid: u1:1, current: frame,
      ..queue }
  } else {
    Phi_xReductionFragmentQueue { lookahead_valid: u1:1, lookahead: frame,
      ..queue }
  }
}

fn phi_x_reduction_fragment_after_pop(
    queue: Phi_xReductionFragmentQueue, pop: u1) -> Phi_xReductionFragmentQueue {
  if pop { phi_x_reduction_fragment_pop(queue)
  } else { queue }
}

fn phi_x_reduction_fragment_update_bank<COUNT: u32>(
    bank: Phi_xReductionFragmentQueue[COUNT],
    pop_valid: u1, pop_source: u32,
    push_valid: u1, push_source: u32,
    push_frame: axis::Frame) -> Phi_xReductionFragmentQueue[COUNT] {
  let after_pop = if pop_valid {
    update(bank, pop_source,
      phi_x_reduction_fragment_pop(bank[pop_source]))
  } else { bank };
  if push_valid {
    update(after_pop, push_source,
      phi_x_reduction_fragment_push(
        after_pop[push_source], push_frame))
  } else { after_pop }
}

struct Phi_xReductionPlaneState {
  input_cursor: u32,
  output_cursor: u32,
  open_tokens: u1[u32:9],
  bank_0: Phi_xReductionFragmentQueue[u32:9],
  bank_1: Phi_xReductionFragmentQueue[u32:9],
  bank_2: Phi_xReductionFragmentQueue[u32:9],
  bank_3: Phi_xReductionFragmentQueue[u32:9],
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
    let (output_ready, output_slot) =
      unroll_for! (offset, selected):
          (u32, (u1, u32)) in u32:0..u32:9 {
        let unwrapped = state.output_cursor + offset;
        let candidate = if unwrapped < u32:9 { unwrapped } else {
          unwrapped - u32:9 };
        let take = !selected.0 && ready_slots[candidate];
        (selected.0 || take,
          if take { candidate } else { selected.1 })
      }((u1:0, u32:0));
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
              state.input_cursor == candidate,
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
    let after_pop_0 = phi_x_reduction_fragment_after_pop(
      queue_0, output_ready &&
        pop_sources[u32:0] == push_source);
    let capacity_0 = !after_pop_0.lookahead_valid;
    let queue_1 = state.bank_1[push_source];
    let after_pop_1 = phi_x_reduction_fragment_after_pop(
      queue_1, output_ready &&
        pop_sources[u32:1] == push_source);
    let capacity_1 = !after_pop_1.lookahead_valid;
    let queue_2 = state.bank_2[push_source];
    let after_pop_2 = phi_x_reduction_fragment_after_pop(
      queue_2, output_ready &&
        pop_sources[u32:2] == push_source);
    let capacity_2 = !after_pop_2.lookahead_valid;
    let queue_3 = state.bank_3[push_source];
    let after_pop_3 = phi_x_reduction_fragment_after_pop(
      queue_3, output_ready &&
        pop_sources[u32:3] == push_source);
    let capacity_3 = !after_pop_3.lookahead_valid;
    let can_insert = work_valid && source_valid && capacity_0 && capacity_1 && capacity_2 && capacity_3;
    let bank_0 = phi_x_reduction_fragment_update_bank(
      state.bank_0, output_ready,
      pop_sources[u32:0], can_insert, push_source,
      work.frames[u32:0]);
    let bank_1 = phi_x_reduction_fragment_update_bank(
      state.bank_1, output_ready,
      pop_sources[u32:1], can_insert, push_source,
      work.frames[u32:1]);
    let bank_2 = phi_x_reduction_fragment_update_bank(
      state.bank_2, output_ready,
      pop_sources[u32:2], can_insert, push_source,
      work.frames[u32:2]);
    let bank_3 = phi_x_reduction_fragment_update_bank(
      state.bank_3, output_ready,
      pop_sources[u32:3], can_insert, push_source,
      work.frames[u32:3]);
    let _done = join(output_tok, input_tok);
    Phi_xReductionPlaneState {
      input_cursor: if state.pending_valid {
        state.input_cursor
      } else if state.input_cursor + u32:1 == u32:1 { u32:0 } else {
        state.input_cursor + u32:1 },
      output_cursor: if !output_ready { state.output_cursor
      } else if output_slot + u32:1 == u32:9 { u32:0 } else {
        output_slot + u32:1 },
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

struct Phi_zReductionFragmentQueue {
  current_valid: u1,
  current: axis::Frame,
  lookahead_valid: u1,
  lookahead: axis::Frame,
}

// Fragment 0 (north) uses inverse fragment 3 at offset [0, 1].
// Fragment 1 (east) uses inverse fragment 2 at offset [-1, 0].
// Fragment 2 (west) uses inverse fragment 1 at offset [1, 0].
// Fragment 3 (south) uses inverse fragment 0 at offset [0, -1].
fn phi_z_reduction_fragment_pop(queue: Phi_zReductionFragmentQueue) -> Phi_zReductionFragmentQueue {
  Phi_zReductionFragmentQueue {
    current_valid: queue.lookahead_valid,
    current: if queue.lookahead_valid { queue.lookahead
      } else { queue.current },
    lookahead_valid: u1:0,
    lookahead: queue.lookahead,
  }
}

fn phi_z_reduction_fragment_push(
    queue: Phi_zReductionFragmentQueue, frame: axis::Frame) -> Phi_zReductionFragmentQueue {
  if !queue.current_valid {
    Phi_zReductionFragmentQueue { current_valid: u1:1, current: frame,
      ..queue }
  } else {
    Phi_zReductionFragmentQueue { lookahead_valid: u1:1, lookahead: frame,
      ..queue }
  }
}

fn phi_z_reduction_fragment_after_pop(
    queue: Phi_zReductionFragmentQueue, pop: u1) -> Phi_zReductionFragmentQueue {
  if pop { phi_z_reduction_fragment_pop(queue)
  } else { queue }
}

fn phi_z_reduction_fragment_update_bank<COUNT: u32>(
    bank: Phi_zReductionFragmentQueue[COUNT],
    pop_valid: u1, pop_source: u32,
    push_valid: u1, push_source: u32,
    push_frame: axis::Frame) -> Phi_zReductionFragmentQueue[COUNT] {
  let after_pop = if pop_valid {
    update(bank, pop_source,
      phi_z_reduction_fragment_pop(bank[pop_source]))
  } else { bank };
  if push_valid {
    update(after_pop, push_source,
      phi_z_reduction_fragment_push(
        after_pop[push_source], push_frame))
  } else { after_pop }
}

struct Phi_zReductionPlaneState {
  input_cursor: u32,
  output_cursor: u32,
  open_tokens: u1[u32:9],
  bank_0: Phi_zReductionFragmentQueue[u32:9],
  bank_1: Phi_zReductionFragmentQueue[u32:9],
  bank_2: Phi_zReductionFragmentQueue[u32:9],
  bank_3: Phi_zReductionFragmentQueue[u32:9],
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
    let (output_ready, output_slot) =
      unroll_for! (offset, selected):
          (u32, (u1, u32)) in u32:0..u32:9 {
        let unwrapped = state.output_cursor + offset;
        let candidate = if unwrapped < u32:9 { unwrapped } else {
          unwrapped - u32:9 };
        let take = !selected.0 && ready_slots[candidate];
        (selected.0 || take,
          if take { candidate } else { selected.1 })
      }((u1:0, u32:0));
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
              state.input_cursor == candidate,
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
    let after_pop_0 = phi_z_reduction_fragment_after_pop(
      queue_0, output_ready &&
        pop_sources[u32:0] == push_source);
    let capacity_0 = !after_pop_0.lookahead_valid;
    let queue_1 = state.bank_1[push_source];
    let after_pop_1 = phi_z_reduction_fragment_after_pop(
      queue_1, output_ready &&
        pop_sources[u32:1] == push_source);
    let capacity_1 = !after_pop_1.lookahead_valid;
    let queue_2 = state.bank_2[push_source];
    let after_pop_2 = phi_z_reduction_fragment_after_pop(
      queue_2, output_ready &&
        pop_sources[u32:2] == push_source);
    let capacity_2 = !after_pop_2.lookahead_valid;
    let queue_3 = state.bank_3[push_source];
    let after_pop_3 = phi_z_reduction_fragment_after_pop(
      queue_3, output_ready &&
        pop_sources[u32:3] == push_source);
    let capacity_3 = !after_pop_3.lookahead_valid;
    let can_insert = work_valid && source_valid && capacity_0 && capacity_1 && capacity_2 && capacity_3;
    let bank_0 = phi_z_reduction_fragment_update_bank(
      state.bank_0, output_ready,
      pop_sources[u32:0], can_insert, push_source,
      work.frames[u32:0]);
    let bank_1 = phi_z_reduction_fragment_update_bank(
      state.bank_1, output_ready,
      pop_sources[u32:1], can_insert, push_source,
      work.frames[u32:1]);
    let bank_2 = phi_z_reduction_fragment_update_bank(
      state.bank_2, output_ready,
      pop_sources[u32:2], can_insert, push_source,
      work.frames[u32:2]);
    let bank_3 = phi_z_reduction_fragment_update_bank(
      state.bank_3, output_ready,
      pop_sources[u32:3], can_insert, push_source,
      work.frames[u32:3]);
    let _done = join(output_tok, input_tok);
    Phi_zReductionPlaneState {
      input_cursor: if state.pending_valid {
        state.input_cursor
      } else if state.input_cursor + u32:1 == u32:1 { u32:0 } else {
        state.input_cursor + u32:1 },
      output_cursor: if !output_ready { state.output_cursor
      } else if output_slot + u32:1 == u32:9 { u32:0 } else {
        output_slot + u32:1 },
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

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter0State {
  active: u1,
  scheduled: phenom_data_cell::ScheduledEffects,
  index: u8,
  window_requested: u1,
  window_granted: u1,
  credit_debt: u1,
  lookahead: u1,
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
    let state_last = state.active && state_effect_info.2;
    let can_receive = !state.active ||
      (state_last && state.credit_debt && !state.lookahead);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phenom_data_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.window_requested && !state.window_granted, u1:0);
    let batch_valid = state.active || incoming_valid;
    let scheduled = if state.active {
      state.scheduled
    } else { incoming };
    let index = if state.active { state.index } else { u8:0 };
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
    let batch_continues = batch_valid && !last;
    // Never apply a stale grant to a batch admitted in this same
    // activation: the virtual credit could otherwise bypass back to
    // SharedService before that batch has made egress_busy visible.
    let grant_usable = grant_valid && state.active &&
      !state.lookahead && batch_continues;
    let fake_credit = grant_usable;
    let swallow_physical = last && state.credit_debt &&
      !state.lookahead;
    let forward_physical = last && !swallow_physical;
    let forward_credit = fake_credit || forward_physical;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phenom_data_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_data_cell::ScheduledRequest>()
      });
    let carry_lookahead = last && swallow_physical &&
      incoming_valid;
    let release = (last && state.lookahead) ||
      (last && state.credit_debt && !incoming_valid) ||
      (grant_valid && !grant_usable);
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let pending_request = state.window_requested && !grant_valid;
    let window_granted =
      (state.window_granted || grant_usable) && !release;
    let credit_debt =
      (state.credit_debt || fake_credit) && !swallow_physical;
    let next_active = carry_lookahead || batch_continues;
    let next_lookahead = if carry_lookahead { u1:1 } else {
      if batch_continues { state.lookahead } else { u1:0 }
    };
    let request = next_active && !next_lookahead &&
      !window_granted && !credit_debt && !pending_request;
    let _request_tok = send_if(
      release_tok, window_request_out, request, u1:1);
    if carry_lookahead {
      SchedulerRouter0State {
        active: u1:1,
        scheduled: incoming,
        index: u8:0,
        window_requested: u1:0,
        window_granted,
        credit_debt,
        lookahead: u1:1,
      }
    } else if batch_continues {
      SchedulerRouter0State {
        active: u1:1,
        scheduled,
        index: index + u8:1,
        window_requested: pending_request || request,
        window_granted,
        credit_debt,
        lookahead: state.lookahead,
      }
    } else {
      SchedulerRouter0State {
        window_requested: pending_request || request,
        ..zero!<SchedulerRouter0State>()
      }
    }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter1State {
  active: u1,
  scheduled: phenom_data_cell::ScheduledEffects,
  index: u8,
  window_requested: u1,
  window_granted: u1,
  credit_debt: u1,
  lookahead: u1,
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
    let state_last = state.active && state_effect_info.2;
    let can_receive = !state.active ||
      (state_last && state.credit_debt && !state.lookahead);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phenom_data_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.window_requested && !state.window_granted, u1:0);
    let batch_valid = state.active || incoming_valid;
    let scheduled = if state.active {
      state.scheduled
    } else { incoming };
    let index = if state.active { state.index } else { u8:0 };
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
    let batch_continues = batch_valid && !last;
    // Never apply a stale grant to a batch admitted in this same
    // activation: the virtual credit could otherwise bypass back to
    // SharedService before that batch has made egress_busy visible.
    let grant_usable = grant_valid && state.active &&
      !state.lookahead && batch_continues;
    let fake_credit = grant_usable;
    let swallow_physical = last && state.credit_debt &&
      !state.lookahead;
    let forward_physical = last && !swallow_physical;
    let forward_credit = fake_credit || forward_physical;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phenom_data_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_data_cell::ScheduledRequest>()
      });
    let carry_lookahead = last && swallow_physical &&
      incoming_valid;
    let release = (last && state.lookahead) ||
      (last && state.credit_debt && !incoming_valid) ||
      (grant_valid && !grant_usable);
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let pending_request = state.window_requested && !grant_valid;
    let window_granted =
      (state.window_granted || grant_usable) && !release;
    let credit_debt =
      (state.credit_debt || fake_credit) && !swallow_physical;
    let next_active = carry_lookahead || batch_continues;
    let next_lookahead = if carry_lookahead { u1:1 } else {
      if batch_continues { state.lookahead } else { u1:0 }
    };
    let request = next_active && !next_lookahead &&
      !window_granted && !credit_debt && !pending_request;
    let _request_tok = send_if(
      release_tok, window_request_out, request, u1:1);
    if carry_lookahead {
      SchedulerRouter1State {
        active: u1:1,
        scheduled: incoming,
        index: u8:0,
        window_requested: u1:0,
        window_granted,
        credit_debt,
        lookahead: u1:1,
      }
    } else if batch_continues {
      SchedulerRouter1State {
        active: u1:1,
        scheduled,
        index: index + u8:1,
        window_requested: pending_request || request,
        window_granted,
        credit_debt,
        lookahead: state.lookahead,
      }
    } else {
      SchedulerRouter1State {
        window_requested: pending_request || request,
        ..zero!<SchedulerRouter1State>()
      }
    }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter2State {
  active: u1,
  scheduled: phi_halo_cell::ScheduledEffects,
  index: u8,
  window_requested: u1,
  window_granted: u1,
  credit_debt: u1,
  lookahead: u1,
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
    let state_reduction_batch = state.active &&
      state.index == u8:0 && state_reduction_prefix.0;
    let state_last = state.active &&
      if state_reduction_batch { state_reduction_prefix.2
      } else { state_effect_info.2 };
    let can_receive = !state.active ||
      (state_last && state.credit_debt && !state.lookahead);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phi_halo_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.window_requested && !state.window_granted, u1:0);
    let batch_valid = state.active || incoming_valid;
    let scheduled = if state.active {
      state.scheduled
    } else { incoming };
    let index = if state.active { state.index } else { u8:0 };
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
    let batch_continues = batch_valid && !last;
    // Never apply a stale grant to a batch admitted in this same
    // activation: the virtual credit could otherwise bypass back to
    // SharedService before that batch has made egress_busy visible.
    let grant_usable = grant_valid && state.active &&
      !state.lookahead && batch_continues;
    let fake_credit = grant_usable;
    let swallow_physical = last && state.credit_debt &&
      !state.lookahead;
    let forward_physical = last && !swallow_physical;
    let forward_credit = fake_credit || forward_physical;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phi_halo_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phi_halo_cell::ScheduledRequest>()
      });
    let carry_lookahead = last && swallow_physical &&
      incoming_valid;
    let release = (last && state.lookahead) ||
      (last && state.credit_debt && !incoming_valid) ||
      (grant_valid && !grant_usable);
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let pending_request = state.window_requested && !grant_valid;
    let window_granted =
      (state.window_granted || grant_usable) && !release;
    let credit_debt =
      (state.credit_debt || fake_credit) && !swallow_physical;
    let next_active = carry_lookahead || batch_continues;
    let next_lookahead = if carry_lookahead { u1:1 } else {
      if batch_continues { state.lookahead } else { u1:0 }
    };
    let request = next_active && !next_lookahead &&
      !window_granted && !credit_debt && !pending_request;
    let _request_tok = send_if(
      release_tok, window_request_out, request, u1:1);
    if carry_lookahead {
      SchedulerRouter2State {
        active: u1:1,
        scheduled: incoming,
        index: u8:0,
        window_requested: u1:0,
        window_granted,
        credit_debt,
        lookahead: u1:1,
      }
    } else if batch_continues {
      SchedulerRouter2State {
        active: u1:1,
        scheduled,
        index: index + if reduction_batch { u8:4 } else { u8:1 },
        window_requested: pending_request || request,
        window_granted,
        credit_debt,
        lookahead: state.lookahead,
      }
    } else {
      SchedulerRouter2State {
        window_requested: pending_request || request,
        ..zero!<SchedulerRouter2State>()
      }
    }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter3State {
  active: u1,
  scheduled: phi_halo_cell::ScheduledEffects,
  index: u8,
  window_requested: u1,
  window_granted: u1,
  credit_debt: u1,
  lookahead: u1,
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
    let state_reduction_batch = state.active &&
      state.index == u8:0 && state_reduction_prefix.0;
    let state_last = state.active &&
      if state_reduction_batch { state_reduction_prefix.2
      } else { state_effect_info.2 };
    let can_receive = !state.active ||
      (state_last && state.credit_debt && !state.lookahead);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phi_halo_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.window_requested && !state.window_granted, u1:0);
    let batch_valid = state.active || incoming_valid;
    let scheduled = if state.active {
      state.scheduled
    } else { incoming };
    let index = if state.active { state.index } else { u8:0 };
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
    let batch_continues = batch_valid && !last;
    // Never apply a stale grant to a batch admitted in this same
    // activation: the virtual credit could otherwise bypass back to
    // SharedService before that batch has made egress_busy visible.
    let grant_usable = grant_valid && state.active &&
      !state.lookahead && batch_continues;
    let fake_credit = grant_usable;
    let swallow_physical = last && state.credit_debt &&
      !state.lookahead;
    let forward_physical = last && !swallow_physical;
    let forward_credit = fake_credit || forward_physical;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phi_halo_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phi_halo_cell::ScheduledRequest>()
      });
    let carry_lookahead = last && swallow_physical &&
      incoming_valid;
    let release = (last && state.lookahead) ||
      (last && state.credit_debt && !incoming_valid) ||
      (grant_valid && !grant_usable);
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let pending_request = state.window_requested && !grant_valid;
    let window_granted =
      (state.window_granted || grant_usable) && !release;
    let credit_debt =
      (state.credit_debt || fake_credit) && !swallow_physical;
    let next_active = carry_lookahead || batch_continues;
    let next_lookahead = if carry_lookahead { u1:1 } else {
      if batch_continues { state.lookahead } else { u1:0 }
    };
    let request = next_active && !next_lookahead &&
      !window_granted && !credit_debt && !pending_request;
    let _request_tok = send_if(
      release_tok, window_request_out, request, u1:1);
    if carry_lookahead {
      SchedulerRouter3State {
        active: u1:1,
        scheduled: incoming,
        index: u8:0,
        window_requested: u1:0,
        window_granted,
        credit_debt,
        lookahead: u1:1,
      }
    } else if batch_continues {
      SchedulerRouter3State {
        active: u1:1,
        scheduled,
        index: index + if reduction_batch { u8:4 } else { u8:1 },
        window_requested: pending_request || request,
        window_granted,
        credit_debt,
        lookahead: state.lookahead,
      }
    } else {
      SchedulerRouter3State {
        window_requested: pending_request || request,
        ..zero!<SchedulerRouter3State>()
      }
    }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter4State {
  active: u1,
  scheduled: phenom_syndrome_cell::ScheduledEffects,
  index: u8,
  window_requested: u1,
  window_granted: u1,
  credit_debt: u1,
  lookahead: u1,
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
    let state_last = state.active && state_effect_info.2;
    let can_receive = !state.active ||
      (state_last && state.credit_debt && !state.lookahead);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phenom_syndrome_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.window_requested && !state.window_granted, u1:0);
    let batch_valid = state.active || incoming_valid;
    let scheduled = if state.active {
      state.scheduled
    } else { incoming };
    let index = if state.active { state.index } else { u8:0 };
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
    let batch_continues = batch_valid && !last;
    // Never apply a stale grant to a batch admitted in this same
    // activation: the virtual credit could otherwise bypass back to
    // SharedService before that batch has made egress_busy visible.
    let grant_usable = grant_valid && state.active &&
      !state.lookahead && batch_continues;
    let fake_credit = grant_usable;
    let swallow_physical = last && state.credit_debt &&
      !state.lookahead;
    let forward_physical = last && !swallow_physical;
    let forward_credit = fake_credit || forward_physical;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phenom_syndrome_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      });
    let carry_lookahead = last && swallow_physical &&
      incoming_valid;
    let release = (last && state.lookahead) ||
      (last && state.credit_debt && !incoming_valid) ||
      (grant_valid && !grant_usable);
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let pending_request = state.window_requested && !grant_valid;
    let window_granted =
      (state.window_granted || grant_usable) && !release;
    let credit_debt =
      (state.credit_debt || fake_credit) && !swallow_physical;
    let next_active = carry_lookahead || batch_continues;
    let next_lookahead = if carry_lookahead { u1:1 } else {
      if batch_continues { state.lookahead } else { u1:0 }
    };
    let request = next_active && !next_lookahead &&
      !window_granted && !credit_debt && !pending_request;
    let _request_tok = send_if(
      release_tok, window_request_out, request, u1:1);
    if carry_lookahead {
      SchedulerRouter4State {
        active: u1:1,
        scheduled: incoming,
        index: u8:0,
        window_requested: u1:0,
        window_granted,
        credit_debt,
        lookahead: u1:1,
      }
    } else if batch_continues {
      SchedulerRouter4State {
        active: u1:1,
        scheduled,
        index: index + u8:1,
        window_requested: pending_request || request,
        window_granted,
        credit_debt,
        lookahead: state.lookahead,
      }
    } else {
      SchedulerRouter4State {
        window_requested: pending_request || request,
        ..zero!<SchedulerRouter4State>()
      }
    }
  }
}

// Routes one committed actor-entry batch in source order. A global
// reservation may admit one lookahead batch while the active batch
// drains; only the active batch can emit downstream effects.
struct SchedulerRouter5State {
  active: u1,
  scheduled: phenom_syndrome_cell::ScheduledEffects,
  index: u8,
  window_requested: u1,
  window_granted: u1,
  credit_debt: u1,
  lookahead: u1,
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
    let state_last = state.active && state_effect_info.2;
    let can_receive = !state.active ||
      (state_last && state.credit_debt && !state.lookahead);
    let (receive_tok, incoming, incoming_valid) =
      recv_if_non_blocking(
        join(), scheduled_in, can_receive,
        zero!<phenom_syndrome_cell::ScheduledEffects>());
    let (grant_tok, _grant, grant_valid) =
      recv_if_non_blocking(
        receive_tok, window_grant_in,
        state.window_requested && !state.window_granted, u1:0);
    let batch_valid = state.active || incoming_valid;
    let scheduled = if state.active {
      state.scheduled
    } else { incoming };
    let index = if state.active { state.index } else { u8:0 };
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
    let batch_continues = batch_valid && !last;
    // Never apply a stale grant to a batch admitted in this same
    // activation: the virtual credit could otherwise bypass back to
    // SharedService before that batch has made egress_busy visible.
    let grant_usable = grant_valid && state.active &&
      !state.lookahead && batch_continues;
    let fake_credit = grant_usable;
    let swallow_physical = last && state.credit_debt &&
      !state.lookahead;
    let forward_physical = last && !swallow_physical;
    let forward_credit = fake_credit || forward_physical;
    let credit_tok = send_if(
      routed_tok, credit_out, forward_credit, phenom_syndrome_cell::ScheduledRequest {
        credit: u1:1,
        ..zero!<phenom_syndrome_cell::ScheduledRequest>()
      });
    let carry_lookahead = last && swallow_physical &&
      incoming_valid;
    let release = (last && state.lookahead) ||
      (last && state.credit_debt && !incoming_valid) ||
      (grant_valid && !grant_usable);
    let release_tok = send_if(
      credit_tok, window_release_out, release, u1:1);
    let pending_request = state.window_requested && !grant_valid;
    let window_granted =
      (state.window_granted || grant_usable) && !release;
    let credit_debt =
      (state.credit_debt || fake_credit) && !swallow_physical;
    let next_active = carry_lookahead || batch_continues;
    let next_lookahead = if carry_lookahead { u1:1 } else {
      if batch_continues { state.lookahead } else { u1:0 }
    };
    let request = next_active && !next_lookahead &&
      !window_granted && !credit_debt && !pending_request;
    let _request_tok = send_if(
      release_tok, window_request_out, request, u1:1);
    if carry_lookahead {
      SchedulerRouter5State {
        active: u1:1,
        scheduled: incoming,
        index: u8:0,
        window_requested: u1:0,
        window_granted,
        credit_debt,
        lookahead: u1:1,
      }
    } else if batch_continues {
      SchedulerRouter5State {
        active: u1:1,
        scheduled,
        index: index + u8:1,
        window_requested: pending_request || request,
        window_granted,
        credit_debt,
        lookahead: state.lookahead,
      }
    } else {
      SchedulerRouter5State {
        window_requested: pending_request || request,
        ..zero!<SchedulerRouter5State>()
      }
    }
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
