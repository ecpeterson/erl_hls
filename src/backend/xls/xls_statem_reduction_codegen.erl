%%%% xls_statem_reduction_codegen
%%%%
%%%% Renders the private, actor-specific DSLX support for one active bounded
%%%% reduction.  The analyzer and Erlang syntax lowering live in
%%%% xls_statem_reduction_lower; this module only accepts closed, typed
%%%% renderer data.

-module(xls_statem_reduction_codegen).
-moduledoc false.

-export([
    declarations/1,
    emit/1,
    functions/1,
    private_width/1,
    tag_member/2
]).

-type lowered() :: #{
    body := iodata(),
    result := iodata()
}.
-type population() ::
    #{mode := count, size := 1..255} |
    #{mode := members, size := 1..255, members := [non_neg_integer(), ...]}.
-type open() :: #{
    phase := atom(),
    name := atom(),
    site := non_neg_integer(),
    population := population(),
    key := lowered(),
    identity := lowered()
}.
-type contribution() :: #{
    phase := atom(),
    tag := atom(),
    name := atom(),
    site := non_neg_integer(),
    mode := count | members,
    build := lowered()
}.
-type completion() :: #{
    phase := atom(),
    name := atom(),
    site := non_neg_integer(),
    body := iodata(),
    result := iodata()
}.
-type reducer() :: #{
    name := atom(),
    body := iodata(),
    result := iodata()
}.
-type spec() :: none | #{
    data := #{name := atom(), dslx_type := iodata()},
    accumulator := #{
        name := atom(),
        dslx_type := iodata(),
        width := pos_integer()
    },
    storage_width := pos_integer(),
    opens := [open(), ...],
    contributions := [contribution(), ...],
    completions := [completion(), ...],
    reducers := [reducer(), ...]
}.

-spec emit(spec()) -> iolist().
emit(Spec) ->
    [declarations(Spec), functions(Spec)].

-spec declarations(spec()) -> iolist().
declarations(none) ->
    [];
declarations(Spec = #{
    data := #{dslx_type := DataType},
    accumulator := #{dslx_type := AccumulatorType},
    opens := Opens
}) ->
    ok = validate_metadata(Spec),
    Names = reduction_names(Spec),
    MemberWidth = member_width(Opens),
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
            ["  ", uppercase(Name), " = u8:", integer_to_list(Index),
                ",\n"]
            || {Index, Name} <- lists:enumerate(0, Names)
        ],
        "}\n\n",
        "enum ReductionSite : u8 {\n",
        [
            ["  ", site_label(Open), " = u8:",
                integer_to_list(maps:get(site, Open)), ",\n"]
            || Open <- Opens
        ],
        "}\n\n",
        "type ReductionMembers = bits[", integer_to_list(MemberWidth),
        "];\n\n",
        "struct ReductionState {\n",
        "  status: ReductionStatus,\n",
        "  site: ReductionSite,\n",
        "  key: u32,\n",
        "  remaining: u8,\n",
        "  seen: ReductionMembers,\n",
        "  accumulator: ", AccumulatorType, ",\n",
        "}\n\n",
        "struct ReductionContribution {\n",
        "  valid: u1,\n",
        "  site: ReductionSite,\n",
        "  mode: ReductionMode,\n",
        "  key: u32,\n",
        "  member: u32,\n",
        "  value: ", AccumulatorType, ",\n",
        "}\n\n",
        "enum ReductionOutcome : u3 {\n",
        "  NOT_CANDIDATE = u3:0,\n",
        "  MISMATCH = u3:1,\n",
        "  PENDING = u3:2,\n",
        "  COMPLETE = u3:3,\n",
        "  WRONG_MODE = u3:4,\n",
        "  UNEXPECTED_MEMBER = u3:5,\n",
        "  DUPLICATE_MEMBER = u3:6,\n",
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
        "  dispatched: u1,\n",
        "}\n\n"
    ].

-spec functions(spec()) -> iolist().
functions(none) ->
    [];
functions(Spec) ->
    ok = validate_metadata(Spec),
    [
        codec_functions(Spec),
        site_functions(Spec),
        open_functions(Spec),
        contribution_functions(Spec),
        reducer_function(Spec),
        apply_function(),
        completion_functions(Spec)
    ].

