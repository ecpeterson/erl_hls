%%%% xls_statem_lower
%%%%
%%%% Validates the Erlang callback surface and lowers it to the closed data
%%%% consumed by xls_statem_codegen.  Generic expression and record lowering
%%%% remains in xls_parse; the renderer never sees Erlang abstract forms.

-module(xls_statem_lower).
-moduledoc false.

-export([lower/3]).

-spec lower(file:filename(), [erl_parse:abstract_form()], [atom(), ...]) ->
    iolist().
lower(Filename, Forms, PhaseNames) ->
    MessageNames = xls_parse:find_attribute(Forms, xls_tags),
    OutputNames = xls_parse:find_attribute(Forms, xls_outputs),
    Capacity = xls_parse:find_attribute(Forms, xls_mailbox_capacity),
    DataName = xls_parse:find_attribute(Forms, xls_data),
    ok = validate_names(PhaseNames, MessageNames, OutputNames, DataName),
    ok = validate_capacity(Capacity),

    RecordNames = MessageNames ++ [DataName],
    Records = [xls_parse:find_record(Forms, Name) || Name <- RecordNames],
    ok = lists:foreach(
        fun xls_parse:validate_record_defaults/1,
        Records
    ),
    MessageWords = maps:from_list([
        {Name, message_words(Forms, Name)} || Name <- MessageNames
    ]),

    EnumAtoms = enum_atoms(PhaseNames),
    Init = lower_init(Forms, DataName, EnumAtoms),
    Entries = lower_entries(
        Forms,
        PhaseNames,
        MessageNames,
        OutputNames,
        DataName,
        EnumAtoms
    ),
    Casts = lower_casts(
        Forms,
        PhaseNames,
        MessageNames,
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
        data_name => DataName,
        record_declarations => RecordDeclarations,
        init => Init,
        entries => Entries,
        casts => Casts
    }).

%%%
%%% init/1
%%%

lower_init(Forms, DataName, EnumAtoms) ->
    [Clause0] = xls_parse:find_function(Forms, init, 1),
    ok = validate_init_head(Clause0),
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
            error({bad_xls_statem_init_result, Line, Last})
    end.

validate_init_head({clause, _Line, [{nil, _PatternLine}], [], _Body}) ->
    ok;
validate_init_head({clause, Line, Patterns, Guards, _Body}) ->
    error({unsupported_xls_statem_init_head, Line, Patterns, Guards}).

%%%
%%% handle_enter/3
%%%

lower_entries(Forms, PhaseNames, MessageNames, OutputNames, DataName,
        EnumAtoms) ->
    Clauses = xls_parse:find_function(Forms, handle_enter, 3),
    Entries = [
        lower_entry(
            Clause,
            PhaseNames,
            MessageNames,
            OutputNames,
            DataName,
            EnumAtoms
        )
        || Clause <- Clauses
    ],
    EntryPhases = [maps:get(phase, Entry) || Entry <- Entries],
    ok = require_unique(entry_phase, EntryPhases),
    case lists:sort(EntryPhases) =:= lists:sort(PhaseNames) of
        true -> Entries;
        false -> error({incomplete_xls_statem_entries, PhaseNames, EntryPhases})
    end.

lower_entry(
    Clause0 = {clause, Line, Patterns, Guards, Body0},
    PhaseNames,
    MessageNames,
    OutputNames,
    DataName,
    EnumAtoms
) ->
    Phase = entry_phase(Line, Patterns, Guards, PhaseNames),
    {Prefix, Last} = split_last(Body0),
    {DataExpression, ActionList} = case Last of
        {tuple, _TupleLine, [DataExpr, ActionExpression]} ->
            {DataExpr, ActionExpression};
        _ -> error({bad_xls_statem_enter_result, Line, Last})
    end,
    Actions = parse_actions(
        ActionList,
        Prefix,
        MessageNames,
        OutputNames,
        Line
    ),
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
    OutputSpecs = maps:from_list([
        {Port, lower_entry_output(
            Clause,
            Prefix,
            maps:get(Port, Actions, none),
            DataName,
            EnumAtoms
        )}
        || Port <- OutputNames
    ]),
    #{
        phase => Phase,
        data => lowered(DataBody, DataResult),
        outputs => OutputSpecs
    }.

lower_entry_output(_Clause, _Prefix, none, _DataName, _EnumAtoms) ->
    #{valid => false};
