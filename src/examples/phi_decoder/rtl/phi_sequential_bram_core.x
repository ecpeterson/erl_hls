// BRAM-backed, time-multiplexed d=3 phi-decoder core.
//
// This is the memory-backed counterpart to phi_sequential_core.x. One shared
// controller operates on 18 data, syndrome, and phi state tuples stored as ten
// 32-bit words per spatial index. The public RAM channels are rewritten by XLS
// codegen into a fixed-latency 1RW memory interface; the test-only RamModel
// preserves the same protocol in the DSLX interpreter.

const CELL_COUNT = u5:18;
const PLANE_COUNT = u5:9;
const CUTOFF_STEP = u32:16;
const NOISE_RATE = u32:0x80000000;
const SEED_STRIDE = u32:0x9e3779b9;

const NORTH = u4:1;
const EAST = u4:2;
const WEST = u4:4;
const SOUTH = u4:8;

const DATA_RNG = u4:0;
const DATA_META = u4:1;
const SYNDROME_RNG = u4:2;
const SYNDROME_META = u4:3;
const PHI_RNG = u4:4;
const PHI_META = u4:5;
const PHI0_A = u4:6;
const PHI1_A = u4:7;
const PHI0_B = u4:8;
const PHI1_B = u4:9;

pub struct Summary {
  step: u32,
  corrections: u16,
  x_corrections: u16,
  z_corrections: u16,
  measurement_bits: uN[18],
}

pub struct RamReq {
  addr: u8,
  data: u32,
  write_mask: (),
  read_mask: (),
  we: u1,
  re: u1,
}

pub struct RamResp { data: u32 }

enum Phase : u6 {
  BOOT = 0,
  DATA_READ_RNG = 1,
  DATA_READ_META = 2,
  DATA_WRITE_RNG = 3,
  DATA_WRITE_META = 4,
  SYNDROME_READ_RNG = 5,
  SYNDROME_READ_META = 6,
  SYNDROME_READ_DATA = 7,
  SYNDROME_READ_PHI_META = 8,
  SYNDROME_WRITE_RNG = 9,
  SYNDROME_WRITE_META = 10,
  SYNDROME_WRITE_PHI_META = 11,
  DIFF_READ_CENTER0 = 12,
  DIFF_READ_CENTER1 = 13,
  DIFF_READ_NEIGHBOR = 14,
  DIFF_READ_META = 15,
  DIVIDE_0 = 16,
  DIVIDE_1 = 17,
  DIFF_WRITE_0 = 18,
  DIFF_WRITE_1 = 19,
  COMPARE_READ_RNG = 20,
  COMPARE_READ_META = 21,
  COMPARE_READ_NEIGHBOR = 22,
  COMPARE_WRITE_RNG = 23,
  COMPARE_WRITE_META = 24,
  APPLY_READ_META = 25,
  APPLY_READ_NEIGHBOR = 26,
  APPLY_WRITE_META = 27,
  APPLY_READ_DATA_META = 28,
  APPLY_WRITE_DATA_META = 29,
  MEASURE_READ = 30,
  DONE = 31,
  BOOT_SEED = 32,
}

struct State {
  phase: Phase,
  step: u32,
  index: u5,
  subindex: u4,
  diffusion_round: u1,

  seed_cursor: u32,

  data_rng: u32,
  data_occurred: u1,
  data_meta: u3,
  syndrome_rng: u32,
  syndrome_previous: u1,
  syndrome_measurement: u1,
  syndrome_parity: u1,
  phi_rng: u32,
  phi_anyon: u1,
  phi_move: u4,
  phi0: s32,
  phi1: s32,
  neighbor_sum0: sN[35],
  neighbor_sum1: sN[35],
  compare_best: s32,
  compare_direction: u4,
  compare_ties: u3,
  incoming_move_parity: u1,

  pending_phi1_numerator: sN[37],
  pending_new_phi0: s32,
  pending_new_phi1: s32,
  div_dividend: uN[38],
  div_quotient: uN[38],
  div_remainder: u6,
  div_divisor: u6,
  div_bit: u6,
  div_negative: u1,