-spec private_width(spec()) -> non_neg_integer().
private_width(none) ->
    0;
private_width(#{
    accumulator := #{width := AccumulatorWidth},
    storage_width := DeclaredWidth,
    opens := Opens
}) ->
    %% status + site + key + remaining + seen + accumulator
    ComputedWidth = 2 + 8 + 32 + 8 + member_width(Opens) +
        AccumulatorWidth,
    case DeclaredWidth of
        ComputedWidth -> ComputedWidth;
        _ -> error({inconsistent_reduction_storage_width,
            DeclaredWidth, ComputedWidth})
    end.

%% The private accumulator participates in xls_parse's record-value tagged
%% representation, but it is not a public wire schema.  The caller inserts
%% this member at the end of the module's existing Tag declaration.
-spec tag_member(spec(), non_neg_integer()) -> iolist().
tag_member(none, _Selector) ->
    [];
tag_member(#{accumulator := #{name := Name}}, Selector)
        when Selector >= 0, Selector =< 255 ->
    ["  ", uppercase(Name), " = u8:", integer_to_list(Selector), ",\n"].

codec_functions(Spec = #{
    accumulator := #{
        name := AccumulatorName,
        width := AccumulatorWidth
    }
}) ->
    MemberWidth = member_width(maps:get(opens, Spec)),
    SeenStart = 50,
    AccumulatorStart = SeenStart + MemberWidth,
    TotalWidth = AccumulatorStart + AccumulatorWidth,
    AccumulatorFunction = record_function_name(AccumulatorName),
    [
        "fn reduction_state_from_bits(\n",
        "    raw: bits[", integer_to_list(TotalWidth),
        "]) -> ReductionState {\n",
        "  ReductionState {\n",
        "    status: raw[0:2] as ReductionStatus,\n",
        "    site: raw[2:10] as ReductionSite,\n",
        "    key: raw[10:42] as u32,\n",
        "    remaining: raw[42:50] as u8,\n",
        "    seen: raw[50:", integer_to_list(AccumulatorStart),
        "] as ReductionMembers,\n",
        "    accumulator: ", AccumulatorFunction,
        "_from_bits(raw[", integer_to_list(AccumulatorStart), ":",
        integer_to_list(TotalWidth), "]),\n",
        "  }\n",
        "}\n\n",
        "fn bits_from_reduction_state(\n",
        "    state: ReductionState) -> bits[",
        integer_to_list(TotalWidth), "] {\n",
        "  bits_from_", AccumulatorFunction, "(state.accumulator) ++\n",
        "    (state.seen as bits[", integer_to_list(MemberWidth), "]) ++\n",
        "    (state.remaining as bits[8]) ++\n",
        "    (state.key as bits[32]) ++\n",
        "    (state.site as bits[8]) ++\n",
        "    (state.status as bits[2])\n",
        "}\n\n"
    ].

site_functions(#{opens := Opens}) ->
    MemberWidth = member_width(Opens),
    [
        "fn reduction_site_name(site: ReductionSite) -> ReductionName {\n",
        "  match site {\n",
        [
            ["    ReductionSite::", site_label(Open), " => ",
                "ReductionName::", uppercase(maps:get(name, Open)), ",\n"]
            || Open <- Opens
        ],
        "  }\n",
        "}\n\n",
        "fn reduction_site_mode(site: ReductionSite) -> ReductionMode {\n",
        "  match site {\n",
        [
            ["    ReductionSite::", site_label(Open), " => ",
                mode_value(maps:get(mode, maps:get(population, Open))),
                ",\n"]
            || Open <- Opens
        ],
        "  }\n",
        "}\n\n",
        "fn reduction_site_population(site: ReductionSite) -> u8 {\n",
        "  match site {\n",
        [
            ["    ReductionSite::", site_label(Open), " => u8:",
                integer_to_list(maps:get(size, maps:get(population, Open))),
                ",\n"]
            || Open <- Opens
        ],
        "  }\n",
        "}\n\n",
        "fn reduction_member_bit(\n",
        "    site: ReductionSite, member: u32) -> ReductionMembers {\n",
        "  match (site, member) {\n",
        member_arms(Opens, MemberWidth),
        "    _ => zero!<ReductionMembers>(),\n",
        "  }\n",
        "}\n\n"
    ].

open_functions(#{
    data := #{dslx_type := DataType},
    accumulator := #{dslx_type := AccumulatorType},
    opens := Opens
}) ->
    [
        "fn reduction_phase_opens(phase: Phase) -> u1 {\n",
        "  match phase {\n",
        [
            ["    Phase::", uppercase(maps:get(phase, Open)),
                " => u1:1,\n"]
            || Open <- Opens
        ],
        "    _ => u1:0,\n",
        "  }\n",
        "}\n\n",
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
        "fn reduction_open(\n",
        "    old_phase: Phase, phase: Phase, data: ", DataType,
        ") -> ReductionState {\n",
        "  match phase {\n",
        [open_arm(Open) || Open <- Opens],
        "    _ => zero!<ReductionState>(),\n",
        "  }\n",
        "}\n\n"
    ].

