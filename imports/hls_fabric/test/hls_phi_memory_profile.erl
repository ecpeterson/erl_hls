-module(hls_phi_memory_profile).
-moduledoc "A zero-simulated-time host for measuring the complete phi application's service capacity.".
-export([run/1, describe/1]).

-doc "Serves public packets over test-only FIFOs, applies the ordinary reducer, and checks the selected BEAM witness. FIFO waits consume wall time only.".
-spec run(file:filename()) -> ok.
run(Stage) ->
    {ok, _} = application:ensure_all_started(crypto),
    {ok, [Partition]} = file:consult(filename:join(Stage, "deployment.term")),
    {ok, [Options]} = file:consult(filename:join(Stage, "config.term")),
    {ok, [Expected]} = file:consult(filename:join(Stage, "oracle.term")),
    Deployment = #{devices := Devices} = hls_partition_wire:deployment(Partition),
    {Experiment, [_Cutoff]} = phi_memory_experiment:new(Options),
    Debug = hls_phi_profile_debug:open(Stage),
    %% Both processes open in the same order; each request has exactly one reply.
    {ok, Input} = file:open(filename:join(Stage, "host_requests"), [read, raw, binary]),
    {ok, Output} = file:open(filename:join(Stage, "host_responses"), [write, raw, binary]),
    try
        Attach = [{D, {Host, Control}, {1, 0, 0}, Identity}
            || {D, #{host := Host, control := Control, identity := Identity}} <- lists:sort(maps:to_list(Devices))],
        ok = respond(Output, Attach ++ hls_phi_profile_debug:initial(Debug)),
        serve(Input, Output, #{deployment => Deployment, experiment => Experiment,
            expected => Expected, stage => Stage, attached => [], events => 0, commands => 0, debug => Debug})
    after
        file:close(Input), file:close(Output)
    end.

%% Packet boundaries are public TLAST handshakes, never internal hierarchy reads.
-spec serve(file:io_device(), file:io_device(), map()) -> ok.
serve(Input, Output, State) ->
    {Device, [Route, Header | Words]} = read_packet(Input),
    case Device >= map_size(maps:get(devices, maps:get(deployment, State))) of
        true ->
            {NextDebug, Packets} = hls_phi_profile_debug:reply(Device, [Route, Header | Words], maps:get(debug, State)),
            ok = respond(Output, Packets),
            serve(Input, Output, State#{debug := NextDebug});
        false -> application_packet(Device, Route, Header, Words, Input, Output, State)
    end.

%% Application packets use the unmodified public gateway codec and experiment reducer.
-spec application_packet(non_neg_integer(), non_neg_integer(), non_neg_integer(), [non_neg_integer()],
    file:io_device(), file:io_device(), map()) -> ok.
application_packet(Device, Route, Header, Words, Input, Output,
        State = #{deployment := Deployment = #{devices := Devices}, experiment := Experiment,
            attached := Attached, events := Count, commands := Sent}) ->
    Binding = #{host := Host, control := Control, identity := Identity} = maps:get(Device, Devices),
    <<Source:16, Host:16>> = <<Route:32>>,
    <<Op:8, Tx:8, Flags:8, Size:8>> = <<Header:32>>,
    Size = length(Words),
    Payload = << <<Word:32/little>> || Word <- Words >>,
    case Source of
        Control ->
            %% Each binding must acknowledge the exact attachment once.
            {16#81, 0, 0, Identity, false} = {Op, Tx, Flags, Payload, lists:member(Device, Attached)},
            ok = respond(Output, []),
            serve(Input, Output, State#{attached := [Device | Attached]});
        _ ->
            true = lists:member(Device, Attached),
            {Stream, Event} = hls_partition_wire:event(Binding, {Source, Host}, {Op, Flags, Tx}, Payload),
            case phi_memory_experiment:event(Stream, Event, Experiment) of
                {done, Witness, _} ->
                    Witness = maps:get(expected, State),
                    ok = file:write(Output, <<"ffffffff\n">>),
                    Stage = maps:get(stage, State),
                    Summary = phi_memory_demo:summary(Witness),
                    ok = hls_phi_memory_metrics:write(Stage, <<"Autonomous phi workload, complete status intervals after round 8, zero-simulated-time host; gateway/link/CDC retained. Simulated clocks, not a physical frequency qualification.">>, maps:get(closeout_step, Summary)),
                    ok = hls_bridge_phi_live:save(Stage, "memory-result.json", #{
                        summary => Summary, events => Count+1, commands => Sent}),
                    ok = hls_phi_profile_debug:save(maps:get(debug, State)),
                    ok = file:write_file(filename:join(Stage, "done"), <<>>),
                    io:format("PASS: zero-time host; ~p events, ~p commands; selected witness matches BEAM~n", [Count+1, Sent]);
                {error, Reason, _} -> error({experiment, Reason, Event});
                {Updated, Commands} ->
                    Packets = lists:append([hls_partition_wire:command(Deployment, C) || C <- Commands]),
                    ok = respond(Output, Packets),
                    serve(Input, Output, State#{experiment := Updated, events := Count+1, commands := Sent+length(Packets)})
            end
    end.

%% One line carries a bounded command batch; words retain the gateway's existing ABI.
-spec respond(file:io_device(), [{term(), hls_fabric:route(), hls_fabric:header(), binary()}]) -> ok.
respond(Output, Packets) ->
    Encoded = [begin
        Size = byte_size(Payload) div 4,
        [Device, Size+2, (From bsl 16) bor To,
            (Op bsl 24) bor (Tx bsl 16) bor (Flags bsl 8) bor Size,
            [Word || <<Word:32/little>> <= Payload]]
    end || {Device, {From, To}, {Op, Flags, Tx}, Payload} <- Packets],
    Numbers = lists:flatten([length(Packets), Encoded]),
    file:write(Output, [lists:join(" ", [integer_to_list(N, 16) || N <- Numbers]), "\n"]).

%% A fixed-width text header gives an exact read size; raw FIFO reads need no line lookahead.
-spec read_packet(file:io_device()) -> {non_neg_integer(), [non_neg_integer()]}.
read_packet(Input) ->
    {ok, <<DeviceHex:8/binary, 32, SizeHex:8/binary, 10>>} = file:read(Input, 18),
    Device = binary_to_integer(DeviceHex, 16),
    Size = binary_to_integer(SizeHex, 16),
    true = Size >= 2 andalso Size =< 15,
    {ok, Body} = file:read(Input, Size*9+1),
    Words = [binary_to_integer(W, 16) || W <- binary:split(string:trim(Body), <<" ">>, [global])],
    Size = length(Words),
    {Device, Words}.

-doc "Writes logical source/destination and schema names for the cached deployment's wire lanes.".
-spec describe(file:filename()) -> ok.
describe(Stage) ->
    {ok, [Partition = #{actors := Actors, devices := Devices}]} = file:consult(filename:join(Stage, "deployment.term")),
    Modules = maps:from_list([{Id, M} || #{identity := Id, module := M} <- Actors]),
    Interfaces = hls_actor_interface:from_modules(lists:usort(maps:values(Modules))),
    Lanes = lists:append([begin
        #{tx_lanes := Tx} = hls_partition:device(Partition, D),
        [begin
            Module = maps:get(Source, Modules),
            Interface = maps:get(Module, Interfaces),
            Names = lists:usort(lists:append([hls_actor_interface:output_schemas(Interface, Port) || Port <- Ports])),
            #{device => D, peer => Peer, lane => Wire, source => iolist_to_binary(io_lib:format("~p", [Source])),
                destination => iolist_to_binary(io_lib:format("~p", [Destination])),
                schemas => [#{name => Name, tag => Module:pack_tag(Name), bits => Module:pack_width(Name)} || Name <- Names]}
        end || #{wire_id := Wire, destination_device := Peer, source := Source, destination := Destination, ports := Ports} <- Tx]
    end || D <- Devices]),
    hls_bridge_phi_live:save(Stage, "lane-catalog.json", Lanes).
