-module(router_barrier).
-moduledoc """
Per-node completion of rectangle barriers. The router sends monitored OTP calls
itself to preserve sender order. While a site postpones its reply the router can
still forward traffic. Each parent receives one result for this subtree.
""".
-export([point/3, start/3, receive_reply/2]).
-export_type([call/0, pending/0]).

-doc "A downstream process, its request and the reply that counts as success.".
-type call() :: {pid(), term(), term()}.
-doc "Outstanding subtree requests grouped by their response timer.".
-type pending() :: #{
    reference() => {gen_server:from() | unobserved, gen_server:request_id_collection()}
}.

-define(TIMEOUT, 5000).

-doc "Fence a direct sender with the same receipt and failure rules as a subtree.".
-spec point(pid(), term(), term()) -> ok | {error, term()}.
point(Pid, Request, Expected) ->
    case gen_server:receive_response(gen_server:send_request(Pid, Request), ?TIMEOUT) of
        {reply, Reply} -> result(Reply, Expected);
        {error, _} = Error -> Error;
        timeout -> {error, timeout}
    end.

%% Only a matching typed acknowledgment contributes an ok.
-spec result(term(), term()) -> ok | {error, term()}.
result({error, _} = Error, _) -> Error;
result(Expected, Expected) -> ok;
result(Other, _) -> {error, {unexpected_reply, Other}}.

-doc "Issue the selected calls from the router and complete an empty selection immediately.".
-spec start(gen_server:from() | unobserved, [call()], pending()) -> pending().
start(From, [], Pending) ->
    complete(From, ok),
    Pending;
start(From, Calls, Pending) ->
    Requests = lists:foldl(
        fun({Pid, Request, Expected}, Acc) ->
            gen_server:send_request(Pid, Request, Expected, Acc)
        end,
        gen_server:reqids_new(),
        Calls
    ),
    Timer = erlang:start_timer(?TIMEOUT, self(), barrier),
    Pending#{Timer => {From, Requests}}.

-doc "Complete after the last matching reply, or report the first failure and abandon outstanding reply aliases.".
-spec receive_reply(term(), pending()) -> pending().
receive_reply({timeout, Timer, barrier}, Pending) when is_map_key(Timer, Pending) ->
    {From, Requests} = maps:get(Timer, Pending),
    finish(Timer, From, Requests, {error, timeout}, Pending);
receive_reply(Message, Pending) ->
    match_reply(Message, maps:next(maps:iterator(Pending)), Pending).

%% OTP correlates each reply or monitor signal with exactly one outstanding request.
-spec match_reply(
    term(),
    none
    | {
        reference(),
        {gen_server:from() | unobserved, gen_server:request_id_collection()},
        maps:iterator()
    },
    pending()
) -> pending().
match_reply(_, none, Pending) ->
    Pending;
match_reply(Message, {Timer, {From, Requests}, Next}, Pending) ->
    case gen_server:check_response(Message, Requests, true) of
        no_reply ->
            match_reply(Message, maps:next(Next), Pending);
        {{reply, Reply}, Expected, Rest} ->
            case {result(Reply, Expected), gen_server:reqids_size(Rest)} of
                {ok, N} when N > 0 -> Pending#{Timer := {From, Rest}};
                {Result, _} -> finish(Timer, From, Rest, Result, Pending)
            end;
        {{error, Reason}, _, Rest} ->
            finish(Timer, From, Rest, {error, Reason}, Pending)
    end.

%% Ending the wait releases local monitors and aliases. Commands already sent may still run.
-spec finish(
    reference(),
    gen_server:from() | unobserved,
    gen_server:request_id_collection(),
    ok | {error, term()},
    pending()
) -> pending().
finish(Timer, From, Rest, Result, Pending) ->
    erlang:cancel_timer(Timer, [{async, true}, {info, false}]),
    lists:foreach(
        fun({Id, _}) -> gen_server:receive_response(Id, 0) end, gen_server:reqids_to_list(Rest)
    ),
    complete(From, Result),
    maps:remove(Timer, Pending).

%% Preserve fire-and-forget failure visibility while keeping the router available during admission.
-spec complete(gen_server:from() | unobserved, ok | {error, term()}) -> ok.
complete(unobserved, ok) -> ok;
complete(unobserved, {error, Reason}) -> error({broadcast_failed, Reason});
complete(From, Result) -> gen_server:reply(From, Result).
