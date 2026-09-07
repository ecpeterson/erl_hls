%%%% xls_statem_reduction_lower
%%%%
%%%% Recognizes the deliberately bounded actor-reduction source contract and
%%%% lowers its private expressions for xls_statem_reduction_codegen.

-module(xls_statem_reduction_lower).
-moduledoc false.

-export([
    analyze_internal_groups/2,
    analyze_reductions/6,
    lower_reductions/3,
    reduction_interface/1,
    reduction_records/3,
    split_entry_actions/2
]).

-spec split_entry_actions(erl_parse:abstract_expr(), erl_anno:location()) ->
    {none | map(), [erl_parse:abstract_expr()]}.
split_entry_actions(ActionList, Line) ->
    Expressions = literal_list(ActionList, Line),
    {Reduction, CastExpressions} = case Expressions of
        [{tuple, _TupleLine, [
            {atom, _OpenLine, open_reduction},
            _Name,
            _Key,
            _Population,
            _Operator
        ]} = Open | Rest] ->
            {parse_open_action(Open, Line), Rest};
        _ ->
            {none, Expressions}
    end,
    case lists:any(fun is_open_reduction_action/1, CastExpressions) of
        true -> error({hls_statem_open_reduction_must_be_first, Line});
        false -> ok
    end,
    {Reduction, CastExpressions}.

parse_open_action(
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
    #{
        line => TupleLine,
        name => Name,
        key_expression => Key,
        population => parse_reduction_population(PopulationExpression),
        accumulator => Accumulator,
        identity_expression => Identity
    };
parse_open_action(Action, EntryLine) ->
    error({unsupported_hls_statem_open_reduction, EntryLine, Action}).

parse_reduction_population({tuple, Line, [
    {atom, _CountLine, count},
    {integer, _ValueLine, Count}
]}) when Count >= 1, Count =< 255 ->
    #{mode => count, size => Count, source_line => Line};
parse_reduction_population({tuple, Line, [
    {atom, _MembersLine, members},
    MemberList
]}) ->
    MemberExpressions = literal_list(MemberList, Line),
    Members = [u32_literal(Member, reduction_member)
        || Member <- MemberExpressions],
    case Members =/= [] andalso length(Members) =< 255 andalso
            length(Members) =:= length(lists:usort(Members)) of
        true -> #{
            mode => members,
            size => length(Members),
            members => Members,
            source_line => Line
        };
        false -> error({invalid_hls_statem_reduction_members, Line, Members})
    end;
parse_reduction_population(Population) ->
    error({unsupported_hls_statem_reduction_population, Population}).

is_open_reduction_action({tuple, _Line, [
    {atom, _OpenLine, open_reduction} | _Rest
]}) ->
    true;
is_open_reduction_action(_Action) ->
    false.

%%%
%%% Actor-local reduction analysis
%%%

analyze_internal_groups(Clauses, PhaseNames) ->
    xls_callback_lower:group_by(
        Clauses,
        fun(Clause) -> internal_key(Clause, PhaseNames) end
    ).

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
    PhaseNames
) ->
    require_declared(internal_phase, Phase, PhaseNames),
    {Name, Phase};
internal_key({clause, Line, Patterns, _Guards, _Body}, _PhaseNames) ->
    error({unsupported_hls_statem_internal_head, Line, Patterns}).

analyze_reductions(
    Forms,
    Entries,
    CastGroups,
    InternalGroups,
    MessageNames,
    DataName
) ->
    Opens = [
        Reduction#{
            phase => maps:get(phase, Entry),
            entry_clause => maps:get(clause, Entry),
            entry_prefix => maps:get(prefix, Entry)
        }
        || Entry <- Entries,
           Reduction <- [maps:get(reduction, Entry)],
           Reduction =/= none
    ],
    {Contributions, OrdinaryCastGroups} = split_contribution_groups(
        CastGroups
    ),
    case Opens of
        [] ->
            case {Contributions, InternalGroups} of
                {[], []} -> {none, OrdinaryCastGroups};
                _ -> error({hls_statem_reduction_without_open,
                    Contributions, InternalGroups})
            end;
        _ ->
            Accumulator = common_accumulator(Opens),
            ok = require_private_accumulator(
                Accumulator,
                DataName,
                MessageNames
            ),
            AccumulatorRecord = xls_parse:find_record(Forms, Accumulator),
            ok = xls_parse:validate_record_defaults(AccumulatorRecord),
            SiteOpens = [Open#{site => Site}
                || {Site, Open} <- lists:enumerate(0, Opens)],
            OpenIndex = maps:from_list([
                {maps:get(phase, Open), Open} || Open <- SiteOpens
            ]),
            case map_size(OpenIndex) =:= length(SiteOpens) of
                true -> ok;
                false -> error({multiple_hls_statem_reductions_per_phase,
                    [maps:get(phase, Open) || Open <- SiteOpens]})
            end,
            ValidatedOpens = [
                validate_reduction_open(Open, Forms, DataName)
                || Open <- SiteOpens
            ],
            ValidatedContributions = [
                validate_contribution(
                    Contribution,
                    reduction_open_for_contribution(
                        Contribution,
                        OpenIndex
                    ),
                    Accumulator,
                    Forms,
                    DataName
                )
                || Contribution <- Contributions
            ],
            ok = require_contributions(ValidatedOpens, ValidatedContributions),
            Completions = validate_completions(
                InternalGroups,
                ValidatedOpens,
                Accumulator
            ),
            Reducers = analyze_reducers(
                Forms,
                lists:usort([maps:get(name, Open) || Open <- Opens]),
                Accumulator
            ),
            {#{
                accumulator => Accumulator,
                accumulator_record => AccumulatorRecord,
                opens => ValidatedOpens,
                contributions => ValidatedContributions,
                completions => Completions,
                reducers => Reducers
            }, OrdinaryCastGroups}
    end.

