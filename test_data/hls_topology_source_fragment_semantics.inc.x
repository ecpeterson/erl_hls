// Appended to a generated topology by tools/test_reduction_dslx.sh.

fn source_fragment_test_frame(value: u32) -> axis::Frame {
  axis::pack(
    hls_topology_source_fragment_fixture::Tag::MESSAGE as u8,
    hls_topology_source_fragment_fixture::bits_from_message(
      hls_topology_source_fragment_fixture::Message { value }))
}

#[test]
fn source_fragment_full_queue_pop_push_test() {
  let first = source_fragment_test_frame(u32:1);
  let second = source_fragment_test_frame(u32:2);
  let third = source_fragment_test_frame(u32:3);
  let queued = reducer_reduction_fragment_push(
    reducer_reduction_fragment_push(
      zero!<ReducerReductionFragmentQueue>(), first),
    second);
  let updated = reducer_reduction_fragment_update_bank<u32:1>(
    [queued], u1:1, u32:0, u1:1, u32:0, third)[u32:0];
  assert_eq(updated.current_valid, u1:1);
  assert_eq(updated.current, second);
  assert_eq(updated.lookahead_valid, u1:1);
  assert_eq(updated.lookahead, third);
}

#[test_proc]
proc SourceFragmentTransposeTest {
  terminator: chan<bool> out;
  batch_out: chan<ReducerReductionBatch> out;
  aggregate_in: chan<
    hls_topology_source_fragment_fixture::ReductionAggregateRequest> in;

  config(terminator: chan<bool> out) {
    let (batch_p, batch_c) =
      chan<ReducerReductionBatch, u32:1>[u32:1](
        "source_fragment_test_batch");
    let (aggregate_p, aggregate_c) =
      chan<hls_topology_source_fragment_fixture::ReductionAggregateRequest,
        u32:9>("source_fragment_test_aggregate");
    spawn ReducerReductionPlane(batch_c, aggregate_p);
    (terminator, batch_p[u32:0], aggregate_c)
  }

  init { () }

  next(state: ()) {
    let sent_tok = unroll_for! (source, tok):
        (u32, token) in u32:0..u32:9 {
      send(tok, batch_out, ReducerReductionBatch {
        source,
        frames: [
          source_fragment_test_frame(u32:100 + source),
          source_fragment_test_frame(u32:200 + source),
        ],
      })
    }(join());
    let received_tok = unroll_for! (slot, tok):
        (u32, token) in u32:0..u32:9 {
      let (next_tok, request) = recv(tok, aggregate_in);
      let x = slot / u32:3;
      let y = slot % u32:3;
      let north_source = x * u32:3 + (y + u32:1) % u32:3;
      let south_source = x * u32:3 + (y + u32:2) % u32:3;
      let expected = u32:300 + north_source + south_source;
      assert_eq(request.slot, slot);
      assert_eq(request.aggregate.valid, u1:1);
      assert_eq(request.aggregate.failed, u1:0);
      assert_eq(request.aggregate.count, uN[2]:2);
      assert_eq(
        request.aggregate.accumulator,
        hls_topology_source_fragment_fixture::Sum { value: expected });
      next_tok
    }(sent_tok);
    let _done = send(received_tok, terminator, true);
    state
  }
}

// Models the causal rule which makes one open-token bit sufficient: source N
// may emit its next opening batch only after aggregate N has retired.  Later
// source batches can nevertheless occupy lookahead queues while the remaining
// destinations finish their preceding window.
#[test_proc]
proc SourceFragmentTwoWindowTest {
  terminator: chan<bool> out;
  batch_out: chan<ReducerReductionBatch> out;
  aggregate_in: chan<
    hls_topology_source_fragment_fixture::ReductionAggregateRequest> in;

  config(terminator: chan<bool> out) {
    let (batch_p, batch_c) =
      chan<ReducerReductionBatch, u32:1>[u32:1](
        "source_fragment_two_window_batch");
    let (aggregate_p, aggregate_c) =
      chan<hls_topology_source_fragment_fixture::ReductionAggregateRequest,
        u32:0>("source_fragment_two_window_aggregate");
    spawn ReducerReductionPlane(batch_c, aggregate_p);
    (terminator, batch_p[u32:0], aggregate_c)
  }

  init { () }

  next(state: ()) {
    let first_sent = unroll_for! (source, tok):
        (u32, token) in u32:0..u32:9 {
      send(tok, batch_out, ReducerReductionBatch {
        source,
        frames: [
          source_fragment_test_frame(u32:100 + source),
          source_fragment_test_frame(u32:200 + source),
        ],
      })
    }(join());
    let second_sent = unroll_for! (slot, tok):
        (u32, token) in u32:0..u32:9 {
      let (received_tok, request) = recv(tok, aggregate_in);
      let x = slot / u32:3;
      let y = slot % u32:3;
      let north_source = x * u32:3 + (y + u32:1) % u32:3;
      let south_source = x * u32:3 + (y + u32:2) % u32:3;
      assert_eq(request.slot, slot);
      assert_eq(
        request.aggregate.accumulator,
        hls_topology_source_fragment_fixture::Sum {
          value: u32:300 + north_source + south_source,
        });
      send(received_tok, batch_out, ReducerReductionBatch {
        source: slot,
        frames: [
          source_fragment_test_frame(u32:1000 + slot),
          source_fragment_test_frame(u32:2000 + slot),
        ],
      })
    }(first_sent);
    let received_tok = unroll_for! (slot, tok):
        (u32, token) in u32:0..u32:9 {
      let (next_tok, request) = recv(tok, aggregate_in);
      let x = slot / u32:3;
      let y = slot % u32:3;
      let north_source = x * u32:3 + (y + u32:1) % u32:3;
      let south_source = x * u32:3 + (y + u32:2) % u32:3;
      assert_eq(request.slot, slot);
      assert_eq(request.aggregate.valid, u1:1);
      assert_eq(request.aggregate.failed, u1:0);
      assert_eq(request.aggregate.count, uN[2]:2);
      assert_eq(
        request.aggregate.accumulator,
        hls_topology_source_fragment_fixture::Sum {
          value: u32:3000 + north_source + south_source,
        });
      next_tok
    }(second_sent);
    let _done = send(received_tok, terminator, true);
    state
  }
}
