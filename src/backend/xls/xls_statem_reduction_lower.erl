%%%% xls_statem_reduction_lower
%%%%
%%%% Recognizes the bounded actor-reduction callback contract. Erlang forms
%%%% remain private to this pass. Full lowering returns the closed, typed IR in
%%%% xls_statem_reduction_ir; parse-transform interface inference stops at a
%%%% structural public summary so it does not execute application transpilers.

-module(xls_statem_reduction_lower).
-moduledoc false.

-export([
    analyze/2,
    analyze_interface/2,
    internal_groups/2,
    split_entry_actions/2, collection_type/2, collection_open/3, collection_contributions/6, normalize_completion/3
]).

-spec split_entry_actions(erl_parse:abstract_expr(), erl_anno:location()) ->
    {none | map(), [erl_parse:abstract_expr()]}.
split_entry_actions(ActionList, Line) ->
    Actions = literal_list(ActionList, Line),
    {Open, Casts} = case Actions of
        [{tuple, _TupleLine, [
            {atom, _OpenLine, open_reduction},
            _Name,
            _Key,
            _Population,
            _Operator
        ]} = Action | Rest] ->
            {parse_open(Action, Line), Rest};
        _ ->
            {none, Actions}
    end,
    case lists:any(fun is_open/1, Casts) of
        true -> error({hls_statem_open_reduction_must_be_first, Line});
        false -> {Open, Casts}
    end.

-doc "Groups internal-event clauses by phase and event tag, preserving source order.".
-spec internal_groups([erl_parse:abstract_clause()], [atom()]) ->
    [{{atom(), atom()}, [erl_parse:abstract_clause(), ...]}].
internal_groups(Clauses, Phases) ->
    xls_callback_lower:group_by(
        Clauses,
        fun(Clause) -> internal_key(Clause, Phases) end
    ).

-doc "Validates reductions and returns closed reducer expressions plus remaining ordinary casts.".
-spec analyze([hls_source:form()], map()) -> #{
    reduction := none | xls_statem_reduction_ir:reduction(),
    cast_groups := list()
}.
analyze(Forms, #{
    phases := Phases,
    data_name := DataName
} = Context) ->
    case analyze_source(Forms, Context) of
        #{reduction := none, cast_groups := OrdinaryCastGroups} ->
            #{reduction => none, cast_groups => OrdinaryCastGroups};
        #{reduction := Source, cast_groups := OrdinaryCastGroups} ->
            AccumulatorName = maps:get(accumulator_name, Source),
            AccumulatorRecord = maps:get(accumulator_record, Source),
            EnumAtoms = enum_atoms(Phases),
            DataType = type_ref(Forms, DataName),
            AccumulatorType = type_ref(AccumulatorRecord),
            Sites = close_sites(
                maps:get(opens, Source),
                maps:get(contributions, Source),
                maps:get(completions, Source),
                DataName,
                AccumulatorName,
                AccumulatorType,
                EnumAtoms
            ),
            ClosedReducers = [close_reducer(
                Reducer,
                DataName,
                AccumulatorName,
                AccumulatorType,
                EnumAtoms
            ) || Reducer <- maps:get(reducers, Source)],
            Reduction0 = xls_statem_reduction_ir:new(
                DataType,
                AccumulatorType,
                Sites,
                ClosedReducers
            ),
            Reduction = case xls_statem_continuation:names(Forms) of
                [] -> Reduction0;
                Names -> Reduction0#{continuations => Names}
            end,
            %% Assert the central boundary of this pass: source forms are
            %% consumed here, while only printable expressions escape.
            ok = assert_closed(Reduction),
            #{
                reduction => Reduction,
                cast_groups => OrdinaryCastGroups
            }
    end;
analyze(_Forms, Context) ->
    error({invalid_hls_statem_reduction_context, Context}).

-doc "Validates and summarizes reduction structure without invoking provider transpilers.".
-spec analyze_interface([hls_source:form()], map()) -> #{
    reduction := none | map(),
    cast_groups := list()
}.
analyze_interface(Forms, Context) ->
    case analyze_source(Forms, Context) of
        #{reduction := none, cast_groups := OrdinaryCastGroups} ->
            #{reduction => none, cast_groups => OrdinaryCastGroups};
        #{reduction := Source, cast_groups := OrdinaryCastGroups} ->
            #{
                reduction => source_interface(Source),
                cast_groups => OrdinaryCastGroups
            }
    end.

%% Interface inference runs inside hls_pack while the source tree is still
%% being compiled. Keep it structural: validating and describing a reduction
%% must not execute hls_type transpilers or the DSLX expression renderer.
-spec analyze_source([hls_source:form()], map()) -> map().
analyze_source(Forms, #{
    phases := _Phases,
    entries := Entries,
    cast_groups := CastGroups,
    internal_groups := InternalGroups,
    message_names := MessageNames,
    data_name := DataName
}) ->
    Opens0 = collect_opens([E || E <- Entries,
        not is_map(maps:get(reduction, E, none)) orelse maps:get(kind, maps:get(reduction, E), reduction) =/= gather]),
    {Contributions0, OrdinaryCastGroups} = split_contributions(CastGroups),
    case Opens0 of
        [] ->
            require_no_orphan_reductions(Contributions0, InternalGroups),
            #{reduction => none, cast_groups => OrdinaryCastGroups};
        _ ->
            Opens = identify_sites(Opens0),
            AccumulatorName = common_accumulator(Opens),
            ok = require_private_accumulator(
                AccumulatorName,
                DataName,
                MessageNames
            ),
            ok = xls_names:reduction(Forms, AccumulatorName, Opens),
            AccumulatorRecord = xls_parse:find_record(
                Forms, AccumulatorName),
            ok = xls_parse:validate_record_defaults(AccumulatorRecord),
            OpenIndex = index_opens(Opens),
            ValidOpens = [validate_open(Open, Forms, DataName)
                || Open <- Opens],
            Shapes = contribution_shapes(Forms, Contributions0),
            Contributions = [
                validate_contribution(
                    Contribution,
                    open_for_contribution(Contribution, OpenIndex),
                    AccumulatorName,
                    Forms,
                    DataName,
                    Shapes
                )
                || Contribution <- Contributions0
            ],
            ok = require_contributions(ValidOpens, Contributions),
            Completions = validate_completions(
                InternalGroups,
                ValidOpens,
                AccumulatorName
            ),
            ok = require_reducer_exported(Forms),
            Reducers = analyze_reducers(
                Forms,
                lists:usort([maps:get(name, Open) || Open <- ValidOpens]),
                AccumulatorName,
                AccumulatorRecord
            ),
            #{
                reduction => #{
                    accumulator_name => AccumulatorName,
                    accumulator_record => AccumulatorRecord,
                    opens => ValidOpens,
                    contributions => Contributions,
                    completions => [C#{continuations => xls_statem_continuation:names(Forms)} || C <- Completions],
                    reducers => Reducers
                },
                cast_groups => OrdinaryCastGroups
            }
    end;
