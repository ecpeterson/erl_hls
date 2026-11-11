import axis;
import hls_bits;
import supervisor_controller;
import supervisor_codes;

// Use the emitted service frame, including padding of the final partial byte.
fn command_frame(command: supervisor_controller::Supervisorinput) -> axis::Frame {
  axis::pack(supervisor_controller::Tag::SUPERVISOR_INPUT as u8,
    hls_bits::frame_payload(supervisor_controller::bits_from_supervisorinput(command)))
}

// Invoke the actual compiled Erlang transition; no policy is reimplemented here.
fn step(state: supervisor_controller::Supervisorstate,
        command: supervisor_controller::Supervisorinput) -> supervisor_controller::ServiceResult {
  supervisor_controller::service_step(supervisor_controller::ServiceState {
    data: supervisor_controller::Supervisorservice {supervisor: state}, failure: u32:0
  }, command_frame(command))
}

// Every defined command bit survives framing, including unused enum encodings.
pub fn command_frame_roundtrip(command: supervisor_controller::Supervisorinput) -> bool {
  supervisor_controller::supervisorinput_from_bits(command_frame(command).payload) == command
}

// Arbitrary finite states: a different supervisor incarnation cannot request stop.
pub fn stale_stop_preserves_state(state: supervisor_controller::Supervisorstate,
                                 epoch: u64,
                                 child: supervisor_controller::Supervisorchild) -> bool {
  let result = step(state, supervisor_controller::Supervisorinput {
    op: supervisor_codes::SUPERVISOR_OPERATION_STOP, epoch, child,
    ..zero!<supervisor_controller::Supervisorinput>()
  });
  let reply = supervisor_controller::supervisoroutput_from_bits(result.response.payload);
  epoch == state.epoch || (result.state.failure == u32:0 &&
    result.state.data.supervisor == state && reply.child == child && !reply.command_valid &&
    reply.status == supervisor_codes::SUPERVISOR_STATUS_STALE)
}

// An installed manager may observe its exact grant again; nothing is reallocated.
pub fn exact_start_replay_preserves_state(state: supervisor_controller::Supervisorstate,
                                        child: supervisor_controller::Supervisorchild) -> bool {
  let result = step(state, supervisor_controller::Supervisorinput {
    op: supervisor_codes::SUPERVISOR_OPERATION_START, epoch: state.epoch,
    first: state.first, last: state.last, children: state.children,
    intensity: state.intensity, period: state.period, child,
    ..zero!<supervisor_controller::Supervisorinput>()
  });
  let reply = supervisor_controller::supervisoroutput_from_bits(result.response.payload);
  state.phase == supervisor_codes::SUPERVISOR_PHASE_UNBOUND ||
    (result.state.failure == u32:0 && result.state.data.supervisor == state &&
     reply.child == child && !reply.command_valid &&
     reply.status == supervisor_codes::SUPERVISOR_STATUS_REPLAY)
}

// No finite control command reopens a terminal manager or commands another child.
pub fn terminal_emits_no_child_command(state: supervisor_controller::Supervisorstate,
                                      command: supervisor_controller::Supervisorinput) -> bool {
  let result = step(state, command);
  let reply = supervisor_controller::supervisoroutput_from_bits(result.response.payload);
  let terminal = state.phase == supervisor_codes::SUPERVISOR_PHASE_STOPPED ||
    state.phase == supervisor_codes::SUPERVISOR_PHASE_FAILED;
  !terminal || (result.state.failure == u32:0 && result.state.data.supervisor == state &&
    reply.child == command.child && !reply.command_valid)
}

// These are admission preconditions, not assumptions about the resulting state.
fn valid_grant(epoch: u64, first: u64, last: u64, children: u16,
               intensity: u8, period: u32, now: u64) -> bool {
  epoch != u64:0 && first != u64:0 && first <= last &&
    last < u64:0xffff_ffff_ffff_ffff && children != u16:0 &&
    intensity <= u8:16 && period != u32:0 && now < u64:0xffff_ffff_ffff_ffff
}

