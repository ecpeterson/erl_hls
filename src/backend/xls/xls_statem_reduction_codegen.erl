-module(xls_statem_reduction_codegen).
-moduledoc false.
-export([declarations/1, functions/1, private_width/1, tag_member/2, site_contributions/1]).
-type spec() :: none | xls_statem_reduction_ir:reduction().


-doc "Defines private reduction storage around the declared accumulator type.".
-spec declarations(spec()) -> iolist().
declarations(Spec) ->
    declarations_value(Spec).

%% Emits reduction types only when the actor has a reduction site.
-spec declarations_value(spec()) -> iolist().
declarations_value(none) ->
    [];
declarations_value(Spec = #{
    data := #{dslx_type := DataType},
    accumulator := #{dslx_type := AccumulatorType},
    sites := Sites,
    reducers := Reducers
}) ->
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
            ["  ", xls_names:enum_member(maps:get(name, Reducer)), " = u8:",
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
        runtime_members(Spec, "  expected: ReductionMembers,\n"),
        "  accumulator: ", AccumulatorType, ",\n",
        "  failure: hls_failure::Code,\n",
        "}\n\n",
        "struct ReductionContribution {\n",
        "  valid: u1,\n",
        "  site: ReductionSite,\n",
        "  key: u32,\n",
        "  member: u32,\n",
        "  value: ", AccumulatorType, ",\n",
        "}\n\n",
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
        "  next_event: u8,\n",
        "  reduction: ReductionState,\n",
        "  phase: Phase,\n",
        "  data: ", DataType, ",\n",
        "  directive: Directive,\n",
        "  repeat_phase: u1,\n",
        "  failure: hls_failure::Code,\n",
        "  dispatched: u1,\n",
        "}\n\n"
    ].

-doc "Renders opening, contribution and completion semantics for actor-owned reductions.".
-spec functions(spec()) -> iolist().
functions(Spec) ->
    functions_value(Spec).

%% Omits reduction operations for actors without a reduction site.
-spec functions_value(spec()) -> iolist().
functions_value(none) ->
    [];
