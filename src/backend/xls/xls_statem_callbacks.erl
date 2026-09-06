%%%% xls_statem_callbacks
%%%%
%%%% Classifies phase-function clauses by event kind and normalizes their
%%%% event-specific results to the closed entry/cast shapes consumed by the
%%%% XLS lowerer.  Keeping this boundary explicit leaves room for call clauses
%%%% to acquire their own result conversion without making generic expression
%%%% lowering understand hls_statem callback semantics.

-module(xls_statem_callbacks).
-moduledoc false.

-export([prepare/2]).

-type callback_kind() :: enter | cast.

-spec prepare([erl_parse:abstract_form()], [atom()]) -> #{
    enter := [erl_parse:af_clause()],
    cast := [erl_parse:af_clause()]
}.
prepare(Forms, Phases) ->
    ok = validate_callback_mode(Forms),
    Classified = lists:append([
        [prepare_clause(Clause, Phase)
            || Clause <- callback_clauses(Forms, Phase, 3)]
        || Phase <- Phases
    ]),
    #{
        enter => [Clause || {enter, Clause} <- Classified],
        cast => [Clause || {cast, Clause} <- Classified]
    }.

validate_callback_mode(Forms) ->
    case callback_clauses(Forms, callback_mode, 0) of
        [{clause, _Line, [], [], [
            {cons, _ListLine,
                {atom, _FunctionsLine, state_functions},
                {cons, _TailLine,
                    {atom, _EnterLine, state_enter},
                    {nil, _NilLine}}}
        ]}] ->
            ok;
        Mode ->
            error({unsupported_hls_statem_callback_mode, Mode})
    end.

callback_clauses(Forms, Name, Arity) ->
    Matches = [
        Clauses
        || {function, _Line, FunctionName, FunctionArity, Clauses} <- Forms,
           FunctionName =:= Name,
           FunctionArity =:= Arity
    ],
    case Matches of
        [Clauses] -> Clauses;
        [] -> error({missing_hls_statem_callback, Name, Arity});
        _ -> error({duplicate_hls_statem_callback, Name, Arity})
    end.

-spec prepare_clause(erl_parse:af_clause(), atom()) ->
    {callback_kind(), erl_parse:af_clause()}.
prepare_clause(
    {clause, Line, [{atom, _EventLine, enter}, OldPhase, Data], Guards, Body},
    Phase
) ->
    Rewritten = rewrite_body(
        Body,
        fun(Result) -> normalize_enter_result(Result, Data) end
    ),
    {enter, {clause, Line,
        [OldPhase, {atom, Line, Phase}, Data], Guards, Rewritten}};
prepare_clause(
    {clause, Line, [{atom, _EventLine, cast}, Message, Data], Guards, Body},
    Phase
) ->
    Rewritten = rewrite_body(
        Body,
        fun(Result) -> normalize_cast_result(Result, Phase, Data) end
    ),
    {cast, {clause, Line,
        [Message, {atom, Line, Phase}, Data], Guards, Rewritten}};
prepare_clause({clause, Line, Patterns, _Guards, _Body}, Phase) ->
    error({unsupported_hls_statem_state_head, Phase, Line, Patterns}).

%% Entry and cast clauses deliberately have separate normalizers.  Their
%% surface tuples need not unify in Erlang: only the normalized tuples fed to
%% each event-kind lowering path need one fixed XLS type.  A future call path
%% can add a third clause classifier and reply-bearing normalizer here.
normalize_enter_result(
    {tuple, Line, [{atom, _KeepLine, keep_state}, Data]},
    _CurrentData
) ->
    {tuple, Line, [Data, {nil, Line}]};
normalize_enter_result(
    {tuple, Line, [{atom, _KeepLine, keep_state}, Data, Actions]},
    _CurrentData
) ->
    {tuple, Line, [Data, Actions]};
normalize_enter_result({atom, Line, keep_state_and_data}, CurrentData) ->
    {tuple, Line, [bound_current_data(CurrentData), {nil, Line}]};
normalize_enter_result(
    {tuple, Line, [{atom, _KeepLine, keep_state_and_data}, Actions]},
    CurrentData
) ->
    {tuple, Line, [bound_current_data(CurrentData), Actions]};
normalize_enter_result(Result, _CurrentData) ->
    error({unsupported_hls_statem_enter_result, Result}).

normalize_cast_result(
    {tuple, Line, [{atom, _NextLine, next_state}, Phase, Data]},
    _CurrentPhase,
    _CurrentData
) ->
    cast_conclusion(Line, Phase, Data, consume, false);
