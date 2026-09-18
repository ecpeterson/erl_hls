%%%% xls_statem_lower
%%%%
%%%% Validates the Erlang callback surface and lowers it to the closed data
%%%% consumed by xls_statem_codegen.  Generic expression and record lowering
%%%% remains in xls_parse; the renderer never sees Erlang abstract forms.

-module(xls_statem_lower).
-moduledoc false.

-export([interface/2, lower/3, lower/4]).

-type interface() :: map().

-spec interface([hls_source:form()], [atom(), ...]) -> interface().
-doc "Summarizes the statically dispatched and emitted hls_statem schemas.".
interface(Forms, PhaseNames) ->
    {Annotated, Sites} = xls_failure_sites:prepare(Forms),
    (interface_from_prepared(prepare_interface(Annotated, PhaseNames)))#{failure_origins => Sites}.

-doc "Validates and emits an hls_statem actor with ordinary shared-service settings.".
-spec lower(file:filename(), [hls_source:form()], [atom(), ...]) ->
    iolist().
lower(Filename, Forms, PhaseNames) ->
    lower(Filename, Forms, PhaseNames, #{shared_service => ordinary}).

-doc "Validates and emits an hls_statem actor with the selected service and observation options.".
-spec lower(
    file:filename(),
    [hls_source:form()],
    [atom(), ...],
    #{shared_service := ordinary | aggregate_only, mailbox_debug => boolean(), direct_actor_debug => boolean()}
) -> iolist().
lower(Filename, Forms0, PhaseNames, Options0) ->
    Declarations = declarations(Forms0, PhaseNames),
    {SourceForms, Sites} = xls_failure_sites:prepare(Forms0),
    {Forms, Helpers} = xls_helpers:prepare(SourceForms,
        [{init, 1}, {reduce, 3} | [{Phase, 3} || Phase <- PhaseNames]]),
    Options = validate_options(Options0),
    SharedService = maps:get(shared_service, Options),
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
    CallSpec = maps:get(retained_calls, Prepared),
    HasCalls = CallSpec =/= none,
    Init = lower_init(maps:get(init_clause, Prepared), DataName, EnumAtoms, Prepared),
    Entries = lower_entries(
        maps:get(entries, Prepared),
        Prepared#{message_words => MessageWords},
        EnumAtoms
    ),
    Names = maps:get(continuations, Prepared),
    Casts = lower_casts(
        maps:get(cast_groups, Prepared) ++ maps:get(call_groups, Prepared),
        Names, HasCalls,
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
        continuations => Names,
        retained_calls => CallSpec,
        internal_steps => xls_statem_continuation:lower(maps:get(internal_steps, Prepared),
            Names, DataName, EnumAtoms, HasCalls, fun(C, P) -> normalize_cast_result(C, P, Names, HasCalls) end),
        reductions => Reductions,
        shared_service => SharedService,
        mailbox_debug => xls_scheduler_observation:enabled(Options),
        direct_actor_debug => xls_actor_observation:enabled(Options)
    }).

validate_options(Options) when is_map(Options) ->
    case lists:sort(maps:keys(Options)) -- [mailbox_debug, direct_actor_debug] of
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

%% Validates the fixed vocabulary, storage bounds and optional caller contract.
-spec declarations([hls_source:form()], [atom(), ...]) -> map().
declarations(Forms, PhaseNames) ->
    ok = xls_names:actor(Forms, hls_statem),
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
        continuations => xls_statem_continuation:names(Forms),
        retained_calls => retained_calls(Forms, OutputNames),
        data_name => DataName,
        records => Records
    }.

%% Retained replies leave through one declared output; it must route back to the owning host.
-spec retained_calls([hls_source:form()], [atom()]) -> none | map().
retained_calls(Forms, Outputs) ->
    case xls_parse:find_optional_attribute(Forms, hls_pending_calls) of
        none -> none;
        {ok, _} ->
            Contract = hls_service_contract:from_forms(Forms),
            Port = xls_parse:find_attribute(Forms, hls_reply_port),
            true = lists:member(Port, Outputs),
            true = map_size(maps:get(calls, Contract)) > 0,
            Contract#{port => Port}
    end.

prepare_callbacks(Forms, Declarations) ->
    prepare_callbacks(Forms, Declarations, closed).