analyze_source(_Forms, Context) ->
    error({invalid_hls_statem_reduction_context, Context}).

%%%
%%% Source recognition
%%%

%% Separate fixed site facts from the values evaluated when its entry executes.
-spec parse_open(erl_parse:abstract_expr(), erl_anno:anno()) -> map().
parse_open(
    {tuple, TupleLine, [
        {atom, _OpenLine, open_reduction},
        {atom, _NameLine, Name},
        Key,
        PopulationExpression,
        {tuple, _OperatorLine, [
            {atom, _MonoidLine, commutative_monoid},
            Identity = {record, _IdentityLine, Accumulator, _Fields}
        ]}
    ]},
    _EntryLine
) ->
    {Population, Mask} = parse_open_population(PopulationExpression),
    #{
        line => TupleLine,
        name => Name,
        key_expression => Key,
        member_mask_expression => Mask,
        population => Population,
        accumulator => Accumulator,
        identity_expression => Identity
    };
parse_open(Action, EntryLine) ->
    error({unsupported_hls_statem_open_reduction, EntryLine, Action}).

%% Keep the runtime mask in the entry program; closed interfaces contain only its bound.
-spec parse_open_population(erl_parse:abstract_expr()) -> {map(), none | erl_parse:abstract_expr()}.
parse_open_population({tuple, _Line, [{atom, _, members_mask}, {integer, _, Width}, Mask]})
        when Width >= 1, Width =< 255 ->
    {#{mode => members, size => Width, members => lists:seq(0, Width - 1), runtime_mask => true}, Mask};
parse_open_population(Expression) -> {parse_population(Expression), none}.

parse_population({tuple, _Line, [
    {atom, _CountLine, count},
    {integer, _ValueLine, Count}
]}) when Count >= 1, Count =< 255 ->
    #{mode => count, size => Count};
parse_population({tuple, Line, [
    {atom, _MembersLine, members},
    MemberList
]}) ->
    Members = [u32_literal(Member, reduction_member)
        || Member <- literal_list(MemberList, Line)],
    case Members =/= [] andalso length(Members) =< 255 andalso
            length(Members) =:= length(lists:usort(Members)) of
        true -> #{mode => members, size => length(Members),
            members => Members};
        false -> error({invalid_hls_statem_reduction_members,
            Line, Members})
    end;
parse_population(Population) ->
    error({unsupported_hls_statem_reduction_population, Population}).

is_open({tuple, _Line, [{atom, _AtomLine, open_reduction} | _]}) -> true;
is_open(_Action) -> false.

collect_opens(Entries) ->
    [
        Open#{
            phase => maps:get(phase, Entry),
            entry_clause => maps:get(clause, Entry)
        }
        || Entry <- Entries,
           Open <- [maps:get(reduction, Entry, none)],
           Open =/= none
    ].

identify_sites(Opens) ->
    [Open#{id => ID} || {ID, Open} <- lists:enumerate(0, Opens)].

index_opens(Opens) ->
    Index = maps:from_list([
        {maps:get(phase, Open), Open} || Open <- Opens
    ]),
    case map_size(Index) =:= length(Opens) of
        true -> Index;
        false -> error({multiple_hls_statem_reductions_per_phase,
            [maps:get(phase, Open) || Open <- Opens]})
    end.

common_accumulator(Opens) ->
    case lists:usort([maps:get(accumulator, Open) || Open <- Opens]) of
        [Accumulator] -> Accumulator;
        Accumulators -> error({inconsistent_hls_statem_reduction_accumulator,
            Accumulators})
    end.

require_private_accumulator(Accumulator, DataName, MessageNames) ->
    case lists:member(Accumulator, [none, error, DataName | MessageNames]) of
        true -> error({nonprivate_hls_statem_reduction_accumulator,
            Accumulator});
        false -> ok
    end.

%% Opening expressions may read actor data; the identity remains a complete constant record.
-spec validate_open(map(), [erl_parse:abstract_form()], atom()) -> map().
validate_open(Open = #{
    key_expression := Key,
    identity_expression := Identity,
    accumulator := Accumulator,
    entry_clause := {clause, _Line,
        [_OldPhase, _Phase, DataPattern], _Guards, _Body}
}, Forms, DataName) ->
    Bindings = pattern_bindings(DataPattern, DataName, data, Forms),
    ok = validate_u32_expression(Key, Bindings, [data]),
    ok = validate_member_mask(Open, Bindings),
    case expression_variables(Identity) of
        [] -> ok;
        Variables -> error({nonconstant_hls_statem_reduction_identity,
            maps:get(line, Open), Variables})
    end,
    Accumulator = record_expression_name(Identity),
    ok = case maps:get(kind, Open, reduction) of
        gather -> ok;
        reduction -> validate_complete_record_expression(Identity,
            xls_parse:find_record(Forms, Accumulator), reduction_identity)
    end,
    Open.

