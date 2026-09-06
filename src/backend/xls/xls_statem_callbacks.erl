%%%% Normalize the restricted state-function surface to entry and cast ASTs.
%%%% Scheduling results have one internal shape: phase, data, directive, repeat.
%%%% Results must be final tuples, case/if expressions, or the keep-data atom;
%%%% following a result through arbitrary bindings needs typed dataflow.

-module(xls_statem_callbacks).
-moduledoc false.

-export([prepare/2]).

-spec prepare([erl_parse:abstract_form()], [atom()]) -> {[tuple()], [tuple()]}.
prepare(Forms, Phases) ->
    case xls_parse:find_function(Forms, callback_mode, 0) of
        [{clause, _, [], [], [{cons, _, {atom, _, state_functions},
                {cons, _, {atom, _, state_enter}, {nil, _}}}]}] -> ok;
        Mode -> error({unsupported_hls_statem_callback_mode, Mode})
    end,
    Clauses = lists:append([
        [prepare_clause(Clause, Phase)
            || Clause <- xls_parse:find_function(Forms, Phase, 3)]
        || Phase <- Phases
    ]),
    {[Clause || {enter, Clause} <- Clauses],
     [Clause || {cast, Clause} <- Clauses]}.

prepare_clause({clause, Line, [
        {atom, _, enter}, OldPhase, Data
    ], Guards, Body}, Phase) ->
    {enter, {clause, Line, [OldPhase, {atom, Line, Phase}, Data], Guards,
        rewrite_body(Body, fun(Result) -> entry_result(Result, Data) end)}};
prepare_clause({clause, Line, [
        {atom, _, cast}, Message, Data
    ], Guards, Body}, Phase) ->
    {cast, {clause, Line, [Message, {atom, Line, Phase}, Data], Guards,
        rewrite_body(Body, fun(Result) -> cast_result(Result, Phase, Data) end)}};
prepare_clause({clause, Line, Patterns, _Guards, _Body}, Phase) ->
    error({unsupported_hls_statem_state_head, Phase, Line, Patterns}).

entry_result({tuple, Line, [{atom, _, keep_state}, Data]}, _Current) ->
    {tuple, Line, [Data, {nil, Line}]};
entry_result({tuple, Line, [{atom, _, keep_state}, Data, Actions]}, _Current) ->
    {tuple, Line, [Data, Actions]};
entry_result({atom, Line, keep_state_and_data}, Current) ->
    {tuple, Line, [current_data(Current), {nil, Line}]};
entry_result({tuple, Line, [{atom, _, keep_state_and_data}, Actions]}, Current) ->
    {tuple, Line, [current_data(Current), Actions]};
entry_result(Result, _Current) ->
    error({unsupported_hls_statem_enter_result, Result}).

cast_result({tuple, Line, [{atom, _, next_state}, Phase, Data]}, _Phase, _Current) ->
    conclusion(Line, Phase, Data, consume, false);
cast_result({tuple, Line, [{atom, _, next_state}, Phase, Data, Actions]},
        _Phase, _Current) ->
    conclusion(Line, Phase, Data, directive(Actions), false);
cast_result({tuple, Line, [{atom, _, keep_state}, Data]}, Phase, _Current) ->
    conclusion(Line, {atom, Line, Phase}, Data, consume, false);
cast_result({tuple, Line, [{atom, _, keep_state}, Data, Actions]}, Phase, _Current) ->
    conclusion(Line, {atom, Line, Phase}, Data, directive(Actions), false);
cast_result({atom, Line, keep_state_and_data}, Phase, Current) ->
    conclusion(Line, {atom, Line, Phase}, current_data(Current), consume, false);
cast_result({tuple, Line, [{atom, _, keep_state_and_data}, Actions]},
        Phase, Current) ->
    conclusion(Line, {atom, Line, Phase}, current_data(Current),
        directive(Actions), false);
cast_result({tuple, Line, [{atom, _, repeat_phase}, Data]}, Phase, _Current) ->
    conclusion(Line, {atom, Line, Phase}, Data, consume, true);
cast_result({tuple, Line, [{atom, _, stop}, {atom, _, fail}, Data]},
        Phase, _Current) ->
    conclusion(Line, {atom, Line, Phase}, Data, fail, false);
cast_result({'case', Line, Expression, Clauses}, Phase, Current) ->
    {'case', Line, Expression, [
        rewrite_clause(Clause, Phase, Current) || Clause <- Clauses
    ]};
cast_result({'if', Line, Clauses}, Phase, Current) ->
    {'if', Line, [rewrite_clause(Clause, Phase, Current) || Clause <- Clauses]};
cast_result(Result, _Phase, _Current) ->
    error({unsupported_hls_statem_cast_result, Result}).

conclusion(Line, Phase, Data, Directive, Repeat) ->
    {tuple, Line, [Phase, Data, {atom, Line, Directive}, {atom, Line, Repeat}]}.

directive({nil, _}) -> consume;
directive({cons, _, {atom, _, postpone}, {nil, _}}) -> postpone;
directive(Actions) -> error({unsupported_hls_statem_input_actions, Actions}).

%% Keeping all data requires an explicit binding to that data in the head.
%% Record patterns remain supported when bound as Data = #record{...}.
current_data({var, _, Name} = Data) when Name =/= '_' -> Data;
current_data({match, _, {var, _, Name} = Data, _Pattern}) when Name =/= '_' -> Data;
current_data({match, _, _Pattern, {var, _, Name} = Data}) when Name =/= '_' -> Data;
current_data(Pattern) -> error({unbound_hls_statem_data, Pattern}).

rewrite_clause({clause, Line, Patterns, Guards, Body}, Phase, Current) ->
    {clause, Line, Patterns, Guards,
        rewrite_body(Body, fun(Result) -> cast_result(Result, Phase, Current) end)}.

rewrite_body(Body, Rewrite) ->
    {Prefix, [Result]} = lists:split(length(Body) - 1, Body),
    Prefix ++ [Rewrite(Result)].