common_accumulator(Opens) ->
    case lists:usort([maps:get(accumulator, Open) || Open <- Opens]) of
        [Accumulator] -> Accumulator;
        Accumulators -> error({inconsistent_hls_statem_reduction_accumulator,
            Accumulators})
    end.

require_private_accumulator(Accumulator, DataName, MessageNames) ->
    case lists:member(
            Accumulator,
            [none, error, DataName | MessageNames]
        ) of
        true -> error({nonprivate_hls_statem_reduction_accumulator,
            Accumulator});
        false -> ok
    end.

validate_reduction_open(Open = #{
    key_expression := Key,
    identity_expression := Identity,
    accumulator := Accumulator,
    entry_clause := {clause, _Line, [_Old, _Phase, DataPattern], _Guards,
        _Body}
}, Forms, DataName) ->
    Bindings = pattern_bindings(DataPattern, DataName, data, Forms),
    ok = validate_u32_expression(Key, Bindings, [data]),
    case expression_variables(Identity) of
        [] -> ok;
        Variables -> error({nonconstant_hls_statem_reduction_identity,
            maps:get(line, Open), Variables})
    end,
    Accumulator = record_expression_name(Identity),
    ok = validate_complete_record_expression(
        Identity,
        xls_parse:find_record(Forms, Accumulator),
        reduction_identity
    ),
    Open.

split_contribution_groups(Groups) ->
    {Contributions, OrdinaryGroups} = lists:foldl(
        fun({Key, Clauses}, {ContributionAcc, OrdinaryAcc}) ->
            {GroupContributions, OrdinaryClauses} =
                split_contribution_group(Key, Clauses),
            NextOrdinary = case OrdinaryClauses of
                [] -> OrdinaryAcc;
                _ -> OrdinaryAcc ++ [{Key, OrdinaryClauses}]
            end,
            {ContributionAcc ++ GroupContributions, NextOrdinary}
        end,
        {[], []},
        Groups
    ),
    {Contributions, OrdinaryGroups}.

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
                Tag,
                Phase,
                Rest,
                [Contribution | Contributions],
                Ordinary,
                false
            );
        {true, _Contribution} ->
            error({nonprefix_hls_statem_reduction_contribution,
                Tag, Phase, element(2, Clause)});
        false ->
            split_contribution_group(
                Tag,
                Phase,
                Rest,
                Contributions,
                [Clause | Ordinary],
                true
            )
    end.

contribution_clause(
    Tag,
    Phase,
    Clause = {clause, Line, [_Message, _Phase, DataPattern], _Guards, Body}
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
            DataName = contribution_data_variable(DataPattern, Line, Phase),
            #{next_phase := NextPhase, next_data := NextData} = Contribution0,
            case {NextPhase, NextData} of
                {{atom, _NextPhaseLine, Phase},
                        {var, _NextDataLine, DataName}} -> ok;
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

validate_contribution(
    Contribution = #{
        phase := Phase,
        tag := Tag,
        name := Name,
        mode := Mode,
        key_expression := Key,
        member_expression := Member,
        value_expression := Value,
        clause := {clause, Line,
            [MessagePattern, _PhasePattern, DataPattern], Guards, _Body}
    },
    Open = #{name := Name, population := #{mode := Mode}},
    Accumulator,
    Forms,
    DataName
) ->
    MessageBindings = pattern_bindings(MessagePattern, Tag, message, Forms),
    DataBindings = pattern_bindings(DataPattern, DataName, data, Forms),
    Bindings = maps:merge(DataBindings, MessageBindings),
    ok = validate_contribution_guards(
        Guards,
        Bindings,
        Line,
        Phase,
        Tag
    ),
    ok = validate_u32_expression(Key, Bindings, [message]),
    case Member of
        none -> ok;
        _ -> validate_u32_expression(Member, Bindings, [message])
    end,
    Accumulator = record_expression_name(Value),
    ok = validate_complete_record_expression(
        Value,
        xls_parse:find_record(Forms, Accumulator),
        reduction_value
    ),
    ValueVariables = expression_variables(Value),
    ok = require_variable_origins(
        ValueVariables,
        Bindings,
        [message],
        {hls_statem_reduction_value, Phase, Tag}
    ),
    Contribution#{site => maps:get(site, Open)};
