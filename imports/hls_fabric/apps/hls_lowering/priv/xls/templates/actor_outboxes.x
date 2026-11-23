// Instantiated with an actor module by xls_actor_outbox_dslx. The concrete
// ScheduledEffects/Egress types avoid DSLX's unsupported type parameters.

// Independently drain one reserved actor batch in source order. The producer
// must not send another batch until the credit returns; SLOT identifies it.
proc ActorOutboxDrain<SLOT: u32> {
  batches: chan<actor::ScheduledEffects> in;
  effects: chan<actor::Egress> out;
  credits: chan<actor::ScheduledRequest> out;
  // The effect consumer may stall; only this actor's outbox then waits.
  config(batches: chan<actor::ScheduledEffects> in,
      effects: chan<actor::Egress> out, credits: chan<actor::ScheduledRequest> out) {
    (batches, effects, credits)
  }
  // No batch or credit survives reset.
  init { (false, zero!<actor::ScheduledEffects>(), u8:0) }
  // Return credit after the last effect is accepted. Empty batches also retire.
  next(state: (u1, actor::ScheduledEffects, u8)) {
    let (active, saved, index) = state;
    let (tok, batch) = recv_if(join(), batches, !active, saved);
    let (effect, emit, last) = actor::scheduled_effect(batch, index);
    let emitted = send_if(tok, effects, emit, effect);
    let _credited = send_if(emitted, credits, last,
      actor::ScheduledRequest { slot: SLOT, credit: true,
        ..zero!<actor::ScheduledRequest>() });
    (!last, batch, if last { u8:0 } else { index + u8:1 })
  }
}

// Demultiplex only pre-reserved batches. With one outstanding batch per actor,
// every selected destination has capacity regardless of other actors' outputs.
proc ActorOutboxDispatch<COUNT: u32> {
  incoming: chan<actor::ScheduledEffects> in;
  outgoing: chan<actor::ScheduledEffects>[COUNT] out;
  // Each output must have one batch slot and an independent consumer.
  config(incoming: chan<actor::ScheduledEffects> in,
      outgoing: chan<actor::ScheduledEffects>[COUNT] out) { (incoming, outgoing) }
  // Routing carries no persistent state.
  init { () }
  // Slot identity is trusted scheduler metadata, bounded by COUNT.
  next(state: ()) {
    let (tok, batch) = recv(join(), incoming);
    let _sent = unroll_for! (slot, tok): (u32, token) in u32:0..COUNT {
      send_if(tok, outgoing[slot], batch.slot == slot, batch)
    }(tok);
    state
  }
}

// Pair with SharedService<..., PER_ACTOR_EGRESS=true>. Each actor owns one
// complete batch slot; no permission or credit is shared with another actor.
// Keep codegen outputs registered; effects/credits must have independent sinks.
proc ActorOutboxBank<COUNT: u32> {
  // Give this proc its own credit array; connect each endpoint to a dedicated
  // scheduler producer. Unused outputs cannot share an array with other writers.
  config(incoming: chan<actor::ScheduledEffects> in,
      effects: chan<actor::Egress>[COUNT] out,
      credits: chan<actor::ScheduledRequest>[COUNT] out) {
    let (batches_p, batches_c) = chan<actor::ScheduledEffects, u32:1>[COUNT]("actor_outboxes");
    spawn ActorOutboxDispatch<COUNT>(incoming, batches_p);
    unroll_for! (slot, _): (u32, ()) in u32:0..COUNT {
      spawn ActorOutboxDrain<slot>(batches_c[slot], effects[slot], credits[slot]);
    }(());
    ()
  }
  // All state belongs to the independent drains and their bounded channels.
  init { () }
  // Wiring has no runtime action.
  next(state: ()) { state }
}
