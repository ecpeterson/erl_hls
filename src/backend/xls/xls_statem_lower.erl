%%%% xls_statem_lower
%%%%
%%%% Validates the Erlang callback surface and lowers it to the closed data
%%%% consumed by xls_statem_codegen.  Generic expression and record lowering
%%%% remains in xls_parse; the renderer never sees Erlang abstract forms.

-module(xls_statem_lower).
-moduledoc false.

-export([interface/2, lower/3, lower/4]).

-type interface() :: map().

-spec interface([erl_parse:abstract_form()], [atom(), ...]) -> interface().
-doc "Summarizes the statically dispatched and emitted hls_statem schemas.".
interface(Forms, PhaseNames) ->
    {_, Sites} = xls_failure_sites:prepare(Forms),
    (interface_from_prepared(prepare_interface(Forms, PhaseNames)))#{failure_sites => Sites}.

-spec lower(file:filename(), [erl_parse:abstract_form()], [atom(), ...]) ->
    iolist().
lower(Filename, Forms, PhaseNames) ->
    lower(Filename, Forms, PhaseNames, #{shared_service => ordinary}).

-spec lower(
    file:filename(),
    [erl_parse:abstract_form()],
    [atom(), ...],
    #{shared_service := ordinary | aggregate_only}
) -> iolist().
lower(Filename, Forms0, PhaseNames, Options0) ->
    {SourceForms, Sites} = xls_failure_sites:prepare(Forms0),
    {Forms, Helpers} = xls_helpers:prepare(SourceForms,
        [{init, 1} | [{Phase, 3} || Phase <- PhaseNames]]),
    Options = validate_options(Options0),
    SharedService = maps:get(shared_service, Options),
    Declarations = declarations(Forms, PhaseNames),
    MessageNames = maps:get(message_names, Declarations),
    MessageWords = maps:from_list([
        {Name, xls_parse:message_words(Forms, Name)} || Name <- MessageNames
    ]),
    Prepared = prepare_callbacks(Forms, Declarations),
    OutputNames = maps:get(output_names, Prepared),
    Capacity = maps:get(capacity, Prepared),
    DataName = maps:get(data_name, Prepared),
    Records = maps:get(records, Prepared),
    StateSummary = state_summary(Records, DataName),
    DataWidth = lists:sum([
        hls_type:width(maps:get(type, Field))
        || Field <- maps:get(fields, StateSummary)
    ]),

    EnumAtoms = enum_atoms(PhaseNames),
    Init = lower_init(maps:get(init_clause, Prepared), DataName, EnumAtoms),
    Entries = lower_entries(
        maps:get(entries, Prepared),
        Prepared#{message_words => MessageWords},
        EnumAtoms
    ),
    Casts = lower_casts(
        maps:get(cast_groups, Prepared),
        DataName,
        EnumAtoms
    ),
    Reductions = maps:get(reductions, Prepared),
    ok = validate_shared_service(SharedService, Reductions),
    RecordDeclarations = xls_parse:print([
        [
            xls_parse:struct_from_record(Record), "\n",
            xls_parse:structfrombits_from_record(Record), "\n",
            xls_parse:bitsfromstruct_from_record(Record), "\n"
        ]
        || Record <- Records
    ]),
    xls_statem_codegen:emit(#{
        source => Filename,
        failure_sites => Sites,
        imports => xls_dslx_imports:from_forms(Forms),
        capacity => Capacity,
        phases => PhaseNames,
        message_names => MessageNames,
        message_words => MessageWords,
        output_names => OutputNames,
        max_entry_effects => max_entry_effects(maps:get(entries, Prepared)),
        data_name => DataName,
        data_width => DataWidth,
        record_declarations => RecordDeclarations,
        helper_functions => xls_helpers:emit(Helpers, DataName, EnumAtoms),
        init => Init,
        entries => Entries,
        casts => Casts,
        reductions => Reductions,
        shared_service => SharedService
    }).

validate_options(Options) when is_map(Options) ->
    case lists:sort(maps:keys(Options)) of
        [shared_service] ->
            case maps:get(shared_service, Options) of
                Mode when Mode =:= ordinary; Mode =:= aggregate_only ->
                    Options;
                Mode ->
                    error({invalid_xls_shared_service, Mode})
            end;
        Keys ->
            error({invalid_xls_options, Keys})
    end;