  anyon_seen: u1,
  corrections: u16,
  x_corrections: u16,
  z_corrections: u16,
  measurement_bits: uN[18],
}

fn xorshift32(value: u32) -> u32 {
  let first = value ^ value << u32:13;
  let second = first ^ first >> u32:17;
  second ^ second << u32:5
}

fn ram_address(index: u5, slot: u4) -> u8 {
  ((index as u8) << u32:3) + ((index as u8) << u32:1) + slot as u8
}

fn read_request(index: u5, slot: u4) -> RamReq {
  RamReq {
    addr: ram_address(index, slot),
    data: u32:0,
    write_mask: (),
    read_mask: (),
    we: u1:0,
    re: u1:1,
  }
}

fn write_request(index: u5, slot: u4, data: u32) -> RamReq {
  RamReq {
    addr: ram_address(index, slot),
    data,
    write_mask: (),
    read_mask: (),
    we: u1:1,
    re: u1:0,
  }
}

fn data_pauli(meta: u3) -> u2 { meta[0:2] as u2 }
fn data_event(meta: u3) -> u1 { meta[2:3] as u1 }
fn pack_data_meta(pauli: u2, occurred: u1) -> u3 { occurred ++ pauli }

fn phi_anyon(meta: u5) -> u1 { meta[0:1] as u1 }
fn phi_move(meta: u5) -> u4 { meta[1:5] as u4 }
fn pack_phi_meta(anyon: u1, move: u4) -> u5 { move ++ anyon }

fn local_coordinate(index: u5) -> (u5, u5, u5, u1) {
  let z_plane = index >= PLANE_COUNT;
  let local_index = if z_plane { index - PLANE_COUNT } else { index };
  let x = local_index / u5:3;
  let y = local_index % u5:3;
  let xp = if x == u5:2 { u5:0 } else { x + u5:1 };
  (x, y, xp, z_plane)
}

fn physical_data_index(x: u5, y: u5) -> u5 { x * u5:6 + y }

fn syndrome_data_index(index: u5, arm: u2) -> u5 {
  let (x, y, xp, z_plane) = local_coordinate(index);
  let even_y = y * u5:2;
  if !z_plane {
    match arm {
      u2:0 => physical_data_index(
        x, if y == u5:0 { u5:5 } else { even_y - u5:1 }),
      u2:1 => physical_data_index(xp, even_y),
      u2:2 => physical_data_index(x, even_y),
      _ => physical_data_index(x, even_y + u5:1),
    }
  } else {
    match arm {
      u2:0 => physical_data_index(xp, even_y),
      u2:1 => physical_data_index(xp, even_y + u5:1),
      u2:2 => physical_data_index(x, even_y + u5:1),
      _ => physical_data_index(
        xp, if y == u5:2 { u5:0 } else { even_y + u5:2 }),
    }
  }
}

fn correction_data_index(index: u5, direction: u4) -> u5 {
  let arm = match direction {
    NORTH => u2:0,
    EAST => u2:1,
    WEST => u2:2,
    _ => u2:3,
  };
  syndrome_data_index(index, arm)
}

fn phi_neighbor(index: u5, direction: u4) -> u5 {
  let (x, y, _, z_plane) = local_coordinate(index);
  let nx = match direction {
    EAST => if x == u5:2 { u5:0 } else { x + u5:1 },
    WEST => if x == u5:0 { u5:2 } else { x - u5:1 },
    _ => x,
  };
  let ny = match direction {
    NORTH => if y == u5:0 { u5:2 } else { y - u5:1 },
    SOUTH => if y == u5:2 { u5:0 } else { y + u5:1 },
    _ => y,
  };
  (if z_plane { PLANE_COUNT } else { u5:0 }) + nx * u5:3 + ny
}

