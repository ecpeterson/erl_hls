-module(xls_reduction_codegen).
-moduledoc "Source-fragment aggregate DSLX used by scheduler actor and topology rendering. Consumes the compiler reduction IR; ordinary callback reduction semantics remain compiler-owned.".
%% Aggregate declarations and actor-side application.
-export([declarations/2, functions/2]).

%% Producer-side contribution rendering.
-export([transport_function/1, transport_function/2]).

%% Validated actor rendering input; extra annotations belong to the selected execution backend.
-type spec() :: none | xls_statem_reduction_ir:reduction().

-doc "Defines transport aggregates only for source-fragment placement.".
-spec declarations(spec(), ordinary | aggregate_only) -> iodata().
declarations(_, ordinary) -> [];
declarations(none, aggregate_only) -> error(aggregate_only_requires_reductions);
declarations(Spec = #{accumulator := #{dslx_type := Type}}, aggregate_only) ->
    #{site_bits := Site, remaining_bits := Remaining, member_bits := Member} = xls_statem_reduction_ir:layout(Spec),
    ok = require_fixed_membership(Spec),
    aggregate_declarations(aggregate_only, Site, Remaining, Member, Type).
-doc "Renders transport aggregation around the actor's common reduction functions.".
-spec functions(spec(), ordinary | aggregate_only) -> xls_dslx:value().
functions(_, ordinary) -> [];
functions(none, aggregate_only) -> error(aggregate_only_requires_reductions);
functions(Spec, aggregate_only) ->
    ok = require_fixed_membership(Spec),
    aggregate_functions(aggregate_only, Spec).

%% Defines bounded aggregate values and their destination-slot envelope.
-spec aggregate_declarations('aggregate_only',pos_integer(),pos_integer(),1 .. ((1 bsl 8) - 1),term()) -> iodata().
aggregate_declarations(aggregate_only, SiteBits, RemainingBits, MemberBits,
        AccumulatorType) ->
    [
        "pub struct ReductionAggregate {\n",
        "  valid: u1,\n",
        "  failure: hls_failure::Code,\n",
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

%% Renders aggregate capture, combination and actor-state application.
-spec aggregate_functions('aggregate_only',map()) -> xls_dslx:value().
aggregate_functions(aggregate_only, Spec) ->
    SiteBits = xls_statem_reduction_ir:site_width(Spec),
    [
        transport_function(Spec),
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

-doc "Builds a checked contribution using only the frame, rejecting state-dependent source clauses.".
-spec transport_function(map()) -> xls_dslx:value().
transport_function(#{sites := Sites}) ->
    Contributions = xls_statem_reduction_codegen:site_contributions(Sites),
    ok = require_aggregate_contributions(Contributions),
    transport_text(Contributions).

-doc "Uses a message-only lift under an explicit exclusive protocol assertion; ordinary actor patterns remain checked.".
-spec transport_function(map(), exclusive_epoch) -> xls_dslx:value().
transport_function(#{sites := Sites}, exclusive_epoch) ->
    Lift = fun(C) ->
        case maps:get(independent_lift, C, maps:get(transport, C)) of
            none -> error({exclusive_epoch_state_dependent_guard, maps:get(tag, C)});
            Expression -> C#{transport := Expression}
        end
    end,
    Contributions = [{Site, Lift(C)} || Site <- Sites, C <- maps:get(contributions, Site)],
    case duplicate_values([maps:get(tag, C) || {_, C} <- Contributions]) of
        [] -> transport_text(Contributions);
        Tags -> error({exclusive_epoch_ambiguous_contribution_schemas, Tags})
    end.

%% Both checked and asserted placements use the same lowered expression renderer.
-spec transport_text([{map(), map()}]) -> xls_dslx:value().
transport_text(Contributions) ->
    ["fn reduction_transport_contribution(\n    frame: axis::Frame) -> ReductionContribution {\n",
     "  match frame.header.op as Tag {\n",
     [transport_contribution_arm(C) || C <- Contributions],
     "    _ => zero!<ReductionContribution>(),\n  }\n}\n\n"].

%% Classifies a frame and constructs its state-independent contribution.
-spec transport_contribution_arm({map(),map()}) -> xls_dslx:value().
transport_contribution_arm({Site, #{
    tag := Tag,
    transport := #{body := Body, result := Result}
}}) ->
    [
        "    Tag::", xls_names:enum_member(Tag), " => {\n",
        "      let message = ", xls_names:record_codec(Tag),
        "_from_bits(frame.payload);\n",
        "      let built = {\n",
        xls_dslx:indent(Body, 8),
        "        ", Result, "\n",
        "      };\n",
        "      ReductionContribution {\n",
        "        valid: built.0,\n",
        "        site: ReductionSite::", xls_names:enum_member(maps:get(phase, Site)), ",\n",
        "        key: built.1,\n",
        "        member: built.2,\n",
        "        value: built.3,\n",
        "      }\n",
        "    },\n"
    ].

%% Returns the participant mask required by each fixed-member site.
-spec aggregate_expected_members_function(map()) -> iodata().
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

%% Encodes one site's fixed-member population mask.
-spec aggregate_expected_members_arm(map(),1 .. ((1 bsl 8) - 1)) -> [string(),...].
aggregate_expected_members_arm(Site = #{
    population := #{mode := members, size := Size}
}, MemberBits) ->
    [
        "    ReductionSite::", xls_names:enum_member(maps:get(phase, Site)), " => uN[",
        integer_to_list(MemberBits), "]:",
        integer_to_list((1 bsl Size) - 1), " as ReductionMembers,\n"
    ];
aggregate_expected_members_arm(Site, _MemberBits) ->
    [
        "    ReductionSite::", xls_names:enum_member(maps:get(phase, Site)),
        " => zero!<ReductionMembers>(),\n"
    ].

%% Combines an accepted contribution while retaining an absorbing failure.
-spec aggregate_push_function(pos_integer()) -> [string(),...].
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
        "  let accepted = contribution.valid &&\n",
        "    same_window && within_population && !unexpected && !duplicate;\n",
        "  // A failed fold still drains its population. Its first failure\n",
        "  // absorbs later values without evaluating the reducer again.\n",
        "  let (accumulator, reduced_failure) =\n",
        "    if accepted && !first && !hls_failure::failed(aggregate.failure) {\n",
        "      reduction_reduce(reduction_site_name(contribution.site),\n",
        "        aggregate.accumulator, contribution.value)\n",
        "    } else { (contribution.value, hls_failure::NONE) };\n",
        "  let failure = hls_failure::first(aggregate.failure,\n",
        "    if accepted { reduced_failure } else { hls_failure::REDUCTION_PROTOCOL });\n",
        "  ReductionAggregate {\n",
        "    valid: u1:1,\n",
        "    failure,\n",
        "    site: if first { contribution.site as uN[",
        integer_to_list(SiteBits), "] } else { aggregate.site },\n",
        "    key: if first { contribution.key } else { aggregate.key },\n",
        "    count: if accepted {\n",
        "      aggregate.count + ReductionRemaining:1\n",
        "    } else { aggregate.count },\n",
        "    seen: if accepted && member_mode {\n",
        "      aggregate.seen | member_bit\n",
        "    } else { aggregate.seen },\n",
        "    accumulator: if accepted && !hls_failure::failed(failure) {\n",
        "      accumulator\n",
        "    } else { aggregate.accumulator },\n",
        "  }\n",
        "}\n\n"
    ].

%% Applies a complete aggregate to the recipient's open reduction window.
-spec aggregate_apply_function(pos_integer()) -> [string(),...].
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
        "    if !fresh || !full {\n",
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
        "        failure: aggregate.failure,\n",
        "        ..state\n",
        "      };\n",
        "      ReductionApply {\n",
        "        state: next_state, outcome: ReductionOutcome::COMPLETE }\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

%% Rejects missing, state-dependent or ambiguous transport contributions.
-spec require_aggregate_contributions([any()]) -> 'ok'.
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

%% Returns repeated values once, using exact map-key equality.
-spec duplicate_values([Value]) -> [Value].
duplicate_values(Values) ->
    duplicate_values(Values, #{}, #{}).

%% Returns repeated values once, using exact map-key equality.
-spec duplicate_values([Value], #{Value => true}, #{Value => true}) -> [Value].
duplicate_values([], _Seen, Duplicates) ->
    lists:sort(maps:keys(Duplicates));
duplicate_values([Value | Rest], Seen, Duplicates) ->
    case maps:is_key(Value, Seen) of
        true -> duplicate_values(Rest, Seen, Duplicates#{Value => true});
        false -> duplicate_values(Rest, Seen#{Value => true}, Duplicates)
    end.

%% The existing source-fragment engine has no input for the destination's opening mask.
-spec require_fixed_membership(map()) -> ok.
require_fixed_membership(Spec) ->
    case xls_statem_reduction_ir:has_runtime_members(Spec) of
        false -> ok;
        true -> error(aggregate_only_runtime_membership)
    end.
