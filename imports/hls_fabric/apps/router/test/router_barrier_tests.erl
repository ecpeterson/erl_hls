-module(router_barrier_tests).
-moduledoc "Receipt and sender-order checks over multiple native routing branches.".
-include_lib("eunit/include/eunit.hrl").
-export([whereis/1]).

-doc "Resolve the two occupied leaves in the test registry.".
-spec whereis(router:position()) -> pid() | undefined.
whereis(Site) -> ets:lookup_element(?MODULE, Site, 2, undefined).

%% A held receipt must not stop a later routed message from reaching the same site.
-spec convergecast_test() -> ok.
convergecast_test() ->
    ets:new(?MODULE, [named_table]),
    Owner = self(),
    A = spawn_link(fun() -> site(Owner) end),
    B = spawn(fun() -> site(Owner) end),
    ets:insert(?MODULE, [{{0, 0}, A}, {{0, 3}, B}]),
    {ok, Root} = router:start_link(0, 0, 0, 3),
    try
        ok = router:broadcast(all, ?MODULE, first),
        Both = request(Root, all),
        FromA = ordered_call(A),
        FromB = ordered_call(B),
        gen_server:reply(FromA, ok),
        One = request(Root, router:rectangle(0,0,0,0)),
        receive {A, {'$gen_call', Next, fence}} -> gen_server:reply(Next, ok) after 1000 -> error(stalled) end,
        ?assertEqual({reply, ok}, gen_server:receive_response(One, 1000)),
        ?assertEqual(timeout, gen_server:wait_response(Both, 0)),
        ok = router:broadcast(all, ?MODULE, release),
        receive {B, {'$gen_cast', release}} -> gen_server:reply(FromB, ok) after 1000 -> error(blocked) end,
        ?assertEqual({reply, ok}, gen_server:receive_response(Both, 1000)),
        Failure = request(Root, all),
        receive {B, {'$gen_call', _, fence}} -> B ! stop after 1000 -> error(missing_call) end,
        ?assertMatch({reply, {error, {normal, B}}}, gen_server:receive_response(Failure, 1000)),
        receive {A, {'$gen_call', Late, fence}} -> gen_server:reply(Late, ok) after 1000 -> error(missing_call) end,
        ?assertEqual(ok, router:barrier(router:rectangle(0,1,0,2), ?MODULE, #{request => fence, reply => ok}))
    after
        router:stop(Root),
        A ! stop,
        B ! stop,
        ets:delete(?MODULE)
    end.

%% Observe a barrier asynchronously so the test can release individual sites.
-spec request(pid(), router:selection()) -> gen_server:request_id().
request(Root, Rect) ->
    gen_server:send_request(Root, {barrier, Rect, ?MODULE, #{request => fence, reply => ok}}).

%% The leaf must deliver the earlier cast before the point call; both originate at that leaf.
-spec ordered_call(pid()) -> gen_server:from().
ordered_call(Pid) ->
    receive {Pid, Message} -> ?assertEqual({'$gen_cast', first}, Message) after 1000 -> error(missing_cast) end,
    receive {Pid, {'$gen_call', From, fence}} -> From after 1000 -> error(missing_call) end.

%% Expose actual OTP messages to let the test control reply order and site death.
-spec site(pid()) -> ok.
site(Owner) ->
    receive
        stop -> ok;
        Message -> Owner ! {self(), Message}, site(Owner)
    end.
