// Handwritten DSLX counterpart to the lane in phi_relax_bank.sv.
//
// This deliberately bypasses Erlang lowering and actor/mailbox machinery. It
// exists only to attribute the cost of XLS code generation for the same
// 76-cycle pair of restoring divisions used by the raw sequential baseline.

pub struct Command {
  anyon: u1,
  center0: s32,
  center1: s32,
  north0: s32,
  east0: s32,
  west0: s32,
  south0: s32,
  north1: s32,
  east1: s32,
  west1: s32,
  south1: s32,
}

pub struct Result {
  phi0: s32,
  phi1: s32,
}

enum Phase : u2 {
  IDLE = 0,
  DIVIDE_0 = 1,
  DIVIDE_1 = 2,
}

struct State {
  phase: Phase,
  anyon: u1,
  numerator1: sN[37],
  result0: s32,
  dividend: uN[38],
  quotient: uN[38],
  remainder: u6,
  divisor: u6,
  bit_index: u6,
  negative: u1,
}

fn center_numerator(command: Command) -> sN[37] {
  (command.center0 as sN[37]) * sN[37]:18 +
    (command.center1 as sN[37]) * sN[37]:2 +
    command.north0 as sN[37] + command.east0 as sN[37] +
    command.west0 as sN[37] + command.south0 as sN[37]
}

fn bulk_numerator(command: Command) -> sN[37] {
  command.center0 as sN[37] +
    (command.center1 as sN[37]) * sN[37]:15 +
    command.north1 as sN[37] + command.east1 as sN[37] +
    command.west1 as sN[37] + command.south1 as sN[37]
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
  let next_bit = (state.dividend >> state.bit_index) as u1;
  let shifted = (state.remainder as u7) << u32:1 | next_bit as u7;
  let takes = shifted >= state.divisor as u7;
  let quotient = state.quotient |
    if takes { uN[38]:1 << state.bit_index } else { uN[38]:0 };
  let remainder = if takes {
    (shifted - state.divisor as u7) as u6
  } else {
    shifted as u6
  };
  (quotient, remainder)
}

pub proc RelaxLane {
  command_in: chan<Command> in;
  result_out: chan<Result> out;

  config(command_in: chan<Command> in, result_out: chan<Result> out) {
    (command_in, result_out)
  }

  init { zero!<State>() }

  next(state: State) {
    match state.phase {
      Phase::IDLE => {
        let (_tok, command) = recv(join(), command_in);
        let numerator0 = center_numerator(command);
        let numerator1 = bulk_numerator(command);
        State {
          phase: Phase::DIVIDE_0,
          anyon: command.anyon,
          numerator1,
          dividend: magnitude(numerator0) as uN[38] + uN[38]:12,
          divisor: u6:24,
          bit_index: u6:37,
          negative: numerator0 < sN[37]:0,
          ..zero!<State>()
        }
      },
      Phase::DIVIDE_0 => {
        let (quotient, remainder) = division_step(state);
        if state.bit_index == u6:0 {
          let charge = if state.anyon { sN[39]:65536 } else { sN[39]:0 };
          State {
            phase: Phase::DIVIDE_1,
            numerator1: state.numerator1,
            result0: saturate_s32(
              signed_quotient(state.negative, quotient) + charge),
            dividend:
              magnitude(state.numerator1) as uN[38] + uN[38]:10,
            divisor: u6:20,
            bit_index: u6:37,
            negative: state.numerator1 < sN[37]:0,
            ..zero!<State>()
          }
        } else {
          State {
            quotient,
            remainder,
            bit_index: state.bit_index - u6:1,
            ..state
          }
        }
      },
      Phase::DIVIDE_1 => {
        let (quotient, remainder) = division_step(state);
        if state.bit_index == u6:0 {
          let result = Result {
            phi0: state.result0,
            phi1: saturate_s32(signed_quotient(state.negative, quotient)),
          };
          send(join(), result_out, result);
          zero!<State>()
        } else {
          State {
            quotient,
            remainder,
            bit_index: state.bit_index - u6:1,
            ..state
          }
        }
      },
      _ => zero!<State>(),
    }
  }
}

#[test_proc]
proc RelaxLaneTest {
  terminator: chan<bool> out;
  command_out: chan<Command> out;
  result_in: chan<Result> in;

  config(terminator: chan<bool> out) {
    let (command_p, command_c) = chan<Command, u32:1>("command");
    let (result_p, result_c) = chan<Result, u32:1>("result");
    spawn RelaxLane(command_c, result_p);
    (terminator, command_p, result_c)
  }

  init { () }

  next(state: ()) {
    let positive = Command {
      center0: s32:65536,
      center1: s32:32768,
      north0: s32:16384,
      east0: s32:16384,
      west0: s32:16384,
      south0: s32:16384,
      north1: s32:8192,
      east1: s32:8192,
      west1: s32:8192,
      south1: s32:8192,
      ..zero!<Command>()
    };
    let positive_sent = send(join(), command_out, positive);
    let (positive_tok, positive_actual) = recv(positive_sent, result_in);
    assert_eq(
      positive_actual,
      Result { phi0: s32:54613, phi1: s32:29491 });
    let negative = Command {
      anyon: u1:1,
      center0: s32:-65536,
      center1: s32:-32768,
      north0: s32:-16384,
      east0: s32:-16384,
      west0: s32:-16384,
      south0: s32:-16384,
      north1: s32:-8192,
      east1: s32:-8192,
      west1: s32:-8192,
      south1: s32:-8192,
    };
    let negative_sent = send(positive_tok, command_out, negative);
    let (negative_tok, negative_actual) = recv(negative_sent, result_in);
    assert_eq(
      negative_actual,
      Result { phi0: s32:10923, phi1: s32:-29491 });
    let _done = send(negative_tok, terminator, true);
    state
  }
}
