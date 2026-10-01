-module(hls_gs_deferred).
-moduledoc "Bounded CPU reply ownership and continuation validation for hls_gs.".
-export([new/1, dispatch/6]).
-export_type([pending/0]).

-doc "Pending callers and a nonwrapping allocation sequence, local to one server activation.".
-type pending() :: #{book := hls_reply_book:book(), names := [atom()]}.

-doc "Creates empty reply ownership from a checked retained-server contract.".
-spec new(hls_service_contract:contract()) -> pending().
new(#{pending_calls := N, continuations := Names}) ->
    #{book => hls_reply_book:new(N), names => Names}.

-doc "Runs one callback, validates all actions before replying, and returns its next continuation or none.".
-spec dispatch(call | cast | continue, module(), term(), term(), term(), pending()) ->
    {term(), pending(), none | {continue, atom()}}.
%% The common ownership book allocates a token before the callback can retain it.
dispatch(call, Module, Message, {From, Replies}, State, Pending = #{book := Book}) ->
    case hls_reply_book:admit(Module:pack_tag(element(1, Message)), From, Replies, Book) of
        full -> {State, Pending, none};
        {ok, Handle, Next} -> finish(Module:handle_call(Message, Handle, State), Handle, Pending#{book := Next})
    end;
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
finish({noreply, State, Actions}, _Handle, Pending = #{names := Names, book := Book}) ->
    {Reply, Name} = hls_callback_actions:split(Actions, server, Names),
    Continue = case Name of none -> none; _ -> {continue, Name} end,
    {State, Pending#{book := hls_reply_book:complete(Reply, Book)}, Continue}.