functions_value(Spec) ->
    [
        codec_functions(Spec),
        site_functions(Spec),
        open_functions(Spec),
        contribution_functions(Spec),
        reducer_function(Spec),
        apply_function(Spec),
        completion_function(Spec)
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
    ["  ", xls_names:enum_member(Name), " = u8:", integer_to_list(Selector), ",\n"].

%% Encode and decode exactly the optional member-mask storage described by the IR.
-spec codec_functions(map()) -> iodata().
codec_functions(Spec = #{accumulator := #{name := AccumulatorName}}) ->
    Layout = xls_statem_reduction_ir:layout(Spec),
    SiteBits = maps:get(site_bits, Layout),
    RemainingBits = maps:get(remaining_bits, Layout),
    MemberBits = maps:get(member_bits, Layout),
    TotalBits = maps:get(total_bits, Layout),
    StatusBits = maps:get(status_bits, Layout),
    #{site := #{offset := SiteStart}, key := #{offset := KeyStart},
        remaining := #{offset := RemainingStart}, seen := #{offset := MemberStart},
        expected := #{offset := ExpectedStart}, accumulator := #{offset := AccumulatorStart}, failure := #{offset := FailureStart}} =
        xls_statem_reduction_ir:packed_layout(Spec),
    AccumulatorFunction = xls_names:record_codec(AccumulatorName),
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
        integer_to_list(ExpectedStart), "] as ReductionMembers,\n",
        runtime_members(Spec, ["    expected: raw[", integer_to_list(ExpectedStart), ":",
            integer_to_list(AccumulatorStart), "] as ReductionMembers,\n"]),
        "    accumulator: ", AccumulatorFunction, "_from_bits(raw[",
        integer_to_list(AccumulatorStart), ":",
        integer_to_list(FailureStart), "]),\n",
        "    failure: raw[", integer_to_list(FailureStart), ":",
        integer_to_list(TotalBits), "] as hls_failure::Code,\n",
        "  }\n",
        "}\n\n",
        "fn bits_from_reduction_state(\n",
        "    state: ReductionState) -> bits[", integer_to_list(TotalBits),
        "] {\n",
        "  state.failure ++\n",
        "    bits_from_", AccumulatorFunction, "(state.accumulator) ++\n",
        runtime_members(Spec, ["    state.expected ++\n"]),
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
                "ReductionName::", xls_names:enum_member(maps:get(name, Site)), ",\n"]
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

%% Runtime membership adds an expected mask only to actors which use that form.
-spec open_functions(map()) -> iodata().
open_functions(Spec = #{accumulator := #{dslx_type := AccumulatorType}}) ->
    [
        "fn reduction_open_site(\n",
        "    site: ReductionSite, key: u32, identity: ", AccumulatorType,
        runtime_members(Spec, ", expected: ReductionMembers"),
        ") -> ReductionState {\n",
        runtime_members(Spec, [
            "  let population = unroll_for! (index, total): (u32, ReductionRemaining) in u32:0..u32:",
            integer_to_list(xls_statem_reduction_ir:member_width(Spec)), " {\n",
            "    total + ((expected >> index) as u1 as ReductionRemaining)\n",
            "  }(ReductionRemaining:0);\n"]),
        "  ReductionState {\n",
        "    status: ReductionStatus::OPEN,\n",
        "    site,\n",
        "    key,\n",
        case xls_statem_reduction_ir:has_runtime_members(Spec) of
            false -> "    remaining: reduction_site_population(site),\n";
            true -> "    expected,\n"
                "    remaining: if reduction_site_mode(site) == ReductionMode::MEMBERS { population }\n"
                "      else { reduction_site_population(site) },\n"
        end,
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
        "    Tag::", xls_names:enum_member(Tag), " => {\n",
        "      let message = ", xls_names:record_codec(Tag),
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
        "        Phase::", xls_names:enum_member(maps:get(phase, Site)), " => {\n",
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
        ", right: ", AccumulatorType, ") -> (", AccumulatorType,
        ", hls_failure::Code) {\n",
        "  match name {\n",
        [reducer_arm(Reducer) || Reducer <- Reducers],
        "  }\n",
        "}\n\n"
    ].

reducer_arm(#{name := Name, body := Body, result := Result}) ->
    [
        "    ReductionName::", xls_names:enum_member(Name), " => {\n",
        xls_parse_io:indent(Body, 6),
        "      ", Result, "\n",
        "    },\n"
    ].

%% Check an expected runtime mask before accepting any member contribution.
-spec apply_function(map()) -> iodata().
apply_function(Spec) ->
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
        case xls_statem_reduction_ir:has_runtime_members(Spec) of
            false -> "      member_bit == zero!<ReductionMembers>();\n";
            true -> "      (member_bit == zero!<ReductionMembers>() ||\n"
                "       (state.expected & member_bit) == zero!<ReductionMembers>());\n"
        end,
        "    let duplicate = member_mode &&\n",
        "      (state.seen & member_bit) != zero!<ReductionMembers>();\n",
        "    if unexpected {\n",
        "      ReductionApply { state,\n",
        "        outcome: ReductionOutcome::UNEXPECTED_MEMBER }\n",
        "    } else if duplicate {\n",
        "      ReductionApply { state,\n",
        "        outcome: ReductionOutcome::DUPLICATE_MEMBER }\n",
        "    } else {\n",
        "      // Failure is private until every contribution has arrived.\n",
        "      let (accumulator, failure) = if hls_failure::failed(state.failure) {\n",
        "        (state.accumulator, state.failure)\n",
        "      } else {\n",
        "        reduction_reduce(reduction_site_name(state.site),\n",
        "          state.accumulator, contribution.value)\n",
        "      };\n",
        "      let remaining = state.remaining - ReductionRemaining:1;\n",
        "      let complete = remaining == ReductionRemaining:0;\n",
        "      let next_state = ReductionState {\n",
        "        status: if complete { ReductionStatus::COMPLETE }\n",
        "          else { ReductionStatus::OPEN },\n",
        "        remaining,\n",
        "        seen: if member_mode { state.seen | member_bit }\n",
        "          else { state.seen },\n",
        "        accumulator: if hls_failure::failed(failure) { state.accumulator }\n",
        "          else { accumulator },\n",
        "        failure,\n",
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

%% Dispatches only completed scalar folds and carries any declared continuation.
-spec completion_function(map()) -> iodata().
completion_function(#{
    data := #{dslx_type := DataType},
    accumulator := #{dslx_type := AccumulatorType},
    sites := Sites
} = Spec) ->
    [
        "fn reduction_dispatch_completion(\n",
        "    state: ReductionState, phase: Phase, data: ", DataType,
        ") -> ReductionDispatch {\n",
        "  if state.status != ReductionStatus::COMPLETE {\n",
        "    ReductionDispatch { reduction: state, phase, data,\n",
        "      ..zero!<ReductionDispatch>() }\n",
        "  } else if hls_failure::failed(state.failure) {\n",
        "    ReductionDispatch { reduction: state, phase, data,\n",
        "      directive: Directive::FAIL, failure: state.failure,\n",
        "      dispatched: u1:1, ..zero!<ReductionDispatch>() }\n",
        "  } else {\n",
        "    let key = state.key;\n",
        "    let accumulator: ", AccumulatorType,
        " = state.accumulator;\n",
        "    match (state.site, phase) {\n",
        [completion_arm(Site#{completion_events => maps:get(continuations, Spec, []) =/= []}) || Site <- Sites],
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

%% Each source completion owns its selected failure and optional next event.
-spec completion_arm(map()) -> iodata().
completion_arm(Site = #{
    phase := Phase,
    completion := #{body := Body, result := Result}
}) ->
    [
        "      (ReductionSite::", site_label(Site), ", Phase::",
        xls_names:enum_member(Phase), ") => {\n",
        "        let conclusion = {\n",
        xls_parse_io:indent(Body, 10),
        "          ", Result, "\n",
        "        };\n",
        "        ReductionDispatch {\n",
        "          reduction: zero!<ReductionState>(),\n",
        "          next_event: ", case maps:get(completion_events, Site, false) of true -> "conclusion.5"; false -> "u8:0" end, ",\n",
        "          phase: conclusion.0,\n",
        "          data: conclusion.1,\n",
        "          directive: conclusion.2,\n",
        "          repeat_phase: conclusion.3,\n",
        "          failure: conclusion.4,\n",
        "          dispatched: u1:1,\n",
        "        }\n",
        "      },\n"
    ].

-doc "Flattens the checked contribution clauses from all reduction sites.".
-spec site_contributions([map()]) -> [{map(), map()}].
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

mode_value(count) -> "ReductionMode::COUNT";
mode_value(members) -> "ReductionMode::MEMBERS".

site_label(#{phase := Phase}) ->
    xls_names:enum_member(Phase).

%% Static-only actors retain the original private-state fields and widths.
-spec runtime_members(map(), iodata()) -> iodata().
runtime_members(Spec, Text) ->
    case xls_statem_reduction_ir:has_runtime_members(Spec) of true -> Text; false -> [] end.