%% Masks are integral literals or direct actor-data reads, so checking them cannot repeat effects.
-spec validate_member_mask(map(), map()) -> ok.
validate_member_mask(#{member_mask_expression := none}, _Bindings) -> ok;
validate_member_mask(#{member_mask_expression := Mask}, Bindings) ->
    require_variable_origins(expression_variables(Mask), Bindings, [data], reduction_member_mask),
    case Mask of
        {integer, _, _} -> ok;
        {var, _, Name} ->
            #{type := Type} = maps:get(Name, Bindings),
            require_mask_type(Type);
        {record_field, _, {var, _, Object}, Record, {atom, _, Field}} ->
            #{type := {record, Record}, fields := Fields} = maps:get(Object, Bindings),
            require_mask_type(maps:get(Field, Fields));
        _ -> error({unsupported_hls_statem_reduction_mask, Mask})
    end.

%% A bounded bit set may use any signed or unsigned integral source width.
-spec require_mask_type(hls_type:descriptor()) -> ok.
require_mask_type({hls_type, hls_nums, Name, _}) when
        Name =:= u8; Name =:= u16; Name =:= u32; Name =:= u64; Name =:= uN;
        Name =:= s8; Name =:= s16; Name =:= s32; Name =:= s64; Name =:= sN -> ok;
require_mask_type(Type) -> error({invalid_hls_statem_reduction_mask_type, Type}).

split_contributions(Groups) ->
    lists:foldl(
        fun({Key, Clauses}, {ContributionAcc, OrdinaryAcc}) ->
            {Found, Ordinary} = split_contribution_group(Key, Clauses),
            NextOrdinary = case Ordinary of
                [] -> OrdinaryAcc;
                _ -> OrdinaryAcc ++ [{Key, Ordinary}]
            end,
            {ContributionAcc ++ Found, NextOrdinary}
        end,
        {[], []},
        Groups
    ).

split_contribution_group({Tag, Phase}, Clauses) ->
    split_contribution_group(Tag, Phase, Clauses, [], [], false).

split_contribution_group(
    _Tag, _Phase, [], Contributions, Ordinary, _SawOrdinary
) ->
    {lists:reverse(Contributions), lists:reverse(Ordinary)};
split_contribution_group(
    Tag, Phase, [Clause | Rest], Contributions, Ordinary, SawOrdinary
) ->
    case contribution_clause(Tag, Phase, Clause) of
        {true, Contribution} when not SawOrdinary ->
            split_contribution_group(
                Tag, Phase, Rest,
                [Contribution | Contributions], Ordinary, false
            );
        {true, _Contribution} ->
            error({nonprefix_hls_statem_reduction_contribution,
                Tag, Phase, element(2, Clause)});
        false ->
            split_contribution_group(
                Tag, Phase, Rest,
                Contributions, [Clause | Ordinary], true
            )
    end.

contribution_clause(
    Tag,
    Phase,
    Clause = {clause, Line,
        [_Message, _Phase, DataPattern], _Guards, Body}
) ->
    {Prefix, Result} = split_last(Body),
    case contribution_result(Result) of
        none ->
            case contains_atom(contribute, Result) of
                true -> error({unsupported_hls_statem_contribution_result,
                    Line, Result});
                false -> false
            end;
        Contribution0 ->
            case Prefix of
                [] -> ok;
                _ -> error({unsupported_hls_statem_contribution_prefix,
                    Line, Prefix})
            end,
            DataVariable = whole_record_variable(DataPattern),
            #{next_phase := NextPhase, next_data := NextData} = Contribution0,
            case {NextPhase, NextData} of
                {{atom, _PhaseLine, Phase},
                        {var, _DataLine, DataVariable}} -> ok;
                _ -> error({mutating_hls_statem_contribution,
                    Line, Phase, NextPhase, NextData})
            end,
            {true, maps:without([next_phase, next_data], Contribution0#{
                line => Line,
                tag => Tag,
                phase => Phase,
                clause => Clause
            })}
    end.

contribution_result({tuple, _Line, [NextPhase, NextData,
        {tuple, DirectiveLine, [
            {atom, _ContributeLine, contribute},
            {atom, _NameLine, Name},
            Key,
            Value
        ]}]}) ->
    #{
        name => Name,
        mode => count,
        key_expression => Key,
        member_expression => none,
        value_expression => Value,
        directive_line => DirectiveLine,
        next_phase => NextPhase,
        next_data => NextData
    };
contribution_result({tuple, _Line, [NextPhase, NextData,
        {tuple, DirectiveLine, [
            {atom, _ContributeLine, contribute},
            {atom, _NameLine, Name},
            Key,
            Member,
            Value
        ]}]}) ->
    #{
        name => Name,
        mode => members,
        key_expression => Key,
        member_expression => Member,
        value_expression => Value,
        directive_line => DirectiveLine,
        next_phase => NextPhase,
        next_data => NextData
    };
contribution_result(_Result) ->
    none.

contribution_shapes(Forms, Contributions) ->
    Requests = lists:foldl(fun
        (#{tag := Tag, clause := {clause, _, [Message | _], [], _}}, Acc) ->
            Fields = xls_pattern_totality:shape_fields(Message),
            Acc#{Tag => lists:usort(Fields ++ maps:get(Tag, Acc, []))};
        (_, Acc) -> Acc
    end, #{}, Contributions),
    xls_type_shape:records(Forms, Requests).

%% Validate immutable contribution values and the exact data dependencies of capture.
-spec validate_contribution(map(), map(), atom(), [erl_parse:abstract_form()], atom(), map()) -> map().
validate_contribution(
    Contribution = #{
        phase := Phase,
        tag := Tag,
        name := Name,
        mode := Mode,
        key_expression := Key,
        member_expression := Member,
        value_expression := Value,
        clause := {clause, _Line,
            [MessagePattern, _PhasePattern, DataPattern], Guards, _Body}
    },
    Open = #{name := Name, population := #{mode := Mode}},
    Accumulator,
    Forms,
    DataName,
    Shapes
) ->
    MessageBindings = pattern_bindings(MessagePattern, Tag, message, Forms),
    DataBindings = pattern_bindings(DataPattern, DataName, data, Forms),
    Bindings = maps:merge(DataBindings, MessageBindings),
    ok = validate_u32_expression(Key, Bindings, [message]),
    case Member of
        none -> ok;
        _ -> validate_u32_expression(Member, Bindings, [message])
    end,
    Accumulator = record_expression_name(Value),
    ok = case maps:get(kind, Open, reduction) of
        gather -> ok;
        reduction -> validate_complete_record_expression(Value,
            xls_parse:find_record(Forms, Accumulator), reduction_value)
    end,
    ok = require_variable_origins(
        expression_variables(Value),
        Bindings,
        [message],
        {hls_statem_reduction_value, Phase, Tag}
    ),
    Contribution#{
        site => maps:get(id, Open),
        capture_checks => case Guards of
            [] -> xls_pattern_totality:prove(MessagePattern, maps:get(Tag, Shapes));
            _ -> none
        end,
        independent_lift => lists:all(fun(Variable) ->
            case maps:get(Variable, MessageBindings, none) of
                #{origin := message} -> true;
                _ -> false
            end
        end, expression_variables(Guards)),
        source_transportable => source_transportable(
            MessagePattern, DataPattern, Guards)
    };
validate_contribution(Contribution, Open, _Accumulator, _Forms, _DataName, _Shapes) ->
    error({hls_statem_reduction_contribution_mismatch,
        public_contribution(Contribution), public_open(Open)}).

open_for_contribution(Contribution, OpenIndex) ->
    Phase = maps:get(phase, Contribution),
    case maps:find(Phase, OpenIndex) of
        {ok, Open} -> Open;
        error -> error({hls_statem_reduction_contribution_without_open,
            public_contribution(Contribution)})
    end.