validate_options(Options) ->
    error({invalid_xls_options, Options}).

validate_shared_service(ordinary, _Reductions) ->
    ok;
validate_shared_service(aggregate_only, none) ->
    error(aggregate_only_requires_reductions);
validate_shared_service(aggregate_only, #{sites := Sites}) ->
    %% Aggregate-only is a low-level actor artifact: a future topology may
    %% classify a partial schema upstream and send its fallback messages on the
    %% ordinary request port.  Whole-schema capture is therefore proved by the
    %% source-fragment planner, while this boundary only requires that the
    %% aggregate contribution itself can be evaluated without actor state.
    Contributions = [{maps:get(phase, Site), Contribution}
        || Site <- Sites,
           Contribution <- maps:get(contributions, Site)],
    Nontransportable = [
        #{phase => Phase, schema => maps:get(tag, Contribution)}
        || {Phase, Contribution} <- Contributions,
           maps:get(source_transportable, Contribution) =:= false
    ],
    case Nontransportable of
        [] -> ok;
        _ -> error({aggregate_only_nontransportable_contributions,
            Nontransportable})
    end,
    Tags = [maps:get(tag, Contribution)
        || {_Phase, Contribution} <- Contributions],
    case duplicate_values(Tags) of
        [] -> ok;
        Duplicates -> error({aggregate_only_ambiguous_contribution_schemas,
            Duplicates})
    end.

prepare_interface(Forms, PhaseNames) ->
    prepare_callbacks(Forms, declarations(Forms, PhaseNames), interface).

declarations(Forms, PhaseNames) ->
    MessageNames = xls_parse:find_tags(Forms),
    OutputNames = xls_parse:find_attribute(Forms, hls_outputs),
    Capacity = xls_parse:find_attribute(Forms, hls_mailbox_capacity),
    DataName = xls_parse:find_attribute(Forms, hls_data),
    ok = validate_names(PhaseNames, MessageNames, OutputNames, DataName),
    ok = validate_capacity(Capacity),

    RecordNames = MessageNames ++ [DataName],
    Records = [xls_parse:find_record(Forms, Name) || Name <- RecordNames],
    ok = lists:foreach(
        fun xls_parse:validate_record_defaults/1,
        Records
    ),
    #{
        module => xls_parse:find_attribute(Forms, module),
        phases => PhaseNames,
        message_names => MessageNames,
        output_names => OutputNames,
        capacity => Capacity,
        data_name => DataName,
        records => Records
    }.

prepare_callbacks(Forms, Declarations) ->
    prepare_callbacks(Forms, Declarations, closed).

prepare_callbacks(Forms, Declarations, ReductionMode) ->
    PhaseNames = maps:get(phases, Declarations),
    MessageNames = maps:get(message_names, Declarations),
    OutputNames = maps:get(output_names, Declarations),
    InitClause = xls_init:clause(Forms, hls_statem),
    _ = rewrite_init_result(InitClause),
    Callbacks = xls_statem_callbacks:prepare(
        Forms,
        PhaseNames
    ),
    Entries = analyze_entries(
        maps:get(enter, Callbacks),
        PhaseNames,
        MessageNames,
        OutputNames
    ),
    CastGroups0 = analyze_cast_groups(
        maps:get(cast, Callbacks),
        PhaseNames,
        MessageNames
    ),
    InternalGroups = xls_statem_reduction_lower:internal_groups(
        maps:get(internal, Callbacks),
        PhaseNames
    ),
    ReductionContext = #{
        phases => PhaseNames,
        entries => Entries,
        cast_groups => CastGroups0,
        internal_groups => InternalGroups,
        message_names => MessageNames,
        data_name => maps:get(data_name, Declarations)
    },
    ReductionSlots = prepare_reduction_slots(
        ReductionMode,
        Forms,
        ReductionContext,
        maps:get(records, Declarations)
    ),
    maps:merge(Declarations#{
        init_clause => InitClause,
        initial_phase => initial_phase(InitClause, PhaseNames),
        entries => Entries
    }, ReductionSlots).

prepare_reduction_slots(closed, Forms, Context, Records) ->
    #{reduction := Reduction, cast_groups := CastGroups} =
        xls_statem_reduction_lower:analyze(Forms, Context),
    #{
        records => reduction_records(Forms, Records, Reduction),
        cast_groups => CastGroups,
        reductions => Reduction,
        reduction_interface => reduction_interface(Reduction)
    };