%% Partitions callback kinds before deriving entry and reduction interfaces.
-spec prepare_callbacks([hls_source:form()], map(), interface | closed) -> map().
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
    CallGroups = analyze_cast_groups(maps:get(call, Callbacks), PhaseNames, MessageNames),
    case CallGroups =/= [] andalso maps:get(retained_calls, Declarations) =:= none of
        true -> error(hls_statem_calls_not_declared); false -> ok
    end,
    {StepGroups, CompletionClauses} = xls_statem_continuation:groups(
        maps:get(internal, Callbacks), maps:get(continuations, Declarations)),
    InternalGroups = xls_statem_reduction_lower:internal_groups(
        CompletionClauses,
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
        call_groups => CallGroups,
        internal_steps => StepGroups,
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

%% Describes public routing and all actor-private storage required by a scheduler.
-spec interface_from_prepared(map()) -> interface().
interface_from_prepared(Prepared) ->
    Entries = maps:get(entries, Prepared),
    CastGroups = maps:get(cast_groups, Prepared) ++ maps:get(call_groups, Prepared),
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
        none -> with_continuation_width(Base, Prepared);
        Interface -> with_continuation_width(Base#{reductions => Interface}, Prepared)
    end.

%% Finite event state is private scheduler storage, separate from application data.
-spec with_continuation_width(map(), map()) -> map().
with_continuation_width(Interface, #{retained_calls := #{pending_calls := N, port := Port, calls := Calls}}) ->
    Interface#{continuation_width => 8, reply_storage_width => 96 + 72 * N,
        reply_effects => [#{port => Port, schema => Tag} || Tag <- lists:usort(lists:append(maps:values(Calls)))]};
with_continuation_width(Interface, #{continuations := []}) -> Interface;
with_continuation_width(Interface, _Prepared) -> Interface#{continuation_width => 8}.

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

initial_phase(Clause, PhaseNames) ->
    Phases = lists:usort([case Result of
        {tuple, _, [{atom, _, ok}, {atom, _, Phase}, _Data]} -> Phase;
        _ -> unknown
    end || Result <- xls_callback_result:results(Clause)]),
    [require_declared(initial_phase, Phase, PhaseNames)
        || Phase <- Phases, Phase =/= unknown],
    case Phases of
        [Phase] when Phase =/= unknown ->
            Phase;
        _ -> unknown
    end.

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

%% Builds the checked cold-start state with fresh reply ownership.
-spec lower_init(erl_parse:abstract_clause(), atom(), map(), map()) -> xls_init:lowered().
lower_init(Clause0, DataName, EnumAtoms, Spec) ->
    Clause = rewrite_init_result(Clause0),
    Postprocessor = fun(R) -> [
        "Machine {\n",
        "  phase: ", R, ".0,\n",
        "  entered_from: ", R, ".0,\n",
        "  data: ", R, ".1.1,\n",
        xls_statem_reply_codegen:initial(Spec),
        "  enter_pending: u1:1,\n",
        "  ..zero!<Machine>()\n",
        "}"
    ] end,
    xls_init:lower(Clause, DataName, Postprocessor, EnumAtoms).

rewrite_init_result(Clause) ->
    xls_callback_result:map(Clause, fun
        ({tuple, TupleLine, [
            {atom, _OkLine, ok},
            Phase,
            Data
        ]}) -> {tuple, TupleLine, [Phase, Data]};
        (Expression) ->
            error({bad_hls_statem_init_result, element(2, Expression), Expression})
    end).

%%%
%%% Phase entry
%%%

%% TODO(XLS sum types): leaf constructors could return native tagged-tuple
%% variants through case/if, replacing layout interning and the xls_map bridge
%% to a hand-packed EntryOutcome. Named action segments could then rejoin at
%% their bindings instead of copying the continuation into each alternative.
%% Retain the entry plan's bounded alternatives,
%% evaluation order, failure predicate, and conservative interface analysis.
%% Lowers entry alternatives into interned, statically routed effect layouts.
-spec lower_entries([map()], map(), map()) -> [map()].
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
    PayloadBits = max(case xls_statem_reply_codegen:enabled(Prepared) of true -> 128; false -> 1 end, lists:max([lists:sum([
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
    ["old_phase", "phase", ["(Tag::", xls_names:enum_member(DataName), ", data)"]].

%%%
%%% Cast dispatch
%%%

%% Lowers schema/phase groups through the common checked callback path.
-spec lower_casts(list(), [atom()], boolean(), atom(), map()) -> [map()].
lower_casts(Groups, Names, HasCalls, DataName, EnumAtoms) ->
    [
        lower_cast_group(
            Key,
            Group,
            Names, HasCalls,
            DataName,
            EnumAtoms
        )
        || {Key, Group} <- Groups
    ].

%% Carries a call handle only for call clauses; cast clauses retain their original arguments.
-spec lower_cast_group({atom(), atom()}, [erl_parse:abstract_clause()], [atom()], boolean(), atom(), map()) -> map().
lower_cast_group(
    {Tag, Phase},
    Clauses0,
    Names, HasCalls,
    DataName,
    EnumAtoms
) ->
    Clauses = [
        strip_dispatched_phase(normalize_cast_result(Clause, Phase, Names, HasCalls))
        || Clause <- Clauses0
    ],
    MessageValue = [
        "(Tag::", xls_names:enum_member(Tag), ", message, bits_from_",
        xls_names:record_codec(Tag), "(message))"
    ],
    IsCall = case hd(Clauses0) of {clause, _, Patterns0, _, _} -> length(Patterns0) =:= 4 end,
    Arguments = [
        xls_pattern_lower:record_argument(Tag, "message", MessageValue),
        xls_pattern_lower:value_argument("phase"),
        xls_pattern_lower:record_argument(
            DataName,
            "data",
            ["(Tag::", xls_names:enum_member(DataName), ", data)"]
        )
    ] ++ case IsCall of true -> [xls_pattern_lower:value_argument("call_from")]; false -> [] end,
    Tail = case {Names, HasCalls} of
        {[], false} -> [];
        {_, false} -> ", u8:0";
        {_, true} -> ", u8:0, u64:0, zero!<axis::Frame>(), true"
    end,
    Failure = fun(Code) -> ["(phase, data, Directive::FAIL, u1:0, ", Code, Tail, ")"] end,
    [{clause, FirstLine, _, _, _} | _] = Clauses,
    {Body, Result} = xls_callback_lower:lower(
        Clauses,
        Arguments,
        DataName,
        fun(R) -> [
            "(", R, ".0, ", R, ".1.1, ", R, ".2, ", R, ".3, ", R, ".4",
                case {Names, HasCalls} of {[], false} -> []; _ -> [", ", R, ".5"] end,
                case HasCalls of true -> [", ", R, ".6, ", R, ".7, ", R, ".8"]; false -> [] end, ")"
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
%% from having to know about hls_statem callback semantics. The shared result
%% normalizer exposes constructors through aliases and structural choices.
%% Adds finite internal events and retained replies to checked callback conclusions.
-spec normalize_cast_result(erl_parse:abstract_clause(), atom(), [atom()], boolean()) -> erl_parse:abstract_clause().
normalize_cast_result(Clause = {clause, _, Patterns, _, _}, Phase, Names, HasCalls) ->
    Map = case {Names, HasCalls} of {[], false} -> fun xls_callback_result:map/2; _ -> fun xls_callback_result:map_actions/2 end,
    Map(Clause, fun(Result) ->
        ok = validate_call_directive(Patterns, Result),
        xls_statem_continuation:normalize(Result, Names, HasCalls,
            fun(R) -> normalize_cast_result_expression(R, Phase) end)
    end).

%% A call is consumed once; replay would need to preserve its previously allocated handle.
-spec validate_call_directive([term()], term()) -> ok.
validate_call_directive([_, _, _, _], {tuple, _, [_, _, Directive | _]}) ->
    case Directive of
        {atom, _, consume} -> ok;
        {atom, _, fail} -> ok;
        _ -> error({unsupported_hls_statem_call_directive, Directive})
    end;
validate_call_directive(_Patterns, _Result) -> ok.

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

%% Extracts the statically selected schema and phase from cast or call patterns.
-spec cast_head(erl_anno:anno(), [erl_parse:abstract_expr()], [atom()], [atom()]) -> {atom(), atom()}.
cast_head(Line, [Message, Phase, Data, _From], MessageNames, PhaseNames) ->
    cast_head(Line, [Message, Phase, Data], MessageNames, PhaseNames);
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
        {Name, ["Phase::", xls_names:enum_member(Name)]} || Name <- PhaseNames
    ],
    DirectiveAtoms = [
        {consume, "Directive::CONSUME"},
        {postpone, "Directive::POSTPONE"},
        {fail, "Directive::FAIL"}
    ],
    maps:from_list(PhaseAtoms ++ DirectiveAtoms).

%% Avoids testing a phase literal after the dispatch table has already selected it.
-spec strip_dispatched_phase(erl_parse:abstract_clause()) -> erl_parse:abstract_clause().
strip_dispatched_phase({clause, Line, [First, Phase, Third, From], Guards, Body}) ->
    {clause, Line, [First, dispatched_phase_variable(Phase), Third, From], Guards, Body};
strip_dispatched_phase({clause, Line, [First, Phase, Third], Guards, Body}) ->
    {clause, Line, [First, dispatched_phase_variable(Phase), Third],
        Guards, Body}.

dispatched_phase_variable({atom, Line, _Phase}) ->
    {var, Line, '_'}.
