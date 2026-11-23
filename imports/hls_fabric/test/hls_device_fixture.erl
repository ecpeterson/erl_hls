-module(hls_device_fixture).
%% A deterministic wire-level device model. Real hls_fabric brokers write
%% complete routed packets to files and receive replies through OS FIFOs.
%% Holding output models delayed device completion, not clocked RTL backpressure.
-behaviour(gen_server).
-export([start/1, stop/1, hold/1, release/1, stats/1, stop_broker/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start(Options) -> gen_server:start(?MODULE, Options, []).
stop(Pid) -> gen_server:stop(Pid).
hold(Pid) -> gen_server:call(Pid, hold).
release(Pid) -> gen_server:call(Pid, release).
stats(Pid) -> gen_server:call(Pid, stats).
stop_broker(Pid, Kind) -> gen_server:call(Pid, {stop_broker, Kind}).

init(Options) ->
    process_flag(trap_exit, true),
    Root = filename:absname(filename:join(["_build", "device-models",
        binary_to_list(binary:encode_hex(crypto:strong_rand_bytes(12)))])),
    ok = filelib:ensure_dir(filename:join(Root, "placeholder")),
    Streams = maps:from_list([{Kind, stream(Root, Kind, Options)} || Kind <- [application, debug]]),
    Brokers = maps:map(fun(_, #{broker := Broker}) -> Broker end, Streams),
    self() ! poll,
    {ok, #{root => Root, streams => Streams, brokers => Brokers, actors => #{}, held => [], holding => false,
        received => 0, transmitted => 0}}.

stream(Root, Kind, Options) ->
    Prefix = filename:join(Root, atom_to_list(Kind)),
    Tx = Prefix ++ "_tx", Rx = Prefix ++ "_rx",
    ok = file:write_file(Tx, <<>>),
    Port = open_port({spawn_executable, os:find_executable("mkfifo")}, [{args, [Rx]}, exit_status]),
    receive {Port, {exit_status, 0}} -> ok after 3000 -> error(mkfifo_failed) end,
    {ok, Input} = file:open(Tx, [read, raw, binary]),
    {ok, Output} = file:open(Rx, [read, write, raw, binary]),
    {ok, Broker} = hls_fabric:start_link(Tx, Rx, maps:merge(#{tx_limit => 8, tx_route_limit => 4,
        rx_limit => 4, rx_route_limit => 1}, Options)),
    #{io := #{lease := Lease}} = hls_fabric:info(Broker),
    #{broker => Broker, input => Input, output => Output, lease => Lease,
        offset => 0, buffer => <<>>}.

handle_call(hold, _From, State) -> {reply, ok, State#{holding := true}};
handle_call(release, _From, State = #{held := Held}) ->
    Next = lists:foldl(fun(Frame, Acc) -> emit(application, Frame, Acc) end,
        State#{holding := false, held := []}, lists:reverse(Held)),
    {reply, ok, Next};
handle_call(stats, _From, State = #{held := Held}) ->
    {reply, (maps:with([received, transmitted, brokers], State))#{held => length(Held)}, State};
handle_call({stop_broker, Kind}, _From, State = #{brokers := Brokers}) ->
    ok = hls_fabric:stop(maps:get(Kind, Brokers)),
    {reply, ok, State}.
handle_cast(_, State) -> {noreply, State}.
handle_info(poll, State) ->
    Next = lists:foldl(fun read_stream/2, State, [application, debug]),
    erlang:send_after(2, self(), poll),
    {noreply, Next};
handle_info(_, State) -> {noreply, State}.

read_stream(Kind, State = #{streams := Streams}) ->
    #{input := Input, offset := Offset, buffer := Buffer} = Stream = maps:get(Kind, Streams),
    case file:pread(Input, Offset, 65536) of
        eof -> State;
        {ok, Bytes} ->
            {Frames, Rest} = frames(<<Buffer/binary, Bytes/binary>>, []),
            Next = State#{streams := Streams#{Kind := Stream#{buffer := Rest, offset := Offset + byte_size(Bytes)}}},
            lists:foldl(fun(Frame, Acc) -> consume(Kind, Frame, Acc) end, Next, Frames)
    end.

frames(<<Dest:16/little, Source:16/little, Words:8, Tx:8, Flags:8, Tag:8,
        Payload:(Words*4)/binary, Rest/binary>>, Acc) ->
    frames(Rest, [{{Source, Dest}, {Tag, Tx, Flags}, Payload} | Acc]);
frames(Rest, Acc) -> {lists:reverse(Acc), Rest}.

consume(application, {{Source, Dest}, {Tag, Tx, 0}, Payload},
        State = #{actors := Actors, received := Received}) ->
    Type = regsvc:unpack_tag(Tag),
    {Message, <<>>} = regsvc:unpack(Type, Payload),
    Actor = maps:get(Dest, Actors, regsvc:init([])),
    Base = State#{received := Received + 1},
    case Tx of
        255 ->
            {noreply, NewActor} = regsvc:handle_cast(Message, Actor),
            Base#{actors := Actors#{Dest => NewActor}};
        _ ->
            {reply, Reply, NewActor} = regsvc:handle_call(Message, Actor),
            Packet = {{Dest, Source}, {regsvc:pack_tag(element(1, Reply)), Tx, 0}, regsvc:pack(Reply)},
            respond(Packet, Base#{actors := Actors#{Dest => NewActor}})
    end;
consume(debug, {{Source, Dest}, {1, Tx, 0}, <<>>}, State = #{received := Rx, transmitted := TxCount}) ->
    Payload = <<5:32/little, 0:32, (Rx*2):32/little, Rx:32/little, 0:32,
        (TxCount*2):32/little, TxCount:32/little, 0:32, 0:32, 0:32>>,
    emit(debug, {{Dest, Source}, {16#81, Tx, 0}, Payload}, State).

respond(Frame, State = #{holding := true, held := Held}) -> State#{held := [Frame | Held]};
respond(Frame, State) -> emit(application, Frame, State).

emit(Kind, {Route, Header, Payload}, State = #{streams := Streams, transmitted := Count}) ->
    #{output := FD} = maps:get(Kind, Streams),
    {ok, Bytes} = hls_fabric_io:encode(Route, Header, Payload),
    ok = file:write(FD, Bytes),
    case Kind of application -> State#{transmitted := Count + 1}; debug -> State end.

terminate(_, #{streams := Streams, root := Root}) ->
    [begin
        case is_process_alive(Broker) of true -> hls_fabric:stop(Broker); false -> ok end,
        %% Finish an idle reader's permitted frame, then confirm actual closure.
        ok = file:write(Output, <<0:64>>),
        ok = file:close(Output),
        ok = file:close(Input),
        ok = hls_fabric:await_closed(Lease, 3000)
    end || #{broker := Broker, input := Input, output := Output, lease := Lease} <- maps:values(Streams)],
    file:del_dir_r(Root), ok.
