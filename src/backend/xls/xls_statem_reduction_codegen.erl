%%%% xls_statem_reduction_codegen
%%%%
%%%% Renders actor-local DSLX reduction support from the closed IR produced by
%%%% xls_statem_reduction_lower.  Transport and scheduler placement are
%%%% deliberately outside this module.

-module(xls_statem_reduction_codegen).
-moduledoc false.

-export([
    declarations/1,
    declarations/2,
    functions/1,
    functions/2,
    private_width/1,
    tag_member/2
]).

-type spec() :: none | xls_statem_reduction_ir:reduction().

-spec declarations(spec()) -> iolist().
declarations(Spec) ->
    declarations(Spec, ordinary).

-spec declarations(spec(), ordinary | aggregate_only) -> iolist().
declarations(none, ordinary) ->
    [];
declarations(none, aggregate_only) ->
    error(aggregate_only_requires_reductions);
declarations(Spec = #{
    data := #{dslx_type := DataType},
    accumulator := #{dslx_type := AccumulatorType},
    sites := Sites,
    reducers := Reducers
}, Mode) when Mode =:= ordinary; Mode =:= aggregate_only ->
    Layout = xls_statem_reduction_ir:layout(Spec),
    SiteBits = maps:get(site_bits, Layout),
    RemainingBits = maps:get(remaining_bits, Layout),
    MemberBits = maps:get(member_bits, Layout),
    [
        "enum ReductionStatus : u2 {\n",
        "  IDLE = u2:0,\n",
        "  OPEN = u2:1,\n",
        "  COMPLETE = u2:2,\n",
        "}\n\n",
        "enum ReductionMode : u1 {\n",
        "  COUNT = u1:0,\n",
        "  MEMBERS = u1:1,\n",
        "}\n\n",
        "enum ReductionName : u8 {\n",
        [
            ["  ", uppercase(maps:get(name, Reducer)), " = u8:",
                integer_to_list(Index), ",\n"]
            || {Index, Reducer} <- lists:enumerate(0, Reducers)
        ],
        "}\n\n",
        "enum ReductionSite : uN[", integer_to_list(SiteBits), "] {\n",
        [
            ["  ", site_label(Site), " = uN[",
                integer_to_list(SiteBits), "]:",
                integer_to_list(maps:get(id, Site)), ",\n"]
            || Site <- Sites
        ],
        "}\n\n",
        "type ReductionRemaining = uN[",
        integer_to_list(RemainingBits), "];\n",
        "type ReductionMembers = bits[", integer_to_list(MemberBits),
        "];\n\n",
        "struct ReductionState {\n",
        "  status: ReductionStatus,\n",
        "  site: ReductionSite,\n",
        "  key: u32,\n",
        "  remaining: ReductionRemaining,\n",
        "  seen: ReductionMembers,\n",
        "  accumulator: ", AccumulatorType, ",\n",
        "}\n\n",
        "struct ReductionContribution {\n",
        "  valid: u1,\n",
        "  site: ReductionSite,\n",
        "  key: u32,\n",
        "  member: u32,\n",
        "  value: ", AccumulatorType, ",\n",
        "}\n\n",
        aggregate_declarations(Mode, SiteBits, RemainingBits, MemberBits,
            AccumulatorType),
        "enum ReductionOutcome : u3 {\n",
        "  NOT_CANDIDATE = u3:0,\n",
        "  MISMATCH = u3:1,\n",
        "  PENDING = u3:2,\n",
        "  COMPLETE = u3:3,\n",
        "  UNEXPECTED_MEMBER = u3:4,\n",
        "  DUPLICATE_MEMBER = u3:5,\n",
        "}\n\n",
        "struct ReductionApply {\n",
        "  state: ReductionState,\n",
        "  outcome: ReductionOutcome,\n",
        "}\n\n",
        "struct ReductionDispatch {\n",
        "  reduction: ReductionState,\n",
        "  phase: Phase,\n",
        "  data: ", DataType, ",\n",
        "  directive: Directive,\n",
        "  repeat_phase: u1,\n",
        "  failure: hls_failure::Code,\n",
        "  dispatched: u1,\n",
        "}\n\n"
    ].