normalize_cast_result(
    {tuple, Line, [
        {atom, _NextLine, next_state}, Phase, Data, Actions
    ]},
    _CurrentPhase,
    _CurrentData
) ->
    cast_conclusion(Line, Phase, Data, input_directive(Actions), false);
normalize_cast_result(
    {tuple, Line, [{atom, _KeepLine, keep_state}, Data]},
    CurrentPhase,
    _CurrentData
) ->
    cast_conclusion(
        Line,
        {atom, Line, CurrentPhase},
        Data,
        consume,
        false
    );
normalize_cast_result(
    {tuple, Line, [{atom, _KeepLine, keep_state}, Data, Actions]},
    CurrentPhase,
    _CurrentData
) ->
    cast_conclusion(
        Line,
        {atom, Line, CurrentPhase},
        Data,
        input_directive(Actions),
        false
    );
normalize_cast_result(
    {atom, Line, keep_state_and_data},
    CurrentPhase,
    CurrentData
) ->
    cast_conclusion(
        Line,
        {atom, Line, CurrentPhase},
        bound_current_data(CurrentData),
        consume,
        false
    );
normalize_cast_result(
    {tuple, Line, [{atom, _KeepLine, keep_state_and_data}, Actions]},
    CurrentPhase,
    CurrentData
) ->
    cast_conclusion(
        Line,
        {atom, Line, CurrentPhase},
        bound_current_data(CurrentData),
        input_directive(Actions),
        false
    );
normalize_cast_result(
    {tuple, Line, [{atom, _RepeatLine, repeat_phase}, Data]},
    CurrentPhase,
    _CurrentData
) ->
    cast_conclusion(
        Line,
        {atom, Line, CurrentPhase},
        Data,
        consume,
        true
    );
normalize_cast_result(
    {tuple, Line, [
        {atom, _StopLine, stop}, {atom, _FailLine, fail}, Data
    ]},
    CurrentPhase,
    _CurrentData
) ->
    cast_conclusion(
        Line,
        {atom, Line, CurrentPhase},
        Data,
        fail,
        false
    );
normalize_cast_result(
    {'case', Line, Expression, Clauses},
    CurrentPhase,
    CurrentData
) ->
    {'case', Line, Expression, [
        rewrite_cast_clause(Clause, CurrentPhase, CurrentData)
        || Clause <- Clauses
    ]};
normalize_cast_result({'if', Line, Clauses}, CurrentPhase, CurrentData) ->
    {'if', Line, [
        rewrite_cast_clause(Clause, CurrentPhase, CurrentData)
        || Clause <- Clauses
    ]};
normalize_cast_result(Result, _CurrentPhase, _CurrentData) ->
    error({unsupported_hls_statem_cast_result, Result}).

cast_conclusion(Line, Phase, Data, Directive, Repeat) ->
    {tuple, Line, [
        Phase,
        Data,
        {atom, Line, Directive},
        {atom, Line, Repeat}
    ]}.

input_directive({nil, _Line}) ->
    consume;
input_directive(
    {cons, _Line, {atom, _PostponeLine, postpone}, {nil, _NilLine}}
) ->
    postpone;
input_directive(Actions) ->
    error({unsupported_hls_statem_input_actions, Actions}).

%% `keep_state_and_data` can only be lowered when the complete data value is
%% available as a source variable.  A bound record pattern is sufficient.
bound_current_data({var, _Line, Name} = Data) when Name =/= '_' ->
    Data;
bound_current_data(
    {match, _Line, {var, _VarLine, Name} = Data, _Pattern}
) when Name =/= '_' ->
    Data;
bound_current_data(
    {match, _Line, _Pattern, {var, _VarLine, Name} = Data}
) when Name =/= '_' ->
    Data;
bound_current_data(Pattern) ->
    error({unbound_hls_statem_data, Pattern}).

rewrite_cast_clause(
    {clause, Line, Patterns, Guards, Body},
    CurrentPhase,
    CurrentData
) ->
    Rewritten = rewrite_body(
        Body,
        fun(Result) ->
            normalize_cast_result(Result, CurrentPhase, CurrentData)
        end
    ),
    {clause, Line, Patterns, Guards, Rewritten}.

rewrite_body(Body, Rewrite) ->
    {Prefix, [Result]} = lists:split(length(Body) - 1, Body),
    Prefix ++ [Rewrite(Result)].
