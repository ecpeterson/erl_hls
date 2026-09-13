-module(phi_memory_fabric_fixture).

-behavior(gen_server).

-export([
    start_link/0,
    stop/1,
    route_owners/1,
    sends/1,
    await_sends/3,
    fail_next_send/2,
    hold_next_send/1,
    client_info/2,
    deliver/4
]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-doc "Starts an in-memory stand-in for the hls_fabric call interface.".
-spec start_link() -> gen_server:start_ret().
start_link() ->
    gen_server:start_link(?MODULE, [], []).

-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:stop(Pid).

-spec route_owners(pid()) -> map().
route_owners(Pid) ->
    gen_server:call(Pid, route_owners).

-spec sends(pid()) -> [{tuple(), tuple(), binary()}].
sends(Pid) ->
    gen_server:call(Pid, sends).

-spec await_sends(pid(), non_neg_integer(), timeout()) ->
    [{tuple(), tuple(), binary()}].
await_sends(Pid, Count, Timeout) ->
    gen_server:call(Pid, {await_sends, Count}, Timeout).

fail_next_send(Pid, Reason) -> gen_server:call(Pid, {fail_next_send, Reason}).
hold_next_send(Pid) -> gen_server:call(Pid, hold_next_send).

client_info(Pid, Route) -> gen_server:call(Pid, {client_info, Route}).

-doc "Delivers one routed frame to its registered owner.".
-spec deliver(pid(), tuple(), tuple(), binary()) -> ok | {error, route}.
deliver(Pid, Route, Header, Payload) ->
    gen_server:call(Pid, {deliver, Route, Header, Payload}).

init([]) ->
    {ok, #{routes => #{}, sends => [], waiters => []}}.

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
handle_call(
    {send, _Route, _Header, _Payload},
    _From,
    State = #{send_error := Reason}
) ->
    {reply, {error, Reason}, maps:remove(send_error, State)};
handle_call({fail_next_send, Reason}, _From, State) ->
    {reply, ok, State#{send_error => Reason}};
handle_call(hold_next_send, _From, State) ->
    {reply, ok, State#{hold_send => true}};
handle_call({send, Route, Header, Payload}, _From,
        State = #{sends := Sends, waiters := Waiters, hold_send := true}) ->
    UpdatedSends = [{Route, Header, Payload} | Sends],
    RemainingWaiters = reply_waiters(UpdatedSends, Waiters),
    {noreply, maps:remove(hold_send, State#{sends := UpdatedSends, waiters := RemainingWaiters})};
handle_call(
    {send, Route, Header, Payload},
    _From,
    State = #{sends := Sends, waiters := Waiters}
) ->
    UpdatedSends = [{Route, Header, Payload} | Sends],
    RemainingWaiters = reply_waiters(UpdatedSends, Waiters),
    {reply, ok, State#{sends := UpdatedSends, waiters := RemainingWaiters}};
handle_call(route_owners, _From, State = #{routes := Routes}) ->
    {reply, Routes, State};
handle_call({client_info, Route}, _From, State = #{routes := Routes}) ->
    {reply, hls_fabric:client_info(maps:get(Route, Routes)), State};
handle_call(sends, _From, State = #{sends := Sends}) ->
    {reply, lists:reverse(Sends), State};
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
handle_call(
    {deliver, Route, Header, Payload},
    _From,
    State = #{routes := Routes}
) ->
    case Routes of
        #{Route := Owner} ->
            gen_server:cast(
                Owner,
                {'$hls_fabric_frame', Route, Header, Payload}
            ),
            {reply, ok, State};
        #{} ->
            {reply, {error, route}, State}
    end.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(_Message, State) ->
    {noreply, State}.

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
