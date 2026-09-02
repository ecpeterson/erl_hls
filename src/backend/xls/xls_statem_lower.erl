%%%% xls_statem_lower
%%%%
%%%% Validates the Erlang callback surface and lowers it to the closed data
%%%% consumed by xls_statem_codegen.  Generic expression and record lowering
%%%% remains in xls_parse; the renderer never sees Erlang abstract forms.

-module(xls_statem_lower).
-moduledoc false.

-export([interface/2, lower/3]).

-type interface() :: map().

-spec interface([erl_parse:abstract_form()], [atom(), ...]) -> interface().
-doc "Summarizes the statically dispatched and emitted hls_statem schemas.".
interface(Forms, PhaseNames) ->
    interface_from_prepared(prepare(Forms, PhaseNames)).

-spec lower(file:filename(), [erl_parse:abstract_form()], [atom(), ...]) ->
    iolist().
lower(Filename, Forms, PhaseNames) ->
    Declarations = declarations(Forms, PhaseNames),
    MessageNames = maps:get(message_names, Declarations),
    MessageWords = maps:from_list([
        {Name, message_words(Forms, Name)} || Name <- MessageNames
    ]),
    Prepared = prepare_callbacks(Forms, Declarations),
    OutputNames = maps:get(output_names, Prepared),
    Capacity = maps:get(capacity, Prepared),
    DataName = maps:get(data_name, Prepared),
    Records = maps:get(records, Prepared),

    EnumAtoms = enum_atoms(PhaseNames),
    Init = lower_init(maps:get(init_clause, Prepared), DataName, EnumAtoms),
    Entries = lower_entries(
        maps:get(entries, Prepared),
        OutputNames,
        DataName,
        EnumAtoms
    ),
    Casts = lower_casts(
        maps:get(cast_groups, Prepared),
        DataName,
        EnumAtoms
    ),
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
        capacity => Capacity,
        phases => PhaseNames,
        message_names => MessageNames,
        message_words => MessageWords,
        output_names => OutputNames,
        max_entry_effects => max_entry_effects(maps:get(entries, Prepared)),
        data_name => DataName,
        record_declarations => RecordDeclarations,
        init => Init,
        entries => Entries,
        casts => Casts
    }).

prepare(Forms, PhaseNames) ->
    prepare_callbacks(Forms, declarations(Forms, PhaseNames)).

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
    PhaseNames = maps:get(phases, Declarations),
    MessageNames = maps:get(message_names, Declarations),
    OutputNames = maps:get(output_names, Declarations),
    [InitClause] = xls_parse:find_function(Forms, init, 1),
    ok = validate_init_head(InitClause),
    _ = rewrite_init_result(InitClause),
    Entries = analyze_entries(
        Forms,
        PhaseNames,
        MessageNames,
        OutputNames
    ),
    CastGroups = analyze_cast_groups(Forms, PhaseNames, MessageNames),
    Declarations#{
        init_clause => InitClause,
        initial_phase => initial_phase(InitClause, PhaseNames),
        entries => Entries,
        cast_groups => CastGroups
    }.

%%%
%%% Actor interface analysis
%%%

interface_from_prepared(Prepared) ->
    Entries = maps:get(entries, Prepared),
    CastGroups = maps:get(cast_groups, Prepared),
    #{
        version => 1,
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
        dispatches => dispatches(
            CastGroups,
            maps:get(message_names, Prepared),
            maps:get(phases, Prepared)
        ),
        entry_effects => lists:append([
            interface_effects(Entry) || Entry <- Entries
        ])
    }.

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

analyze_entries(Forms, PhaseNames, MessageNames, OutputNames) ->
    Clauses = xls_parse:find_function(Forms, handle_enter, 3),
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
    Clause = {clause, Line, Patterns, Guards, Body},
    PhaseNames,
    MessageNames,
    OutputNames
) ->
    Phase = entry_phase(Line, Patterns, Guards, PhaseNames),
    {Prefix, Last} = split_last(Body),
    {DataExpression, ActionList} = case Last of
        {tuple, _TupleLine, [DataExpr, ActionExpression]} ->
            {DataExpr, ActionExpression};
        _ -> error({bad_hls_statem_enter_result, Line, Last})
    end,
    #{
        phase => Phase,
        clause => Clause,
        prefix => Prefix,
        data_expression => DataExpression,
        actions => parse_actions(
            ActionList,
            Prefix,
            MessageNames,
            OutputNames,
            Line
        )
    }.