validate_contribution(Contribution, Open, _Accumulator, _Forms, _DataName) ->
    error({hls_statem_reduction_contribution_mismatch,
        Contribution, Open}).

reduction_open_for_contribution(Contribution, OpenIndex) ->
    Phase = maps:get(phase, Contribution),
    case maps:find(Phase, OpenIndex) of
        {ok, Open} -> Open;
        error -> error({hls_statem_reduction_contribution_without_open,
            Contribution})
    end.

require_contributions(Opens, Contributions) ->
    lists:foreach(
        fun(#{phase := Phase, name := Name}) ->
            case [Contribution
                    || Contribution <- Contributions,
                       maps:get(phase, Contribution) =:= Phase,
                       maps:get(name, Contribution) =:= Name] of
                [] -> error({missing_hls_statem_reduction_contribution,
                    Name, Phase});
                _ -> ok
            end
        end,
        Opens
    ).

validate_completions(InternalGroups, Opens, Accumulator) ->
    Expected = lists:sort([
        {maps:get(name, Open), maps:get(phase, Open)} || Open <- Opens
    ]),
    Actual = lists:sort([Key || {Key, _Clauses} <- InternalGroups]),
    case Actual =:= Expected of
        true -> ok;
        false -> error({incomplete_hls_statem_reduction_completions,
            Expected, Actual})
    end,
    [
        #{name => Name, phase => Phase,
          site => completion_site(Name, Phase, Opens), clauses => [
            validate_completion_clause(Clause, Accumulator)
            || Clause <- Clauses
        ]}
        || {{Name, Phase}, Clauses} <- InternalGroups
    ].

completion_site(Name, Phase, Opens) ->
    [Site] = [maps:get(site, Open)
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
    ], _Guards, Body},
    Accumulator
) ->
    ok = validate_u32_pattern(KeyPattern),
    ok = validate_accumulator_pattern(AccumulatorPattern, Accumulator),
    {_Prefix, Result} = split_last(Body),
    ok = validate_internal_result(Result, Line),
    Clause.

validate_internal_result({tuple, _Line, [
    {atom, _PhaseLine, repeat_phase},
    _Data,
    {atom, _DirectiveLine, consume}
]}, _ContextLine) ->
    ok;
validate_internal_result({tuple, _Line, [
    {atom, _PhaseLine, Phase},
    _Data,
    {atom, _DirectiveLine, Directive}
]}, _ContextLine)
        when Phase =/= repeat_phase,
             (Directive =:= consume orelse Directive =:= fail) ->
    ok;
validate_internal_result({'case', _Line, _Expression, Clauses}, ContextLine) ->
    lists:foreach(
        fun({clause, _ClauseLine, _Patterns, _Guards, Body}) ->
            {_Prefix, Result} = split_last(Body),
            validate_internal_result(Result, ContextLine)
        end,
        Clauses
    );
validate_internal_result({'if', _Line, Clauses}, ContextLine) ->
    lists:foreach(
        fun({clause, _ClauseLine, _Patterns, _Guards, Body}) ->
            {_Prefix, Result} = split_last(Body),
            validate_internal_result(Result, ContextLine)
        end,
        Clauses
    );
validate_internal_result(Result, ContextLine) ->
    error({unsupported_hls_statem_internal_result, ContextLine, Result}).

analyze_reducers(Forms, Names, Accumulator) ->
    Clauses = case [FunctionClauses
            || {function, _Line, reduce, 3, FunctionClauses} <- Forms] of
        [Found] -> Found;
        [] -> error({missing_hls_statem_reducer, Names});
        Found -> error({duplicate_hls_statem_reducer, Found})
    end,
    AccumulatorRecord = xls_parse:find_record(Forms, Accumulator),
    Reducers = [analyze_reducer(Clause, Accumulator, AccumulatorRecord)
        || Clause <- Clauses],
    Actual = lists:sort([maps:get(name, Reducer) || Reducer <- Reducers]),
    case Actual =:= lists:sort(Names) of
        true -> Reducers;
        false -> error({unexpected_hls_statem_reducers, Names, Actual})
    end.

