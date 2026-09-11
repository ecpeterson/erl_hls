-module(xls_statem_reduction_codegen_tests).

-include_lib("eunit/include/eunit.hrl").

none_is_zero_cost_test() ->
    ?assertEqual([], xls_statem_reduction_codegen:declarations(none)),
    ?assertEqual([], xls_statem_reduction_codegen:functions(none)),
    ?assertEqual(0, xls_statem_reduction_codegen:private_width(none)),
    ?assertEqual([], xls_statem_reduction_codegen:tag_member(none, 17)).

aggregate_only_requires_reductions_test() ->
    ?assertError(aggregate_only_requires_reductions,
        xls_statem_reduction_codegen:declarations(none, aggregate_only)),
    ?assertError(aggregate_only_requires_reductions,
        xls_statem_reduction_codegen:functions(none, aggregate_only)).

site_nested_ir_renders_local_reduction_test() ->
    Spec = spec(),
    Text = iolist_to_binary([
        xls_statem_reduction_codegen:declarations(Spec),
        xls_statem_reduction_codegen:functions(Spec)
    ]),
    ?assertEqual(72, xls_statem_reduction_codegen:private_width(Spec)),
    ?assertEqual(
        <<"  SUM_VALUE = u8:17,\n">>,
        iolist_to_binary(xls_statem_reduction_codegen:tag_member(Spec, 17))
    ),
    assert_contains(Text, "enum ReductionStatus : u2"),
    assert_contains(Text, "COUNTING = uN[1]:0"),
    assert_contains(Text, "COLLECTING = uN[1]:1"),
    assert_contains(Text, "type ReductionRemaining = uN[2]"),
    assert_contains(Text, "type ReductionMembers = bits[3]"),
    assert_contains(Text, "raw: bits[72]"),
    assert_contains(Text, "Tag::COUNT_VALUE"),
    assert_contains(Text, "Phase::COUNTING"),
    assert_contains(Text, "Tag::MEMBER_VALUE"),
    assert_contains(Text, "Phase::COLLECTING"),
    assert_contains(Text, "state.status != ReductionStatus::OPEN"),
    assert_contains(Text, "status: if complete { ReductionStatus::COMPLETE }"),
    assert_contains(Text, "state.status != ReductionStatus::COMPLETE"),
    assert_contains(Text, "reduction: zero!<ReductionState>()"),
    ?assertEqual(nomatch, binary:match(Text, <<"WRONG_MODE">>)),
    ?assertEqual(nomatch, binary:match(
        Text,
        <<"struct ReductionContribution {\n  mode:">>
    )).

aggregate_only_renders_transport_and_complete_apply_test() ->
    Spec = spec(),
    Ordinary = iolist_to_binary([
        xls_statem_reduction_codegen:declarations(Spec),
        xls_statem_reduction_codegen:functions(Spec)
    ]),
    AggregateOnly = iolist_to_binary([
        xls_statem_reduction_codegen:declarations(Spec, aggregate_only),
        xls_statem_reduction_codegen:functions(Spec, aggregate_only)
    ]),
    ?assertEqual(nomatch,
        binary:match(Ordinary, <<"ReductionAggregate">>)),
    assert_contains(AggregateOnly, "pub struct ReductionAggregate {"),
    assert_contains(AggregateOnly,
        "pub struct ReductionAggregateRequest {\n"
        "  slot: u32,\n"
        "  aggregate: ReductionAggregate,"),
    assert_contains(AggregateOnly,
        "fn reduction_transport_contribution(\n"
        "    frame: axis::Frame) -> ReductionContribution"),
    assert_contains(AggregateOnly,
        "pub fn reduction_aggregate_batch<COUNT: u32>("),
    assert_contains(AggregateOnly,
        "fn reduction_apply_complete_aggregate("),
    assert_contains(AggregateOnly,
        "state.remaining == population"),
    assert_contains(AggregateOnly,
        "aggregate.count == population"),
    assert_contains(AggregateOnly,
        "reduction_aggregate_expected_members(state.site)"),
    assert_contains(AggregateOnly,
        "accumulator: aggregate.accumulator"),
    [_, AfterFastApply] = binary:split(AggregateOnly,
        <<"fn reduction_apply_complete_aggregate(">>),
    [FastApply, _] = binary:split(AfterFastApply,
        <<"fn reduction_apply(\n">>),
    ?assertEqual(nomatch, binary:match(FastApply, <<"reduction_reduce(">>)).

aggregate_only_rejects_ambiguous_transport_tags_test() ->
    Spec0 = spec(),
    [First, Second0] = maps:get(sites, Spec0),
    [FirstContribution] = maps:get(contributions, First),
    [SecondContribution0] = maps:get(contributions, Second0),
    Second = Second0#{contributions => [SecondContribution0#{
        tag => maps:get(tag, FirstContribution)
    }]},
    Spec = Spec0#{sites => [First, Second]},
    ?assertError(
        {aggregate_only_ambiguous_contribution_schemas, [count_value]},
        xls_statem_reduction_codegen:functions(Spec, aggregate_only)
    ).

spec() ->
    Data = type_ref(cell, "Cell"),
    Accumulator = type_ref(sum_value, "SumValue"),
    Sites = [
        site(
            0,
            counting,
            #{mode => count, size => 2},
            count_value
        ),
        site(
            1,
            collecting,
            #{mode => members, size => 3, members => [2, 5, 9]},
            member_value
        )
    ],
    xls_statem_reduction_ir:new(
        Data,
        Accumulator,
        Sites,
        [#{name => sum, body => [], result => "left"}]
    ).

type_ref(Name, DslxType) ->
    #{
        kind => record,
        name => Name,
        dslx_type => DslxType,
        fields => [#{name => value, type => u32_type()}]
    }.

u32_type() ->
    hls_type:descriptor(
        {remote_type, 0, [{atom, 0, hls_nums}, {atom, 0, u32}, []]}
    ).

site(ID, Phase, Population, Tag) ->
    #{
        id => ID,
        phase => Phase,
        name => sum,
        population => Population,
        opens_conditionally => false,
        contributions => [#{
            tag => Tag,
            build => expression(
                "(u1:1, u32:7, u32:0, zero!<SumValue>())"
            ),
            source_transportable => true,
            source_capture_total => true,
            transport => expression(
                "(u1:1, u32:7, u32:0, zero!<SumValue>())"
            )
        }],
        completion => expression(
            "(phase, data, Directive::CONSUME, u1:0)"
        )
    }.

expression(Result) ->
    #{body => [], result => Result}.

assert_contains(Text, Fragment) ->
    ?assertNotEqual(nomatch, binary:match(Text, iolist_to_binary(Fragment))).
