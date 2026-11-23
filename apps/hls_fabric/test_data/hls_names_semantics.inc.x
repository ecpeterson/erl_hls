fn input_frame(value: u32) -> axis::Frame {
  axis::pack(Tag::INPUT_VALUE as u8, bits_from_inputvalue(InputValue { Key: u32:17, Value: value }))
}

pub fn probe(a: u32, b: u32) -> bits[104] {
  let initial = initial_machine();
  let opened = enter(initial.phase, initial.phase, initial.data);
  let first = reduction_apply(opened.reduction,
    reduction_contribution(input_frame(a), initial.phase, initial.data));
  let second = reduction_apply(first.state,
    reduction_contribution(input_frame(b), initial.phase, initial.data));
  let ordinary = reduction_dispatch_completion(second.state, initial.phase, initial.data);
  let aggregate = reduction_aggregate_batch<u32:2>([input_frame(a), input_frame(b)]);
  let combined = reduction_apply_complete_aggregate(opened.reduction, aggregate);
  let completed = reduction_dispatch_completion(combined.state, initial.phase, initial.data);
  let emitted = enter(initial.phase, completed.phase, completed.data);
  let effect = entry_effect(emitted.effects, u8:0);
  let message = outputvalue_from_bits(effect.frame.payload);
  let data_roundtrip = actordata_from_bits(bits_from_actordata(completed.data));
  let ok = opened.failure == hls_failure::NONE &&
    first.outcome == ReductionOutcome::PENDING && second.outcome == ReductionOutcome::COMPLETE &&
    ordinary.failure == hls_failure::NONE && completed.failure == hls_failure::NONE &&
    completed.phase == Phase::COMPLETE && effect.port == OutputPort::RESULT &&
    effect.frame.header.op == Tag::OUTPUT_VALUE as u8 && emitted.failure == hls_failure::NONE &&
    data_roundtrip == completed.data;
  (ok as u8) ++ ordinary.data.Value ++ completed.data.Value ++ message.Value
}