-spec functions(spec()) -> iolist().
functions(Spec) ->
    functions(Spec, ordinary).

-spec functions(spec(), ordinary | aggregate_only) -> iolist().
functions(none, ordinary) ->
    [];
functions(none, aggregate_only) ->
    error(aggregate_only_requires_reductions);
functions(Spec, Mode) when Mode =:= ordinary; Mode =:= aggregate_only ->
    [
        codec_functions(Spec),
        site_functions(Spec),
        open_functions(Spec),
        contribution_functions(Spec),
        reducer_function(Spec),
        aggregate_functions(Mode, Spec),
        apply_function(),
        completion_function(Spec)
    ].

aggregate_declarations(ordinary, _SiteBits, _RemainingBits, _MemberBits,
        _AccumulatorType) ->
    [];
aggregate_declarations(aggregate_only, SiteBits, RemainingBits, MemberBits,
        AccumulatorType) ->
    [
        "pub struct ReductionAggregate {\n",
        "  valid: u1,\n",
        "  failed: u1,\n",
        "  site: uN[", integer_to_list(SiteBits), "],\n",
        "  key: u32,\n",
        "  count: uN[", integer_to_list(RemainingBits), "],\n",
        "  seen: bits[", integer_to_list(MemberBits), "],\n",
        "  accumulator: ", AccumulatorType, ",\n",
        "}\n\n",
        "pub struct ReductionAggregateRequest {\n",
        "  slot: u32,\n",
        "  aggregate: ReductionAggregate,\n",
        "}\n\n"
    ].

-spec private_width(spec()) -> non_neg_integer().
private_width(none) ->
    0;
private_width(Spec) ->
    xls_statem_reduction_ir:storage_width(Spec).

%% The accumulator record is private, but its generated codec uses the same
%% tagged record-value representation as public wire schemas.
-spec tag_member(spec(), non_neg_integer()) -> iolist().
tag_member(none, _Selector) ->
    [];
