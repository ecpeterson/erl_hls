import axis;
import hls_bits;
import domain_controller;
import domain_codes;

// Pad the serialized physical stream before widening it to the frame capacity.
fn command_frame(command: domain_controller::Domaininput) -> axis::Frame {
  axis::pack(domain_controller::Tag::DOMAIN_INPUT as u8,
    hls_bits::frame_payload(domain_controller::bits_from_domaininput(command)))
}

// Invoke the actual generated source callback, not a handwritten transition model.
fn step(state: domain_controller::Domainstate,
        command: domain_controller::Domaininput) -> domain_controller::ServiceResult {
  domain_controller::service_step(domain_controller::ServiceState {
      data: domain_controller::Controllerstate { lifecycle: state }, failure: u32:0 },
    command_frame(command))
}

// Every field bit reaches the source adapter unchanged, including unused enum
// codes and nonzero partial-byte tails; transition properties cannot hide loss.
pub fn command_frame_roundtrip(command: domain_controller::Domaininput) -> bool {
  domain_controller::domaininput_from_bits(command_frame(command).payload) == command
}

// All finite command/state bits, including unreachable states: admission requires
// a ready, nonzero incarnation in the same committed state as the response.
pub fn admission_consistent(state: domain_controller::Domainstate,
                            command: domain_controller::Domaininput) -> bool {
  let result = step(state, command);
  let reply = domain_controller::domainoutput_from_bits(result.response.payload);
  !reply.admit || (result.state.data.lifecycle.phase == domain_codes::PHASE_READY && result.state.data.lifecycle.current != u64:0)
}

// A mismatched expected incarnation cannot mutate a requested incarnation.
pub fn stale_request_preserves_state(state: domain_controller::Domainstate,
                                    command: domain_controller::Domaininput) -> bool {
  let result = step(state, command);
  let request = command.op == domain_codes::OPERATION_ACTIVATE || command.op == domain_codes::OPERATION_REPLACE || command.op == domain_codes::OPERATION_STOP;
  !request || command.expected == state.current || result.state.data.lifecycle == state
}

// Unused enum bit patterns still reach ordinary wildcard/validation rejection;
// they cannot acquire a meaning by truncation or mutate lifecycle state.
pub fn invalid_control_preserves_state(state: domain_controller::Domainstate,
                                      command: domain_controller::Domaininput) -> bool {
  let result = step(state, command);
  let reply = domain_controller::domainoutput_from_bits(result.response.payload);
  let invalid_operation = (command.op as u32) >= domain_codes::OPERATION_COUNT ||
    command.op == domain_codes::OPERATION_REJECT;
  let invalid_fault = (command.fault as u32) >= domain_codes::FAULT_COUNT &&
    (command.op == domain_codes::OPERATION_FAULT || command.op == domain_codes::OPERATION_ABORT);
  (!(invalid_operation || invalid_fault) || result.state.data.lifecycle == state) &&
    (!invalid_operation || reply.status == domain_codes::STATUS_INVALID)
}

// Every valid first fault for the ready incarnation must close admission and
// retain its cause. This includes nonzero bits at the record's partial-byte tail.
pub fn current_fault_closes_ready(state: domain_controller::Domainstate,
                                 command: domain_controller::Domaininput) -> bool {
  let result = step(state, command);
  let reply = domain_controller::domainoutput_from_bits(result.response.payload);
  let applies = state.phase == domain_codes::PHASE_READY && state.current != u64:0 &&
    state.fault == domain_codes::FAULT_NONE && command.op == domain_codes::OPERATION_FAULT &&
    command.expected == state.current && command.fault != domain_codes::FAULT_NONE &&
    (command.fault as u32) < domain_codes::FAULT_COUNT;
  !applies || (result.state.failure == u32:0 && !reply.admit &&
    reply.status == domain_codes::STATUS_FAILURE &&
    result.state.data.lifecycle.phase == domain_codes::PHASE_FAILED &&
    result.state.data.lifecycle.fault == command.fault)
}

// Readiness can first appear only at the exactly correlated initialization completion.
pub fn readiness_requires_completion(state: domain_controller::Domainstate,
                                     command: domain_controller::Domaininput) -> bool {
  let next = step(state, command).state.data.lifecycle;
  next.phase != domain_codes::PHASE_READY || state.phase == domain_codes::PHASE_READY ||
    (state.phase == domain_codes::PHASE_INITIALIZING && command.op == domain_codes::OPERATION_INITIALIZED && state.transition != u64:0 &&
     command.expected == state.previous && command.target == state.target &&
     command.transition == state.transition)
}

// Rejecting control: admitting every nonzero incarnation would violate readiness.
pub fn incorrect_nonzero_admission(state: domain_controller::Domainstate,
                                  command: domain_controller::Domaininput) -> bool {
  let result = step(state, command);
  let reply = domain_controller::domainoutput_from_bits(result.response.payload);
  reply.admit == (result.state.data.lifecycle.current != u64:0)
}

// Eight arbitrary management inputs from cold start. Completion indications are
// unrestricted inputs: these checks establish correlation and ordering, not that
// a physical backend truthfully fenced/reset/initialized. No clock stall or reset
// is inserted during the bound; incarnation targets retain their full 64-bit width.
pub fn eight_step_history(inputs: domain_controller::Domaininput[8]) -> bool {
  let (_, valid) = for (i, (state, valid)):
      (u32, (domain_controller::Domainstate, bool)) in u32:0..u32:8 {
    let result = step(state, inputs[i]);
    let next = result.state.data.lifecycle;
    let reply = domain_controller::domainoutput_from_bits(result.response.payload);
    (next, valid && result.state.failure == u32:0 &&
      next.current >= state.current && next.target >= state.target &&
      next.current <= next.target &&
      (!reply.admit || (next.phase == domain_codes::PHASE_READY && next.current != u64:0)) &&
      (next.phase != domain_codes::PHASE_READY || state.phase == domain_codes::PHASE_READY ||
        (state.phase == domain_codes::PHASE_INITIALIZING && inputs[i].op == domain_codes::OPERATION_INITIALIZED && state.transition != u64:0 &&
         inputs[i].expected == state.previous && inputs[i].target == state.target &&
         inputs[i].transition == state.transition)))
  }((zero!<domain_controller::Domainstate>(), true));
  valid
}

// Stopped state cannot admit work or start initialization without an explicit fresh replacement.
pub fn stopped_requires_explicit_replacement(state: domain_controller::Domainstate,
                                            command: domain_controller::Domaininput) -> bool {
  let next = step(state, command).state.data.lifecycle;
  state.phase != domain_codes::PHASE_STOPPED || command.op == domain_codes::OPERATION_REPLACE ||
    (next.phase == domain_codes::PHASE_STOPPED && next.current == state.current)
}