analyze_reducer(
    Clause = {clause, Line, [
        {atom, _NameLine, Name},
        Left,
        Right
    ], [], Body},
    Accumulator,
    AccumulatorRecord
) ->
    ok = validate_reducer_accumulator_pattern(Left, Accumulator),
    ok = validate_reducer_accumulator_pattern(Right, Accumulator),
    {_Prefix, Result} = split_last(Body),
    ok = validate_complete_record_expression(
        Result,
        AccumulatorRecord,
        reduction_result
    ),
    #{name => Name, line => Line, clause => Clause, body => Body};
analyze_reducer(Clause, _Accumulator, _AccumulatorRecord) ->
    error({unsupported_hls_statem_reducer, Clause}).

validate_accumulator_pattern({var, _Line, _Name}, _Accumulator) ->
    ok;
validate_accumulator_pattern({record, _Line, Accumulator, _Fields},
        Accumulator) ->
    ok;
validate_accumulator_pattern({match, _Line, Left, Right}, Accumulator) ->
    ok = validate_accumulator_pattern(Left, Accumulator),
    validate_accumulator_pattern(Right, Accumulator);
validate_accumulator_pattern(Pattern, Accumulator) ->
    error({unsupported_hls_statem_accumulator_pattern,
        Accumulator, Pattern}).

validate_reducer_accumulator_pattern(
    {record, _Line, Accumulator, Fields}, Accumulator
) ->
    lists:foreach(
        fun
            ({record_field, _FieldLine, {atom, _AtomLine, _Field}, Pattern}) ->
                validate_irrefutable_pattern(Pattern);
            (Field) ->
                error({unsupported_hls_statem_accumulator_field, Field})
        end,
        Fields
    );
validate_reducer_accumulator_pattern(Pattern, Accumulator) ->
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

reduction_records(_Forms, Records, none) ->
    Records;
reduction_records(_Forms, Records, #{accumulator_record := Record}) ->
    Records ++ [Record].

reduction_interface(none) ->
    none;
reduction_interface(#{
    accumulator_record := AccumulatorRecord,
    opens := Opens,
    contributions := Contributions,
    completions := Completions,
    reducers := Reducers
}) ->
    {attribute, _Line, record, {Accumulator, _Fields}} = AccumulatorRecord,
    Populations = [maps:get(population, Open) || Open <- Opens],
    MaxMemberCount = lists:max([0 | [
        maps:get(size, Population)
        || Population <- Populations,
           maps:get(mode, Population) =:= members
    ]]),
    #{
        accumulator => #{
            name => Accumulator,
            fields => record_fields(AccumulatorRecord)
        },
        site_count => length(Opens),
        max_population => lists:max([
            maps:get(size, Population) || Population <- Populations
        ]),
        max_member_count => MaxMemberCount,
        opens => [
            maps:update_with(
                population,
                fun public_population/1,
                maps:with([site, phase, name, population], Open)
            )
            || Open <- Opens
        ],
        contributions => [maps:with([site, phase, tag, name, mode],
                Contribution)
            || Contribution <- Contributions],
        completions => [maps:with([site, phase, name], Completion)
            || Completion <- Completions],
        reducers => [maps:get(name, Reducer) || Reducer <- Reducers]
    }.

%% Source locations belong to analyzer diagnostics, not to the persisted actor
%% interface. In particular, moving an otherwise unchanged callback must not
%% make an already compiled interface appear stale.
public_population(Population) ->
    maps:without([source_line], Population).

pattern_bindings(Pattern, RecordName, Origin, Forms) ->
    Record = xls_parse:find_record(Forms, RecordName),
    FieldTypes = maps:from_list([
        {xls_parse:record_field_name(Field), hls_type:descriptor(Type)}
        || {typed_record_field, Field, Type} <- record_decl_fields(Record)
    ]),
    pattern_bindings(Pattern, RecordName, FieldTypes, Origin, #{}).

pattern_bindings({var, _Line, '_'}, _RecordName, _FieldTypes, _Origin,
        Bindings) ->
    Bindings;
pattern_bindings({var, _Line, Name}, RecordName, FieldTypes, Origin,
        Bindings) ->
    Bindings#{Name => #{
        type => {record, RecordName},
        fields => FieldTypes,
        origin => Origin
    }};
