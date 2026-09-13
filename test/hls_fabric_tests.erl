-module(hls_fabric_tests).
-include_lib("eunit/include/eunit.hrl").

retired_route_test() ->
    with_fabric(fun(Fabric, Read, _WritePath) ->
        Owner = spawn(fun() -> receive stop -> ok end end),
        Monitor = monitor(process, Owner),
        Route = {7, 0},
        ok = hls_fabric:register_route(Fabric, Route, Owner),
        ok = hls_fabric:register_route(Fabric, Route, Owner),
        ?assertEqual({error, {route_in_use, Route, Owner}},
            hls_fabric:register_route(Fabric, Route, self())),
        Owner ! stop,
        receive {'DOWN', Monitor, process, Owner, normal} -> ok end,
        %% Both registration races (before or after the broker's DOWN) must
        %% retire the route. Repeated attempts must not erase the retirement.
        [?assertEqual({error, {route_retired, Route}},
            hls_fabric:register_route(Fabric, Route, self())) || _ <- lists:seq(1, 3)],
        ok = hls_fabric:register_route(Fabric, {8, 0}, self()),
        %% Deliver a delayed old frame followed by one on an independent route.
        %% Only the independent frame may reach the successor process.
        ok = file:write(Read, [frame(Route, {129, 0, 0}, <<1:32/little>>),
            frame({8, 0}, {129, 0, 0}, <<2:32/little>>)]),
        receive {'$gen_cast', Message} ->
            ?assertMatch({'$hls_fabric_frame', _, {8, 0}, {129, 0, 0}, <<2:32/little>>}, Message)
        after 1000 -> error(no_frame) end
    end).

frame_io_test() ->
    with_fabric(fun(Fabric, Read, WritePath) ->
        ok = hls_fabric:register_route(Fabric, {5, 0}, self()),
        Payload = <<0:8160>>, % maximum 255-word frame
        ok = hls_fabric:send(Fabric, {0, 5}, {127, 255, 0}, Payload),
        ?assertEqual({ok, frame({0, 5}, {127, 255, 0}, Payload)}, file:read_file(WritePath)),
        ?assertEqual({error, {not_sent, {unaligned_payload, 1}}},
            hls_fabric:send(Fabric, {0, 5}, {1, 0, 0}, <<1>>)),
        ok = file:write(Read, frame({5, 0}, {255, 255, 0}, <<1:32/little>>)),
        receive {'$gen_cast', Message} ->
            ?assertMatch({'$hls_fabric_frame', _, {5, 0}, {255, 255, 0}, <<1:32/little>>}, Message)
        after 1000 -> error(no_frame) end
    end).

write_failure_closes_all_routes_test_() ->
    %% /dev/full supplies deterministic ENOSPC on Linux. macOS has no such
    %% device; the portable client tests inject the broker error separately.
    case file:read_file_info("/dev/full") of
        {error, enoent} -> [];
        {ok, _} -> fun() -> with_fabric("/dev/full", fun(Fabric, _Read, _WritePath) ->
            Monitor = monitor(process, Fabric),
            ?assertEqual({error, enospc}, hls_fabric:send(Fabric, {0, 1}, {1, 0, 0}, <<>>)),
            receive {'DOWN', Monitor, process, Fabric, {write_failed, enospc}} -> ok
            after 1000 -> error(broker_did_not_stop) end
        end) end
    end.

with_fabric(Run) -> with_fabric(default, Run).
with_fabric(Write, Run) ->
    Root = filename:absname(filename:join(["_build", "fabric-tests",
        integer_to_list(erlang:unique_integer([positive]))])),
    ReadPath = filename:join(Root, "rx"),
    ok = filelib:ensure_dir(ReadPath),
    Port = open_port({spawn_executable, os:find_executable("mkfifo")},
        [{args, [ReadPath]}, exit_status]),
    receive {Port, {exit_status, 0}} -> ok after 1000 -> error(mkfifo_failed) end,
    %% Keeping both ends open prevents EOF while the broker is being tested.
    {ok, Read} = file:open(ReadPath, [read, write, raw, binary]),
    WritePath = case Write of default -> filename:join(Root, "tx"); _ -> Write end,
    {ok, Fabric} = hls_fabric:start_link(WritePath, ReadPath),
    unlink(Fabric),
    try Run(Fabric, Read, WritePath)
    after
        case is_process_alive(Fabric) of true -> hls_fabric:stop(Fabric); false -> ok end,
        %% Close the writer too, releasing any raw listener read still in flight.
        file:close(Read),
        file:del_dir_r(Root)
    end.

frame({Source, Destination}, {Tag, TxID, Flags}, Payload) ->
    <<Destination:16/little, Source:16/little,
        (byte_size(Payload) div 4):8, TxID:8, Flags:8, Tag:8, Payload/binary>>.