require_contributions(Opens, Contributions) ->
    lists:foreach(
        fun(#{id := Site, phase := Phase, name := Name}) ->
            case [Contribution
                    || Contribution <- Contributions,
                       maps:get(site, Contribution) =:= Site] of
                [] -> error({missing_hls_statem_reduction_contribution,
                    Name, Phase});
                _ -> ok
            end
        end,
        Opens
    ).

require_no_orphan_reductions(Contributions, InternalGroups) ->
    case {Contributions, InternalGroups} of
        {[], []} -> ok;
        _ -> error({hls_statem_reduction_without_open,
            [public_contribution(C) || C <- Contributions],
            internal_group_keys(InternalGroups)})
    end.

%%%
%%% Completion and reducer analysis
%%%

internal_key(
    {clause, _Line, [
        {tuple, _EventLine, [
            {atom, _CompleteLine, reduction_complete},
            {atom, _NameLine, Name},
            _Key,
            _Accumulator
        ]},
        {atom, _PhaseLine, Phase},
        _Data
    ], _Guards, _Body},
    Phases
) ->
    require_declared(internal_phase, Phase, Phases),
    {Name, Phase};
internal_key({clause, Line, Patterns, _Guards, _Body}, _Phases) ->
    error({unsupported_hls_statem_internal_head, Line, Patterns}).

validate_completions(InternalGroups0, Opens, Accumulator) ->
    InternalGroups = normalize_internal_groups(InternalGroups0),
    Expected = lists:sort([
        {maps:get(name, Open), maps:get(phase, Open)} || Open <- Opens
    ]),
    Actual = lists:sort([Key || {Key, _Clauses} <- InternalGroups]),
    case Actual of
        Expected -> ok;
        _ -> error({incomplete_hls_statem_reduction_completions,
            Expected, Actual})
    end,
    [
        #{
            site => completion_site(Name, Phase, Opens),
            clauses => [validate_completion_clause(Clause, Accumulator)
                || Clause <- Clauses]
        }
        || {{Name, Phase}, Clauses} <- InternalGroups
    ].

normalize_internal_groups([]) -> [];
normalize_internal_groups([{Key = {_Name, _Phase}, Clauses} | Rest])
        when is_list(Clauses) ->
    [{Key, Clauses} | normalize_internal_groups(Rest)];
normalize_internal_groups(Groups) ->
    error({invalid_hls_statem_internal_groups, Groups}).

internal_group_keys(Groups) ->
    [Key || {Key, _Clauses} <- normalize_internal_groups(Groups)].

completion_site(Name, Phase, Opens) ->
    [Site] = [maps:get(id, Open)
        || Open <- Opens,
           maps:get(name, Open) =:= Name,
           maps:get(phase, Open) =:= Phase],
    Site.

validate_completion_clause(
    Clause = {clause, Line, [
        {tuple, _EventLine, [
            {atom, _CompleteLine, reduction_complete},
            {atom, _NameLine, _Name},
            KeyPattern,
            AccumulatorPattern
        ]},
        _Phase,
        _Data
    ], _Guards, _Body},
    Accumulator
) ->
    ok = validate_u32_pattern(KeyPattern),
    ok = validate_accumulator_pattern(AccumulatorPattern, Accumulator),
    lists:foreach(fun(Result) -> validate_internal_result(Result, Line) end,
        xls_callback_result:results(Clause)),
    Clause.

%% Completion may consume or fail; finite action validation follows normalization.
-spec validate_internal_result(term(), term()) -> ok.
validate_internal_result({tuple, _Line, [
    {atom, _RepeatLine, repeat_phase},
    _Data,
    {atom, _DirectiveLine, consume}
]}, _ContextLine) -> ok;
validate_internal_result({tuple, _Line, [
    {atom, _PhaseLine, Phase},
    _Data,
    {atom, _DirectiveLine, Directive}
]}, _ContextLine)
        when Phase =/= repeat_phase,
             (Directive =:= consume orelse Directive =:= fail) -> ok;
validate_internal_result({tuple, L, [Phase, Data, {atom, _, consume}, _Actions]}, ContextLine) ->
    validate_internal_result({tuple, L, [Phase, Data, {atom, L, consume}]}, ContextLine);
validate_internal_result(Result, ContextLine) ->
    error({unsupported_hls_statem_internal_result, ContextLine, Result}).

analyze_reducers(Forms, Names, Accumulator, AccumulatorRecord) ->
    Clauses = case [FunctionClauses
            || {function, _Line, reduce, 3, FunctionClauses} <- Forms] of
        [Found] -> Found;
        [] -> error({missing_hls_statem_reducer, Names});
        Found -> error({duplicate_hls_statem_reducer, Found})
    end,
    Reducers = [analyze_reducer(Clause, Accumulator, AccumulatorRecord)
        || Clause <- Clauses],
    Actual = [maps:get(name, Reducer) || Reducer <- Reducers],
    case lists:sort(Actual) of
        Names -> Reducers;
        _ -> error({unexpected_hls_statem_reducers, Names, Actual})
    end.

require_reducer_exported(Forms) ->
    Exports = lists:append([
        Functions
        || {attribute, _Line, export, Functions} <- Forms
    ]),
    case lists:member({reduce, 3}, Exports) of
        true -> ok;
        false -> error({missing_hls_statem_callback, reduce, 3})
    end.

analyze_reducer(
    Clause = {clause, Line, [
        {atom, _NameLine, Name}, Left, Right
    ], [], Body},
    Accumulator,
    AccumulatorRecord
) ->
    ok = validate_reducer_pattern(Left, Accumulator),
    ok = validate_reducer_pattern(Right, Accumulator),
    {_Prefix, Result} = split_last(Body),
    ok = validate_complete_record_expression(
        Result, AccumulatorRecord, reduction_result),
    #{name => Name, line => Line, clause => Clause};
analyze_reducer(Clause, _Accumulator, _AccumulatorRecord) ->
    error({unsupported_hls_statem_reducer, Clause}).

validate_accumulator_pattern({var, _Line, _Name}, _Accumulator) -> ok;
validate_accumulator_pattern({record, _Line, Accumulator, _Fields},
        Accumulator) -> ok;
validate_accumulator_pattern({match, _Line, Left, Right}, Accumulator) ->
    ok = validate_accumulator_pattern(Left, Accumulator),
    validate_accumulator_pattern(Right, Accumulator);
validate_accumulator_pattern(Pattern, Accumulator) ->
    error({unsupported_hls_statem_accumulator_pattern,
        Accumulator, Pattern}).

validate_reducer_pattern({record, _Line, Accumulator, Fields}, Accumulator) ->
    lists:foreach(fun
        ({record_field, _FieldLine, {atom, _AtomLine, _Field}, Pattern}) ->
            validate_irrefutable_pattern(Pattern);
        (Field) ->
            error({unsupported_hls_statem_accumulator_field, Field})
    end, Fields);
validate_reducer_pattern(Pattern, Accumulator) ->
    validate_accumulator_pattern(Pattern, Accumulator).

validate_irrefutable_pattern({var, _Line, _Name}) -> ok;
validate_irrefutable_pattern({match, _Line, Left, Right}) ->
    ok = validate_irrefutable_pattern(Left),
    validate_irrefutable_pattern(Right);
validate_irrefutable_pattern(Pattern) ->
    error({refutable_hls_statem_accumulator_pattern, Pattern}).

validate_u32_pattern({var, _Line, _Name}) -> ok;
validate_u32_pattern({integer, _Line, Value}) ->
    _ = u32_literal(Value, reduction_key),
    ok;
validate_u32_pattern(Pattern) ->
    error({unsupported_hls_statem_reduction_key_pattern, Pattern}).

%%%
%%% Structural interface
%%%

