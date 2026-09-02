// Handwritten, time-multiplexed d=3 phi-decoder core.
//
// This is the XLS-side counterpart to the raw SystemVerilog lower bound. It
// deliberately does not preserve the actor topology: one proc scans all data,
// syndrome, and phi state, and one restoring divider services every field
// update. Decoder corrections are applied directly to the data Pauli frame.
// The routed host boundary is excluded so this artifact isolates scheduling
// and state representation from the separately measured gateway cost.

const DATA_COUNT = u32:18;
const PHI_COUNT = u32:18;
const PLANE_COUNT = u5:9;
const CUTOFF_STEP = u32:16;
const NOISE_RATE = u32:0x80000000;

const NORTH = u4:1;
const EAST = u4:2;
const WEST = u4:4;
const SOUTH = u4:8;

const DATA_SEEDS = u32[DATA_COUNT]:[
  u32:0x9E3779B9, u32:0x2E2AC13A,
  u32:0x3C6EF372, u32:0xCC623AF3,
  u32:0xDAA66D2B, u32:0x6A99B4AC,
  u32:0x78DDE6E4, u32:0x08D12E65,
  u32:0x1715609D, u32:0xA708A81E,
  u32:0xB54CDA56, u32:0x454021D7,
  u32:0x5384540F, u32:0xE3779B90,
  u32:0xF1BBCDC8, u32:0x81AF1549,
  u32:0x8FF34781, u32:0x1FE68F02,
];

const SYNDROME_SEEDS = u32[PHI_COUNT]:[
  u32:0xBE1E08BB, u32:0x5C558274, u32:0xFA8CFC2D,
  u32:0x98C475E6, u32:0x36FBEF9F, u32:0xD5336958,
  u32:0x736AE311, u32:0x11A25CCA, u32:0xAFD9D683,
  u32:0x4E11503C, u32:0xEC48C9F5, u32:0x8A8043AE,
  u32:0x28B7BD67, u32:0xC6EF3720, u32:0x6526B0D9,
  u32:0x035E2A92, u32:0xA195A44B, u32:0x3FCD1E04,
];

const PHI_SEEDS = u32[PHI_COUNT]:[
  u32:0xDE0497BD, u32:0x7C3C1176, u32:0x1A738B2F,
  u32:0xB8AB04E8, u32:0x56E27EA1, u32:0xF519F85A,
  u32:0x93517213, u32:0x3188EBCC, u32:0xCFC06585,
  u32:0x6DF7DF3E, u32:0x0C2F58F7, u32:0xAA66D2B0,
  u32:0x489E4C69, u32:0xE6D5C622, u32:0x850D3FDB,
  u32:0x2344B994, u32:0xC17C334D, u32:0x5FB3AD06,
];

pub struct Summary {
  step: u32,
  corrections: u16,
  x_corrections: u16,
  z_corrections: u16,
  measurement_bits: uN[18],
}

enum Phase : u4 {
  DATA = 0,
  SYNDROME = 1,
  DIFF_PREP = 2,
  DIVIDE_0 = 3,
  DIVIDE_1 = 4,
  COMPARE = 5,
  APPLY = 6,
  DONE = 7,
}

struct State {
  phase: Phase,
  step: u32,
  index: u5,
  diffusion_round: u1,

  data_rng: u32[DATA_COUNT],
  data_pauli: u2[DATA_COUNT],
  data_event: u1[DATA_COUNT],
  syndrome_rng: u32[PHI_COUNT],
  syndrome_previous: u1[PHI_COUNT],
  phi_rng: u32[PHI_COUNT],
  anyon: u1[PHI_COUNT],
  phi0_a: s32[PHI_COUNT],
  phi1_a: s32[PHI_COUNT],
  phi0_b: s32[PHI_COUNT],
  phi1_b: s32[PHI_COUNT],
  move_direction: u4[PHI_COUNT],

  pending_phi1_numerator: sN[37],
  pending_new_phi0: s32,
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
}

fn xorshift32(value: u32) -> u32 {
  let first = value ^ value << u32:13;
  let second = first ^ first >> u32:17;
  second ^ second << u32:5
}

