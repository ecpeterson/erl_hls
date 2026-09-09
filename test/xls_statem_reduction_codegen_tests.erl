-module(xls_statem_reduction_codegen_tests).

-include_lib("eunit/include/eunit.hrl").

none_is_zero_cost_test() ->
    ?assertEqual([], xls_statem_reduction_codegen:declarations(none)),
    ?assertEqual([], xls_statem_reduction_codegen:functions(none)),
    ?assertEqual(0, xls_statem_reduction_codegen:private_width(none)),
    ?assertEqual([], xls_statem_reduction_codegen:tag_member(none, 17)).

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
        key => expression("u32:7"),
        identity => expression("zero!<SumValue>()"),
        contributions => [#{
            tag => Tag,
            build => expression(
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