prepare_reduction_slots(interface, Forms, Context, Records) ->
    #{reduction := ReductionInterface, cast_groups := CastGroups} =
        xls_statem_reduction_lower:analyze_interface(Forms, Context),
    #{
        records => reduction_records(Forms, Records, ReductionInterface),
        cast_groups => CastGroups,
        reduction_interface => ReductionInterface
    }.

reduction_records(_Forms, Records, none) ->
    Records;
reduction_records(Forms, Records, Reduction) ->
    Name = maps:get(name, maps:get(accumulator, Reduction)),
    Records ++ [xls_parse:find_record(Forms, Name)].

%%%
%%% Actor interface analysis
%%%

interface_from_prepared(Prepared) ->
    Entries = maps:get(entries, Prepared),
    CastGroups = maps:get(cast_groups, Prepared),
    ReductionInterface = maps:get(reduction_interface, Prepared),
    Base = #{
        version => 3,
        module => maps:get(module, Prepared),
        phases => maps:get(phases, Prepared),
        initial_phase => maps:get(initial_phase, Prepared),
        outputs => maps:get(output_names, Prepared),
        mailbox_capacity => maps:get(capacity, Prepared),
        state => state_summary(
            maps:get(records, Prepared),
            maps:get(data_name, Prepared)
        ),
        schemas => schema_summaries(
            maps:get(records, Prepared),
            maps:get(message_names, Prepared)
        ),
        dispatches => append_new_dispatches(
            dispatches(
                CastGroups,
                maps:get(message_names, Prepared),
                maps:get(phases, Prepared)
            ),
            reduction_dispatches(ReductionInterface)
        ),
        entry_effects => lists:append([
            interface_effects(Entry) || Entry <- Entries
        ])
    },
    case ReductionInterface of
        none -> Base;
        Interface -> Base#{reductions => Interface}
    end.

reduction_interface(none) -> none;
reduction_interface(Reduction) ->
    xls_statem_reduction_ir:interface(Reduction).

reduction_dispatches(none) -> [];
reduction_dispatches(#{sites := Sites}) ->
    lists:usort([
        #{schema => Tag, phase => maps:get(phase, Site)}
        || Site <- Sites,
           Tag <- maps:get(contributions, Site)
    ]).

append_new_dispatches(Dispatches, Additional) ->
    Dispatches ++ [
        Dispatch
        || Dispatch <- Additional,
           not lists:member(Dispatch, Dispatches)
    ].

state_summary(Records, Name) ->
    [Record] = [
        Candidate
        || Candidate = {attribute, _Line, record, {RecordName, _Fields}} <-
               Records,
           RecordName =:= Name
    ],
    #{
        name => Name,
        fields => record_fields(Record)
    }.

initial_phase({clause, _Line, _Patterns, _Guards, Body}, PhaseNames) ->
    {Prefix, Result} = split_last(Body),
    Phase = case Result of
        {tuple, _TupleLine, [
            {atom, _OkLine, ok},
            PhaseExpression,
            _Data
        ]} ->
            resolve_static_atom(PhaseExpression, Prefix);
        _ -> unknown
    end,
    case Phase of
        unknown -> unknown;
        _ ->
            require_declared(initial_phase, Phase, PhaseNames),
            Phase
    end.

resolve_static_atom({atom, _Line, Value}, _Prefix) ->
    Value;
resolve_static_atom({var, _Line, Name}, Prefix) ->
    case [
        Value
        || {match, _MatchLine,
                {var, _VarLine, Name0},
                {atom, _AtomLine, Value}} <- Prefix,
           Name0 =:= Name
    ] of
        [Value] -> Value;
        _ -> unknown
    end;
resolve_static_atom(_Expression, _Prefix) ->
    unknown.

schema_summaries(Records, MessageNames) ->
    RecordIndex = maps:from_list([
        {Name, Record}
        || Record = {attribute, _Line, record, {Name, _Fields}} <- Records
    ]),
    [
        schema_summary(maps:get(Name, RecordIndex), Name, Selector)
        || {Selector, Name} <- lists:zip(
            lists:seq(3, length(MessageNames) + 2),
            MessageNames
        )
    ].