open_arm(Open = #{
    phase := Phase,
    key := #{body := KeyBody, result := KeyResult},
    identity := #{body := IdentityBody, result := IdentityResult}
}) ->
    [
        "    Phase::", uppercase(Phase), " => {\n",
        "      let key = {\n",
        xls_parse_io:indent(KeyBody, 8),
        "        ", KeyResult, "\n",
        "      };\n",
        "      let identity = {\n",
        xls_parse_io:indent(IdentityBody, 8),
        "        ", IdentityResult, "\n",
        "      };\n",
        "      reduction_open_site(ReductionSite::", site_label(Open),
        ", key, identity)\n",
        "    },\n"
    ].

contribution_functions(#{
    data := #{dslx_type := DataType},
    accumulator := #{dslx_type := AccumulatorType},
    contributions := Contributions
}) ->
    Tags = ordered_unique([maps:get(tag, Contribution)
        || Contribution <- Contributions]),
    [
        "fn reduction_contribution(\n",
        "    frame: axis::Frame, phase: Phase, data: ", DataType,
        ") -> ReductionContribution {\n",
        "  match frame.header.op as Tag {\n",
        [contribution_tag_arm(Tag, Contributions, AccumulatorType)
            || Tag <- Tags],
        "    _ => zero!<ReductionContribution>(),\n",
        "  }\n",
        "}\n\n"
    ].

contribution_tag_arm(Tag, Contributions, AccumulatorType) ->
    Groups = [Contribution
        || Contribution <- Contributions,
           maps:get(tag, Contribution) =:= Tag],
    [
        "    Tag::", uppercase(Tag), " => {\n",
        "      let message = ", record_function_name(Tag),
        "_from_bits(frame.payload);\n",
        "      match phase {\n",
        [contribution_phase_arm(Group, AccumulatorType) || Group <- Groups],
        "        _ => zero!<ReductionContribution>(),\n",
        "      }\n",
        "    },\n"
    ].

contribution_phase_arm(Contribution = #{
    phase := Phase,
    mode := Mode,
    build := #{body := Body, result := Result}
}, _AccumulatorType) ->
    [
        "        Phase::", uppercase(Phase), " => {\n",
        "          let built = {\n",
        xls_parse_io:indent(Body, 12),
        "            ", Result, "\n",
        "          };\n",
        "          ReductionContribution {\n",
        "            valid: built.0,\n",
        "            site: ReductionSite::", site_label(Contribution),
        ",\n",
        "            mode: ", mode_value(Mode), ",\n",
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
        "  } else if reduction_site_mode(state.site) != contribution.mode {\n",
        "    ReductionApply {\n",
        "      state, outcome: ReductionOutcome::WRONG_MODE }\n",
        "  } else {\n",
        "    let member_bit = reduction_member_bit(\n",
        "      state.site, contribution.member);\n",
        "    let member_mode = contribution.mode == ReductionMode::MEMBERS;\n",
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
        "      let remaining = state.remaining - u8:1;\n",
        "      let complete = remaining == u8:0;\n",
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

completion_functions(#{
    data := #{dslx_type := DataType},
    accumulator := #{dslx_type := AccumulatorType},
    completions := Completions
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
        [completion_arm(Completion) || Completion <- Completions],
        "      _ => ReductionDispatch {\n",
        "        reduction: zero!<ReductionState>(),\n",
        "        phase, data, directive: Directive::FAIL,\n",
        "        dispatched: u1:1,\n",
        "        ..zero!<ReductionDispatch>()\n",
        "      },\n",
        "    }\n",
        "  }\n",
        "}\n\n"
    ].

completion_arm(#{
    phase := Phase,
    body := Body,
    result := Result
} = Completion) ->
    [
        "      (ReductionSite::", site_label(Completion), ", Phase::",
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
        "          dispatched: u1:1,\n",
        "        }\n",
        "      },\n"
    ].