pattern_bindings({match, _Line, Left, Right}, RecordName, FieldTypes, Origin,
        Bindings) ->
    LeftBindings = pattern_bindings(
        Left, RecordName, FieldTypes, Origin, Bindings),
    pattern_bindings(Right, RecordName, FieldTypes, Origin, LeftBindings);
pattern_bindings({record, _Line, RecordName, Fields}, RecordName,
        FieldTypes, Origin, Bindings) ->
    lists:foldl(
        fun({record_field, _FieldLine, {atom, _AtomLine, Field}, Value}, Acc) ->
            bind_typed_pattern(
                Value,
                maps:get(Field, FieldTypes),
                Origin,
                Acc
            )
        end,
        Bindings,
        Fields
    );
pattern_bindings(_Pattern, _RecordName, _FieldTypes, _Origin, Bindings) ->
    Bindings.

bind_typed_pattern({var, _Line, '_'}, _Type, _Origin, Bindings) ->
    Bindings;
bind_typed_pattern({var, _Line, Name}, Type, Origin, Bindings) ->
    Bindings#{Name => #{type => Type, origin => Origin}};
bind_typed_pattern({match, _Line, Left, Right}, Type, Origin, Bindings) ->
    bind_typed_pattern(Right, Type, Origin,
        bind_typed_pattern(Left, Type, Origin, Bindings));
bind_typed_pattern(_Pattern, _Type, _Origin, Bindings) ->
    Bindings.

%% A shared reduction sidecar constructs contributions without fetching the
%% actor's application state. Keep contribution recognition independent of
%% that state: the third callback argument may preserve the state value in the
%% result, but it may neither destructure it nor use it to select a clause.
contribution_data_variable({var, _Line, Name}, _ContextLine, _Phase)
        when Name =/= '_' ->
    Name;
contribution_data_variable(Pattern, ContextLine, Phase) ->
    error({actor_dependent_hls_statem_reduction_data_pattern,
        ContextLine, Phase, Pattern}).

