fn shape_frame(key: u32, a: u32, b: u32) -> axis::Frame {
  axis::pack(Tag::VALUE as u8, bits_from_value(Value { key, values: [a, b] }))
}

pub fn probe(a: u32, b: u32, c: u32, d: u32) -> bits[72] {
  let frames = [shape_frame(u32:17, a, b), shape_frame(u32:17, c, d)];
  let opened = reduction_open_site(ReductionSite::GATHERING, u32:17, zero!<Sum>());
  let first = reduction_apply(opened,
    reduction_contribution(frames[u32:0], Phase::GATHERING, zero!<Cell>()));
  let ordinary = reduction_apply(first.state,
    reduction_contribution(frames[u32:1], Phase::GATHERING, zero!<Cell>()));
  let aggregate = reduction_aggregate_batch<u32:2>(frames);
  let applied = reduction_apply_complete_aggregate(opened, aggregate);
  let ok = first.outcome == ReductionOutcome::PENDING &&
    ordinary.outcome == ReductionOutcome::COMPLETE &&
    aggregate.valid && aggregate.failure == hls_failure::NONE &&
    aggregate.count == ReductionRemaining:2 &&
    applied.outcome == ReductionOutcome::COMPLETE &&
    applied.state.failure == hls_failure::NONE;
  (ok as u8) ++ ordinary.state.accumulator.value ++ applied.state.accumulator.value
}

#[test]
fn differing_keys_remain_protocol_errors() {
  let aggregate = reduction_aggregate_batch<u32:2>([
    shape_frame(u32:1, u32:3, u32:5), shape_frame(u32:2, u32:7, u32:9)]);
  assert_eq(aggregate.failure, hls_failure::REDUCTION_PROTOCOL);
}