fn arm_direction(arm: u2) -> u4 {
  match arm { u2:0 => NORTH, u2:1 => EAST, u2:2 => WEST, _ => SOUTH }
}

fn opposite(direction: u4) -> u4 {
  match direction { NORTH => SOUTH, EAST => WEST, WEST => EAST, _ => NORTH }
}

fn source_phi0_slot(round: u1) -> u4 { if round { PHI0_B } else { PHI0_A } }
fn source_phi1_slot(round: u1) -> u4 { if round { PHI1_B } else { PHI1_A } }
fn target_phi0_slot(round: u1) -> u4 { if round { PHI0_A } else { PHI0_B } }
fn target_phi1_slot(round: u1) -> u4 { if round { PHI1_A } else { PHI1_B } }

fn magnitude(value: sN[37]) -> uN[37] {
  if value < sN[37]:0 { -value as uN[37] } else { value as uN[37] }
}

fn signed_quotient(negative: u1, value: uN[38]) -> sN[39] {
  let positive = value as sN[39];
  if negative { -positive } else { positive }
}

fn saturate_s32(value: sN[39]) -> s32 {
  if value > sN[39]:2147483647 {
    s32:2147483647
  } else if value < sN[39]:-2147483648 {
    s32:-2147483648
  } else {
    value as s32
  }
}

fn division_step(state: State) -> (uN[38], u6) {
  let next_bit = (state.div_dividend >> state.div_bit) as u1;
  let shifted = (state.div_remainder as u7) << u32:1 | next_bit as u7;
  let takes = shifted >= state.div_divisor as u7;
  let quotient = state.div_quotient |
    if takes { uN[38]:1 << state.div_bit } else { uN[38]:0 };
  let remainder = if takes {
    (shifted - state.div_divisor as u7) as u6
  } else {
    shifted as u6
  };
  (quotient, remainder)
}

fn update_best(
    best: s32, direction: u4, ties: u3, candidate: s32,
    candidate_direction: u4) -> (s32, u4, u3) {
  if candidate > best {
    (candidate, candidate_direction, u3:1)
  } else if candidate == best {
    (best, direction, ties + u3:1)
  } else {
    (best, direction, ties)
  }
}

fn seed_target(position: u32) -> (u5, u4) {
  if position < u32:9 {
    let local_index = position as u5;
    let x = local_index / u5:3;
    let y = local_index % u5:3;
    (x * u5:6 + y * u5:2, DATA_RNG)
  } else if position < u32:18 {
    let local_index = (position - u32:9) as u5;
    let x = local_index / u5:3;
    let y = local_index % u5:3;
    (x * u5:6 + y * u5:2 + u5:1, DATA_RNG)
  } else if position < u32:36 {
    ((position - u32:18) as u5, SYNDROME_RNG)
  } else {
    ((position - u32:36) as u5, PHI_RNG)
  }
}

fn advance_index(state: State, loop_phase: Phase, done_phase: Phase) -> State {
  if state.index == CELL_COUNT - u5:1 {
    State { phase: done_phase, index: u5:0, ..state }
  } else {
    State {
      phase: loop_phase,
      index: state.index + u5:1,
      ..state
    }
  }
}

fn advance_apply(state: State) -> State {
  if state.index == CELL_COUNT - u5:1 {
    if state.step >= CUTOFF_STEP && !state.anyon_seen {
      State {
        phase: Phase::MEASURE_READ,
        index: u5:0,
        measurement_bits: uN[18]:0,
        ..state
      }
    } else {
      State {
        phase: Phase::DATA_READ_RNG,
        step: state.step + u32:1,
        index: u5:0,
        anyon_seen: u1:0,
        ..state
      }
    }
  } else {
    State {
      phase: Phase::APPLY_READ_META,
      index: state.index + u5:1,
      ..state
    }
  }
}