order_entries(Entries, PhaseNames) ->
    EntryIndex = maps:from_list([
        {maps:get(phase, Entry), Entry} || Entry <- Entries
    ]),
    [maps:get(Phase, EntryIndex) || Phase <- PhaseNames].

interface_effects(#{phase := Phase, actions := Actions}) ->
    [
        maybe_conditional_effect(Action, #{
            phase => Phase,
            order => maps:get(order, Action),
            port => maps:get(port, Action),
            schema => maps:get(tag, Action)
        })
        || Action <- Actions
    ].

maybe_conditional_effect(#{condition := _Condition}, Effect) ->
    Effect#{conditional => true};
maybe_conditional_effect(_Action, Effect) ->
    Effect.

max_entry_effects(Entries) ->
    lists:max([length(maps:get(actions, Entry)) || Entry <- Entries]).

analyze_cast_groups(Forms, PhaseNames, MessageNames) ->
    Clauses = xls_parse:find_function(Forms, handle_cast, 3),
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
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        [],
        DataName,
        Postprocessor,
        "zero!<Machine>()",
        EnumAtoms
    ),
    lowered(Body, Result).

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

validate_init_head({clause, _Line, [{nil, _PatternLine}], [], _Body}) ->
    ok;
validate_init_head({clause, Line, Patterns, Guards, _Body}) ->
    error({unsupported_hls_statem_init_head, Line, Patterns, Guards}).

%%%
%%% handle_enter/3
%%%

lower_entries(Entries, OutputNames, DataName, EnumAtoms) ->
    [
        lower_entry(Entry, OutputNames, DataName, EnumAtoms)
        || Entry <- Entries
    ].

lower_entry(
    #{
        phase := Phase,
        clause := Clause0,
        prefix := Prefix,
        data_expression := DataExpression,
        actions := OrderedActions
    },
    OutputNames,
    DataName,
    EnumAtoms
) ->
    Clause = strip_dispatched_phase(Clause0),
    DataClause = replace_body(Clause, Prefix ++ [DataExpression]),
    {DataBody, DataResult} = xls_parse:branch_from_clause(
        DataClause,
        enter_args(DataName),
        DataName,
        fun(R) -> [R, ".1"] end,
        "data",
        EnumAtoms
    ),
    Effects = [
        lower_entry_effect(
            Clause,
            Prefix,
            Action,
            DataName,
            EnumAtoms
        )
        || Action <- OrderedActions
    ],
    true = length(Effects) =< length(OutputNames),
    #{
        phase => Phase,
        data => lowered(DataBody, DataResult),
        effects => Effects
    }.

lower_entry_effect(Clause, Prefix,
        Action = #{message := Message, port := Port, tag := Tag}, DataName,
        EnumAtoms) ->
    MessageClause = replace_body(Clause, Prefix ++ [Message]),
    {Body, Result} = xls_parse:branch_from_clause(
        MessageClause,
        enter_args(DataName),
        DataName,
        fun(R) -> ["axis::pack(", R, ".0 as u8, ", R, ".2)"] end,
        "zero!<axis::Frame>()",
        EnumAtoms
    ),
    (lowered(Body, Result))#{
        port => Port,
        tag => Tag,
        valid => lower_effect_condition(
            Action,
            Clause,
            Prefix,
            DataName,
            EnumAtoms
        )
    }.

