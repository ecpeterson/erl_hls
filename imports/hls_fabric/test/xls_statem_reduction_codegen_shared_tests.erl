-module(xls_statem_reduction_codegen_shared_tests).

-include_lib("eunit/include/eunit.hrl").


%% Checks aggregate only requires reductions.
-spec aggregate_only_requires_reductions_test() -> 'ok'.
aggregate_only_requires_reductions_test() ->
    ?assertError(aggregate_only_requires_reductions,
        xls_shared_reduction_codegen:declarations(none, aggregate_only)),
    ?assertError(aggregate_only_requires_reductions,
        xls_shared_reduction_codegen:functions(none, aggregate_only)).

%% Checks aggregate only renders transport and complete apply.
-spec aggregate_only_renders_transport_and_complete_apply_test() -> 'ok'.
aggregate_only_renders_transport_and_complete_apply_test() ->
    Spec = spec(),
    Ordinary = iolist_to_binary([
        xls_statem_reduction_codegen:declarations(Spec),
        xls_statem_reduction_codegen:functions(Spec)
    ]),
    AggregateOnly = iolist_to_binary([
        xls_shared_reduction_codegen:declarations(Spec, aggregate_only),
        xls_shared_reduction_codegen:functions(Spec, aggregate_only)
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
    FastApply = AfterFastApply,
    ?assertEqual(nomatch, binary:match(FastApply, <<"reduction_reduce(">>)).

%% Checks aggregate only rejects ambiguous transport tags.
-spec aggregate_only_rejects_ambiguous_transport_tags_test() -> 'ok'.
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
        xls_shared_reduction_codegen:functions(Spec, aggregate_only)
    ).

%% Builds the minimal checked input required by the renderer under test.
-spec spec() -> any().
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
        [#{name => sum, body => [], result => "(left, hls_failure::NONE)"}]
    ).

%% Builds a logical type reference for the reduction-rendering witness.
-spec type_ref('cell' | 'sum_value',[67 | 83 | 86 | 97 | 101 | 108 | 109 | 117,...]) -> map().
type_ref(Name, DslxType) ->
    #{
        kind => record,
        name => Name,
        dslx_type => DslxType,
        fields => [#{name => value, type => u32_type()}]
    }.

%% Builds the unsigned-word type used by the test reduction.
-spec u32_type() -> any().
u32_type() ->
    hls_type:descriptor(
        {remote_type, 0, [{atom, 0, hls_nums}, {atom, 0, u32}, []]}
    ).

%% Builds one checked reduction site with the requested population and phase.
-spec site(0 | 1,'collecting' | 'counting',map(),'count_value' | 'member_value') -> map().
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
            "(phase, data, Directive::CONSUME, u1:0, hls_failure::NONE)"
        )
    }.

%% Parses one test expression without executing it.
-spec expression([1 .. ((1 bsl 8) - 1),...]) -> map().
expression(Result) ->
    #{body => [], result => Result}.

%% Requires the generated artifact to contain the selected structural marker.
-spec assert_contains(binary(),[1 .. ((1 bsl 8) - 1),...]) -> 'ok'.
assert_contains(Text, Fragment) ->
    ?assertNotEqual(nomatch, binary:match(Text, iolist_to_binary(Fragment))).