// Two composed transitions: valid grant from cold state, then the first fresh
// child observation. Initial startup spends exactly one ID and no restart slot.
pub fn initial_allocation_consumes_one(epoch: u64, first: u64, last: u64,
                                      children: u16, intensity: u8,
                                      period: u32, now: u64) -> bool {
  let installed = step(supervisor_controller::initial_service_state().data.supervisor,
    supervisor_controller::Supervisorinput {
      op: supervisor_codes::SUPERVISOR_OPERATION_START, epoch, first, last,
      children, intensity, period, now,
      ..zero!<supervisor_controller::Supervisorinput>()
    });
  let result = step(installed.state.data.supervisor, supervisor_controller::Supervisorinput {
    op: supervisor_codes::SUPERVISOR_OPERATION_INSPECT, now, slot: u16:0,
    child: supervisor_controller::Supervisorchild {
      phase: supervisor_codes::CHILD_PHASE_FRESH,
      ..zero!<supervisor_controller::Supervisorchild>()
    },
    observed: supervisor_controller::Domainstate {
      phase: supervisor_codes::PHASE_UNBOUND,
      ..zero!<supervisor_controller::Domainstate>()
    },
    ..zero!<supervisor_controller::Supervisorinput>()
  });
  let reply = supervisor_controller::supervisoroutput_from_bits(result.response.payload);
  let next = result.state.data.supervisor;
  !valid_grant(epoch, first, last, children, intensity, period, now) ||
    (installed.state.failure == u32:0 && result.state.failure == u32:0 &&
     reply.command_valid && reply.command.op == supervisor_codes::OPERATION_ACTIVATE &&
     reply.command.expected == u64:0 && reply.command.target == first &&
     reply.command.transition == first && next.next == first + u64:1 && next.count == u8:0 &&
     next.first == first && next.last == last &&
     reply.child.phase == supervisor_codes::CHILD_PHASE_STARTING && reply.child.target == first)
}

// A legal outstanding restart has already spent its ID and timestamp. The
// ordered observation still names the failed predecessor: retry the same tuple,
// preserving the cursor/window instead of allocating or charging another time.
pub fn pending_retry_preserves_allocation(previous: u64, target: u64,
                                         last: u64, now: u64) -> bool {
  let valid = previous != u64:0 && previous < target && target <= last &&
    last < u64:0xffff_ffff_ffff_ffff && now < u64:0xffff_ffff_ffff_ffff;
  let state = supervisor_controller::Supervisorstate {
    phase: supervisor_codes::SUPERVISOR_PHASE_RUNNING, epoch: u64:1,
    first: previous, last, next: target + u64:1, children: u16:1, started: u16:1,
    intensity: u8:2, period: u32:10, last_time: now, count: u8:1,
    times: u64[16]:[now, u64:0, ...],
    ..zero!<supervisor_controller::Supervisorstate>()
  };
  let child = supervisor_controller::Supervisorchild {
    phase: supervisor_codes::CHILD_PHASE_RESTARTING, expected: previous, target
  };
  let result = step(state, supervisor_controller::Supervisorinput {
    op: supervisor_codes::SUPERVISOR_OPERATION_INSPECT, now, child,
    observed: supervisor_controller::Domainstate {
      phase: supervisor_codes::PHASE_FAILED, current: previous, target: previous,
      transition: previous, fault: supervisor_codes::FAULT_ACTOR_FAILURE,
      ..zero!<supervisor_controller::Domainstate>()
    },
    ..zero!<supervisor_controller::Supervisorinput>()
  });
  let reply = supervisor_controller::supervisoroutput_from_bits(result.response.payload);
  !valid || (result.state.failure == u32:0 && result.state.data.supervisor == state &&
    reply.child == child && reply.command_valid &&
    reply.command.op == supervisor_codes::OPERATION_REPLACE &&
    reply.command.expected == previous && reply.command.target == target &&
    reply.command.transition == target)
}

// Deliberately wrong: accepting a valid grant does not mean its children started.
// The expected counterexample is a legal nonzero epoch from cold state.
pub fn incorrect_start_is_running(epoch: u64) -> bool {
  let result = step(supervisor_controller::initial_service_state().data.supervisor,
    supervisor_controller::Supervisorinput {
      op: supervisor_codes::SUPERVISOR_OPERATION_START, epoch,
      first: u64:1, last: u64:3, children: u16:2, intensity: u8:2, period: u32:1,
      ..zero!<supervisor_controller::Supervisorinput>()
    });
  epoch == u64:0 || result.state.data.supervisor.phase == supervisor_codes::SUPERVISOR_PHASE_RUNNING
}
