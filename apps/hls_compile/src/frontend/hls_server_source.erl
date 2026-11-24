-module(hls_server_source).
-moduledoc "Normalizes bounded server callbacks into one-state actor source before common interface analysis and XLS lowering. Preserves original callback annotations and evaluation order; no generated text is parsed. Native execution adapts the same callback contract through hls_actor_callback.".
%% Shared source entry for either actor vocabulary.
-export([normalize/1]).

-doc "Returns state-machine forms and phase names; server declarations/callbacks are checked before introducing one inert phase and its reply port.".
-spec normalize([hls_source:form()]) -> {[hls_source:form()], [atom(), ...]}.
normalize(Forms) ->
    case hls_source:find_optional_attribute(Forms, hls_phases) of
        {ok, Phases} -> {Forms, Phases};
        none -> server(Forms)
    end.

%% The server's public callback vocabulary remains the authority for its schema.
-spec server([hls_source:form()]) -> {[hls_source:form()], [atom(), ...]}.
server(Forms) ->
    Contract = hls_service_contract:from_forms(Forms),
    Arity = hls_service_contract:call_arity(Forms),
    Init = xls_init:clause(Forms, hls_gs),
    Phase = hls_server,
    case [F || F = {function, _, hls_server, 3, _} <- Forms] of
        [] -> ok;
        _ -> error({reserved_hls_server_callback, Phase})
    end,
    Calls = clauses(Forms, handle_call, Arity),
    Casts = clauses(Forms, handle_cast, 2),
    Continues = clauses(Forms, handle_continue, 2),
    _ =
        case {Arity, Continues} of
            {2, [_ | _]} -> error(immediate_server_continuation);
            _ -> ok
        end,
    Entry =
        {clause, 0, [{atom, 0, enter}, {var, 0, '_'}, {var, 0, 'Data'}], [], [
            {tuple, 0, [{var, 0, 'Data'}, {nil, 0}]}
        ]},
    Functions = [
        {function, 0, Phase, 3,
            [Entry] ++
                [callback(C, call, Arity) || C <- Calls] ++
                [callback(C, cast, Arity) || C <- Casts] ++
                [callback(C, internal, Arity) || C <- Continues]}
    ],
    {clause, L, Args, Guards, Body} = Init,
    Initial =
        {function, L, init, 1, [
            {clause, L, Args, Guards,
                lists:droplast(Body) ++
                    [{tuple, L, [{atom, L, ok}, {atom, L, Phase}, lists:last(Body)]}]}
        ]},
    Capacity =
        case hls_source:find_optional_attribute(Forms, hls_mailbox_capacity) of
            none -> 1;
            {ok, N} -> N
        end,
    Attrs = [
        {attribute, 0, hls_phases, [Phase]},
        {attribute, 0, hls_data, hls_actor_source:state(Forms)},
        {attribute, 0, hls_outputs, [reply]},
        {attribute, 0, hls_reply_port, reply},
        {attribute, 0, hls_mailbox_capacity, Capacity},
        {attribute, 0, hls_server_contract, Contract}
    ],
    Kept = [F || F <- Forms, keep(F)],
    {Kept ++ Attrs ++ [Initial | Functions], [Phase]}.

%% Replace only declarations and initialization which acquire normalized forms.
-spec keep(hls_source:form()) -> boolean().
keep({function, _, init, 1, _}) ->
    false;
keep({attribute, _, Name, _}) when
    Name =:= hls_data;
    Name =:= hls_outputs;
    Name =:= hls_reply_port;
    Name =:= hls_mailbox_capacity
->
    false;
keep(_) ->
    true.

%% Missing optional callback families contribute no dispatch alternatives.
-spec clauses([hls_source:form()], atom(), arity()) -> [erl_parse:abstract_clause()].
clauses(Forms, Name, Arity) ->
    lists:append([Cs || {function, _, F, A, Cs} <- Forms, F =:= Name, A =:= Arity]).

%% Preserve callback heads and capture result fields before reordering state/reply.
-spec callback(erl_parse:abstract_clause(), call | cast | internal, 2 | 3) ->
    erl_parse:abstract_clause().
callback(Clause = {clause, L, Args, _, _}, Kind, Arity) ->
    From = fresh_from(Clause, 0),
    Data = fresh_from({Clause, From}, 0),
    {Head, Handle} =
        case {Kind, Args} of
            {call, [Request, Pattern]} ->
                {[{tuple, L, [{atom, L, call}, From]}, Request, {match, L, Data, Pattern}], From};
            {call, [Request, Token, Pattern]} ->
                {
                    [
                        {tuple, L, [{atom, L, call}, {match, L, From, Token}]},
                        Request,
                        {match, L, Data, Pattern}
                    ],
                    From
                };
            {_, [Message, Pattern]} ->
                {[{atom, L, Kind}, Message, {match, L, Data, Pattern}], none}
        end,
    {clause, L, _, Guards, Body} = xls_callback_result:map_evaluated_actions(
        Clause, fun(Value) -> terminal_result(Value, Data, Handle, Kind, Arity) end
    ),
    {clause, L, Head, Guards, Body}.

