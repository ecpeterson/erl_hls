-module(hls_actor_broker_fixture).
%% Distribution/codec witness, not an FPGA execution model. Each accepted
%% frame is recorded; raw debug replies can be held past connection teardown.
-behaviour(gen_server).
-export([start/1, stop/1, stats/1, reject/3, hold/1, release/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start(Kind) -> gen_server:start(?MODULE, Kind, []).
stop(Pid) -> gen_server:stop(Pid).
stats(Pid) -> gen_server:call(Pid, stats).
reject(Pid, Endpoint, Reject) -> gen_server:call(Pid, {reject, Endpoint, Reject}).
hold(Pid) -> gen_server:call(Pid, hold).
release(Pid) -> gen_server:call(Pid, release).

init(Kind) -> {ok, #{kind => Kind, routes => #{}, events => [], rejected => 0,
    reject => #{}, holding => false, held => [], discarded => 0}}.

handle_call(info, _From, State = #{routes := Routes}) ->
    {reply, #{routes => Routes}, State};
handle_call(stats, _From, State = #{events := Events, held := Held}) ->
    {reply, (maps:with([routes, rejected, discarded], State))#{
        events => lists:reverse(Events), held => length(Held)}, State};
handle_call({register_route, Route, Owner}, _From, State = #{routes := Routes}) ->
    case Routes of
        #{Route := {Owner, _}} -> {reply, ok, State};
        #{Route := _} -> {reply, {error, retired}, State};
        _ ->
            Ref = monitor(process, Owner),
            {reply, ok, State#{routes := Routes#{Route => {Owner, Ref}}}}
    end;
handle_call({reject, Endpoint, Reject}, _From, State = #{reject := Rejected}) ->
    {reply, ok, State#{reject := Rejected#{Endpoint => Reject}}};
handle_call(hold, _From, State) -> {reply, ok, State#{holding := true}};
handle_call(release, _From, State = #{held := Held}) ->
    Next = lists:foldl(fun emit/2, State#{holding := false, held := []}, lists:reverse(Held)),
    {reply, ok, Next};
handle_call({send, Route = {_, Endpoint}, Header, Payload, infinity}, From,
        State = #{reject := Rejected, events := Events, rejected := Count}) ->
    case maps:get(Endpoint, Rejected, false) of
        true -> {reply, {error, {not_sent, {route_tx_limit, Route}}}, State#{rejected := Count + 1}};
        false ->
            Frame = {Route, Header, Payload},
            gen_server:reply(From, ok),
            {noreply, accepted(Frame, State#{events := [Frame | Events]})}
    end.

handle_cast({ack, _, _}, State) -> {noreply, State}.
handle_info({'DOWN', Ref, process, Owner, _Reason}, State = #{routes := Routes}) ->
    {noreply, State#{routes := maps:map(fun
        (_, {Pid, Monitor}) when Pid =:= Owner, Monitor =:= Ref -> retired;
        (_, Value) -> Value
    end, Routes)}}.

accepted({{Source, Endpoint}, {Tag, Tx, 0}, Payload}, State = #{kind := debug}) ->
    respond({{Endpoint, Source}, {Tag bor 16#80, Tx, 0}, Payload}, State);
accepted({{Source, Endpoint}, {Tag, Tx, 0}, <<Value:32/little>>}, State = #{kind := application}) ->
    Tag = regsvc:pack_tag(ping),
    respond({{Endpoint, Source}, {regsvc:pack_tag(ack), Tx, 0}, <<Value:32/little>>}, State);
accepted({_Route, {Tag, 255, 1}, <<_Slot:32/little, _Value:32/little>>}, State = #{kind := application}) ->
    Tag = hls_actor_pid_fixture:pack_tag(work),
    State.

respond(Frame, State = #{holding := true, held := Held}) -> State#{held := [Frame | Held]};
respond(Frame, State) -> emit(Frame, State).

emit({Route, Header, Payload}, State = #{routes := Routes, discarded := Discarded}) ->
    case maps:get(Route, Routes) of
        {Owner, _} when is_pid(Owner) ->
            case is_process_alive(Owner) of
                true ->
                    gen_server:cast(Owner, {'$hls_fabric_frame', make_ref(), Route, Header, Payload}),
                    State;
                false -> State#{discarded := Discarded + 1}
            end;
        retired -> State#{discarded := Discarded + 1}
    end.