validate_contribution_guards(Guards, Bindings, Line, Phase, Tag) ->
    Variables = expression_variables(Guards),
    case [
        Name
        || Name <- Variables,
           maps:get(origin, maps:get(Name, Bindings, #{}), missing) =:= data
    ] of
        [] -> ok;
        ActorVariables ->
            error({actor_dependent_hls_statem_reduction_guard,
                Line, Phase, Tag, ActorVariables})
    end.

validate_u32_expression({integer, _Line, Value}, _Bindings, _Origins) ->
    _ = u32_literal(Value, reduction_value),
    ok;
validate_u32_expression({var, _Line, Name}, Bindings, Origins) ->
    require_u32_binding(Name, Bindings, Origins);
validate_u32_expression(
    {record_field, _Line, {var, _ObjectLine, Object}, Record,
        {atom, _FieldLine, Field}},
    Bindings,
    Origins
) ->
    case maps:get(Object, Bindings, missing) of
        #{type := {record, Record}, fields := Fields, origin := Origin}
                when is_list(Origins) ->
            case lists:member(Origin, Origins) of
                true -> ok;
                false -> error({invalid_hls_statem_reduction_origin,
                    Object, Origin, Origins})
            end,
            case maps:get(Field, Fields, missing) of
                missing -> error({unknown_hls_statem_reduction_field,
                    Record, Field});
                Type -> require_u32_type(Type, {Record, Field})
            end;
        Binding -> error({unsupported_hls_statem_reduction_object,
            Object, Binding})
    end;
validate_u32_expression(Expression, _Bindings, _Origins) ->
    error({unsupported_hls_statem_u32_reduction_expression, Expression}).

require_u32_binding(Name, Bindings, Origins) ->
    case maps:get(Name, Bindings, missing) of
        #{type := Type, origin := Origin} = Binding ->
            case lists:member(Origin, Origins) of
                true -> require_u32_type(Type, Name);
                false -> error({invalid_hls_statem_reduction_origin,
                    Name, Binding, Origins})
            end;
        missing -> error({unbound_hls_statem_reduction_value, Name})
    end.

require_u32_type({hls_type, hls_nums, u32, []}, _Context) -> ok;
require_u32_type(Type, Context) ->
    error({invalid_hls_statem_reduction_u32, Context, Type}).

require_variable_origins(Variables, Bindings, Origins, Context) ->
    lists:foreach(
        fun(Name) ->
            case maps:get(Name, Bindings, missing) of
                #{origin := Origin} when is_list(Origins) ->
                    case lists:member(Origin, Origins) of
                        true -> ok;
                        false -> error({invalid_hls_statem_reduction_origin,
                            Context, Name, Origin, Origins})
                    end;
                missing -> error({unbound_hls_statem_reduction_value,
                    Context, Name})
            end
        end,
        Variables
    ).

record_expression_name({record, _Line, Name, _Fields}) ->
    Name;
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
expression_variables(_Term) ->
    [].

contains_atom(Atom, {atom, _Line, Atom}) -> true;
contains_atom(Atom, Tuple) when is_tuple(Tuple) ->
    lists:any(fun(Element) -> contains_atom(Atom, Element) end,
        tuple_to_list(Tuple));
contains_atom(Atom, List) when is_list(List) ->
    lists:any(fun(Element) -> contains_atom(Atom, Element) end, List);
contains_atom(_Atom, _Term) -> false.

record_decl_fields({attribute, _Line, record, {_Name, Fields}}) ->
    Fields.

u32_literal({integer, _Line, Value}, Context) ->
    u32_literal(Value, Context);
u32_literal(Value, _Context)
        when is_integer(Value), Value >= 0, Value =< 16#ffffffff ->
    Value;
u32_literal(Value, Context) ->
    error({invalid_hls_statem_u32_literal, Context, Value}).

%%%
%%% Actor-local reduction lowering
%%%

lower_reductions(none, _DataName, _EnumAtoms) ->
    none;
lower_reductions(#{
    accumulator := Accumulator,
    accumulator_record := AccumulatorRecord,
    opens := Opens,
    contributions := Contributions,
    completions := Completions,
    reducers := Reducers
}, DataName, EnumAtoms) ->
    AccumulatorType = record_struct_type(Accumulator),
    AccumulatorWidth = xls_parse:record_width(AccumulatorRecord),
    MaxMemberCount = lists:max([0 | [
        maps:get(size, maps:get(population, Open))
        || Open <- Opens,
           maps:get(mode, maps:get(population, Open)) =:= members
    ]]),
    #{
        data => #{name => DataName, dslx_type => record_struct_type(DataName)},
        accumulator => #{
            name => Accumulator,
            dslx_type => AccumulatorType,
            width => AccumulatorWidth
        },
        site_count => length(Opens),
        max_member_count => MaxMemberCount,
        storage_width => 50 + max(1, MaxMemberCount) + AccumulatorWidth,
        opens => [
            lower_reduction_open(
                Open,
                DataName,
                AccumulatorType,
                EnumAtoms
            )
            || Open <- Opens
        ],
        contributions => [
            lower_contribution_group(
                Key,
                Group,
                DataName,
                Accumulator,
                AccumulatorType,
                EnumAtoms
            )
            || {Key, Group} <- xls_callback_lower:group_by(
                Contributions,
                fun(Contribution) ->
                    {maps:get(tag, Contribution),
                        maps:get(phase, Contribution)}
                end
            )
        ],
        completions => [
            lower_completion_group(
                Completion,
                DataName,
                Accumulator,
                AccumulatorType,
                EnumAtoms
            )
            || Completion <- Completions
        ],
        reducers => [
            lower_reducer(
                Reducer,
                DataName,
                Accumulator,
                AccumulatorType,
                EnumAtoms
            )
            || Reducer <- Reducers
        ]
    }.

lower_reduction_open(
    Open = #{
        entry_clause := Clause0,
        entry_prefix := Prefix,
        key_expression := Key,
        identity_expression := Identity
    },
    DataName,
    AccumulatorType,
    EnumAtoms
) ->
    Clause = strip_dispatched_phase(Clause0),
    KeyLowered = lower_entry_reduction_expression(
        Clause,
        Prefix,
        typed_u32_expression(Key),
        DataName,
        fun(R) -> R end,
        "u32:0",
        EnumAtoms
    ),
    IdentityLowered = lower_entry_reduction_expression(
        Clause,
        Prefix,
        Identity,
        DataName,
        fun(R) -> [R, ".1"] end,
        ["zero!<", AccumulatorType, ">()"],
        EnumAtoms
    ),
    #{
        site => maps:get(site, Open),
        phase => maps:get(phase, Open),
        name => maps:get(name, Open),
        population => maps:without(
            [source_line],
            maps:get(population, Open)
        ),
        key => KeyLowered,
        identity => IdentityLowered
    }.

lower_entry_reduction_expression(
    Clause,
    Prefix,
    Expression,
    DataName,
    Postprocessor,
    Failure,
    EnumAtoms
) ->
    ExpressionClause = replace_body(Clause, Prefix ++ [Expression]),
    {Body, Result} = xls_parse:branch_from_clause(
        ExpressionClause,
        enter_args(DataName),
        DataName,
        Postprocessor,
        Failure,
        EnumAtoms
    ),
    lowered(Body, Result).

