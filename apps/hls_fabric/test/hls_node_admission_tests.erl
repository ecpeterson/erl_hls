-module(hls_node_admission_tests).
-moduledoc "Host-only second-peer witnesses for capacity waiting and destination-scoped rejection; endpoints are controlled mocks, not RTL.".
-include_lib("eunit/include/eunit.hrl").

%% Remote peer helper using the same distribution connection for both targets.
-export([capacity_sequence/4]).

%% Busy before admission waits without replaying accepted work or disconnecting another actor.
-spec busy_cast_peer_test_() -> term().
busy_cast_peer_test_() ->
    [{timeout, 30, fun() -> capacity_case(Rejection) end} || Rejection <- [unsupported, accepted_busy]].

%% Each rejection case starts fresh mock endpoints and a real second-node distribution peer.
-spec capacity_case(atom()) -> ok.
capacity_case(Rejection) ->
    hls_test_nodes:distribution(),
    Parent = self(),
    Left = spawn(fun() -> endpoint(blocked, 0, none, Parent) end),
    Right = spawn(fun() -> endpoint(ready, 0, none, Parent) end),
    Snapshot = #{phase => ready, handle => {a, 1}, actors => #{left => Left, right => Right}},
    Owner = spawn(fun() -> status_owner(Snapshot) end),
    Service = #{name => pair, domain => #{owner => Owner, id => a}},
    {ok, Device} = hls_node:start_link(name(), #{}, [Service], #{queue_limit => 2}), unlink(Device),
    {Peer, Remote} = hls_test_nodes:start_peer(),
    try
        #{pair := #{actors := #{left := A, right := B}}} = hls_node:services(Device),
        Worker = erpc:call(Remote, ?MODULE, capacity_sequence, [A, B, self(), Rejection]),
        receive {capacity_waiting, Left} -> ok after 5000 -> error(no_capacity_subscription) end,
        receive {other_progress, Worker, {report, 0}} -> ok after 5000 -> error(other_actor_blocked) end,
        Left ! allow,
        Worker ! continue,
        receive {complete, Worker, {report, 1}, noconnection, {report, 0}} -> ok
            after 5000 -> error(cast_not_isolated) end,
        ?assert(is_process_alive(Left)),
        ?assert(is_process_alive(Right)),
        ?assertEqual(1, maps:size(maps:get(connections, hls_node:info(Device)))),
        %% The original cast is tried twice but accepted once; accepted-busy is never retried.
        ?assertEqual({2, 1}, gen_server:call(Left, stats))
    after
        peer:stop(Peer), catch hls_node:stop(Device),
        [exit(P, kill) || P <- [Owner, Left, Right]]
    end,
    ok.

-doc "Shows another actor progressing while a cast waits, then observes only the rejected target's connection loss.".
-spec capacity_sequence(pid(), pid(), pid(), atom()) -> pid().
capacity_sequence(A, B, Parent, Rejection) -> spawn(fun() ->
    Ref = monitor(process, A),
    gen_server:cast(A, {add, 1}),
    Parent ! {other_progress, self(), gen_server:call(B, {read, 0}, 3000)},
    receive continue -> ok after 5000 -> error(no_capacity_release) end,
    Result = gen_server:call(A, {read, 0}, 3000),
    %% Acknowledged rejection has an ordinary reply channel and must preserve this binding.
    Expected = case Rejection of unsupported -> {error, unsupported}; accepted_busy -> {error, busy} end,
    ?assertEqual(Expected, gen_server:call(A, {'$hls_domain_cast', {Rejection, 0}}, 3000)),
    ?assertEqual(Result, gen_server:call(A, {read, 0}, 3000)),
    gen_server:cast(A, {Rejection, 0}),
    Reason = receive {'DOWN', Ref, process, A, Why} -> Why
        after 3000 -> error(no_target_retirement) end,
    Parent ! {complete, self(), Result, Reason, gen_server:call(B, {read, 0}, 3000)}
end).

%% The first add is known not admitted; only explicit allow resolves its reserved capacity request.
-spec endpoint(blocked | ready, non_neg_integer(), none | gen_server:from(), pid()) -> no_return().
endpoint(Mode, Count, Waiter, Parent) -> endpoint(Mode, Count, Waiter, Parent, 0).

%% Counts submitted adds separately from accepted adds to detect transparent replay.
-spec endpoint(blocked | ready, non_neg_integer(), none | gen_server:from(), pid(), non_neg_integer()) -> no_return().
endpoint(Mode, Count, Waiter, Parent, Attempts) ->
    receive
        {'$gen_call', From, {'$hls_submit', _Token, cast, {add, 1}}} when Mode =:= blocked ->
            gen_server:reply(From, {error, busy}),
            endpoint(Mode, Count, Waiter, Parent, Attempts + 1);
        {'$gen_call', From = {Caller, _}, {'$hls_submit', Token, cast, {add, 1}}} ->
            Caller ! {hls_admitted, self(), Token},
            gen_server:reply(From, ok),
            endpoint(Mode, Count + 1, Waiter, Parent, Attempts + 1);
        {'$gen_call', From = {Caller, _}, {'$hls_submit', Token, call, {read, 0}}} ->
            Caller ! {hls_admitted, self(), Token},
            gen_server:reply(From, {report, Count}),
            endpoint(Mode, Count, Waiter, Parent, Attempts);
        {'$gen_call', From, {'$hls_submit', _Token, cast, {unsupported, 0}}} ->
            gen_server:reply(From, {error, unsupported}),
            endpoint(Mode, Count, Waiter, Parent, Attempts);
        {'$gen_call', From = {Caller, _}, {'$hls_submit', Token, cast, {accepted_busy, 0}}} ->
            Caller ! {hls_admitted, self(), Token},
            gen_server:reply(From, {error, busy}),
            endpoint(Mode, Count, Waiter, Parent, Attempts);
        {'$gen_call', From, '$hls_capacity'} when Waiter =:= none ->
            Parent ! {capacity_waiting, self()},
            endpoint(Mode, Count, From, Parent, Attempts);
        allow when Waiter =/= none ->
            gen_server:reply(Waiter, ok),
            endpoint(ready, Count, none, Parent, Attempts);
        {'$gen_call', From, stats} ->
            gen_server:reply(From, {Attempts, Count}),
            endpoint(Mode, Count, Waiter, Parent, Attempts)
    end.

%% A fixed ready snapshot models binding discovery, not lifecycle or hardware behavior.
-spec status_owner(map()) -> no_return().
status_owner(Snapshot) ->
    receive {'$gen_call', From, {status, a}} ->
        gen_server:reply(From, {ok, Snapshot}), status_owner(Snapshot)
    end.

%% Allocate a unique fake-node name on the active distribution host.
-spec name() -> node().
name() ->
    [_Local, Host] = string:split(atom_to_list(node()), "@"),
    list_to_atom("admission_fpga_" ++ integer_to_list(erlang:unique_integer([positive])) ++ "@" ++ Host).