source_interface(#{
    accumulator_record := AccumulatorRecord,
    opens := Opens,
    contributions := Contributions,
    reducers := Reducers
}) ->
    Accumulator = maps:with([name, fields], type_ref(AccumulatorRecord)),
    #{
        accumulator => Accumulator,
        sites => [source_interface_site(Open, Contributions)
            || Open <- Opens],
        reducers => [maps:get(name, Reducer) || Reducer <- Reducers]
    }.

source_interface_site(#{
    id := Site,
    phase := Phase,
    name := Name,
    population := Population,
    opens_conditionally := OpensConditionally
}, Contributions) ->
    SiteContributions = [Contribution
        || Contribution <- Contributions,
           maps:get(site, Contribution) =:= Site],
    Groups = xls_callback_lower:group_by(
        SiteContributions,
        fun(Contribution) -> maps:get(tag, Contribution) end
    ),
    #{
        id => Site,
        phase => Phase,
        name => Name,
        population => Population,
        opens_conditionally => OpensConditionally,
        contributions => [Tag || {Tag, _Group} <- Groups],
        source_transportable => lists:all(
            fun({_Tag, Group}) ->
                lists:all(fun(Contribution) ->
                    maps:get(source_transportable, Contribution)
                end, Group)
            end,
            Groups
        ),
        source_capture_total => lists:all(
            fun({_Tag, Group}) -> lists:any(fun source_capture_total/1, Group)
            end,
            Groups
        )
    }.

%%%
%%% Closing into typed IR
%%%

close_sites(Opens, Contributions, Completions, DataName, AccumulatorName,
        AccumulatorType, EnumAtoms) ->
    [close_site(
        Open,
        [Contribution || Contribution <- Contributions,
            maps:get(site, Contribution) =:= maps:get(id, Open)],
        completion_for(Open, Completions),
        DataName,
        AccumulatorName,
        AccumulatorType,
        EnumAtoms
    ) || Open <- Opens].

completion_for(Open, Completions) ->
    [Completion] = [Candidate
        || Candidate <- Completions,
           maps:get(site, Candidate) =:= maps:get(id, Open)],
    Completion.

close_site(Open, Contributions, Completion, DataName, AccumulatorName,
        AccumulatorType, EnumAtoms) ->
    #{
        id => maps:get(id, Open),
        phase => maps:get(phase, Open),
        name => maps:get(name, Open),
        population => maps:get(population, Open),
        opens_conditionally => maps:get(opens_conditionally, Open),
        contributions => [
            close_contribution_group(
                Tag,
                Group,
                DataName,
                AccumulatorType,
                EnumAtoms
            )
            || {Tag, Group} <- xls_callback_lower:group_by(
                Contributions,
                fun(Contribution) -> maps:get(tag, Contribution) end
            )
        ],
        completion => close_completion(
            Completion,
            maps:get(phase, Open),
            DataName,
            AccumulatorName,
            EnumAtoms
        )
    }.

%% Close a message schema while retaining the existing source-capture requirements.
-spec close_contribution_group(atom(), [map()], atom(), map(), map()) -> map().
close_contribution_group(Tag, Contributions, DataName, AccumulatorType,
        EnumAtoms) ->
    Clauses = [rewrite_contribution_clause(Contribution)
        || Contribution <- Contributions],
    MessageValue = [
        "(Tag::", xls_names:enum_member(Tag), ", message, bits_from_",
        xls_names:record_codec(Tag), "(message))"
    ],
    Arguments = [
        xls_pattern_lower:record_argument(Tag, "message", MessageValue),
        xls_pattern_lower:value_argument("phase"),
        xls_pattern_lower:record_argument(
            DataName,
            "data",
            ["(Tag::", xls_names:enum_member(DataName), ", data)"]
        )
    ],
    Failure = ["(u1:0, u32:0, u32:0, zero!<",
        maps:get(dslx_type, AccumulatorType), ">())"],
    {Body, Result} = xls_callback_lower:lower(
        Clauses,
        Arguments,
        DataName,
        fun(R) -> ["(u1:1, ", R, ".0, ", R, ".1, ", R, contribution_value_suffix(Contributions), ")"] end,
        Failure,
        fun(_Kind) -> Failure end,
        EnumAtoms
    ),
    SourceTransportable = lists:all(fun(Contribution) ->
        maps:get(source_transportable, Contribution)
    end, Contributions),
    %% A source-side plane captures the whole message schema, so merely being
    %% able to evaluate each contribution away from actor state is not enough:
    %% at least one contributing clause must accept every value of that schema.
    %% Keep this fact separate from transportability because ordinary actor
    %% dispatch can legitimately retain a partial contribution and fallback.
    SourceCaptureTotal = lists:any(fun source_capture_total/1, Contributions),
    Transport = case SourceTransportable of
        true -> close_transport_contribution_group(
            Tag, Contributions, DataName, AccumulatorType, EnumAtoms);
        false -> none
    end,
    %% This candidate omits the actor data pattern. It is not permission to
    %% bypass that pattern: a backend must separately establish or explicitly
    %% assert exclusive protocol ownership and validate the eventual open.
    IndependentLift = case lists:all(fun(C) -> maps:get(independent_lift, C) end, Contributions) of
        true -> close_transport_contribution_group(Tag, Contributions, DataName, AccumulatorType, EnumAtoms);
        false -> none
    end,
    %% The owning site already fixes name, phase, and population mode.
    #{
        tag => Tag,
        build => lowered(Body, Result),
        source_transportable => SourceTransportable,
        source_capture_total => SourceCaptureTotal,
        transport => Transport,
        independent_lift => IndependentLift
    }.