lower_contribution_group(
    {Tag, Phase},
    Contributions,
    DataName,
    Accumulator,
    AccumulatorType,
    EnumAtoms
) ->
    [Site] = lists:usort([maps:get(site, Item)
        || Item <- Contributions]),
    [Name] = lists:usort([maps:get(name, Item)
        || Item <- Contributions]),
    [Mode] = lists:usort([maps:get(mode, Item)
        || Item <- Contributions]),
    Clauses = [
        rewrite_contribution_clause(Contribution)
        || Contribution <- Contributions
    ],
    MessageValue = [
        "(Tag::", uppercase(Tag), ", message, bits_from_",
        record_function_name(Tag), "(message))"
    ],
    Arguments = [
        xls_pattern_lower:record_argument(Tag, "message", MessageValue),
        xls_pattern_lower:value_argument("phase"),
        xls_pattern_lower:record_argument(
            DataName,
            "data",
            ["(Tag::", uppercase(DataName), ", data)"]
        )
    ],
    Failure = [
        "(u1:0, u32:0, u32:0, zero!<", AccumulatorType, ">())"
    ],
    {Body, Result} = xls_callback_lower:lower(
        Clauses,
        Arguments,
        DataName,
        fun(R) -> [
            "(u1:1, ", R, ".0, ", R, ".1, ", R, ".2.1)"
        ] end,
        Failure,
        Failure,
        EnumAtoms
    ),
    #{
        site => Site,
        tag => Tag,
        phase => Phase,
        name => Name,
        mode => Mode,
        build => lowered(Body, Result),
        accumulator => Accumulator
    }.

rewrite_contribution_clause(#{
    clause := Clause0,
    key_expression := Key,
    member_expression := Member0,
    value_expression := Value
}) ->
    TypedKey = typed_u32_expression(Key),
    Member = case Member0 of
        %% A bare Erlang zero lowers to DSLX `uN[0]:0` when it is first
        %% materialized in this candidate tuple.  Give the count-mode
        %% placeholder its protocol type explicitly so every match arm has
        %% the same `(u1, u32, u32, Accumulator)` result.
        none -> typed_u32_expression({integer, element(2, Key), 0});
        _ -> typed_u32_expression(Member0)
    end,
    Candidate = {tuple, element(2, Key), [TypedKey, Member, Value]},
    strip_dispatched_phase(replace_body(Clause0, [Candidate])).

typed_u32_expression({integer, Line, Value}) ->
    {call, Line,
        {remote, Line,
            {atom, Line, hls_type},
            {atom, Line, as}},
        [
            {call, Line,
                {remote, Line,
                    {atom, Line, hls_nums},
                    {atom, Line, u32}},
                []},
            {integer, Line, Value}
        ]};
typed_u32_expression(Expression) ->
    Expression.

lower_completion_group(
    #{site := Site, phase := Phase, name := Name, clauses := Clauses0},
    DataName,
    Accumulator,
    AccumulatorType,
    EnumAtoms
) ->
    Clauses = [
        strip_dispatched_internal_phase(
            normalize_cast_result(
                flatten_completion_clause(Clause),
                Phase
            )
        )
        || Clause <- Clauses0
    ],
    Arguments = [
        xls_pattern_lower:value_argument("key"),
        xls_pattern_lower:record_argument(
            Accumulator,
            "accumulator",
            [
                "(Tag::", uppercase(Accumulator), ", accumulator, ",
                "bits_from_", record_function_name(Accumulator),
                "(accumulator))"
            ]
        ),
        xls_pattern_lower:value_argument("phase"),
        xls_pattern_lower:record_argument(
            DataName,
            "data",
            ["(Tag::", uppercase(DataName), ", data)"]
        )
    ],
    Failure = "(phase, data, Directive::FAIL, u1:0)",
    {Body, Result} = xls_callback_lower:lower(
        Clauses,
        Arguments,
        DataName,
        fun(R) -> [
            "(", R, ".0, ", R, ".1.1, ", R, ".2, ", R, ".3)"
        ] end,
        Failure,
        Failure,
        EnumAtoms
    ),
    #{
        site => Site,
        phase => Phase,
        name => Name,
        body => xls_parse:print(Body),
        result => xls_parse:print(Result),
        accumulator_type => AccumulatorType
    }.

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

strip_dispatched_internal_phase(
    {clause, Line, [Key, Accumulator, Phase, Data], Guards, Body}
) ->
    {clause, Line,
        [Key, Accumulator, dispatched_phase_variable(Phase), Data],
        Guards,
        Body}.