tag_member(#{accumulator := #{name := Name}}, Selector)
        when Selector >= 0, Selector =< 255 ->
    ["  ", uppercase(Name), " = u8:", integer_to_list(Selector), ",\n"].

codec_functions(Spec = #{accumulator := #{name := AccumulatorName}}) ->
    Layout = xls_statem_reduction_ir:layout(Spec),
    SiteBits = maps:get(site_bits, Layout),
    RemainingBits = maps:get(remaining_bits, Layout),
    MemberBits = maps:get(member_bits, Layout),
    AccumulatorBits = maps:get(accumulator_bits, Layout),
    TotalBits = maps:get(total_bits, Layout),
    StatusBits = maps:get(status_bits, Layout),
    StatusStart = 0,
    SiteStart = StatusStart + StatusBits,
    KeyStart = SiteStart + SiteBits,
    RemainingStart = KeyStart + 32,
    MemberStart = RemainingStart + RemainingBits,
    AccumulatorStart = MemberStart + MemberBits,
    AccumulatorFunction = record_function_name(AccumulatorName),
    [
        "fn reduction_state_from_bits(\n",
        "    raw: bits[", integer_to_list(TotalBits),
        "]) -> ReductionState {\n",
        "  ReductionState {\n",
        "    status: raw[0:", integer_to_list(StatusBits),
        "] as ReductionStatus,\n",
        "    site: raw[", integer_to_list(SiteStart), ":",
        integer_to_list(KeyStart), "] as ReductionSite,\n",
        "    key: raw[", integer_to_list(KeyStart), ":",
        integer_to_list(RemainingStart), "] as u32,\n",
        "    remaining: raw[", integer_to_list(RemainingStart), ":",
        integer_to_list(MemberStart), "] as ReductionRemaining,\n",
        "    seen: raw[", integer_to_list(MemberStart), ":",
        integer_to_list(AccumulatorStart), "] as ReductionMembers,\n",
        "    accumulator: ", AccumulatorFunction, "_from_bits(raw[",
        integer_to_list(AccumulatorStart), ":",
        integer_to_list(AccumulatorStart + AccumulatorBits), "]),\n",
        "  }\n",
        "}\n\n",
        "fn bits_from_reduction_state(\n",
        "    state: ReductionState) -> bits[", integer_to_list(TotalBits),
        "] {\n",
        "  bits_from_", AccumulatorFunction, "(state.accumulator) ++\n",
        "    (state.seen as bits[", integer_to_list(MemberBits), "]) ++\n",
        "    (state.remaining as bits[",
        integer_to_list(RemainingBits), "]) ++\n",
        "    (state.key as bits[32]) ++\n",
        "    (state.site as bits[", integer_to_list(SiteBits), "]) ++\n",
        "    (state.status as bits[", integer_to_list(StatusBits), "])\n",
        "}\n\n"
    ].

site_functions(Spec = #{sites := Sites}) ->
    MemberBits = xls_statem_reduction_ir:member_width(Spec),
    [
        "fn reduction_site_name(site: ReductionSite) -> ReductionName {\n",
        "  match site {\n",
        [
            ["    ReductionSite::", site_label(Site), " => ",
                "ReductionName::", uppercase(maps:get(name, Site)), ",\n"]
            || Site <- Sites
        ],
        "  }\n",
        "}\n\n",
        "fn reduction_site_mode(site: ReductionSite) -> ReductionMode {\n",
        "  match site {\n",
        [
            ["    ReductionSite::", site_label(Site), " => ",
                mode_value(maps:get(mode, maps:get(population, Site))),
                ",\n"]
            || Site <- Sites
        ],
        "  }\n",
        "}\n\n",
        "fn reduction_site_population(\n",
        "    site: ReductionSite) -> ReductionRemaining {\n",
        "  match site {\n",
        [
            ["    ReductionSite::", site_label(Site),
                " => ReductionRemaining:",
                integer_to_list(maps:get(size,
                    maps:get(population, Site))), ",\n"]
            || Site <- Sites
        ],
        "  }\n",
        "}\n\n",
        "fn reduction_member_bit(\n",
        "    site: ReductionSite, member: u32) -> ReductionMembers {\n",
        "  match (site, member) {\n",
        member_arms(Sites, MemberBits),
        "    _ => zero!<ReductionMembers>(),\n",
        "  }\n",
        "}\n\n"
    ].

open_functions(#{
    accumulator := #{dslx_type := AccumulatorType}
}) ->
    [
        "fn reduction_open_site(\n",
        "    site: ReductionSite, key: u32, identity: ", AccumulatorType,
        ") -> ReductionState {\n",
        "  ReductionState {\n",
        "    status: ReductionStatus::OPEN,\n",
        "    site,\n",
        "    key,\n",
        "    remaining: reduction_site_population(site),\n",
        "    accumulator: identity,\n",
        "    ..zero!<ReductionState>()\n",
        "  }\n",
        "}\n\n",
        "\n"
    ].

contribution_functions(#{
    data := #{dslx_type := DataType},
    sites := Sites
}) ->
    Contributions = site_contributions(Sites),
    Tags = lists:uniq([maps:get(tag, Contribution)
        || {_Site, Contribution} <- Contributions]),
    [
        "fn reduction_contribution(\n",
        "    frame: axis::Frame, phase: Phase, data: ", DataType,
        ") -> ReductionContribution {\n",
        "  match frame.header.op as Tag {\n",
        [
            contribution_tag_arm(Tag, Contributions)
            || Tag <- Tags
        ],
        "    _ => zero!<ReductionContribution>(),\n",
        "  }\n",
        "}\n\n"
    ].

contribution_tag_arm(Tag, Contributions) ->
    Tagged = [{Site, Contribution}
        || {Site, Contribution} <- Contributions,
           maps:get(tag, Contribution) =:= Tag],
    [
        "    Tag::", uppercase(Tag), " => {\n",
        "      let message = ", record_function_name(Tag),
        "_from_bits(frame.payload);\n",
        "      match phase {\n",
        [contribution_phase_arm(Contribution) || Contribution <- Tagged],
        "        _ => zero!<ReductionContribution>(),\n",
        "      }\n",
        "    },\n"
    ].

contribution_phase_arm({Site, #{
    build := #{body := Body, result := Result}
}}) ->
    [
        "        Phase::", uppercase(maps:get(phase, Site)), " => {\n",
        "          let built = {\n",
        xls_parse_io:indent(Body, 12),
        "            ", Result, "\n",
        "          };\n",
        "          ReductionContribution {\n",
        "            valid: built.0,\n",
        "            site: ReductionSite::", site_label(Site), ",\n",
        "            key: built.1,\n",
        "            member: built.2,\n",
        "            value: built.3,\n",
        "          }\n",
        "        },\n"
    ].