%% Private value records arrive without the callback record tag wrapper.
-spec contribution_value_suffix([map(), ...]) -> string().
contribution_value_suffix([#{value_expression := {record, _, {value, _}, _}} | _]) -> ".2";
contribution_value_suffix(_) -> ".2.1".

source_capture_total(#{capture_checks := Checks}) -> Checks =/= none.

capture_assertions(Tag, Contributions) ->
    case [Checks || #{capture_checks := Checks} <- Contributions, Checks =/= none] of
        [] -> [];
        [Checks | _] -> xls_pattern_totality:assertions(xls_names:record_type(Tag), Checks)
    end.

%% Message-only lifting retains source guards and checked element construction.
-spec close_transport_contribution_group(atom(), [map()], atom(), map(), map()) -> map().
close_transport_contribution_group(Tag, Contributions, DataName,
        AccumulatorType, EnumAtoms) ->
    Clauses = [rewrite_transport_contribution_clause(Contribution)
        || Contribution <- Contributions],
    MessageValue = [
        "(Tag::", xls_names:enum_member(Tag), ", message, bits_from_",
        xls_names:record_codec(Tag), "(message))"
    ],
    Arguments = [
        xls_pattern_lower:record_argument(Tag, "message", MessageValue)
    ],
    Failure = ["(u1:0, u32:0, u32:0, zero!<",
        maps:get(dslx_type, AccumulatorType), ">())"],
    {Body, Result} = xls_callback_lower:lower(
        Clauses,
        Arguments,
        DataName,
        fun(R) -> ["(u1:1, ", R, ".0, ", R, ".1, ", R, contribution_value_suffix(Contributions), ")"] end,
        Failure,
        fun(_Kind) -> Failure end,
        EnumAtoms
    ),
    lowered([capture_assertions(Tag, Contributions), Body], Result).

rewrite_contribution_clause(#{
    clause := Clause0,
    key_expression := Key,
    member_expression := Member0,
    value_expression := Value
}) ->
    Candidate = contribution_candidate(Key, Member0, Value),
    strip_dispatched_phase(replace_body(Clause0, [Candidate])).

rewrite_transport_contribution_clause(#{
    clause := {clause, Line, [Message, _Phase, _Data], Guards, _Body},
    key_expression := Key,
    member_expression := Member,
    value_expression := Value
}) ->
    {clause, Line, [Message], Guards,
        [contribution_candidate(Key, Member, Value)]}.

contribution_candidate(Key, Member0, Value) ->
    Member = case Member0 of
        none -> typed_u32_expression({integer, element(2, Key), 0});
        _ -> typed_u32_expression(Member0)
    end,
    {tuple, element(2, Key), [
        typed_u32_expression(Key), Member, Value
    ]}.

%% Preserve source clause order while passing the accumulator only to the completion callback.
-spec close_completion(map(), atom(), atom(), atom(), map()) -> map().
close_completion(#{clauses := Clauses0} = Completion, Phase, DataName,
        AccumulatorName, EnumAtoms) ->
    Names = maps:get(continuations, Completion, []),
    Clauses = [
        strip_dispatched_internal_phase(
            xls_callback_result:map(flatten_completion_clause(Clause), fun(R) -> normalize_completion(R, Phase, Names) end)
        )
        || Clause <- Clauses0
    ],
    AccumulatorValue = [
        "(Tag::", xls_names:enum_member(AccumulatorName), ", accumulator, bits_from_",
        xls_names:record_codec(AccumulatorName), "(accumulator))"
    ],
    Arguments = [
        xls_pattern_lower:value_argument("key"),
        xls_pattern_lower:record_argument(
            AccumulatorName, "accumulator", AccumulatorValue),
        xls_pattern_lower:value_argument("phase"),
        xls_pattern_lower:record_argument(
            DataName,
            "data",
            ["(Tag::", xls_names:enum_member(DataName), ", data)"]
        )
    ],
    Failure = fun(Code) -> ["(phase, data, Directive::FAIL, u1:0, ", Code,
        case Names of [] -> []; _ -> ", u8:0" end, ")"] end,
    [{clause, FirstLine, _, _, _} | _] = Clauses,
    {Body, Result} = xls_callback_lower:lower(
        Clauses,
        Arguments,
        DataName,
        fun(R) -> ["(", R, ".0, ", R, ".1.1, ", R, ".2, ",
            R, ".3, ", R, ".4", case Names of [] -> []; _ -> [", ", R, ".5"] end, ")"] end,
        Failure(xls_failure_sites:at(function_clause, FirstLine)),
        Failure,
        EnumAtoms
    ),
    lowered(Body, Result).

flatten_completion_clause({clause, Line, [
    {tuple, _EventLine, [
        {atom, _CompleteLine, reduction_complete},
        {atom, _NameLine, _Name},
        Key,
        Accumulator
    ]},
    Phase,
    Data
], Guards, Body}) ->
    {clause, Line, [Key, Accumulator, Phase, Data], Guards, Body}.

normalize_internal_result_expression({tuple, Line, [
    {atom, _RepeatLine, repeat_phase}, Data, {atom, _ConsumeLine, consume}
]}, Phase) ->
    {tuple, Line, [
        {atom, Line, Phase}, Data, {atom, Line, consume},
        {atom, Line, true},
        {xls_map, 0, {atom, 0, false}, fun(_) -> "hls_failure::NONE" end}
    ]};
normalize_internal_result_expression(
    {tuple, Line, [{atom, _RepeatLine, repeat_phase} | _] = Elements},
    _Phase
) ->
    error({bad_hls_statem_repeat_result, Line, Elements});
normalize_internal_result_expression({tuple, Line, [Phase, Data, Directive]},
        _CurrentPhase) ->
    Result = {tuple, Line, [Phase, Data, Directive, {atom, Line, false}]},
    {xls_map, Line, Result, fun(R) ->
        ["(", R, ".0, ", R, ".1, ", R, ".2, ", R, ".3, ",
            "hls_failure::check(", R, ".2 == Directive::FAIL, ",
            xls_failure_sites:at(explicit_fail, Line), "))"]
    end};
normalize_internal_result_expression(Expression, _Phase) ->
    error({unsupported_hls_statem_internal_result, Expression}).

strip_dispatched_internal_phase({clause, Line,
        [Key, Accumulator, Phase, Data], Guards, Body}) ->
    {clause, Line,
        [Key, Accumulator, dispatched_phase_variable(Phase), Data],
        Guards, Body}.

close_reducer(#{name := Name, clause := {clause, Line, [
        {atom, _NameLine, Name}, Left, Right
    ], Guards, Body}}, DataName, AccumulatorName, AccumulatorType,
        EnumAtoms) ->
    Clause = {clause, Line, [Left, Right], Guards, Body},
    Arguments = [
        xls_pattern_lower:record_argument(
            AccumulatorName,
            "left",
            accumulator_argument(AccumulatorName, "left")
        ),
        xls_pattern_lower:record_argument(
            AccumulatorName,
            "right",
            accumulator_argument(AccumulatorName, "right")
        )
    ],
    Failure = fun(Code) ->
        ["(zero!<", maps:get(dslx_type, AccumulatorType), ">(), ", Code, ")"]
    end,
    {LoweredBody, Result} = xls_callback_lower:lower(
        [Clause],
        Arguments,
        DataName,
        fun(R) -> ["(", R, ".1, hls_failure::NONE)"] end,
        Failure(xls_failure_sites:at(function_clause, Line)),
        Failure,
        EnumAtoms
    ),
    #{
        name => Name,
        body => xls_parse:print(LoweredBody),
        result => xls_parse:print(Result)
    }.

accumulator_argument(Name, Variable) ->
    [
        "(Tag::", xls_names:enum_member(Name), ", ", Variable, ", bits_from_",
        xls_names:record_codec(Name), "(", Variable, "))"
    ].

type_ref(Forms, Name) ->
    type_ref(xls_parse:find_record(Forms, Name)).

