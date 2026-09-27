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
  let ok = first.outcome == ReductionOutcome::PENDING &&
    ordinary.outcome == ReductionOutcome::COMPLETE &&
    ordinary.state.failure == hls_failure::NONE;
  (ok as u8) ++ ordinary.state.accumulator.value ++ ordinary.state.accumulator.value
}