lower_effect_condition(
        #{condition := Condition}, Clause, Prefix, DataName, EnumAtoms) ->
    ConditionClause = replace_body(Clause, Prefix ++ [Condition]),
    {Body, Result} = xls_parse:branch_from_clause(
        ConditionClause,
        enter_args(DataName),
        DataName,
        fun(R) -> R end,
        "bool:false",
        EnumAtoms
    ),
    lowered(Body, Result);
lower_effect_condition(_Action, _Clause, _Prefix, _DataName, _EnumAtoms) ->
    lowered([], "bool:true").

enter_args(DataName) ->
    [
        "old_phase",
        "phase",
        ["(Tag::", uppercase(DataName), ", data)"]
    ].

parse_actions(ActionList, Prefix, MessageNames, OutputNames, Line) ->
    %% The list shape and ports remain static. A cast_if condition controls
    %% whether its allocated ordered slot emits at runtime.
    ActionExpressions = literal_list(ActionList, Line),
    Bindings = record_bindings(Prefix),
    Parsed = lists:map(
        fun({Order, Action}) ->
            (parse_action(
                Action,
                Bindings,
                MessageNames,
                OutputNames,
                Line
            ))#{order => Order}
        end,
        lists:enumerate(0, ActionExpressions)
    ),
    Ports = [maps:get(port, Action) || Action <- Parsed],
    ok = require_unique(entry_output, Ports),
    Parsed.

parse_action(
    {tuple, _TupleLine, [
        {atom, _CastLine, cast},
        {atom, _PortLine, Port},
        Message
    ]},
    Bindings,
    MessageNames,
    OutputNames,
    _Line
) ->
    require_declared(entry_output, Port, OutputNames),
    Tag = message_tag(Message, Bindings),
    require_declared(entry_message, Tag, MessageNames),
    #{port => Port, tag => Tag, message => Message};
parse_action(
    {tuple, _TupleLine, [
        {atom, _CastLine, cast_if},
        Condition,
        {atom, _PortLine, Port},
        Message
    ]},
    Bindings,
    MessageNames,
    OutputNames,
    _Line
) ->
    require_declared(entry_output, Port, OutputNames),
    Tag = message_tag(Message, Bindings),
    require_declared(entry_message, Tag, MessageNames),
    #{
        port => Port,
        tag => Tag,
        message => Message,
        condition => Condition
    };
parse_action(Action, _Bindings, _MessageNames, _OutputNames, Line) ->
    error({bad_hls_statem_entry_action, Line, Action}).

message_tag({record, _Line, Tag, _Fields}, _Bindings) ->
    Tag;
message_tag({record, _Line, _Base, Tag, _Fields}, _Bindings) ->
    Tag;
message_tag({var, _Line, Name}, Bindings) ->
    case maps:find(Name, Bindings) of
        {ok, Tag} -> Tag;
        error -> error({unknown_hls_statem_action_message_type, Name})
    end;
message_tag(Message, _Bindings) ->
    error({unsupported_hls_statem_action_message, Message}).

record_bindings(Expressions) ->
    lists:foldl(
        fun
            ({match, _Line, {var, _VarLine, Name},
                    {record, _RecordLine, Tag, _Fields}}, Bindings) ->
                Bindings#{Name => Tag};
            (_Expression, Bindings) ->
                Bindings
        end,
        #{},
        Expressions
    ).

literal_list({nil, _Line}, _ContextLine) ->
    [];
literal_list({cons, _Line, Head, Tail}, ContextLine) ->
    [Head | literal_list(Tail, ContextLine)];
literal_list(Expression, ContextLine) ->
    error({nonliteral_hls_statem_actions, ContextLine, Expression}).

%%%
%%% handle_cast/3
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
        tag => Tag,
        phase => Phase,
        body => xls_parse:print(Body),
        result => xls_parse:print(Result)
    }.

%% `repeat_phase` is a scheduling boundary rather than a phase value. Normalize
%% both callback result forms to one XLS product whose final bit requests the
%% boundary. Keeping this rewrite here prevents the generic expression lowerer
%% from having to know about hls_statem callback semantics.  The conclusion
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
    error({unsupported_hls_statem_cast_result, Expression}).

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
    case lists:member(repeat_phase, PhaseNames) of
        true -> error({reserved_hls_statem_phase, repeat_phase});
        false -> ok
    end,
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

message_words(Forms, Name) ->
    Width = xls_parse:record_width(xls_parse:find_record(Forms, Name)),
    case Width rem 32 of
        0 when Width =< 96 -> Width div 32;
        0 -> error({xls_message_too_wide, Name, Width, 96});
        _ -> error({xls_message_not_word_aligned, Name, Width, 32})
    end.

require_unique(Kind, Values) ->
    case length(Values) =:= length(lists:usort(Values)) of
        true -> ok;
        false -> error({duplicate_hls_statem_declaration, Kind, Values})
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

replace_body({clause, Line, Patterns, Guards, _Body}, Body) ->
    {clause, Line, Patterns, Guards, Body}.

split_last(List) ->
    {lists:droplast(List), lists:last(List)}.

lowered(Body, Result) ->
    #{
        body => xls_parse:print(Body),
        result => xls_parse:print(Result)
    }.

uppercase(Atom) ->
    string:uppercase(atom_to_list(Atom)).

record_function_name(Atom) ->
    lists:delete($_, atom_to_list(Atom)).
