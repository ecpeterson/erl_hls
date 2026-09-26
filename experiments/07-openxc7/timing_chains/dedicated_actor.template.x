// Experimental dedicated execution of the unchanged generated actor callbacks.
// Ordinary mailboxes keep FIFO order, phase-local postponement and their declared
// capacity. Aggregate collectors and the surrounding routing remain unchanged.
struct DedicatedState {
  machine: SharedMachine,
  frames: axis::Frame[MAILBOX_DEPTH],
  postponed: u1[MAILBOX_DEPTH],
  occupied: u32,
}

// One actor owns its state and mailbox; output acceptance commits its activation.
proc DedicatedActor<SLOT: u32> {
  input: chan<axis::Frame> in;
  output: chan<ScheduledEffects> out;
  @AGGREGATE_FIELD@

  // Bind one ordinary mailbox, one batch output and optional aggregate input.
  config(input: chan<axis::Frame> in, output: chan<ScheduledEffects> out
         @AGGREGATE_ARGUMENT@) {
    (input, output @AGGREGATE_VALUE@)
  }

  // Use the production initial state, before any configuration message arrives.
  init { DedicatedState { machine: initial_shared_machine(),
    ..zero!<DedicatedState>() } }

  // Select already stored messages; fresh arrivals become eligible next time.
  next(state: DedicatedState) {
    let failed = hls_failure::failed(state.machine.failure);
    let internal = @INTERNAL@;
    let entry = state.machine.enter_pending;
    @RECEIVE_AGGREGATE@
    let (mail_valid, mail_index) = unroll_for! (i, found):
        (u32, (u1, u32)) in u32:0..MAILBOX_DEPTH {
      let take = !found.0 && i < state.occupied && !state.postponed[i];
      (found.0 || take, if take { i } else { found.1 })
    }((false, u32:0));
    let received = mail_valid && !internal && !entry && !aggregate_valid;
    let active = !failed && (internal || entry || aggregate_valid || received);
    let result = shared_execute(SharedExecutorRequest {
      slot: SLOT, machine: bits_from_machine(state.machine),
      frame: state.frames[mail_index], received, egress_ready: true,
      @AGGREGATE_REQUEST@
      ..zero!<SharedExecutorRequest>()
    });
    let consume = active && received && result.dispatched &&
      result.directive == Directive::CONSUME;
    let postpone = active && received && result.dispatched &&
      result.directive == Directive::POSTPONE;
    let boundary = active && result.phase_boundary;
    let remaining = state.occupied - consume as u32;
    let (frames, postponed) = unroll_for! (i, acc):
        (u32, (axis::Frame[MAILBOX_DEPTH], u1[MAILBOX_DEPTH]))
        in u32:0..MAILBOX_DEPTH {
      let from = if consume && i >= mail_index { i + u32:1 } else { i };
      let live = i < remaining;
      (update(acc.0, i, if live { state.frames[from] } else { zero!<axis::Frame>() }),
       update(acc.1, i, live && !boundary &&
         (state.postponed[from] || (postpone && from == mail_index))))
    }((zero!<axis::Frame[MAILBOX_DEPTH]>(), zero!<u1[MAILBOX_DEPTH]>()));
    let (tok, frame, valid) = recv_if_non_blocking(
      aggregate_tok, input, !failed && state.occupied < MAILBOX_DEPTH,
      zero!<axis::Frame>());
    let _done = send_if(tok, output, active && result.effects_valid,
      ScheduledEffects { slot: SLOT, effects: result.effects });
    DedicatedState {
      machine: if active { machine_from_bits(result.machine) } else { state.machine },
      frames: if valid { update(frames, remaining, frame) } else { frames },
      postponed: if valid { update(postponed, remaining, false) } else { postponed },
      occupied: remaining + valid as u32,
    }
  }
}

// Deliver configuration before ordinary requests, preserving each input order.
proc DedicatedIngress {
  startup: chan<ScheduledRequest> in;
  input: chan<ScheduledRequest> in;
  outputs: chan<axis::Frame>[2] out;
  // The benchmark supplies exactly one startup frame per actor.
  config(startup: chan<ScheduledRequest> in, input: chan<ScheduledRequest> in,
         outputs: chan<axis::Frame>[2] out) { (startup, input, outputs) }
  // Count the two configuration frames before admitting runtime messages.
  init { u32:0 }
  // Demultiplex by the unchanged local actor address.
  next(count: u32) {
    let boot = count < u32:2;
    let (t0, first) = recv_if(join(), startup, boot, zero!<ScheduledRequest>());
    let (t1, ordinary) = recv_if(t0, input, !boot, zero!<ScheduledRequest>());
    let request = if boot { first } else { ordinary };
    let _done = unroll_for! (i, tok): (u32, token) in u32:0..u32:2 {
      send_if(tok, outputs[i], request.slot == i, request.frame)
    }(t1);
    count + boot as u32
  }
}

// Drain the router's old group credit independently of output backpressure.
proc DedicatedCreditSink {
  input: chan<ScheduledRequest> in;
  // These credits acknowledge batches, not mailbox messages.
  config(input: chan<ScheduledRequest> in) { (input,) }
  // No credit state is needed: bounded per-actor output channels own capacity.
  init { () }
  // Consume each acknowledgement exactly once.
  next(state: ()) { let (_, _) = recv(join(), input); state }
}

// Merge whole batches fairly, preserving each actor's effect order.
proc DedicatedEgress {
  inputs: chan<ScheduledEffects>[2] in;
  output: chan<ScheduledEffects> out;
  // Keep the existing group's router and global effect-window interface.
  config(inputs: chan<ScheduledEffects>[2] in, output: chan<ScheduledEffects> out) {
    (inputs, output)
  }
  // Poll actor zero first, then alternate even when an input is empty.
  init { u32:0 }
  // Receive at most one complete batch; a stalled send retains that batch.
  next(cursor: u32) {
    let (t0, a, av) = recv_if_non_blocking(join(), inputs[u32:0],
      cursor == u32:0, zero!<ScheduledEffects>());
    let (t1, b, bv) = recv_if_non_blocking(t0, inputs[u32:1],
      cursor == u32:1, zero!<ScheduledEffects>());
    let valid = av || bv;
    let value = if av { a } else { b };
    let _done = send_if(t1, output, valid, value);
    u32:1 - cursor
  }
}

@AGGREGATE_DEMUX@

// Two dedicated actors substitute for one two-actor SharedService benchmark group.
pub proc DedicatedGroup {
  // All non-memory channels retain their original types and meaning.
  config(requests: chan<ScheduledRequest>[2] in,
         startup: chan<ScheduledRequest> in,
         output: chan<ScheduledEffects> out @AGGREGATE_ARGUMENT@) {
    let (mail_p, mail_c) = chan<axis::Frame, u32:1>[2]("dedicated_mail");
    let (effect_p, effect_c) = chan<ScheduledEffects, u32:1>[2]("dedicated_effect");
    @AGGREGATE_CHANNELS@
    spawn DedicatedIngress(startup, requests[u32:0], mail_p);
    spawn DedicatedCreditSink(requests[u32:1]);
    spawn DedicatedEgress(effect_c, output);
    spawn DedicatedActor<u32:0>(mail_c[u32:0], effect_p[u32:0] @AGGREGATE_ZERO@);
    spawn DedicatedActor<u32:1>(mail_c[u32:1], effect_p[u32:1] @AGGREGATE_ONE@);
    ()
  }
  // Structural grouping owns no scheduler state.
  init { () }
  // All work belongs to the child actors and channel adapters.
  next(state: ()) { state }
}