lower_reducer(
    #{name := Name, clause := {clause, Line, [
        {atom, _NameLine, Name},
        Left,
        Right
    ], Guards, Body}},
    DataName,
    Accumulator,
    AccumulatorType,
    EnumAtoms
) ->
    Clause = {clause, Line, [Left, Right], Guards, Body},
    TaggedLeft = accumulator_argument_value(Accumulator, "left"),
    TaggedRight = accumulator_argument_value(Accumulator, "right"),
    Arguments = [
        xls_pattern_lower:record_argument(
            Accumulator, "left", TaggedLeft),
        xls_pattern_lower:record_argument(
            Accumulator, "right", TaggedRight)
    ],
    Failure = ["zero!<", AccumulatorType, ">()"],
    {LoweredBody, Result} = xls_callback_lower:lower(
        [Clause],
        Arguments,
        DataName,
        fun(R) -> [R, ".1"] end,
        Failure,
        Failure,
        EnumAtoms
    ),
    #{
        name => Name,
        body => xls_parse:print(LoweredBody),
        result => xls_parse:print(Result)
    }.

accumulator_argument_value(Accumulator, Variable) ->
    [
        "(Tag::", uppercase(Accumulator), ", ", Variable, ", ",
        "bits_from_", record_function_name(Accumulator), "(", Variable,
        "))"
    ].

record_struct_type(Name) ->
    string:titlecase(record_function_name(Name)).

record_fields({attribute, _Line, record, {_Name, Fields}}) ->
    [
        #{
            name => xls_parse:record_field_name(Field),
            type => hls_type:descriptor(Type)
        }
        || {typed_record_field, Field, Type} <- Fields
    ].

literal_list({nil, _Line}, _ContextLine) ->
    [];
literal_list({cons, _Line, Head, Tail}, ContextLine) ->
    [Head | literal_list(Tail, ContextLine)];
literal_list(Expression, ContextLine) ->
    error({nonliteral_hls_statem_actions, ContextLine, Expression}).

require_declared(Kind, Value, Values) ->
    case lists:member(Value, Values) of
        true -> ok;
        false -> error({undeclared_hls_statem_name, Kind, Value, Values})
    end.

strip_dispatched_phase(
    {clause, Line, [First, Phase, Third], Guards, Body}
) ->
    {clause, Line,
        [First, dispatched_phase_variable(Phase), Third], Guards, Body}.

dispatched_phase_variable({atom, Line, _Phase}) ->
    {var, Line, '_'}.

replace_body({clause, Line, Patterns, Guards, _Body}, Body) ->
    {clause, Line, Patterns, Guards, Body}.

split_last(List) ->
    {lists:droplast(List), lists:last(List)}.

enter_args(DataName) ->
    [
        "old_phase",
        "phase",
        ["(Tag::", uppercase(DataName), ", data)"]
    ].

lowered(Body, Result) ->
    #{
        body => xls_parse:print(Body),
        result => xls_parse:print(Result)
    }.

normalize_cast_result(
    {clause, Line, Patterns, Guards, Body0},
    Phase
) ->
    {Prefix, Result0} = split_last(Body0),
    Result = normalize_cast_result_expression(Result0, Phase),
    {clause, Line, Patterns, Guards, Prefix ++ [Result]}.

normalize_cast_result_expression(
    {tuple, Line, [
        {atom, _RepeatLine, repeat_phase},
        Data,
        {atom, _ConsumeLine, consume}
    ]},
    Phase
) ->
    {tuple, Line, [
        {atom, Line, Phase},
        Data,
        {atom, Line, consume},
        {atom, Line, true}
    ]};
normalize_cast_result_expression(
    {tuple, Line, [{atom, _RepeatLine, repeat_phase} | _] = Elements},
    _Phase
) ->
    error({bad_hls_statem_repeat_result, Line, Elements});
normalize_cast_result_expression(
    {tuple, Line, [NextPhase, Data, Directive]},
    _Phase
) ->
    {tuple, Line, [
        NextPhase,
        Data,
        Directive,
        {atom, Line, false}
    ]};
normalize_cast_result_expression(
    {'case', Line, Expression, Clauses},
    Phase
) ->
    {'case', Line, Expression, [
        normalize_cast_result(Clause, Phase) || Clause <- Clauses
    ]};
normalize_cast_result_expression(
    {'if', Line, Clauses},
    Phase
) ->
    {'if', Line, [
        normalize_cast_result(Clause, Phase) || Clause <- Clauses
    ]};
normalize_cast_result_expression(Expression, _Phase) ->
    error({unsupported_hls_statem_internal_result, Expression}).

uppercase(Atom) ->
    string:uppercase(atom_to_list(Atom)).

record_function_name(Atom) ->
    lists:delete($_, atom_to_list(Atom)).
