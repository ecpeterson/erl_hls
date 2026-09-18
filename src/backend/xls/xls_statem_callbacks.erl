%%%% xls_statem_callbacks
%%%%
%%%% Classifies phase-function clauses by event kind and adapts their heads to
%%%% the fixed entry/cast shapes consumed by the XLS lowerer. Callback bodies
%%%% already use those fixed shapes and pass through unchanged.

-module(xls_statem_callbacks).
-moduledoc false.

-export([prepare/2]).

-type callback_kind() :: enter | cast | internal.

-doc "Classifies state-function clauses as enter, cast or internal and normalizes their event heads.".
-spec prepare([hls_source:form()], [atom()]) -> #{
    enter := [erl_parse:abstract_clause()],
    cast := [erl_parse:abstract_clause()],
    internal := [erl_parse:abstract_clause()]
}.
prepare(Forms, Phases) ->
    Classified = lists:append([
        [prepare_clause(Clause, Phase)
            || Clause <- callback_clauses(Forms, Phase, 3)]
        || Phase <- Phases
    ]),
    #{
        enter => [Clause || {enter, Clause} <- Classified],
        cast => [Clause || {cast, Clause} <- Classified],
        internal => [Clause || {internal, Clause} <- Classified]
    }.

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

%% Replace the event discriminator by the containing function's known phase.
-spec prepare_clause(erl_parse:abstract_clause(), atom()) ->
    {callback_kind(), erl_parse:abstract_clause()}.
prepare_clause(
    {clause, Line, [{atom, _EventLine, enter}, OldPhase, Data], Guards, Body},
    Phase
) ->
    {enter, {clause, Line,
        [OldPhase, {atom, Line, Phase}, Data], Guards, Body}};
prepare_clause(
    {clause, Line, [{atom, _EventLine, cast}, Message, Data], Guards, Body},
    Phase
) ->
    {cast, {clause, Line,
        [Message, {atom, Line, Phase}, Data], Guards, Body}};
prepare_clause(
    {clause, Line, [{atom, _EventLine, internal}, Event, Data], Guards, Body},
    Phase
) ->
    {internal, {clause, Line,
        [Event, {atom, Line, Phase}, Data], Guards, Body}};
prepare_clause({clause, Line, Patterns, _Guards, _Body}, Phase) ->
    error({unsupported_hls_statem_state_head, Phase, Line, Patterns}).