schema_summary(Record, Name, Selector) ->
    #{
        name => Name,
        selector => Selector,
        fields => record_fields(Record)
    }.

record_fields({attribute, _Line, record, {_Name, Fields}}) ->
    [
        #{
            name => xls_parse:record_field_name(Field),
            type => hls_type:descriptor(Type)
        }
        || {typed_record_field, Field, Type} <- Fields
    ].

analyze_entries(Clauses, PhaseNames, MessageNames, OutputNames) ->
    Entries = [
        analyze_entry(Clause, PhaseNames, MessageNames, OutputNames)
        || Clause <- Clauses
    ],
    EntryPhases = [maps:get(phase, Entry) || Entry <- Entries],
    ok = require_unique(entry_phase, EntryPhases),
    case lists:sort(EntryPhases) =:= lists:sort(PhaseNames) of
        true -> order_entries(Entries, PhaseNames);
        false -> error({incomplete_hls_statem_entries,
            PhaseNames, EntryPhases})
    end.

analyze_entry(
    Clause = {clause, Line, Patterns, Guards, _Body},
    PhaseNames,
    MessageNames,
    OutputNames
) ->
    Phase = entry_phase(Line, Patterns, Guards, PhaseNames),
    (xls_statem_entry:analyze(Clause, MessageNames, OutputNames))#{phase => Phase}.

order_entries(Entries, PhaseNames) ->
    EntryIndex = maps:from_list([
        {maps:get(phase, Entry), Entry} || Entry <- Entries
    ]),
    [maps:get(Phase, EntryIndex) || Phase <- PhaseNames].