pub proc SequentialBramCore {
  ram_req_out: chan<RamReq> out;
  ram_resp_in: chan<RamResp> in;
  ram_wr_comp_in: chan<()> in;
  summary_out: chan<Summary> out;

  config(
      ram_req_out: chan<RamReq> out,
      ram_resp_in: chan<RamResp> in,
      ram_wr_comp_in: chan<()> in,
      summary_out: chan<Summary> out
  ) { (ram_req_out, ram_resp_in, ram_wr_comp_in, summary_out) }

  init {
    State {
      seed_cursor: SEED_STRIDE,
      ..zero!<State>()
    }
  }

  next(state: State) {
    match state.phase {
      Phase::BOOT => {
        let tok = send(
          join(), ram_req_out,
          write_request(state.index, state.subindex, u32:0));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        if state.subindex != PHI1_B {
          State { subindex: state.subindex + u4:1, ..state }
        } else if state.index == CELL_COUNT - u5:1 {
          State {
            phase: Phase::BOOT_SEED,
            step: u32:0,
            index: u5:0,
            subindex: u4:0,
            ..state
          }
        } else {
          State {
            index: state.index + u5:1,
            subindex: u4:0,
            ..state
          }
        }
      },
      Phase::BOOT_SEED => {
        let (target_index, target_slot) = seed_target(state.step);
        let tok = send(
          join(), ram_req_out,
          write_request(target_index, target_slot, state.seed_cursor));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        if state.step == u32:53 {
          State {
            phase: Phase::DATA_READ_RNG,
            step: u32:0,
            index: u5:0,
            ..state
          }
        } else {
          State {
            step: state.step + u32:1,
            seed_cursor: state.seed_cursor + SEED_STRIDE,
            ..state
          }
        }
      },
      Phase::DATA_READ_RNG => {
        let tok = send(join(), ram_req_out, read_request(state.index, DATA_RNG));
        let (_tok, response) = recv(tok, ram_resp_in);
        let quiet = state.step >= CUTOFF_STEP;
        let next_random = xorshift32(response.data);
        State {
          phase: Phase::DATA_READ_META,
          data_rng: if quiet { response.data } else { next_random },
          data_occurred: (!quiet && next_random < NOISE_RATE) as u1,
          ..state
        }
      },
      Phase::DATA_READ_META => {
        let tok = send(join(), ram_req_out, read_request(state.index, DATA_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        let occurred = state.data_occurred;
        let old_meta = response.data as u3;
        let pauli = data_pauli(old_meta) ^
          if occurred { u2:3 } else { u2:0 };
        State {
          phase: Phase::DATA_WRITE_RNG,
          data_meta: pack_data_meta(pauli, occurred),
          ..state
        }
      },
      Phase::DATA_WRITE_RNG => {
        let tok = send(
          join(), ram_req_out,
          write_request(state.index, DATA_RNG, state.data_rng));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        State { phase: Phase::DATA_WRITE_META, ..state }
      },
      Phase::DATA_WRITE_META => {
        let tok = send(
          join(), ram_req_out,
          write_request(state.index, DATA_META, state.data_meta as u32));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        advance_index(
          state, Phase::DATA_READ_RNG, Phase::SYNDROME_READ_RNG)
      },
      Phase::SYNDROME_READ_RNG => {
        let tok = send(
          join(), ram_req_out, read_request(state.index, SYNDROME_RNG));
        let (_tok, response) = recv(tok, ram_resp_in);
        let quiet = state.step >= CUTOFF_STEP;
        let next_random = xorshift32(response.data);
        State {
          phase: Phase::SYNDROME_READ_META,
          syndrome_rng: if quiet { response.data } else { next_random },
          syndrome_measurement: (!quiet && next_random < NOISE_RATE) as u1,
          syndrome_parity: u1:0,
          ..state
        }
      },
      Phase::SYNDROME_READ_META => {
        let tok = send(
          join(), ram_req_out, read_request(state.index, SYNDROME_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        State {
          phase: Phase::SYNDROME_READ_DATA,
          subindex: u4:0,
          syndrome_previous: response.data[0:1] as u1,
          ..state
        }
      },
      Phase::SYNDROME_READ_DATA => {
        let arm = state.subindex as u2;
        let data_index = syndrome_data_index(state.index, arm);
        let tok = send(join(), ram_req_out, read_request(data_index, DATA_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        let parity = state.syndrome_parity ^ data_event(response.data as u3);
        if state.subindex == u4:3 {
          State {
            phase: Phase::SYNDROME_READ_PHI_META,
            syndrome_parity: parity,
            ..state
          }
        } else {
          State {
            subindex: state.subindex + u4:1,
            syndrome_parity: parity,
            ..state
          }
        }
      },
      Phase::SYNDROME_READ_PHI_META => {
        let tok = send(join(), ram_req_out, read_request(state.index, PHI_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        let meta = response.data as u5;
        let detection = state.syndrome_parity ^ state.syndrome_measurement ^
          state.syndrome_previous;
        State {
          phase: Phase::SYNDROME_WRITE_RNG,
          syndrome_previous: state.syndrome_measurement,
          phi_anyon: phi_anyon(meta) ^ detection,
          phi_move: phi_move(meta),
          ..state
        }
      },
      Phase::SYNDROME_WRITE_RNG => {
        let tok = send(
          join(), ram_req_out,
          write_request(state.index, SYNDROME_RNG, state.syndrome_rng));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        State { phase: Phase::SYNDROME_WRITE_META, ..state }
      },
      Phase::SYNDROME_WRITE_META => {
        let tok = send(
          join(), ram_req_out,
          write_request(
            state.index, SYNDROME_META, state.syndrome_previous as u32));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        State { phase: Phase::SYNDROME_WRITE_PHI_META, ..state }
      },
      Phase::SYNDROME_WRITE_PHI_META => {
        let tok = send(
          join(), ram_req_out,
          write_request(
            state.index, PHI_META,
            pack_phi_meta(state.phi_anyon, state.phi_move) as u32));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        let next = advance_index(
          state, Phase::SYNDROME_READ_RNG, Phase::DIFF_READ_CENTER0);
        if state.index == CELL_COUNT - u5:1 {
          State { diffusion_round: u1:0, ..next }
        } else {
          next
        }
      },
      Phase::DIFF_READ_CENTER0 => {
        let tok = send(
          join(), ram_req_out,
          read_request(state.index, source_phi0_slot(state.diffusion_round)));
        let (_tok, response) = recv(tok, ram_resp_in);
        State {
          phase: Phase::DIFF_READ_CENTER1,
          phi0: response.data as s32,
          neighbor_sum0: sN[35]:0,
          neighbor_sum1: sN[35]:0,
          ..state
        }
      },
      Phase::DIFF_READ_CENTER1 => {
        let tok = send(
          join(), ram_req_out,
          read_request(state.index, source_phi1_slot(state.diffusion_round)));
        let (_tok, response) = recv(tok, ram_resp_in);
        State {
          phase: Phase::DIFF_READ_NEIGHBOR,
          subindex: u4:0,
          phi1: response.data as s32,
          ..state
        }
      },
      Phase::DIFF_READ_NEIGHBOR => {
        let arm = (state.subindex >> u32:1) as u2;
        let slot = if state.subindex[0:1] {
          source_phi1_slot(state.diffusion_round)
        } else {
          source_phi0_slot(state.diffusion_round)
        };
        let neighbor = phi_neighbor(state.index, arm_direction(arm));
        let tok = send(join(), ram_req_out, read_request(neighbor, slot));
        let (_tok, response) = recv(tok, ram_resp_in);
        let sum0 = if !state.subindex[0:1] {
          state.neighbor_sum0 + response.data as s32 as sN[35]
        } else {
          state.neighbor_sum0
        };
        let sum1 = if state.subindex[0:1] {
          state.neighbor_sum1 + response.data as s32 as sN[35]
        } else {
          state.neighbor_sum1
        };
        if state.subindex == u4:7 {
          State {
            phase: Phase::DIFF_READ_META,
            neighbor_sum0: sum0,
            neighbor_sum1: sum1,
            ..state
          }
        } else {
          State {
            subindex: state.subindex + u4:1,
            neighbor_sum0: sum0,
            neighbor_sum1: sum1,
            ..state
          }
        }
      },
      Phase::DIFF_READ_META => {
        let tok = send(join(), ram_req_out, read_request(state.index, PHI_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        let numerator0 = (state.phi0 as sN[37]) * sN[37]:18 +
          (state.phi1 as sN[37]) * sN[37]:2 +
          state.neighbor_sum0 as sN[37];
        let numerator1 = state.phi0 as sN[37] +
          (state.phi1 as sN[37]) * sN[37]:15 +
          state.neighbor_sum1 as sN[37];
        State {
          phase: Phase::DIVIDE_0,
          phi_anyon: phi_anyon(response.data as u5),
          pending_phi1_numerator: numerator1,
          div_dividend: magnitude(numerator0) as uN[38] + uN[38]:12,
          div_quotient: uN[38]:0,
          div_remainder: u6:0,
          div_divisor: u6:24,
          div_bit: u6:37,
          div_negative: numerator0 < sN[37]:0,
          ..state
        }
      },
      Phase::DIVIDE_0 => {
        let (quotient, remainder) = division_step(state);
        if state.div_bit == u6:0 {
          let charge = if state.phi_anyon { sN[39]:65536 } else { sN[39]:0 };
          State {
            phase: Phase::DIVIDE_1,
            pending_new_phi0: saturate_s32(
              signed_quotient(state.div_negative, quotient) + charge),
            div_dividend:
              magnitude(state.pending_phi1_numerator) as uN[38] + uN[38]:10,
            div_quotient: uN[38]:0,
            div_remainder: u6:0,
            div_divisor: u6:20,
            div_bit: u6:37,
            div_negative: state.pending_phi1_numerator < sN[37]:0,
            ..state
          }
        } else {
          State {
            div_quotient: quotient,
            div_remainder: remainder,
            div_bit: state.div_bit - u6:1,
            ..state
          }
        }
      },
      Phase::DIVIDE_1 => {
        let (quotient, remainder) = division_step(state);
        if state.div_bit == u6:0 {
          State {
            phase: Phase::DIFF_WRITE_0,
            pending_new_phi1:
              saturate_s32(signed_quotient(state.div_negative, quotient)),
            ..state
          }
        } else {
          State {
            div_quotient: quotient,
            div_remainder: remainder,
            div_bit: state.div_bit - u6:1,
            ..state
          }
        }
      },
      Phase::DIFF_WRITE_0 => {
        let tok = send(
          join(), ram_req_out,
          write_request(
            state.index, target_phi0_slot(state.diffusion_round),
            state.pending_new_phi0 as u32));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        State { phase: Phase::DIFF_WRITE_1, ..state }
      },
      Phase::DIFF_WRITE_1 => {
        let tok = send(
          join(), ram_req_out,
          write_request(
            state.index, target_phi1_slot(state.diffusion_round),
            state.pending_new_phi1 as u32));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        if state.index == CELL_COUNT - u5:1 {
          if state.diffusion_round {
            State {
              phase: Phase::COMPARE_READ_RNG,
              index: u5:0,
              ..state
            }
          } else {
            State {
              phase: Phase::DIFF_READ_CENTER0,
              index: u5:0,
              diffusion_round: u1:1,
              ..state
            }
          }
        } else {
          State {
            phase: Phase::DIFF_READ_CENTER0,
            index: state.index + u5:1,
            ..state
          }
        }
      },
      Phase::COMPARE_READ_RNG => {
        let tok = send(join(), ram_req_out, read_request(state.index, PHI_RNG));
        let (_tok, response) = recv(tok, ram_resp_in);
        State {
          phase: Phase::COMPARE_READ_META,
          phi_rng: xorshift32(response.data),
          ..state
        }
      },
      Phase::COMPARE_READ_META => {
        let tok = send(join(), ram_req_out, read_request(state.index, PHI_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        State {
          phase: Phase::COMPARE_READ_NEIGHBOR,
          subindex: u4:0,
          phi_anyon: phi_anyon(response.data as u5),
          compare_best: s32:-2147483648,
          compare_direction: u4:0,
          compare_ties: u3:0,
          ..state
        }
      },
      Phase::COMPARE_READ_NEIGHBOR => {
        let arm = state.subindex as u2;
        let direction = arm_direction(arm);
        let neighbor = phi_neighbor(state.index, direction);
        let tok = send(join(), ram_req_out, read_request(neighbor, PHI0_A));
        let (_tok, response) = recv(tok, ram_resp_in);
        let (best, best_direction, ties) = update_best(
          state.compare_best,
          state.compare_direction,
          state.compare_ties,
          response.data as s32,
          direction);
        if state.subindex == u4:3 {
          let winner = if ties == u3:1 { best_direction } else { u4:0 };
          let selected = state.phi_anyon && winner != u4:0 &&
            state.phi_rng[u32:31+:u1];
          State {
            phase: Phase::COMPARE_WRITE_RNG,
            phi_move: if selected { winner } else { u4:0 },
            compare_best: best,
            compare_direction: best_direction,
            compare_ties: ties,
            ..state
          }
        } else {
          State {
            subindex: state.subindex + u4:1,
            compare_best: best,
            compare_direction: best_direction,
            compare_ties: ties,
            ..state
          }
        }
      },
      Phase::COMPARE_WRITE_RNG => {
        let tok = send(
          join(), ram_req_out,
          write_request(state.index, PHI_RNG, state.phi_rng));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        State { phase: Phase::COMPARE_WRITE_META, ..state }
      },
      Phase::COMPARE_WRITE_META => {
        let tok = send(
          join(), ram_req_out,
          write_request(
            state.index, PHI_META,
            pack_phi_meta(state.phi_anyon, state.phi_move) as u32));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        advance_index(
          state, Phase::COMPARE_READ_RNG, Phase::APPLY_READ_META)
      },
      Phase::APPLY_READ_META => {
        let tok = send(join(), ram_req_out, read_request(state.index, PHI_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        let meta = response.data as u5;
        State {
          phase: Phase::APPLY_READ_NEIGHBOR,
          subindex: u4:0,
          phi_anyon: phi_anyon(meta),
          phi_move: phi_move(meta),
          incoming_move_parity: u1:0,
          ..state
        }
      },
      Phase::APPLY_READ_NEIGHBOR => {
        let arm = state.subindex as u2;
        let direction = arm_direction(arm);
        let neighbor = phi_neighbor(state.index, direction);
        let tok = send(join(), ram_req_out, read_request(neighbor, PHI_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        let incoming = phi_move(response.data as u5) == opposite(direction);
        let parity = state.incoming_move_parity ^ incoming;
        if state.subindex == u4:3 {
          let has_correction = state.phi_move != u4:0;
          let next_anyon = state.phi_anyon ^ has_correction ^ parity;
          State {
            phase: Phase::APPLY_WRITE_META,
            phi_anyon: next_anyon,
            incoming_move_parity: parity,
            anyon_seen: state.anyon_seen || next_anyon,
            corrections: state.corrections + has_correction as u16,
            x_corrections: state.x_corrections +
              (has_correction && state.index < PLANE_COUNT) as u16,
            z_corrections: state.z_corrections +
              (has_correction && state.index >= PLANE_COUNT) as u16,
            ..state
          }
        } else {
          State {
            subindex: state.subindex + u4:1,
            incoming_move_parity: parity,
            ..state
          }
        }
      },
      Phase::APPLY_WRITE_META => {
        let tok = send(
          join(), ram_req_out,
          write_request(
            state.index, PHI_META,
            pack_phi_meta(state.phi_anyon, state.phi_move) as u32));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        if state.phi_move != u4:0 {
          State { phase: Phase::APPLY_READ_DATA_META, ..state }
        } else {
          advance_apply(state)
        }
      },
      Phase::APPLY_READ_DATA_META => {
        let data_index = correction_data_index(state.index, state.phi_move);
        let tok = send(join(), ram_req_out, read_request(data_index, DATA_META));
        let (_tok, response) = recv(tok, ram_resp_in);
        let meta = response.data as u3;
        let correction = if state.index < PLANE_COUNT { u2:1 } else { u2:2 };
        State {
          phase: Phase::APPLY_WRITE_DATA_META,
          data_meta: pack_data_meta(
            data_pauli(meta) ^ correction, data_event(meta)),
          ..state
        }
      },
      Phase::APPLY_WRITE_DATA_META => {
        let data_index = correction_data_index(state.index, state.phi_move);
        let tok = send(
          join(), ram_req_out,
          write_request(data_index, DATA_META, state.data_meta as u32));
        let (_tok, _) = recv(tok, ram_wr_comp_in);
        advance_apply(state)
      },
      Phase::MEASURE_READ => {
        let tok = send(join(), ram_req_out, read_request(state.index, DATA_META));
        let (tok, response) = recv(tok, ram_resp_in);
        let measurement_bit =
          ((data_pauli(response.data as u3) >> u2:1) & u2:1) as uN[18];
        let measurement =
          state.measurement_bits | measurement_bit << state.index;
        if state.index == CELL_COUNT - u5:1 {
          let summary = Summary {
            step: state.step,
            corrections: state.corrections,
            x_corrections: state.x_corrections,
            z_corrections: state.z_corrections,
            measurement_bits: measurement,
          };
          let _done = send(tok, summary_out, summary);
          State {
            phase: Phase::DONE,
            measurement_bits: measurement,
            ..state
          }
        } else {
          State {
            index: state.index + u5:1,
            measurement_bits: measurement,
            ..state
          }
        }
      },
      _ => state,
    }
  }
}

// Interpreter-only behavioral model. Codegen targets SequentialBramCore and
// rewrites its three RAM channels into one external fixed-latency port.
proc RamModel {
  req_in: chan<RamReq> in;
  resp_out: chan<RamResp> out;
  wr_comp_out: chan<()> out;

  config(
      req_in: chan<RamReq> in,
      resp_out: chan<RamResp> out,
      wr_comp_out: chan<()> out
  ) { (req_in, resp_out, wr_comp_out) }

  init { u32[256]:[u32:0, ...] }

  next(memory: u32[256]) {
    let (tok, request) = recv(join(), req_in);
    let _response_tok = send_if(
      tok, resp_out, request.re, RamResp { data: memory[request.addr] });
    let _write_tok = send_if(tok, wr_comp_out, request.we, ());
    if request.we {
      update(memory, request.addr, request.data)
    } else {
      memory
    }
  }
}

#[test_proc]
proc SequentialBramCoreTest {
  terminator: chan<bool> out;
  summary_in: chan<Summary> in;

  config(terminator: chan<bool> out) {
    let (req_p, req_c) = chan<RamReq>("ram_req");
    let (resp_p, resp_c) = chan<RamResp>("ram_resp");
    let (wr_comp_p, wr_comp_c) = chan<()>("ram_wr_comp");
    let (summary_p, summary_c) = chan<Summary>("summary");
    spawn RamModel(req_c, resp_p, wr_comp_p);
    spawn SequentialBramCore(req_p, resp_c, wr_comp_c, summary_p);
    (terminator, summary_c)
  }

  init { () }

  next(state: ()) {
    let (tok, summary) = recv(join(), summary_in);
    assert_eq(
      (
        summary.step,
        summary.corrections,
        summary.x_corrections,
        summary.z_corrections,
        summary.measurement_bits,
      ),
      (u32:21, u16:84, u16:45, u16:39, uN[18]:0x1320c));
    let _done = send(tok, terminator, true);
    state
  }
}
