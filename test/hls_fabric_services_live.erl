-module(hls_fabric_services_live).
-export([run/1]).

%% Only public clients and external testbench handshakes. No VPI introspection.
run(Stage) ->
    {ok, App} = hls_fabric:start_link(filename:join(Stage, "app_tx"), filename:join(Stage, "app_rx")),
    {ok, Debug} = hls_fabric:start_link(filename:join(Stage, "debug_tx"), filename:join(Stage, "debug_rx")),
    Clients = [begin
        {ok, A} = hls_gs:start_link(regsvc, [], [{fabric, App, ID}]),
        {ok, D} = hls_debug:start_link(regsvc, {fabric, Debug, ID}),
        {ID, A, D}
    end || ID <- [2, 9, 42]],
    try
        Requests = [begin
            R = gen_server:send_request(A, {ping, ID}),
            {ID, R}
        end || {ID, A, _} <- Clients],
        await(filename:join(Stage, "app_held"), 10000),
        Blocked = [begin
            #{pending := 1} = Info = hls_fabric:client_info(A),
            {ok, Counters} = hls_debug:get_counters(D),
            {ID, Info, Counters}
        end || {ID, A, D} <- Clients],
        true = lists:all(fun({_, _, #{app_tx_stall_cycles := N}}) -> N > 0 end, Blocked),
        save(Stage, "blocked.term", #{clients => Blocked, fabric => hls_fabric:info(App)}),
        ok = file:write_file(filename:join(Stage, "release_app"), <<>>),
        replies(Requests),
        %% Independent endpoint state, variable-length replies, casts and many
        %% concurrent callers exercise all three non-contiguous routes.
        lists:foreach(fun({ID, A, _}) ->
            ok = regsvc:set(A, 0, ID, 16#ffffffff),
            [ID, 0, 0] = regsvc:bulk_get(A, 0, 3)
        end, Clients),
        lists:foreach(fun(Round) ->
            Batch = [{Round*10000 + ID*100 + N,
                gen_server:send_request(A, {ping, Round*10000 + ID*100 + N})}
                || N <- lists:seq(1, 64), {ID, A, _} <- Clients],
            Queries = [gen_server:send_request(D, get_counters) || {_, _, D} <- Clients],
            replies(Batch),
            [{reply, {ok, #{version := 5}}} = gen_server:wait_response(Q, 10000) || Q <- Queries]
        end, lists:seq(1, 5)),
        Recovered = [begin
            #{pending := 0, ignored_replies := 0} = Info = hls_fabric:client_info(A),
            {ok, #{app_rx_frames := 323, app_tx_frames := 322, observation_drops := 0} = Counters} = hls_debug:get_counters(D),
            %% Empty the earlier bank, then identify a fresh round trip through
            %% public trace records at each endpoint's own boundary.
            {ok, _} = hls_debug:get_trace(D),
            ID = regsvc:ping(A, ID),
            {ok, #{events := Events, observation_drops := 0, dropped := 0} = Trace} = hls_debug:get_trace(D),
            [application_rx, application_tx] = [Kind || #{kind := Kind} <- Events],
            {ID, Info, Counters, Trace}
        end || {ID, A, D} <- Clients],
        save(Stage, "recovered.term", Recovered),
        io:format("PASS: three service IDs, 960 concurrent pings, isolated state, variable replies and public stall/recovery diagnostics~n")
    after
        [begin hls_debug:stop(D),regsvc:stop(A) end || {_, A, D} <- Clients],
        hls_fabric:stop(App),hls_fabric:stop(Debug)
    end,
    file:write_file(filename:join(Stage, "done"), <<>>).

replies(Requests) ->
    [{reply, {ack, Value}} = gen_server:wait_response(R, 10000) || {Value, R} <- Requests],
    ok.

save(Stage, Name, Value) ->
    file:write_file(filename:join(Stage, Name), io_lib:format("~p.~n", [Value])).

await(_Path, 0) -> error(stimulus_timeout);
await(Path, Left) ->
    case file:read_file(Path) of
        {ok, _} -> ok;
        {error, enoent} -> timer:sleep(1),await(Path, Left-1)
    end.