fn local_coordinate(index: u5) -> (u5, u5, u5, u1) {
  let z_plane = index >= PLANE_COUNT;
  let local = if z_plane { index - PLANE_COUNT } else { index };
  let x = local / u5:3;
  let y = local % u5:3;
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

fn center_numerator(
    phi0: s32[PHI_COUNT], phi1: s32[PHI_COUNT], index: u5) -> sN[37] {
  let north = phi_neighbor(index, NORTH);
  let east = phi_neighbor(index, EAST);
  let west = phi_neighbor(index, WEST);
  let south = phi_neighbor(index, SOUTH);
  (phi0[index] as sN[37]) * sN[37]:18 +
    (phi1[index] as sN[37]) * sN[37]:2 +
    phi0[north] as sN[37] + phi0[east] as sN[37] +
    phi0[west] as sN[37] + phi0[south] as sN[37]
}

fn bulk_numerator(
    phi0: s32[PHI_COUNT], phi1: s32[PHI_COUNT], index: u5) -> sN[37] {
  let north = phi_neighbor(index, NORTH);
  let east = phi_neighbor(index, EAST);
  let west = phi_neighbor(index, WEST);
  let south = phi_neighbor(index, SOUTH);
  phi0[index] as sN[37] +
    (phi1[index] as sN[37]) * sN[37]:15 +
    phi1[north] as sN[37] + phi1[east] as sN[37] +
    phi1[west] as sN[37] + phi1[south] as sN[37]
}

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
  let shifted =
    (state.div_remainder as u7) << u32:1 | next_bit as u7;
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

fn winner_direction(phi0: s32[PHI_COUNT], index: u5) -> u4 {
  let north = phi0[phi_neighbor(index, NORTH)];
  let east = phi0[phi_neighbor(index, EAST)];
  let west = phi0[phi_neighbor(index, WEST)];
  let south = phi0[phi_neighbor(index, SOUTH)];
  let best0 = if north > east { north } else { east };
  let best1 = if west > south { west } else { south };
  let best = if best0 > best1 { best0 } else { best1 };
  let ties = (north == best) as u3 + (east == best) as u3 +
    (west == best) as u3 + (south == best) as u3;
  if ties != u3:1 {
    u4:0
  } else if north == best {
    NORTH
  } else if east == best {
    EAST
  } else if west == best {
    WEST
  } else {
    SOUTH
  }
}

fn incoming_move(moves: u4[PHI_COUNT], index: u5) -> u1 {
  (moves[phi_neighbor(index, NORTH)] == SOUTH) ^
    (moves[phi_neighbor(index, EAST)] == WEST) ^
    (moves[phi_neighbor(index, WEST)] == EAST) ^
    (moves[phi_neighbor(index, SOUTH)] == NORTH)
}

fn measurement_bits(paulis: u2[DATA_COUNT]) -> uN[18] {
  unroll_for! (index, mask): (u32, uN[18]) in u32:0..DATA_COUNT {
    mask | ((((paulis[index] >> u2:1) & u2:1) as uN[18]) << index)
  }(uN[18]:0)
}

pub proc SequentialCore {
  summary_out: chan<Summary> out;

  config(summary_out: chan<Summary> out) { (summary_out,) }

  init {
    State {
      data_rng: DATA_SEEDS,
      syndrome_rng: SYNDROME_SEEDS,
      phi_rng: PHI_SEEDS,
      ..zero!<State>()
    }
  }

  next(state: State) {
    match state.phase {
      Phase::DATA => {
        let quiet = state.step >= CUTOFF_STEP;
        let next_random = xorshift32(state.data_rng[state.index]);
        let event = !quiet && next_random < NOISE_RATE;
        let data_rng = if quiet {
          state.data_rng
        } else {
          update(state.data_rng, state.index, next_random)
        };
        let data_event = update(state.data_event, state.index, event);
        let data_pauli = if event {
          update(
            state.data_pauli,
            state.index,
            state.data_pauli[state.index] ^ u2:3)
        } else {
          state.data_pauli
        };
        if state.index == u5:17 {
          State {
            phase: Phase::SYNDROME,
            index: u5:0,
            data_rng,
            data_event,
            data_pauli,
            ..state
          }
        } else {
          State {
            index: state.index + u5:1,
            data_rng,
            data_event,
            data_pauli,
            ..state
          }
        }
      },
      Phase::SYNDROME => {
        let quiet = state.step >= CUTOFF_STEP;
        let parity =
          state.data_event[syndrome_data_index(state.index, u2:0)] ^
          state.data_event[syndrome_data_index(state.index, u2:1)] ^
          state.data_event[syndrome_data_index(state.index, u2:2)] ^
          state.data_event[syndrome_data_index(state.index, u2:3)];
        let next_random = xorshift32(state.syndrome_rng[state.index]);
        let measurement = !quiet && next_random < NOISE_RATE;
        let detection = parity ^ measurement ^
          state.syndrome_previous[state.index];
        let syndrome_rng = if quiet {
          state.syndrome_rng
        } else {
          update(state.syndrome_rng, state.index, next_random)
        };
        let syndrome_previous = update(
          state.syndrome_previous, state.index, measurement);
        let anyon = update(
          state.anyon,
          state.index,
          state.anyon[state.index] ^ detection);
        if state.index == u5:17 {
          State {
            phase: Phase::DIFF_PREP,
            index: u5:0,
            diffusion_round: u1:0,
            syndrome_rng,
            syndrome_previous,
            anyon,
            ..state
          }
        } else {
          State {
            index: state.index + u5:1,
            syndrome_rng,
            syndrome_previous,
            anyon,
            ..state
          }
        }
      },
      Phase::DIFF_PREP => {
        let phi0 = if state.diffusion_round { state.phi0_b } else { state.phi0_a };
        let phi1 = if state.diffusion_round { state.phi1_b } else { state.phi1_a };
        let numerator0 = center_numerator(phi0, phi1, state.index);
        let numerator1 = bulk_numerator(phi0, phi1, state.index);
        State {
          phase: Phase::DIVIDE_0,
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
          let charge = if state.anyon[state.index] {
            sN[39]:65536
          } else {
            sN[39]:0
          };
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
          let new_phi1 =
            saturate_s32(signed_quotient(state.div_negative, quotient));
          let phi0_a = if state.diffusion_round {
            update(state.phi0_a, state.index, state.pending_new_phi0)
          } else {
            state.phi0_a
          };
          let phi1_a = if state.diffusion_round {
            update(state.phi1_a, state.index, new_phi1)
          } else {
            state.phi1_a
          };
          let phi0_b = if state.diffusion_round {
            state.phi0_b
          } else {
            update(state.phi0_b, state.index, state.pending_new_phi0)
          };
          let phi1_b = if state.diffusion_round {
            state.phi1_b
          } else {
            update(state.phi1_b, state.index, new_phi1)
          };
          if state.index == u5:17 {
            if state.diffusion_round {
              State {
                phase: Phase::COMPARE,
                index: u5:0,
                phi0_a,
                phi1_a,
                phi0_b,
                phi1_b,
                ..state
              }
            } else {
              State {
                phase: Phase::DIFF_PREP,
                index: u5:0,
                diffusion_round: u1:1,
                phi0_a,
                phi1_a,
                phi0_b,
                phi1_b,
                ..state
              }
            }
          } else {
            State {
              phase: Phase::DIFF_PREP,
              index: state.index + u5:1,
              phi0_a,
              phi1_a,
              phi0_b,
              phi1_b,
              ..state
            }
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
      Phase::COMPARE => {
        let direction = winner_direction(state.phi0_a, state.index);
        let next_random = xorshift32(state.phi_rng[state.index]);
        let selected = state.anyon[state.index] && direction != u4:0 &&
          next_random[u32:31+:u1];
        let move_direction = update(
          state.move_direction,
          state.index,
          if selected { direction } else { u4:0 });
        let phi_rng = update(state.phi_rng, state.index, next_random);
        if state.index == u5:17 {
          State {
            phase: Phase::APPLY,
            index: u5:0,
            anyon_seen: u1:0,
            move_direction,
            phi_rng,
            ..state
          }
        } else {
          State {
            index: state.index + u5:1,
            move_direction,
            phi_rng,
            ..state
          }
        }
      },
      Phase::APPLY => {
        let move = state.move_direction[state.index];
        let next_anyon = state.anyon[state.index] ^ (move != u4:0) ^
          incoming_move(state.move_direction, state.index);
        let anyon = update(state.anyon, state.index, next_anyon);
        let has_correction = move != u4:0;
        let correction_index = correction_data_index(state.index, move);
        let correction_pauli =
          if state.index < PLANE_COUNT { u2:1 } else { u2:2 };
        let data_pauli = if has_correction {
          update(
            state.data_pauli,
            correction_index,
            state.data_pauli[correction_index] ^ correction_pauli)
        } else {
          state.data_pauli
        };
        let corrections = state.corrections + has_correction as u16;
        let x_corrections = state.x_corrections +
          (has_correction && state.index < PLANE_COUNT) as u16;
        let z_corrections = state.z_corrections +
          (has_correction && state.index >= PLANE_COUNT) as u16;
        if state.index == u5:17 {
          let quiescent = state.step >= CUTOFF_STEP &&
            !(state.anyon_seen || next_anyon);
          if quiescent {
            let summary = Summary {
              step: state.step,
              corrections,
              x_corrections,
              z_corrections,
              measurement_bits: measurement_bits(data_pauli),
            };
            let _done = send(join(), summary_out, summary);
            State {
              phase: Phase::DONE,
              index: u5:0,
              anyon,
              data_pauli,
              corrections,
              x_corrections,
              z_corrections,
              ..state
            }
          } else {
            State {
              phase: Phase::DATA,
              step: state.step + u32:1,
              index: u5:0,
              anyon_seen: u1:0,
              anyon,
              data_pauli,
              corrections,
              x_corrections,
              z_corrections,
              ..state
            }
          }
        } else {
          State {
            index: state.index + u5:1,
            anyon_seen: state.anyon_seen || next_anyon,
            anyon,
            data_pauli,
            corrections,
            x_corrections,
            z_corrections,
            ..state
          }
        }
      },
      _ => state,
    }
  }
}

#[test_proc]
proc SequentialCoreTest {
  terminator: chan<bool> out;
  summary_in: chan<Summary> in;

  config(terminator: chan<bool> out) {
    let (summary_p, summary_c) = chan<Summary, u32:1>("summary");
    spawn SequentialCore(summary_p);
    (terminator, summary_c)
  }

  init { () }

  next(state: ()) {
    let (tok, summary) = recv(join(), summary_in);
    assert_eq(summary.step, u32:21);
    assert_eq(summary.corrections, u16:84);
    assert_eq(summary.x_corrections, u16:45);
    assert_eq(summary.z_corrections, u16:39);
    assert_eq(summary.measurement_bits, uN[18]:0x1320c);
    let _done = send(tok, terminator, true);
    state
  }
}
