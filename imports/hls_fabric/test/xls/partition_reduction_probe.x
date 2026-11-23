// Exercise the generated collector with two ordered, aliased contribution lanes.
import axis;
import phi_halo_cell;
import hls_reduction_fragments;

// GENERATED_COLLECTOR

// Keep test inputs independent of the actor wire packing convention.
proc Encode {
  input: chan<bits[128]> in;
  output: chan<axis::Frame> out;
  // Input words are opcode, epoch and two signed scalar values.
  config(input: chan<bits[128]> in, output: chan<axis::Frame> out) { (input, output) }
  // No test state is retained here.
  init { () }
  // Use the compiled actor's codec, including its hardware byte order.
  next(state: ()) {
    let (tok, value) = recv(join(), input);
    let message = phi_halo_cell::Phi {
      epoch: value[64+:u32], values: [value[32+:s32], value[0+:s32]],
    };
    let frame = axis::Frame {
      header: axis::Header { op: value[96+:u32] as u8, payload_words: u8:3, ..zero!<axis::Header>() },
      payload: phi_halo_cell::bits_from_phi(message),
    };
    let _sent = send(tok, output, frame);
    state
  }
}

// Expose aggregate fields in a stable test-only layout.
proc Observe {
  input: chan<phi_halo_cell::ReductionAggregateRequest> in;
  output: chan<bits[256]> out;
  // Reports contain slot, key, count, failure, and two signed accumulator values.
  config(input: chan<phi_halo_cell::ReductionAggregateRequest> in, output: chan<bits[256]> out) { (input, output) }
  // The output channel retains stalled reports.
  init { () }
  // Inspect the actual public typed aggregate rather than its incidental packed width.
  next(state: ()) {
    let (tok, request) = recv(join(), input);
    let a = request.aggregate;
    let _sent = send(tok, output, request.slot ++ a.key ++ (a.count as u32) ++
      (a.failure as u32) ++ (a.accumulator.value0 as bits[64]) ++ (a.accumulator.value1 as bits[64]));
    state
  }
}

// Match the destination-side two-slot fragment storage used by the board experiment.
pub proc Top {
  config(left: chan<bits[128]> in, right: chan<bits[128]> in,
      opened: chan<u1> in, report: chan<bits[256]> out) {
    let (left_p, left_c) = chan<axis::Frame, u32:1>("left");
    let (right_p, right_c) = chan<axis::Frame, u32:1>("right");
    let (a_p, a_c) = chan<axis::Frame, u32:2>[u32:2]("a");
    let (b_p, b_c) = chan<axis::Frame, u32:2>[u32:2]("b");
    let (aggregate_p, aggregate_c) = chan<phi_halo_cell::ReductionAggregateRequest, u32:1>("aggregate");
    spawn Encode(left, left_p);
    spawn Encode(right, right_p);
    spawn hls_reduction_fragments::Split<u32:2>(left_c, a_p);
    spawn hls_reduction_fragments::Split<u32:2>(right_c, b_p);
    spawn ReductionCollector<u32:0>(a_c[u32:0], a_c[u32:1], b_c[u32:0], b_c[u32:1], opened, aggregate_p);
    spawn Observe(aggregate_c, report);
    ()
  }
  // All window state belongs to the generated collector and bounded channels.
  init { () }
  // Connectivity only.
  next(state: ()) { state }
}