reducer_function(#{
    accumulator := #{dslx_type := AccumulatorType},
    reducers := Reducers
}) ->
    [
        "fn reduction_reduce(\n",
        "    name: ReductionName, left: ", AccumulatorType,
        ", right: ", AccumulatorType, ") -> ", AccumulatorType, " {\n",
        "  match name {\n",
        [reducer_arm(Reducer) || Reducer <- Reducers],
        "  }\n",
        "}\n\n"
    ].

reducer_arm(#{name := Name, body := Body, result := Result}) ->
    [
        "    ReductionName::", uppercase(Name), " => {\n",
        xls_parse_io:indent(Body, 6),
        "      ", Result, "\n",
        "    },\n"
    ].

aggregate_functions(ordinary, _Spec) ->
    [];
aggregate_functions(aggregate_only, Spec = #{sites := Sites}) ->
    Contributions = site_contributions(Sites),
    ok = require_aggregate_contributions(Contributions),
    SiteBits = xls_statem_reduction_ir:site_width(Spec),
    [
        "fn reduction_transport_contribution(\n",
        "    frame: axis::Frame) -> ReductionContribution {\n",
        "  match frame.header.op as Tag {\n",
        [transport_contribution_arm(Contribution)
            || Contribution <- Contributions],
        "    _ => zero!<ReductionContribution>(),\n",
        "  }\n",
        "}\n\n",
        aggregate_expected_members_function(Spec),
        aggregate_push_function(SiteBits),
        "pub fn reduction_aggregate_batch<COUNT: u32>(\n",
        "    frames: axis::Frame[COUNT]) -> ReductionAggregate {\n",
        "  unroll_for! (index, aggregate):\n",
        "      (u32, ReductionAggregate) in u32:0..COUNT {\n",
        "    reduction_aggregate_push(aggregate, frames[index])\n",
        "  }(zero!<ReductionAggregate>())\n",
        "}\n\n",
        aggregate_apply_function(SiteBits)
    ].

transport_contribution_arm({Site, #{
    tag := Tag,
    source_transportable := true,
    transport := #{body := Body, result := Result}
}}) ->
    [
        "    Tag::", uppercase(Tag), " => {\n",
        "      let message = ", record_function_name(Tag),
        "_from_bits(frame.payload);\n",
        "      let built = {\n",
        xls_parse_io:indent(Body, 8),
        "        ", Result, "\n",
        "      };\n",
        "      ReductionContribution {\n",
        "        valid: built.0,\n",
        "        site: ReductionSite::", site_label(Site), ",\n",
        "        key: built.1,\n",
        "        member: built.2,\n",
        "        value: built.3,\n",
        "      }\n",
        "    },\n"
    ].

aggregate_expected_members_function(Spec = #{sites := Sites}) ->
    MemberBits = xls_statem_reduction_ir:member_width(Spec),
    [
        "fn reduction_aggregate_expected_members(\n",
        "    site: ReductionSite) -> ReductionMembers {\n",
        "  match site {\n",
        [aggregate_expected_members_arm(Site, MemberBits)
            || Site <- Sites],
        "  }\n",
        "}\n\n"
    ].

aggregate_expected_members_arm(Site = #{
    population := #{mode := members, size := Size}
}, MemberBits) ->
    [
        "    ReductionSite::", site_label(Site), " => uN[",
        integer_to_list(MemberBits), "]:",
        integer_to_list((1 bsl Size) - 1), " as ReductionMembers,\n"
    ];
aggregate_expected_members_arm(Site, _MemberBits) ->
    [
        "    ReductionSite::", site_label(Site),
        " => zero!<ReductionMembers>(),\n"
    ].

aggregate_push_function(SiteBits) ->
    [
        "fn reduction_aggregate_push(\n",
        "    aggregate: ReductionAggregate, frame: axis::Frame)\n",
        "    -> ReductionAggregate {\n",
        "  let contribution = reduction_transport_contribution(frame);\n",
        "  let first = !aggregate.valid;\n",
        "  let member_mode = reduction_site_mode(contribution.site) ==\n",
        "    ReductionMode::MEMBERS;\n",
        "  let member_bit = reduction_member_bit(\n",
        "    contribution.site, contribution.member);\n",
        "  let same_window = first ||\n",
        "    (aggregate.site == contribution.site as uN[",
        integer_to_list(SiteBits), "] &&\n",
        "     aggregate.key == contribution.key);\n",
        "  let within_population = aggregate.count <\n",
        "    reduction_site_population(contribution.site);\n",
        "  let unexpected = member_mode &&\n",
        "    member_bit == zero!<ReductionMembers>();\n",
        "  let duplicate = member_mode && !first &&\n",
        "    (aggregate.seen & member_bit) != zero!<ReductionMembers>();\n",
        "  let accepted = !aggregate.failed && contribution.valid &&\n",
        "    same_window && within_population && !unexpected && !duplicate;\n",
        "  ReductionAggregate {\n",
        "    valid: u1:1,\n",
        "    failed: aggregate.failed || !accepted,\n",
        "    site: if first { contribution.site as uN[",
        integer_to_list(SiteBits), "] } else { aggregate.site },\n",
        "    key: if first { contribution.key } else { aggregate.key },\n",
        "    count: if accepted {\n",
        "      aggregate.count + ReductionRemaining:1\n",
        "    } else { aggregate.count },\n",
        "    seen: if accepted && member_mode {\n",
        "      aggregate.seen | member_bit\n",
        "    } else { aggregate.seen },\n",
        "    accumulator: if !accepted { aggregate.accumulator } else {\n",
        "      if first { contribution.value } else {\n",
        "        reduction_reduce(\n",
        "          reduction_site_name(contribution.site),\n",
        "          aggregate.accumulator, contribution.value)\n",
        "      }\n",
        "    },\n",
        "  }\n",
        "}\n\n"
    ].

aggregate_apply_function(SiteBits) ->
    [
        "fn reduction_apply_complete_aggregate(\n",
        "    state: ReductionState, aggregate: ReductionAggregate)\n",
        "    -> ReductionApply {\n",
        "  if !aggregate.valid {\n",
        "    ReductionApply {\n",
        "      state, outcome: ReductionOutcome::NOT_CANDIDATE }\n",
        "  } else if state.status != ReductionStatus::OPEN ||\n",
        "      state.site as uN[", integer_to_list(SiteBits),
        "] != aggregate.site ||\n",
        "      state.key != aggregate.key {\n",
        "    ReductionApply { state, outcome: ReductionOutcome::MISMATCH }\n",
        "  } else {\n",
        "    let population = reduction_site_population(state.site);\n",
        "    let fresh = state.remaining == population &&\n",
        "      state.seen == zero!<ReductionMembers>();\n",
        "    let full = aggregate.count == population;\n",
        "    let member_mode = reduction_site_mode(state.site) ==\n",
        "      ReductionMode::MEMBERS;\n",
        "    let members_ok = aggregate.seen ==\n",
        "      reduction_aggregate_expected_members(state.site);\n",
        "    if aggregate.failed || !fresh || !full {\n",
        "      ReductionApply { state, outcome: ReductionOutcome::MISMATCH }\n",
        "    } else if !members_ok {\n",
        "      ReductionApply { state,\n",
        "        outcome: ReductionOutcome::UNEXPECTED_MEMBER }\n",
        "    } else {\n",
        "      let next_state = ReductionState {\n",
        "        status: ReductionStatus::COMPLETE,\n",
        "        remaining: ReductionRemaining:0,\n",
        "        seen: if member_mode { aggregate.seen }\n",
        "          else { state.seen },\n",
        "        accumulator: aggregate.accumulator,\n",
        "        ..state\n",
        "      };\n",
        "      ReductionApply {\n",
        "        state: next_state, outcome: ReductionOutcome::COMPLETE }\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

require_aggregate_contributions(Contributions) ->
    Nontransportable = [
        #{phase => maps:get(phase, Site),
          schema => maps:get(tag, Contribution)}
        || {Site, Contribution} <- Contributions,
           maps:get(source_transportable, Contribution) =/= true
    ],
    case Nontransportable of
        [] -> ok;
        _ -> error({aggregate_only_nontransportable_contributions,
            Nontransportable})
    end,
    Tags = [maps:get(tag, Contribution)
        || {_Site, Contribution} <- Contributions],
    case duplicate_values(Tags) of
        [] -> ok;
        Duplicates -> error({aggregate_only_ambiguous_contribution_schemas,
            Duplicates})
    end.

apply_function() ->
    [
        "fn reduction_apply(\n",
        "    state: ReductionState,\n",
        "    contribution: ReductionContribution) -> ReductionApply {\n",
        "  if !contribution.valid {\n",
        "    ReductionApply {\n",
        "      state, outcome: ReductionOutcome::NOT_CANDIDATE }\n",
        "  } else if state.status != ReductionStatus::OPEN ||\n",
        "      state.site != contribution.site ||\n",
        "      state.key != contribution.key {\n",
        "    ReductionApply {\n",
        "      state, outcome: ReductionOutcome::MISMATCH }\n",
        "  } else {\n",
        "    let member_bit = reduction_member_bit(\n",
        "      state.site, contribution.member);\n",
        "    let member_mode = reduction_site_mode(state.site) ==\n",
        "      ReductionMode::MEMBERS;\n",
        "    let unexpected = member_mode &&\n",
        "      member_bit == zero!<ReductionMembers>();\n",
        "    let duplicate = member_mode &&\n",
        "      (state.seen & member_bit) != zero!<ReductionMembers>();\n",
        "    if unexpected {\n",
        "      ReductionApply { state,\n",
        "        outcome: ReductionOutcome::UNEXPECTED_MEMBER }\n",
        "    } else if duplicate {\n",
        "      ReductionApply { state,\n",
        "        outcome: ReductionOutcome::DUPLICATE_MEMBER }\n",
        "    } else {\n",
        "      let remaining = state.remaining - ReductionRemaining:1;\n",
        "      let complete = remaining == ReductionRemaining:0;\n",
        "      let next_state = ReductionState {\n",
        "        status: if complete { ReductionStatus::COMPLETE }\n",
        "          else { ReductionStatus::OPEN },\n",
        "        remaining,\n",
        "        seen: if member_mode { state.seen | member_bit }\n",
        "          else { state.seen },\n",
        "        accumulator: reduction_reduce(\n",
        "          reduction_site_name(state.site),\n",
        "          state.accumulator, contribution.value),\n",
        "        ..state\n",
        "      };\n",
        "      ReductionApply {\n",
        "        state: next_state,\n",
        "        outcome: if complete { ReductionOutcome::COMPLETE }\n",
        "          else { ReductionOutcome::PENDING },\n",
        "      }\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

completion_function(#{
    data := #{dslx_type := DataType},
    accumulator := #{dslx_type := AccumulatorType},
    sites := Sites
}) ->
    [
        "fn reduction_dispatch_completion(\n",
        "    state: ReductionState, phase: Phase, data: ", DataType,
        ") -> ReductionDispatch {\n",
        "  if state.status != ReductionStatus::COMPLETE {\n",
        "    ReductionDispatch { reduction: state, phase, data,\n",
        "      ..zero!<ReductionDispatch>() }\n",
        "  } else {\n",
        "    let key = state.key;\n",
        "    let accumulator: ", AccumulatorType,
        " = state.accumulator;\n",
        "    match (state.site, phase) {\n",
        [completion_arm(Site) || Site <- Sites],
        "      _ => ReductionDispatch {\n",
        "        reduction: zero!<ReductionState>(),\n",
        "        phase, data, directive: Directive::FAIL,\n",
        "        failure: hls_failure::REDUCTION_PROTOCOL,\n",
        "        dispatched: u1:1,\n",
        "        ..zero!<ReductionDispatch>()\n",
        "      },\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

completion_arm(Site = #{
    phase := Phase,
    completion := #{body := Body, result := Result}
}) ->
    [
        "      (ReductionSite::", site_label(Site), ", Phase::",
        uppercase(Phase), ") => {\n",
        "        let conclusion = {\n",
        xls_parse_io:indent(Body, 10),
        "          ", Result, "\n",
        "        };\n",
        "        ReductionDispatch {\n",
        "          reduction: zero!<ReductionState>(),\n",
        "          phase: conclusion.0,\n",
        "          data: conclusion.1,\n",
        "          directive: conclusion.2,\n",
        "          repeat_phase: conclusion.3,\n",
        "          failure: conclusion.4,\n",
        "          dispatched: u1:1,\n",
        "        }\n",
        "      },\n"
    ].

site_contributions(Sites) ->
    lists:append([
        [{Site, Contribution}
            || Contribution <- maps:get(contributions, Site)]
        || Site <- Sites
    ]).

member_arms(Sites, MemberBits) ->
    lists:append([
        member_site_arms(Site, MemberBits)
        || Site <- Sites
    ]).

member_site_arms(Site = #{
    population := #{mode := members, members := Members}
}, MemberBits) ->
    [
        [
            "    (ReductionSite::", site_label(Site), ", u32:",
            integer_to_list(Member), ") =>\n",
            "      (uN[", integer_to_list(MemberBits),
            "]:1 << u32:", integer_to_list(Index),
            ") as ReductionMembers,\n"
        ]
        || {Index, Member} <- lists:enumerate(0, Members)
    ];
member_site_arms(_Site, _MemberBits) ->
    [].

duplicate_values(Values) ->
    duplicate_values(Values, #{}, #{}).

duplicate_values([], _Seen, Duplicates) ->
    lists:sort(maps:keys(Duplicates));
duplicate_values([Value | Rest], Seen, Duplicates) ->
    case maps:is_key(Value, Seen) of
        true -> duplicate_values(Rest, Seen, Duplicates#{Value => true});
        false -> duplicate_values(Rest, Seen#{Value => true}, Duplicates)
    end.

mode_value(count) -> "ReductionMode::COUNT";
mode_value(members) -> "ReductionMode::MEMBERS".

site_label(#{phase := Phase}) ->
    uppercase(Phase).

uppercase(Atom) ->
    string:uppercase(atom_to_list(Atom)).

record_function_name(Atom) ->
    lists:delete($_, atom_to_list(Atom)).
