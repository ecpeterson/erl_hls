-module(hls_gs_deferred).
-moduledoc "Bounded CPU reply ownership and continuation validation for hls_gs.".
-export([new/1, dispatch/6]).
-export_type([pending/0]).

-doc "Pending callers and a nonwrapping allocation sequence, local to one server activation.".
-type pending() :: #{limit := pos_integer(), next := pos_integer(),
    names := [atom()], callers := #{non_neg_integer() => {gen_server:from(), [atom()]}}}.

-doc "Creates empty reply ownership from a checked retained-server contract.".
-spec new(hls_service_contract:contract()) -> pending().
new(#{pending_calls := N, continuations := Names}) ->
    #{limit => N, next => 1, names => Names, callers => #{}}.

-doc "Runs one callback, validates all actions before replying, and returns its next continuation or none.".
-spec dispatch(call | cast | continue, module(), term(), term(), term(), pending()) ->
    {term(), pending(), none | {continue, atom()}}.
%% Exhaustion ends the activation instead of reissuing a handle.
dispatch(call, _Module, _Message, _From, _State, #{next := Sequence}) when Sequence >= (1 bsl 56) ->
    error(reply_handle_exhausted);
%% Reject excess calls without preventing the casts that release retained calls.
dispatch(call, _Module, _Message, {From, _Replies}, State,
        Pending = #{limit := Limit, callers := Callers}) when map_size(Callers) >= Limit ->
    gen_server:reply(From, {error, {remote_error, busy}}),
    {State, Pending, none};
%% Tokens carry the request tag for hardware contract checks; their sequence never wraps.
dispatch(call, Module, Message, {From, Replies}, State,
        Pending = #{next := Sequence, callers := Callers}) ->
    true = Sequence < (1 bsl 56),
    Handle = (Sequence bsl 8) bor Module:pack_tag(element(1, Message)),
    Next = Pending#{next := Sequence + 1, callers := Callers#{Handle => {From, Replies}}},
    finish(Module:handle_call(Message, Handle, State), Handle, Next);
%% Casts consume no reply-table slot.
dispatch(cast, Module, Message, _From, State, Pending) ->
    finish(Module:handle_cast(Message, State), none, Pending);
%% gen_server gives continuations priority over every later mailbox message.
dispatch(continue, Module, Name, _From, State, Pending) ->
    finish(Module:handle_continue(Name, State), none, Pending).

%% Normalize immediate and retained forms into one reply and one continuation.
-spec finish(term(), none | non_neg_integer(), pending()) ->
    {term(), pending(), none | {continue, atom()}}.
finish({reply, Reply, State}, Handle, Pending) when is_integer(Handle) ->
    finish({noreply, State, [{reply, Handle, Reply}]}, none, Pending);
finish({reply, Reply, State, {continue, Name}}, Handle, Pending) when is_integer(Handle) ->
    finish({noreply, State, [{reply, Handle, Reply}, {continue, Name}]}, none, Pending);
finish({noreply, State}, _Handle, Pending) -> {State, Pending, none};
finish({noreply, State, {continue, Name}}, Handle, Pending) ->
    finish({noreply, State, [{continue, Name}]}, Handle, Pending);
finish({noreply, State, Actions}, _Handle, Pending = #{names := Names, callers := Callers}) ->
    {Reply, Continue} = actions(Actions),
    true = Continue =:= none orelse lists:member(element(2, Continue), Names),
    NextCallers = case Reply of
        none -> Callers;
        {reply, Token, Value} ->
            case maps:take(Token, Callers) of
                error -> Callers;
                {{From, Allowed}, Rest} ->
                    case is_tuple(Value) andalso tuple_size(Value) > 0 andalso
                            lists:member(element(1, Value), Allowed) of
                        true -> ok;
                        false -> error({reply_contract, Value, Allowed})
                    end,
                    gen_server:reply(From, Value),
                    Rest
            end
    end,
    {State, Pending#{callers := NextCallers}, Continue}.

%% Only one reply followed by one continuation is accepted per bounded callback step.
-spec actions(term()) -> {none | {reply, non_neg_integer(), term()}, none | {continue, atom()}}.
actions([]) -> {none, none};
actions([{continue, Name}]) when is_atom(Name) -> {none, {continue, Name}};
actions([{reply, Handle, Reply}]) when is_integer(Handle), Handle >= 0 ->
    {{reply, Handle, Reply}, none};
actions([{reply, Handle, Reply}, {continue, Name}])
        when is_integer(Handle), Handle >= 0, is_atom(Name) ->
    {{reply, Handle, Reply}, {continue, Name}};
actions(Actions) -> error({invalid_hls_server_actions, Actions}).