member_arms(Opens, MemberWidth) ->
    lists:append([
        member_site_arms(Open, MemberWidth)
        || Open <- Opens
    ]).

member_site_arms(Open = #{population := #{mode := members,
        members := Members}}, MemberWidth) ->
    [
        [
            "    (ReductionSite::", site_label(Open), ", u32:",
            integer_to_list(Member), ") =>\n",
            "      (uN[", integer_to_list(MemberWidth), "]:1 << u32:",
            integer_to_list(Index), ") as ReductionMembers,\n"
        ]
        || {Index, Member} <- lists:enumerate(0, Members)
    ];
member_site_arms(_Open, _MemberWidth) ->
    [].

member_width(Opens) ->
    max(1, lists:max([0 | [
        maps:get(size, Population)
        || #{population := Population = #{mode := members}} <- Opens
    ]])).

reduction_names(#{opens := Opens}) ->
    ordered_unique([maps:get(name, Open) || Open <- Opens]).

ordered_unique(Values) ->
    ordered_unique(Values, #{}, []).

ordered_unique([], _Seen, Reversed) ->
    lists:reverse(Reversed);
ordered_unique([Value | Rest], Seen, Reversed) ->
    case maps:is_key(Value, Seen) of
        true -> ordered_unique(Rest, Seen, Reversed);
        false -> ordered_unique(Rest, Seen#{Value => true}, [Value | Reversed])
    end.

validate_metadata(#{
    opens := Opens,
    contributions := Contributions,
    completions := Completions,
    reducers := Reducers
}) ->
    ok = require_unique(open_phase,
        [maps:get(phase, Open) || Open <- Opens]),
    ok = require_unique(open_site,
        [maps:get(site, Open) || Open <- Opens]),
    ok = require_unique(contribution_phase_tag, [
        {maps:get(phase, Contribution), maps:get(tag, Contribution)}
        || Contribution <- Contributions
    ]),
    ok = require_unique(completion_phase_site, [
        {maps:get(phase, Completion), maps:get(site, Completion)}
        || Completion <- Completions
    ]),
    ok = require_unique(reducer_name,
        [maps:get(name, Reducer) || Reducer <- Reducers]),
    lists:foreach(fun validate_population/1, Opens),
    ok.

validate_population(#{population := #{mode := count, size := Size}})
        when Size >= 1, Size =< 255 ->
    ok;
validate_population(#{population := #{
    mode := members,
    size := Size,
    members := Members
}}) when Size >= 1, Size =< 255 ->
    case length(Members) =:= Size andalso
            length(lists:usort(Members)) =:= Size of
        true -> ok;
        false -> error({invalid_reduction_codegen_population, Members})
    end.

require_unique(Kind, Values) ->
    case length(Values) =:= length(lists:usort(Values)) of
        true -> ok;
        false -> error({duplicate_reduction_codegen, Kind, Values})
    end.

mode_value(count) -> "ReductionMode::COUNT";
mode_value(members) -> "ReductionMode::MEMBERS".

site_label(#{phase := Phase}) ->
    uppercase(Phase).

uppercase(Atom) ->
    string:uppercase(atom_to_list(Atom)).

record_function_name(Atom) ->
    lists:delete($_, atom_to_list(Atom)).