lower_entry_output(Clause, Prefix, #{message := Message}, DataName,
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
    (lowered(Body, Result))#{valid => true}.

enter_args(DataName) ->
    [
        "old_phase",
        "phase",
        ["(Tag::", uppercase(DataName), ", data)"]
    ].

parse_actions(ActionList, Prefix, MessageNames, OutputNames, Line) ->
    ActionExpressions = literal_list(ActionList, Line),
    Bindings = record_bindings(Prefix),
    Parsed = lists:map(
        fun(Action) ->
            parse_action(Action, Bindings, MessageNames, OutputNames, Line)
        end,
        ActionExpressions
    ),
    Ports = [maps:get(port, Action) || Action <- Parsed],
    ok = require_unique(entry_output, Ports),
    maps:from_list([{maps:get(port, Action), Action} || Action <- Parsed]).

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
    ok = require_declared(entry_output, Port, OutputNames),
    Tag = message_tag(Message, Bindings),
    ok = require_declared(entry_message, Tag, MessageNames),
    #{port => Port, tag => Tag, message => Message};
parse_action(Action, _Bindings, _MessageNames, _OutputNames, Line) ->
    error({bad_xls_statem_entry_action, Line, Action}).

message_tag({record, _Line, Tag, _Fields}, _Bindings) ->
    Tag;
message_tag({var, _Line, Name}, Bindings) ->
    case maps:find(Name, Bindings) of
        {ok, Tag} -> Tag;
        error -> error({unknown_xls_statem_action_message_type, Name})
    end;
message_tag(Message, _Bindings) ->
    error({unsupported_xls_statem_action_message, Message}).

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
    error({nonliteral_xls_statem_actions, ContextLine, Expression}).

%%%
%%% handle_cast/3
%%%

lower_casts(Forms, PhaseNames, MessageNames, DataName, EnumAtoms) ->
    Clauses = xls_parse:find_function(Forms, handle_cast, 3),
    Casts = [
        lower_cast(
            Clause,
            PhaseNames,
            MessageNames,
            DataName,
            EnumAtoms
        )
        || Clause <- Clauses
    ],
    Keys = [{maps:get(tag, Cast), maps:get(phase, Cast)} || Cast <- Casts],
    ok = require_unique(cast_phase, Keys),
    Casts.

lower_cast(
    Clause0 = {clause, Line, Patterns, Guards, _Body},
    PhaseNames,
    MessageNames,
    DataName,
    EnumAtoms
) ->
    {Tag, Phase} = cast_head(
        Line,
        Patterns,
        Guards,
        MessageNames,
        PhaseNames
    ),
    Clause = strip_dispatched_phase(Clause0),
    {Body, Result} = xls_parse:branch_from_clause(
        Clause,
        [
            "message",
            "phase",
            ["(Tag::", uppercase(DataName), ", data)"]
        ],
        DataName,
        fun(R) -> ["(", R, ".0, ", R, ".1.1, ", R, ".2)"] end,
        "(phase, data, Directive::FAIL)",
        EnumAtoms
    ),
    #{
        tag => Tag,
        phase => Phase,
        body => xls_parse:print(Body),
        result => xls_parse:print(Result)
    }.

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
    ok = require_declared(entry_phase, Phase, PhaseNames),
    Phase;
entry_phase(Line, Patterns, Guards, _PhaseNames) ->
    error({unsupported_xls_statem_enter_head, Line, Patterns, Guards}).

cast_head(_Line, [
    {record, _MessageLine, Tag, _Fields},
    {atom, _PhaseLine, Phase},
    {var, _DataLine, _Data}
], [], MessageNames, PhaseNames) ->
    ok = require_declared(cast_message, Tag, MessageNames),
    ok = require_declared(cast_phase, Phase, PhaseNames),
    {Tag, Phase};
cast_head(Line, Patterns, Guards, _MessageNames, _PhaseNames) ->
    error({unsupported_xls_statem_cast_head, Line, Patterns, Guards}).

validate_capacity(Capacity)
        when is_integer(Capacity), Capacity > 0, Capacity =< 255 ->
    ok;
validate_capacity(Capacity) ->
    error({invalid_xls_mailbox_capacity, Capacity}).

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
        false -> error({duplicate_xls_statem_declaration, Kind, Values})
    end.

require_declared(Kind, Value, Values) when is_list(Values) ->
    case lists:member(Value, Values) of
        true -> ok;
        false -> error({undeclared_xls_statem_name, Kind, Value, Values})
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
    {var, Line, '_DispatchedPhase'}.

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
