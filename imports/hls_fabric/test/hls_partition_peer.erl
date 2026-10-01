-module(hls_partition_peer).
-moduledoc "Credited broker model for host ordering/failure tests; the full memory test uses real brokers and RTL.".
-behaviour(gen_server).
-export([start/1, set/2, emit/2, stats/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-doc "Starts a test broker advertising the given device binding.".
-spec start(map()) -> {ok, pid()}.
start(Binding) -> gen_server:start(?MODULE, Binding, []).
-doc "Selects normal, hold, reject_once, reject_forever or ambiguous writes; normal releases held writes.".
-spec set(pid(), atom()) -> ok.
set(Pid, Mode) -> gen_server:call(Pid, {mode, Mode}).
-doc "Queues a hardware event behind the route's single receive credit.".
-spec emit(pid(), {hls_fabric:route(), hls_fabric:header(), binary()}) -> ok.
emit(Pid, Event) -> gen_server:call(Pid, {emit, Event}).
-doc "Returns admitted controls and outstanding receipts.".
-spec stats(pid()) -> map().
stats(Pid) -> gen_server:call(Pid, stats).

-doc "Creates an initially attached-capable device model.".
-spec init(map()) -> {ok, map()}.
init(Binding) -> {ok, #{binding => Binding, routes => #{}, receipts => #{}, outgoing => queue:new(),
    controls => [], mode => normal, held => [], sessions => #{}}}.

-doc "Models broker route reservation, write outcomes and single-credit delivery.".
-spec handle_call(term(), gen_server:from(), map()) -> {reply, term(), map()} | {noreply, map()}.
%% Physical broker admission precedes each logical session's route registrations.
handle_call(attach_session, {Session, _}, State = #{sessions := Sessions}) ->
    Ref = monitor(process, Session),
    {reply, ok, State#{sessions := Sessions#{Session => Ref}}};
%% Session ownership is remembered so retirement is observable after failure.
handle_call({session, Session, {register_route, Route, Owner}}, _From, State = #{routes := Routes}) ->
    case maps:is_key(Route, Routes) of
        true -> {reply, {error, retired}, State};
        false -> {reply, ok, State#{routes := Routes#{Route => {Session, Owner}}}}
    end;
%% Attachment returns the device's identity; the host must compare it.
handle_call({session, _, {send, {Host, Control}, {1, 0, 0}, _Identity, _Deadline}}, _From,
        State = #{binding := #{host := Host, control := Control, identity := Identity}}) ->
    {reply, ok, output({{Control, Host}, {16#81, 0, 0}, Identity}, State)};
%% Controlled write outcomes exercise admission retries separately from ambiguous delivery.
handle_call({session, _, {send, Route, {2, 0, 0}, Bytes, Deadline}}, From,
        State = #{mode := Mode, controls := Controls, held := Held}) ->
    case {Mode, erlang:monotonic_time(millisecond) >= Deadline} of
        {_, true} -> {reply, {error, {not_sent, timeout}}, State};
        {reject_once, false} -> {reply, {error, {not_sent, tx_limit}}, State#{mode := normal}};
        {reject_forever, false} -> {reply, {error, {not_sent, tx_limit}}, State};
        {ambiguous, false} -> {reply, {error, write_failed}, State};
        {hold, false} -> {noreply, State#{held := [From | Held], controls := [{Route, Bytes} | Controls]}};
        {normal, false} -> {reply, ok, State#{controls := [{Route, Bytes} | Controls]}}
    end;
%% Releasing a stalled writer does not require application event consumption.
handle_call({mode, Mode}, _From, State = #{held := Held}) ->
    case Mode of
        normal -> [gen_server:reply(From, ok) || From <- Held],
            {reply, ok, State#{mode := Mode, held := []}};
        _ -> {reply, ok, State#{mode := Mode}}
    end;
%% Hardware event injection is independent of command write completion.
handle_call({emit, Event}, _From, State) -> {reply, ok, output(Event, State)};
%% Tests observe only public broker transactions and their ownership.
handle_call(stats, _From, State = #{controls := Controls, receipts := Receipts}) ->
    {reply, #{controls => lists:reverse(Controls), receipts => map_size(Receipts), routes => maps:get(routes, State)}, State}.

-doc "Returns a receipt's credit only for the registered owner.".
-spec handle_cast(term(), map()) -> {noreply, map()}.
%% Matching acknowledgment lets the next hardware frame advance on its route.
handle_cast({ack, Owner, Receipt}, State = #{receipts := Receipts}) ->
    case Receipts of
        #{Receipt := {Owner, _}} -> {noreply, pump(State#{receipts := maps:remove(Receipt, Receipts)})};
        _ -> {noreply, State}
    end.

-doc "Retires routes and outstanding receipts when a logical session exits.".
-spec handle_info(term(), map()) -> {noreply, map()}.
%% A replacement session cannot reuse a retired route within this broker lifetime.
handle_info({'DOWN', Ref, process, Session, _}, State = #{sessions := Sessions, routes := Routes, receipts := Receipts}) ->
    Ref = maps:get(Session, Sessions),
    Retired = [Route || {Route, {S, _}} <- maps:to_list(Routes), S =:= Session],
    {noreply, State#{routes := lists:foldl(fun(R, A) -> A#{R := retired} end, Routes, Retired),
        receipts := maps:filter(fun(_, {_, R}) -> not lists:member(R, Retired) end, Receipts)}}.

%% Retain hardware output when the host has exhausted its receive credit.
-spec output(tuple(), map()) -> map().
output(Frame, State = #{outgoing := Queue}) -> pump(State#{outgoing := queue:in(Frame, Queue)}).

%% Model a single ordered physical receive stream with one credit per route.
-spec pump(map()) -> map().
pump(State = #{outgoing := Queue, routes := Routes, receipts := Receipts}) ->
    case queue:out(Queue) of
        {empty, _} -> State;
        {{value, {Route, Header, Bytes}}, Rest} ->
            case maps:get(Route, Routes) of
                retired -> pump(State#{outgoing := Rest});
                {_, Owner} ->
                    case lists:any(fun({_, R}) -> R =:= Route end, maps:values(Receipts)) of
                        true -> State;
                        false ->
                            Receipt = make_ref(),
                            gen_server:cast(Owner, {'$hls_fabric_frame', Receipt, Route, Header, Bytes}),
                            pump(State#{outgoing := Rest, receipts := Receipts#{Receipt => {Owner, Route}}})
                    end
            end
    end.
