-module(hls_fabric_test_wire).
-moduledoc "Controlled in-memory broker used by host transaction and debug tests.".

-behavior(gen_server).

-export([
    start_link/0,
    stop/1,
    route_owners/1,
    sends/1,
    await_sends/3,
    fail_next_send/2,
    hold_next_send/1,
    hold_sends/1,
    release_sends/1,
    client_info/2,
    deliver/4
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-doc "Starts an in-memory stand-in for the hls_fabric call interface.".
-spec start_link() -> gen_server:start_ret().
start_link() ->
    gen_server:start_link(?MODULE, [], []).

-doc "Stops the fixture broker.".
-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:stop(Pid).

-doc "Reads current registered return-route owners.".
-spec route_owners(pid()) -> map().
route_owners(Pid) ->
    gen_server:call(Pid, route_owners).

-doc "Returns accepted sends in their submission order.".
-spec sends(pid()) -> [{tuple(), tuple(), binary()}].
sends(Pid) ->
    gen_server:call(Pid, sends).

-doc "Waits until the fixture has accepted the requested number of sends.".
-spec await_sends(pid(), non_neg_integer(), timeout()) ->
    [{tuple(), tuple(), binary()}].
await_sends(Pid, Count, Timeout) ->
    gen_server:call(Pid, {await_sends, Count}, Timeout).

-doc "Injects one send rejection before recording a frame.".
-spec fail_next_send(pid(), term()) -> ok.
fail_next_send(Pid, Reason) -> gen_server:call(Pid, {fail_next_send, Reason}).
-doc "Defers one send completion until explicit release.".
-spec hold_next_send(pid()) -> ok.
hold_next_send(Pid) -> gen_server:call(Pid, hold_next_send).
-doc "Defers all send completions until explicit release.".
-spec hold_sends(pid()) -> ok.
hold_sends(Pid) -> gen_server:call(Pid, hold_sends).
-doc "Completes held writes in accepted order.".
-spec release_sends(pid()) -> ok.
release_sends(Pid) -> gen_server:call(Pid, release_sends).

-doc "Reads the registered owner after preceding fixture deliveries.".
-spec client_info(pid(), tuple()) -> map().
client_info(Pid, Route) -> gen_server:call(Pid, {client_info, Route}).

-doc "Delivers one routed frame to its registered owner.".
-spec deliver(pid(), tuple(), tuple(), binary()) -> ok | {error, route}.
deliver(Pid, Route, Header, Payload) ->
    gen_server:call(Pid, {deliver, Route, Header, Payload}).

-doc "Starts with no routes, sends or delayed completions.".
-spec init([]) -> {ok, map()}.
init([]) ->
    {ok, #{routes => #{}, sends => [], waiters => [], held => []}}.

-doc "Implements controlled route registration, sends, delivery and completion barriers.".
-spec handle_call(term(), gen_server:from(), map()) -> {reply, term(), map()} | {noreply, map()}.
%% Reserves a return route, accepting idempotent registration by the same owner.
handle_call(
    {register_route, Route, Owner},
    _From,
    State = #{routes := Routes}
) ->
    case Routes of
        #{Route := Owner} ->
            {reply, ok, State};
        #{Route := Existing} ->
            {reply, {error, {route_in_use, Route, Existing}}, State};
        #{} ->
            {reply, ok, State#{routes := Routes#{Route => Owner}}}
    end;
%% Consumes an injected rejection without recording or completing a write.
handle_call(
    {send, _Route, _Header, _Payload, _Deadline},
    _From,
    State = #{send_error := Reason}
) ->
    {reply, {error, Reason}, maps:remove(send_error, State)};
%% Arms one rejection for the next send request.
handle_call({fail_next_send, Reason}, _From, State) ->
    {reply, ok, State#{send_error => Reason}};
%% Blocks one accepted write completion until release_sends.
handle_call(hold_next_send, _From, State) ->
    {reply, ok, State#{hold_send => once}};
%% Blocks all subsequent accepted write completions until release_sends.
handle_call(hold_sends, _From, State) ->
    {reply, ok, State#{hold_send => always}};
%% Releases held completions in submission order and returns to immediate writes.
handle_call(release_sends, _From, State = #{held := Held}) ->
    [gen_server:reply(From, ok) || From <- lists:reverse(Held)],
    {reply, ok, maps:remove(hold_send, State#{held := []})};
%% Records a held write and satisfies observers without replying to its sender.
handle_call({send, Route, Header, Payload, _Deadline}, From,
        State = #{sends := Sends, waiters := Waiters, hold_send := Mode, held := Held}) ->
    UpdatedSends = [{Route, Header, Payload} | Sends],
    RemainingWaiters = reply_waiters(UpdatedSends, Waiters),
    Updated = State#{sends := UpdatedSends, waiters := RemainingWaiters, held := [From | Held]},
    {noreply, case Mode of once -> maps:remove(hold_send, Updated); always -> Updated end};
%% Records an ordinary write and acknowledges it immediately.
handle_call(
    {send, Route, Header, Payload, _Deadline},
    _From,
    State = #{sends := Sends, waiters := Waiters}
) ->
    UpdatedSends = [{Route, Header, Payload} | Sends],
    RemainingWaiters = reply_waiters(UpdatedSends, Waiters),
    {reply, ok, State#{sends := UpdatedSends, waiters := RemainingWaiters}};
%% Exposes route ownership for client-lifetime assertions.
handle_call(route_owners, _From, State = #{routes := Routes}) ->
    {reply, Routes, State};
%% Orders a client inspection after this broker's preceding frame deliveries.
handle_call({client_info, Route}, _From, State = #{routes := Routes}) ->
    {reply, hls_fabric:client_info(maps:get(Route, Routes)), State};
%% Returns the chronological accepted frame history.
handle_call(sends, _From, State = #{sends := Sends}) ->
    {reply, lists:reverse(Sends), State};
%% Defers a send-count observation until enough frames have been accepted.
handle_call(
    {await_sends, Count},
    From,
    State = #{sends := Sends, waiters := Waiters}
) ->
    case length(Sends) >= Count of
        true ->
            {reply, lists:reverse(Sends), State};
        false ->
            {noreply, State#{waiters := [{Count, From} | Waiters]}}
    end;
%% Delivers a frame only to a registered return-route owner.
handle_call(
    {deliver, Route, Header, Payload},
    _From,
    State = #{routes := Routes}
) ->
    case Routes of
        #{Route := Owner} ->
            gen_server:cast(
                Owner,
                {'$hls_fabric_frame', make_ref(), Route, Header, Payload}
            ),
            {reply, ok, State};
        #{} ->
            {reply, {error, route}, State}
    end.

-doc "Ignores asynchronous messages not used by this fixture.".
-spec handle_cast(term(), map()) -> {noreply, map()}.
handle_cast(_Message, State) ->
    {noreply, State}.

-doc "Ignores unrelated process messages.".
-spec handle_info(term(), map()) -> {noreply, map()}.
handle_info(_Message, State) ->
    {noreply, State}.

%% Releases satisfied send-count barriers and retains the remaining waiters.
-spec reply_waiters([tuple()], [{non_neg_integer(), gen_server:from()}]) -> [{non_neg_integer(), gen_server:from()}].
reply_waiters(Sends, Waiters) ->
    Count = length(Sends),
    Chronological = lists:reverse(Sends),
    lists:filtermap(
        fun
            ({Expected, From}) when Count >= Expected ->
                gen_server:reply(From, Chronological),
                false;
            (Waiter) ->
                {true, Waiter}
        end,
        Waiters
    ).
