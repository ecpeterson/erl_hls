// Appended to the equal-cardinality count/member topology by
// tools/test_reduction_dslx.sh. Both sites deliberately share this plane.

fn population_count_frame(value: u32) -> axis::Frame {
  axis::pack(
    hls_reduction_plan_population_fixture::Tag::COUNT_MESSAGE as u8,
    hls_reduction_plan_population_fixture::bits_from_countmessage(
      hls_reduction_plan_population_fixture::Countmessage { value }))
}

fn population_member_frame(member: u32, value: u32) -> axis::Frame {
  axis::pack(
    hls_reduction_plan_population_fixture::Tag::MEMBER_MESSAGE as u8,
    hls_reduction_plan_population_fixture::bits_from_membermessage(
      hls_reduction_plan_population_fixture::Membermessage {
        member,
        value,
      }))
}

fn population_neighbor_sum(slot: u32, base: u32) -> u32 {
  let x = slot / u32:3;
  let y = slot % u32:3;
  let north_source = x * u32:3 + (y + u32:1) % u32:3;
  let south_source = x * u32:3 + (y + u32:2) % u32:3;
  base * u32:2 + north_source + south_source
}

#[test_proc]
proc SourceFragmentAlternatingPopulationTest {
  terminator: chan<bool> out;
  batch_out: chan<ReducerReductionBatch> out;
  aggregate_in: chan<
    hls_reduction_plan_population_fixture::ReductionAggregateRequest> in;

  config(terminator: chan<bool> out) {
    let (batch_p, batch_c) =
      chan<ReducerReductionBatch, u32:1>[u32:1](
        "source_fragment_population_batch");
    let (aggregate_p, aggregate_c) =
      chan<hls_reduction_plan_population_fixture::ReductionAggregateRequest,
        u32:0>("source_fragment_population_aggregate");
    spawn ReducerReductionPlane(batch_c, aggregate_p);
    (terminator, batch_p[u32:0], aggregate_c)
  }

  init { () }

  next(state: ()) {
    let count_sent = unroll_for! (source, tok):
        (u32, token) in u32:0..u32:9 {
      let frame = population_count_frame(u32:100 + source);
      send(tok, batch_out, ReducerReductionBatch {
        source,
        frames: [frame, frame],
      })
    }(join());
    let count_received = unroll_for! (slot, tok):
        (u32, token) in u32:0..u32:9 {
      let (next_tok, request) = recv(tok, aggregate_in);
      assert_eq(request.slot, slot);
      assert_eq(request.aggregate.valid, u1:1);
      assert_eq(request.aggregate.failed, u1:0);
      assert_eq(
        request.aggregate.site,
        uN[1]:0);
      assert_eq(request.aggregate.key, u32:0);
      assert_eq(request.aggregate.count, uN[2]:2);
      assert_eq(request.aggregate.seen, uN[2]:0);
      assert_eq(
        request.aggregate.accumulator,
        hls_reduction_plan_population_fixture::Sum {
          value: population_neighbor_sum(slot, u32:100),
        });
      next_tok
    }(count_sent);
    let members_sent = unroll_for! (source, tok):
        (u32, token) in u32:0..u32:9 {
      send(tok, batch_out, ReducerReductionBatch {
        source,
        frames: [
          population_member_frame(u32:0, u32:1000 + source),
          population_member_frame(u32:1, u32:1000 + source),
        ],
      })
    }(count_received);
    let members_received = unroll_for! (slot, tok):
        (u32, token) in u32:0..u32:9 {
      let (next_tok, request) = recv(tok, aggregate_in);
      assert_eq(request.slot, slot);
      assert_eq(request.aggregate.valid, u1:1);
      assert_eq(request.aggregate.failed, u1:0);
      assert_eq(
        request.aggregate.site,
        uN[1]:1);
      assert_eq(request.aggregate.key, u32:1);
      assert_eq(request.aggregate.count, uN[2]:2);
      assert_eq(request.aggregate.seen, uN[2]:3);
      assert_eq(
        request.aggregate.accumulator,
        hls_reduction_plan_population_fixture::Sum {
          value: population_neighbor_sum(slot, u32:1000),
        });
      next_tok
    }(members_sent);
    let next_count_sent = unroll_for! (source, tok):
        (u32, token) in u32:0..u32:9 {
      let frame = population_count_frame(u32:2000 + source);
      send(tok, batch_out, ReducerReductionBatch {
        source,
        frames: [frame, frame],
      })
    }(members_received);
    let next_count_received = unroll_for! (slot, tok):
        (u32, token) in u32:0..u32:9 {
      let (next_tok, request) = recv(tok, aggregate_in);
      assert_eq(request.slot, slot);
      assert_eq(request.aggregate.valid, u1:1);
      assert_eq(request.aggregate.failed, u1:0);
      assert_eq(
        request.aggregate.site,
        uN[1]:0);
      assert_eq(request.aggregate.key, u32:0);
      assert_eq(
        request.aggregate.accumulator,
        hls_reduction_plan_population_fixture::Sum {
          value: population_neighbor_sum(slot, u32:2000),
        });
      next_tok
    }(next_count_sent);
    let _done = send(next_count_received, terminator, true);
    state
  }
}