type_ref({attribute, _Line, record, {Name, Fields0}}) ->
    Fields = [
        begin
            Type = hls_type:descriptor(TypeExpression),
            #{name => xls_parse:record_field_name(Field), type => Type}
        end
        || {typed_record_field, Field, TypeExpression} <- Fields0
    ],
    #{
        kind => record,
        name => Name,
        dslx_type => xls_names:record_type(Name),
        fields => Fields
    }.

%%%
%%% Typed source validation
%%%

pattern_bindings(Pattern, RecordName, Origin, Forms) ->
    Record = xls_parse:find_record(Forms, RecordName),
    FieldTypes = maps:from_list([
        {xls_parse:record_field_name(Field), hls_type:descriptor(Type)}
        || {typed_record_field, Field, Type} <- record_decl_fields(Record)
    ]),
    pattern_bindings(Pattern, RecordName, FieldTypes, Origin, #{}).

pattern_bindings({var, _Line, '_'}, _Record, _Fields, _Origin, Bindings) ->
    Bindings;
pattern_bindings({var, _Line, Name}, Record, Fields, Origin, Bindings) ->
    Bindings#{Name => #{
        type => {record, Record}, fields => Fields, origin => Origin
    }};
pattern_bindings({match, _Line, Left, Right}, Record, Fields, Origin,
        Bindings) ->
    pattern_bindings(Right, Record, Fields, Origin,
        pattern_bindings(Left, Record, Fields, Origin, Bindings));
pattern_bindings({record, _Line, Record, PatternFields}, Record, Fields,
        Origin, Bindings) ->
    lists:foldl(fun
        ({record_field, _FieldLine, {atom, _AtomLine, Field}, Value}, Acc) ->
            bind_typed_pattern(Value, maps:get(Field, Fields), Origin, Acc)
    end, Bindings, PatternFields);
pattern_bindings(_Pattern, _Record, _Fields, _Origin, Bindings) ->
    Bindings.

bind_typed_pattern({var, _Line, '_'}, _Type, _Origin, Bindings) -> Bindings;
bind_typed_pattern({var, _Line, Name}, Type, Origin, Bindings) ->
    Bindings#{Name => #{type => Type, origin => Origin}};
bind_typed_pattern({match, _Line, Left, Right}, Type, Origin, Bindings) ->
    bind_typed_pattern(Right, Type, Origin,
        bind_typed_pattern(Left, Type, Origin, Bindings));
bind_typed_pattern({cons, _Line, Head, Tail}, Type, Origin, Bindings) ->
    {Element, Rest} = list_pattern_types(Type),
    bind_typed_pattern(Tail, Rest, Origin,
        bind_typed_pattern(Head, Element, Origin, Bindings));
bind_typed_pattern(_Pattern, _Type, _Origin, Bindings) -> Bindings.

%% Provenance survives destructuring even when a provider keeps its component
%% types opaque (for example phi_field). Such a projection can contribute a
%% value, but cannot qualify as a u32 key without a known element descriptor.
list_pattern_types({hls_type, Module, Name, [Element, Size]})
        when Module =:= hls_lists, Name =:= list;
             Module =:= hls_vec, Name =:= vector ->
    {Element, {hls_type, Module, Name, [Element, max(0, Size - 1)]}};
list_pattern_types(_Opaque) -> {unknown, unknown}.

whole_record_variable({var, _Line, Name}) when Name =/= '_' -> Name;
whole_record_variable({match, _Line, {var, _VarLine, Name}, _Pattern})
        when Name =/= '_' -> Name;
whole_record_variable({match, _Line, _Pattern, {var, _VarLine, Name}})
        when Name =/= '_' -> Name;
whole_record_variable(Pattern) -> error({unbound_hls_statem_data, Pattern}).

source_transportable(MessagePattern, {var, _Line, DataVariable}, Guards)
        when DataVariable =/= '_' ->
    MessageVariables = expression_variables(MessagePattern),
    GuardVariables = expression_variables(Guards),
    not lists:member(DataVariable, MessageVariables) andalso
        not lists:member(DataVariable, GuardVariables);
source_transportable(_MessagePattern, _DataPattern, _Guards) ->
    false.

%% Keys and members use u32 values; an explicit conversion also permits computed expressions.
-spec validate_u32_expression(erl_parse:abstract_expr(), map(), [atom()]) -> ok.
validate_u32_expression({call, _, {remote, _, {atom, _, hls_type}, {atom, _, as}},
        [{call, _, {remote, _, {atom, _, hls_nums}, {atom, _, u32}}, []},
         Expression]}, Bindings, Origins) ->
    %% Explicit conversion gives the lowered expression its required result type.
    %% Normal expression lowering still rejects unsupported operations or effects.
    require_variable_origins(expression_variables(Expression), Bindings, Origins, reduction_value);
validate_u32_expression({integer, _Line, Value}, _Bindings, _Origins) ->
    _ = u32_literal(Value, reduction_value),
    ok;
validate_u32_expression({var, _Line, Name}, Bindings, Origins) ->
    require_u32_binding(Name, Bindings, Origins);
validate_u32_expression({record_field, _Line,
        {var, _ObjectLine, Object}, Record, {atom, _FieldLine, Field}},
        Bindings, Origins) ->
    case maps:get(Object, Bindings, missing) of
        #{type := {record, Record}, fields := Fields, origin := Origin} ->
            require_origin(Object, Origin, Origins),
            case maps:find(Field, Fields) of
                {ok, Type} -> require_u32_type(Type, {Record, Field});
                error -> error({unknown_hls_statem_reduction_field,
                    Record, Field})
            end;
        Binding -> error({unsupported_hls_statem_reduction_object,
            Object, Binding})
    end;
validate_u32_expression(Expression, _Bindings, _Origins) ->
    error({unsupported_hls_statem_u32_reduction_expression, Expression}).

require_u32_binding(Name, Bindings, Origins) ->
    case maps:get(Name, Bindings, missing) of
        #{type := Type, origin := Origin} ->
            require_origin(Name, Origin, Origins),
            require_u32_type(Type, Name);
        missing -> error({unbound_hls_statem_reduction_value, Name})
    end.

require_origin(_Context, Origin, Origins) ->
    case lists:member(Origin, Origins) of
        true -> ok;
        false -> error({invalid_hls_statem_reduction_origin,
            Origin, Origins})
    end.

require_u32_type({hls_type, hls_nums, u32, []}, _Context) -> ok;
require_u32_type(Type, Context) ->
    error({invalid_hls_statem_reduction_u32, Context, Type}).

require_variable_origins(Variables, Bindings, Origins, Context) ->
    lists:foreach(fun(Name) ->
        case maps:get(Name, Bindings, missing) of
            #{origin := Origin} -> require_origin(Context, Origin, Origins);
            missing -> error({unbound_hls_statem_reduction_value,
                Context, Name})
        end
    end, Variables).