%% Literal callback-tail errors terminate the hardware actor at the source site.
%% ERTS retains the atom reason; hardware reports explicit_fail plus that site.
%% Error expressions in helpers or other value positions remain unsupported.
-spec terminal_result(term(), term(), term(), call | cast | internal, 2 | 3) -> term().
terminal_result(
    {call, L, {remote, _, {atom, _, erlang}, {atom, _, error}}, [{atom, _, _}]},
    Data,
    _,
    _,
    _
) ->
    {tuple, L, [{atom, L, hls_server}, Data, {atom, L, fail}]};
terminal_result(Value, _, From, Kind, Arity) ->
    checked_result(Value, From, Kind, Arity).

%% Synthetic reply arguments must never capture a source variable.
-spec fresh_from(term(), non_neg_integer()) -> {var, 0, atom()}.
fresh_from(Clause, N) ->
    Name = list_to_atom("_HlsServerFrom" ++ integer_to_list(N)),
    case contains_variable(Clause, Name) of
        true -> fresh_from(Clause, N + 1);
        false -> {var, 0, Name}
    end.

%% Inspect source syntax without interpreting its application values.
-spec contains_variable(term(), atom()) -> boolean().
contains_variable({var, _, Name}, Name) ->
    true;
contains_variable(T, Name) when is_tuple(T) -> contains_variable(tuple_to_list(T), Name);
contains_variable(L, Name) when is_list(L) ->
    lists:any(fun(V) -> contains_variable(V, Name) end, L);
contains_variable(_, _) ->
    false.

%% Immediate calls must reply in the same callback; their casts cannot retain work.
-spec checked_result(term(), term(), call | cast | internal, 2 | 3) -> term().
checked_result(V = {tuple, _, [{atom, _, reply}, _, _]}, From, call, 2) -> result(V, From);
checked_result(V = {tuple, _, [{atom, _, noreply}, _]}, From, cast, 2) -> result(V, From);
checked_result(V, _, _, 2) -> error({invalid_immediate_server_result, V});
checked_result(V, From, _, 3) -> result(V, From).

%% Server result vocabulary becomes ordinary consume/reply/internal-event actions.
-spec result(term(), term()) -> term().
result({tuple, L, [{atom, _, reply}, Reply, Data]}, From) when From =/= none ->
    outcome(L, Data, [{tuple, L, [{atom, L, reply}, From, Reply]}]);
result(
    {tuple, L, [{atom, _, reply}, Reply, Data, {tuple, _, [{atom, _, continue}, Name]}]}, From
) when
    From =/= none
->
    outcome(L, Data, [{tuple, L, [{atom, L, reply}, From, Reply]}, continuation(L, Name)]);
result({tuple, L, [{atom, _, noreply}, Data]}, _) ->
    outcome(L, Data, []);
result({tuple, L, [{atom, _, noreply}, Data, {tuple, _, [{atom, _, continue}, Name]}]}, _) ->
    outcome(L, Data, [continuation(L, Name)]);
result({tuple, L, [{atom, _, noreply}, Data, Actions]}, _) ->
    outcome(L, Data, actions(Actions));
result(Value, _) ->
    error({invalid_hls_server_result, Value}).

%% Normalize only the existing bounded reply-then-continuation action grammar.
-spec actions(term()) -> [term()].
actions({nil, _}) ->
    [];
actions({cons, L, {tuple, _, [{atom, _, continue}, Name]}, {nil, _}}) ->
    [continuation(L, Name)];
actions({cons, _, Reply = {tuple, _, [{atom, _, reply}, _, _]}, Tail}) ->
    [Reply | actions_tail(Tail)];
actions(Value) ->
    error({invalid_hls_server_actions, Value}).

%% A reply may be followed by one continuation, never another reply.
-spec actions_tail(term()) -> [term()].
actions_tail({nil, _}) ->
    [];
actions_tail({cons, L, {tuple, _, [{atom, _, continue}, Name]}, {nil, _}}) ->
    [continuation(L, Name)];
actions_tail(Value) ->
    error({invalid_hls_server_actions, Value}).

%% Internal event names remain declared finite atoms.
-spec continuation(erl_anno:anno(), term()) -> term().
continuation(L, Name = {atom, _, _}) ->
    {tuple, L, [{atom, L, next_event}, {atom, L, internal}, Name]};
continuation(_, Value) ->
    error({invalid_hls_server_continuation, Value}).

%% The single phase never reenters or postpones an ordinary server request.
-spec outcome(erl_anno:anno(), term(), [term()]) -> term().
outcome(L, Data, Actions) ->
    Base = [{atom, L, hls_server}, Data, {atom, L, consume}],
    case Actions of
        [] ->
            {tuple, L, Base};
        _ ->
            {tuple, L,
                Base ++ [lists:foldr(fun(A, Tail) -> {cons, L, A, Tail} end, {nil, L}, Actions)]}
    end.
