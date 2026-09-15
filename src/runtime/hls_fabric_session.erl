-module(hls_fabric_session).
-moduledoc false.
-behavior(gen_server).
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% This process owns a logical session, never raw descriptors. Forward the
%% original reply alias so the device owner remains the only admission queue.
start_link(Device) -> gen_server:start_link(?MODULE, Device, []).

init(Device) ->
    Monitor = monitor(process, Device),
    case gen_server:call(Device, attach_session) of
        ok -> {ok, #{device => Device, monitor => Monitor, draining => none}};
        {error, Reason} -> {stop, Reason}
    end.

handle_call(drain_session, From, State = #{device := Device, draining := none}) ->
    gen_server:cast(Device, {drain_session, self()}),
    {noreply, State#{draining := From}};
handle_call(drain_session, _From, State) ->
    {reply, {error, draining}, State};
handle_call(Request, From, State = #{device := Device}) ->
    Device ! {'$gen_call', From, {session, self(), Request}},
    {noreply, State}.

handle_cast({ack, Owner, Receipt}, State = #{device := Device}) ->
    gen_server:cast(Device, {ack, Owner, Receipt}),
    {noreply, State};
handle_cast({session_drained, Device}, State = #{device := Device, draining := From}) when From =/= none ->
    gen_server:reply(From, ok),
    {stop, normal, State};
handle_cast(_Message, State) -> {noreply, State}.

handle_info({'DOWN', Monitor, process, Device, Reason}, State = #{device := Device, monitor := Monitor}) ->
    {stop, {device_down, Reason}, State};
handle_info(_Message, State) -> {noreply, State}.