%% Raw internal collection elements and tagged scalar accumulators share source records.
-spec record_expression_name(term()) -> atom().
record_expression_name({record, _Line, {value, Name}, _Fields}) -> Name;
record_expression_name({record, _Line, Name, _Fields}) -> Name;
record_expression_name(Expression) ->
    error({unsupported_hls_statem_reduction_record_expression, Expression}).

validate_complete_record_expression(
    {record, Line, Name, Fields},
    {attribute, _RecordLine, record, {Name, DeclaredFields}},
    Context
) ->
    Declared = lists:sort([
        xls_parse:record_field_name(Field)
        || {typed_record_field, Field, _Type} <- DeclaredFields
    ]),
    Present = [Field
        || {record_field, _FieldLine, {atom, _AtomLine, Field}, _Value} <-
               Fields],
    case length(Present) =:= length(Fields) andalso
            lists:sort(Present) =:= Declared andalso
            length(Present) =:= length(lists:usort(Present)) of
        true -> ok;
        false -> error({incomplete_hls_statem_reduction_record,
            Context, Line, Name, Declared, Present})
    end;
validate_complete_record_expression(Expression, Record, Context) ->
    error({unsupported_hls_statem_reduction_record_expression,
        Context, Expression, Record}).

expression_variables({var, _Line, '_'}) -> [];
expression_variables({var, _Line, Name}) -> [Name];
expression_variables(Tuple) when is_tuple(Tuple) ->
    lists:usort(lists:append([
        expression_variables(Element) || Element <- tuple_to_list(Tuple)
    ]));
expression_variables(List) when is_list(List) ->
    lists:usort(lists:append([expression_variables(Item) || Item <- List]));
expression_variables(_Term) -> [].

contains_atom(Atom, {atom, _Line, Atom}) -> true;
contains_atom(Atom, Tuple) when is_tuple(Tuple) ->
    lists:any(fun(Element) -> contains_atom(Atom, Element) end,
        tuple_to_list(Tuple));
contains_atom(Atom, List) when is_list(List) ->
    lists:any(fun(Element) -> contains_atom(Atom, Element) end, List);
contains_atom(_Atom, _Term) -> false.

record_decl_fields({attribute, _Line, record, {_Name, Fields}}) -> Fields.

%%%
%%% Small AST and output helpers
%%%

literal_list({nil, _Line}, _ContextLine) -> [];
literal_list({cons, _Line, Head, Tail}, ContextLine) ->
    [Head | literal_list(Tail, ContextLine)];
literal_list(Expression, ContextLine) ->
    error({nonliteral_hls_statem_actions, ContextLine, Expression}).

u32_literal({integer, _Line, Value}, Context) -> u32_literal(Value, Context);
u32_literal(Value, _Context)
        when is_integer(Value), Value >= 0, Value =< 16#ffffffff -> Value;
u32_literal(Value, Context) ->
    error({invalid_hls_statem_u32_literal, Context, Value}).

require_declared(Kind, Value, Values) ->
    case lists:member(Value, Values) of
        true -> ok;
        false -> error({undeclared_hls_statem_name, Kind, Value, Values})
    end.

typed_u32_expression({integer, Line, Value}) ->
    {call, Line,
        {remote, Line, {atom, Line, hls_type}, {atom, Line, as}},
        [
            {call, Line,
                {remote, Line,
                    {atom, Line, hls_nums}, {atom, Line, u32}},
                []},
            {integer, Line, Value}
        ]};
typed_u32_expression(Expression) -> Expression.

strip_dispatched_phase({clause, Line, [First, Phase, Third], Guards, Body}) ->
    {clause, Line,
        [First, dispatched_phase_variable(Phase), Third], Guards, Body}.

dispatched_phase_variable({atom, Line, _Phase}) -> {var, Line, '_'}.

replace_body({clause, Line, Patterns, Guards, _Body}, Body) ->
    {clause, Line, Patterns, Guards, Body}.

split_last(List) -> {lists:droplast(List), lists:last(List)}.

lowered(Body, Result) ->
    #{body => xls_parse:print(Body), result => xls_parse:print(Result)}.

enum_atoms(Phases) ->
    maps:from_list(
        [{Phase, ["Phase::", xls_names:enum_member(Phase)]} || Phase <- Phases] ++
        [
            {consume, "Directive::CONSUME"},
            {postpone, "Directive::POSTPONE"},
            {fail, "Directive::FAIL"}
        ]
    ).

public_contribution(Contribution) ->
    maps:with([tag, phase, name, mode], Contribution).

public_open(Open) ->
    maps:with([id, phase, name, population, accumulator], Open).

assert_closed(Term) ->
    case contains_source_ast(Term) of
        false -> ok;
        true -> error({open_hls_statem_reduction_ir, Term})
    end.

contains_source_ast({clause, _, _, _, _}) -> true;
contains_source_ast({attribute, _, _, _}) -> true;
contains_source_ast(Tuple) when is_tuple(Tuple) ->
    lists:any(fun contains_source_ast/1, tuple_to_list(Tuple));
contains_source_ast(Map) when is_map(Map) ->
    lists:any(fun({Key, Value}) ->
        contains_source_ast(Key) orelse contains_source_ast(Value)
    end, maps:to_list(Map));
contains_source_ast(List) when is_list(List) ->
    lists:any(fun contains_source_ast/1, List);
contains_source_ast(_Term) -> false.

-doc "Returns the checked record type used by a collection element or callback data.".
-spec collection_type([hls_source:form()], atom()) -> map().
collection_type(Forms, Name) -> type_ref(Forms, Name).

-doc "Validates source-only key, mask and constant padding expressions for a collection opening.".
-spec collection_open(map(), [hls_source:form()], atom()) -> map().
collection_open(Open, Forms, Data) -> validate_open(Open, Forms, Data).

-doc "Validates element contributions with scalar-reduction provenance rules and optionally closes their lifts.".
-spec collection_contributions([hls_source:form()], atom(), map(), [map()], [atom()], interface | closed) -> [map()].
collection_contributions(Forms, Data, Open = #{accumulator := Element}, Cs, Phases, Mode) ->
    Shapes = contribution_shapes(Forms, Cs),
    Valid = [validate_contribution(C, Open, Element, Forms, Data, Shapes) || C <- Cs],
    case Mode of
        interface -> Valid;
        closed -> [close_contribution_group(Tag, Group, Data, type_ref(Forms, Element), enum_atoms(Phases)) ||
            {Tag, Group} <- xls_callback_lower:group_by(Valid, fun(C) -> maps:get(tag, C) end)]
    end.

-doc "Normalizes a consuming or failing completion, permitting declared finite continuations but no replies.".
-spec normalize_completion(term(), atom(), [atom()]) -> term().
normalize_completion(Result, Phase, Names) ->
    ok = validate_internal_result(Result, element(2, Result)),
    xls_statem_continuation:normalize(Result, Names, false,
        fun(R) -> normalize_internal_result_expression(R, Phase) end).