interface_effects(#{phase := Phase} = Entry) ->
    [Effect#{phase => Phase} || Effect <- xls_statem_entry:effects(Entry)].

max_entry_effects(Entries) ->
    lists:max([xls_statem_entry:max_effects(Entry) || Entry <- Entries]).

analyze_cast_groups(Clauses, PhaseNames, MessageNames) ->
    xls_callback_lower:group_by(
        Clauses,
        fun(Clause) ->
            cast_key(Clause, MessageNames, PhaseNames)
        end
    ).

dispatches(CastGroups, MessageNames, PhaseNames) ->
    Keys = maps:from_keys([Key || {Key, _Clauses} <- CastGroups], true),
    [
        #{schema => Schema, phase => Phase}
        || Schema <- MessageNames,
           Phase <- PhaseNames,
           maps:is_key({Schema, Phase}, Keys)
    ].

%%%
%%% init/1
%%%

lower_init(Clause0, DataName, EnumAtoms) ->
    Clause = rewrite_init_result(Clause0),
    Postprocessor = fun(R) -> [
        "Machine {\n",
        "  phase: ", R, ".0,\n",
        "  entered_from: ", R, ".0,\n",
        "  data: ", R, ".1.1,\n",
        "  enter_pending: u1:1,\n",
        "  ..zero!<Machine>()\n",
        "}"
    ] end,
    xls_init:lower(Clause, DataName, Postprocessor, EnumAtoms).

rewrite_init_result({clause, Line, Patterns, Guards, Body0}) ->
    {Prefix, Last} = split_last(Body0),
    case Last of
        {tuple, TupleLine, [
            {atom, _OkLine, ok},
            Phase,
            Data
        ]} ->
            {clause, Line, Patterns, Guards,
                Prefix ++ [{tuple, TupleLine, [Phase, Data]}]};
        _ ->
            error({bad_hls_statem_init_result, Line, Last})
    end.

%%%
%%% Phase entry
%%%

%% TODO(XLS sum types): leaf constructors could return native tagged-tuple
%% variants through case/if, replacing layout interning and the xls_map bridge
%% to a hand-packed EntryOutcome. Named action segments could then rejoin at
%% their bindings instead of copying the continuation into each alternative.
%% Retain the entry plan's bounded alternatives,
%% evaluation order, failure predicate, and conservative interface analysis.
lower_entries(Entries, Prepared, EnumAtoms) ->
    #{data_name := DataName, message_words := MessageWords,
        reductions := Reductions} = Prepared,
    {Layouts, {LayoutCount, _}} = lists:mapfoldl(
        fun(#{phase := Phase, variants := Variants}, Index) ->
            lists:mapfoldl(fun(Variant = #{actions := Actions}, {Next, Seen}) ->
                Key = {Phase, Actions},
                case maps:find(Key, Seen) of
                    {ok, Layout} ->
                        {Variant#{layout => Layout, phase => Phase}, {Next, Seen}};
                    error when Next < 256 ->
                        {Variant#{layout => Next, phase => Phase},
                            {Next + 1, Seen#{Key => Next}}};
                    error -> error({too_many_hls_statem_entry_layouts, 256})
                end
            end, Index, Variants)
        end, {0, #{}}, Entries),
    true = LayoutCount > 0,
    AllLayouts = lists:append(Layouts),
    PayloadBits = max(1, lists:max([lists:sum([
        maps:get(Tag, MessageWords) * 32 || #{tag := Tag} <- Actions])
        || #{actions := Actions} <- AllLayouts])),
    [begin
        Clause = xls_statem_entry:map_leaves(strip_dispatched_phase(Program),
            fun(Id, Value) ->
                Variant = lists:nth(Id + 1, EntryLayouts),
                {xls_map, 0, Value, fun(R) ->
                    xls_statem_codegen:entry_value(R, Variant,
                        PayloadBits, MessageWords, Reductions)
                end}
            end),
        Outcome = xls_parse:clause_outcome(Clause, enter_args(DataName),
            DataName, EnumAtoms),
        #{phase => Phase, layouts => lists:uniq([
                maps:with([phase, layout, actions], Layout) || Layout <- EntryLayouts]),
            evaluation => maps:map(fun(_Key, V) -> xls_parse:print(V) end, Outcome)}
    end || {#{phase := Phase, program := Program}, EntryLayouts} <-
        lists:zip(Entries, Layouts)].

enter_args(DataName) ->
    ["old_phase", "phase", ["(Tag::", uppercase(DataName), ", data)"]].

%%%
%%% Cast dispatch
%%%

lower_casts(Groups, DataName, EnumAtoms) ->
    [
        lower_cast_group(
            Key,
            Group,
            DataName,
            EnumAtoms
        )
        || {Key, Group} <- Groups
    ].

lower_cast_group(
    {Tag, Phase},
    Clauses0,
    DataName,
    EnumAtoms
) ->
    Clauses = [
        strip_dispatched_phase(normalize_cast_result(Clause, Phase))
        || Clause <- Clauses0
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
    Failure = fun(Code) -> ["(phase, data, Directive::FAIL, u1:0, ", Code, ")"] end,
    [{clause, FirstLine, _, _, _} | _] = Clauses,
    {Body, Result} = xls_callback_lower:lower(
        Clauses,
        Arguments,
        DataName,
        fun(R) -> [
            "(", R, ".0, ", R, ".1.1, ", R, ".2, ", R, ".3, ", R, ".4)"
        ] end,
        Failure(xls_failure_sites:at(function_clause, FirstLine)),
        Failure,
        EnumAtoms
    ),
    #{
        tag => Tag,
        phase => Phase,
        body => xls_parse:print(Body),
        result => xls_parse:print(Result)
    }.

%% `repeat_phase` is a scheduling boundary rather than a phase value. Normalize
%% both callback result forms to one XLS product whose final bit requests the
%% boundary. Keeping this rewrite here prevents the generic expression lowerer
%% from having to know about hls_statem callback semantics. The conclusion
%% must be the syntactically final tuple, case, or if: following an arbitrary
%% value through local bindings would require typed expression dataflow here.
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
        {atom, Line, true},
        {xls_map, 0, {atom, 0, false}, fun(_) -> "hls_failure::NONE" end}
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
    Result = {tuple, Line, [NextPhase, Data, Directive, {atom, Line, false}]},
    {xls_map, Line, Result, fun(R) ->
        ["(", R, ".0, ", R, ".1, ", R, ".2, ", R, ".3, ",
            cast_failure(Directive, Line, R), ")"]
    end};
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
    error({unsupported_hls_statem_cast_result, Expression}).

cast_failure({atom, _, Directive}, _Line, _Result)
        when Directive =:= consume; Directive =:= postpone ->
    "hls_failure::NONE";
cast_failure({atom, _, fail}, Line, _Result) ->
    xls_failure_sites:at(explicit_fail, Line);
cast_failure(_Directive, Line, Result) ->
    ["hls_failure::check(", Result, ".2 == Directive::FAIL, ",
        xls_failure_sites:at(explicit_fail, Line), ")"].

cast_key(
    {clause, Line, Patterns, _Guards, _Body},
    MessageNames,
    PhaseNames
) ->
    {Tag, Phase} = cast_head(
        Line,
        Patterns,
        MessageNames,
        PhaseNames
    ),
    {Tag, Phase}.

cast_head(_Line, [MessagePattern, {atom, _PhaseLine, Phase}, _DataPattern],
        MessageNames, PhaseNames) ->
    Tag = xls_pattern_lower:record_pattern_name(MessagePattern),
    require_declared(cast_message, Tag, MessageNames),
    require_declared(cast_phase, Phase, PhaseNames),
    {Tag, Phase};
cast_head(Line, Patterns, _MessageNames, _PhaseNames) ->
    error({unsupported_hls_statem_cast_head, Line, Patterns}).

%%%
%%% Validation and AST utilities
%%%

validate_names(PhaseNames, MessageNames, OutputNames, DataName)
        when is_list(PhaseNames), is_list(MessageNames), is_list(OutputNames),
             is_atom(DataName) ->
    true = PhaseNames =/= [],
    true = MessageNames =/= [],
    true = OutputNames =/= [],
    case length(OutputNames) =< 255 of
        true -> ok;
        false -> error({too_many_hls_statem_outputs,
            length(OutputNames), 255})
    end,
    lists:foreach(
        fun(Phase) ->
            case lists:member(Phase, [repeat_phase, reduce, terminate]) of
                true -> error({reserved_hls_statem_phase, Phase});
                false -> ok
            end
        end,
        PhaseNames
    ),
    ok = require_unique(phase, PhaseNames),
    ok = require_unique(message_tag, MessageNames),
    ok = require_unique(output, OutputNames),
    false = lists:member(DataName, MessageNames),
    ok.

entry_phase(_Line, [
    {var, _OldLine, _OldPhase},
    {atom, _PhaseLine, Phase},
    {var, _DataLine, _Data}
], [], PhaseNames) ->
    require_declared(entry_phase, Phase, PhaseNames),
    Phase;
entry_phase(Line, Patterns, Guards, _PhaseNames) ->
    error({unsupported_hls_statem_enter_head, Line, Patterns, Guards}).

validate_capacity(Capacity)
        when is_integer(Capacity), Capacity > 0, Capacity =< 255 ->
    ok;
validate_capacity(Capacity) ->
    error({invalid_hls_mailbox_capacity, Capacity}).

require_unique(Kind, Values) ->
    case length(Values) =:= length(lists:usort(Values)) of
        true -> ok;
        false -> error({duplicate_hls_statem_declaration, Kind, Values})
    end.

duplicate_values(Values) ->
    duplicate_values(Values, #{}, #{}).

duplicate_values([], _Seen, Duplicates) ->
    lists:sort(maps:keys(Duplicates));
duplicate_values([Value | Rest], Seen, Duplicates) ->
    case maps:is_key(Value, Seen) of
        true -> duplicate_values(Rest, Seen, Duplicates#{Value => true});
        false -> duplicate_values(Rest, Seen#{Value => true}, Duplicates)
    end.

require_declared(Kind, Value, Values) when is_list(Values) ->
    case lists:member(Value, Values) of
        true -> ok;
        false -> error({undeclared_hls_statem_name, Kind, Value, Values})
    end.

enum_atoms(PhaseNames) ->
    PhaseAtoms = [
        {Name, ["Phase::", uppercase(Name)]} || Name <- PhaseNames
    ],
    DirectiveAtoms = [
        {consume, "Directive::CONSUME"},
        {postpone, "Directive::POSTPONE"},
        {fail, "Directive::FAIL"}
    ],
    maps:from_list(PhaseAtoms ++ DirectiveAtoms).

strip_dispatched_phase({clause, Line, [First, Phase, Third], Guards, Body}) ->
    {clause, Line, [First, dispatched_phase_variable(Phase), Third],
        Guards, Body}.

dispatched_phase_variable({atom, Line, _Phase}) ->
    {var, Line, '_'}.

split_last(List) ->
    {lists:droplast(List), lists:last(List)}.

uppercase(Atom) ->
    string:uppercase(atom_to_list(Atom)).

record_function_name(Atom) ->
    lists:delete($_, atom_to_list(Atom)).
