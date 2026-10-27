-module(hls_mixed_topology_dslx).
-export([fixture/1, write/2, cpu/0, cpu/1]).

-doc "Builds the selected test topology and its matching execution profile.".
-spec fixture('coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {term(),term()}}}) -> {term(),map()}.
fixture({ingress, Placement}) ->
    {Plan, Specs} = fixture(Placement),
    #{actors := Actors, routes := Routes, startup := Startup} = Plan,
    Family = {family, workers, {embed, [2, 3], [1, 1]}},
    Singleton = {actor, extra, {at, [5, 2]}},
    %% Normalize the same actor declarations, with an external command source.
    Spec = #{version => 1,
        actors => maps:from_list([{Id, M} || #{id := Id, module := M} <- Actors, Id =/= source]),
        families => #{workers => #{module => hls_mixed_worker, shape => [2, 2]}},
        ingresses => [{commands, {rectangle, [7, 6]}, [
            {all, [work, pulse], [Family, Singleton]},
            {family, [work], [Family]}, {singleton, [work], [Singleton]}]}],
        externals => [{reports, out, [report]}, {acks, out, [kick]}],
        routes => [case Source of
            {collector, feedback} -> {Source, [{external, acks}]};
            _ -> {Source, Recipients}
        end || #{source := Source = {Id, _}, recipients := Recipients} <- Routes, Id =/= source],
        route_relations => [{{workers, Port}, [{actor, collector}]} || Port <- [result_a, result_b]],
        startup => [{Id, Messages} || #{target := Id, messages := Messages} <- Startup, Id =/= source]},
    {hls_topology:normalize(Spec), Specs};
fixture({components, _Policy}) ->
    Left = definition(source, collector, extra, workers, reports),
    Right = definition(source_peer, collector_peer, extra_peer, workers_peer, reports_peer),
    Joined = maps:map(fun
        (version, Version) -> Version;
        (K, V) when K =:= actors; K =:= families -> maps:merge(V, maps:get(K, Right));
        (K, V) -> V ++ maps:get(K, Right)
    end, Left),
    %% Interleave the group indices between components to exercise local grant
    %% positions, which must not be confused with global scheduler indices.
    {hls_topology:normalize(Joined),
        #{even => group([{family, workers, {interleaved, 0, 2}}]),
          even_peer => group([{family, workers_peer, {interleaved, 0, 2}}]),
          odd => group([{family, workers, {interleaved, 1, 2}}]),
          odd_peer => group([{family, workers_peer, {interleaved, 1, 2}}])}};
fixture(Placement) ->
    Plan = hls_topology:normalize(definition(source, collector, extra, workers, reports)),
    Specs = case Placement of
        direct -> #{};
        one -> #{workers => group([{family, workers}])};
        two -> #{even => group([{family, workers, {interleaved, 0, 2}}]),
            odd => group([{family, workers, {interleaved, 1, 2}}])};
        coalesced -> #{workers => group([{actor, extra}, {family, workers}])}
    end,
    {Plan, Specs}.

%% Builds the logical mixed-actor graph independently of executor placement.
-spec definition('source' | 'source_peer','collector' | 'collector_peer','extra' | 'extra_peer','workers' | 'workers_peer','reports' | 'reports_peer') -> map().
definition(Source, Collector, Extra, Family, Reports) ->
    Members = [{{Family, X, Y}, 2 * X + Y} || X <- [0, 1], Y <- [0, 1]] ++ [{Extra, 4}],
    #{version => 1,
        actors => #{Source => hls_mixed_source, Collector => hls_mixed_collector,
            Extra => hls_mixed_worker},
        families => #{Family => #{module => hls_mixed_worker, shape => [2, 2]}},
        ingresses => [], externals => [{Reports, out, [report]}],
        routes => [{{Source, Port}, queued, [{actor, Id} || {Id, _} <- Members]}
            || Port <- [first, second]] ++ [
                {{Extra, Port}, [{actor, Collector}]} || Port <- [result_a, result_b]] ++ [
                {{Collector, report}, [{external, Reports}]},
                {{Collector, feedback}, [{actor, Source}]}],
        route_relations => [{{Family, Port}, [{actor, Collector}]} || Port <- [result_a, result_b]],
        startup => [{Source, [{kick, 0}]}] ++ [{Id, [{configure, I}]} || {Id, I} <- Members]}.

%% Assigns the selected fixture members to one shared executor.
-spec group([{'actor','extra'} | {'family','workers'} | {'family','workers' | 'workers_peer',{term(),term(),term()}},...]) -> map().
group(Members) -> #{members => Members, state_storage => block_ram, mailbox_storage => block_ram}.

-doc "Writes generated DSLX and the matching oracle or wrapper files into the test stage.".
-spec write('coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {term(),term()}}},atom() | binary() | [atom() | [any()] | char()]) -> 'ok' | {'error',atom()}.
write(Placement, Stage) ->
    {Plan, Specs} = fixture(Placement),
    Options = #{direct_actor_debug => true, mailbox_debug => map_size(Specs) > 0},
    Profile = maps:merge(#{name => mixed_topology, channel_depth => 1,
        actor_egress_depth => 0, scheduler_groups => Specs,
        effect_window_partition => window_policy(Placement)}, Options),
    Requirements = xls_shared_topology_dslx:artifact_requirements(Plan, Profile),
    Artifacts = maps:map(fun(Module, Requirement) ->
        xls_shared_parse:to_artifact(filename:join("test", atom_to_list(Module) ++ ".erl"), Requirement)
    end, Requirements),
    maps:foreach(fun(Module, Artifact) ->
        ok = file:write_file(filename:join(Stage, atom_to_list(Module) ++ ".x"), xls_emitted:bytes(Artifact))
    end, Artifacts),
    ok = file:write_file(filename:join(Stage, "mixed_topology.x"), xls_shared_topology_dslx:emit(Plan, Profile)),
    ok = file:write_file(filename:join(Stage, "actors.json"),
        json:encode(xls_scheduler_debug:projection(Plan, Specs, Artifacts, Options))),
    Scheduler = hls_scheduler_plan:normalize(Plan, Specs),
    Bindings = xls_scheduler_ram_v:bindings(Scheduler),
    Direct = xls_actor_observation:bindings(Plan, hls_scheduler_plan:placements(Scheduler)),
    {MailboxWires, MailboxPorts} = case map_size(Specs) of
        0 -> {[], []};
        _ -> {xls_scheduler_observation:wires(Scheduler), xls_scheduler_observation:ports(Scheduler)}
    end,
    Wrapper = ["module mixed_topology_wrapper(input wire clk, reset,\n",
        input_ports(Placement),
        "  output wire [127:0] _reports_out, output wire _reports_out_vld, input wire _reports_out_rdy);\n",
        xls_scheduler_ram_v:wires(Bindings), MailboxWires, xls_actor_observation:wires(Direct),
        "mixed_topology dut(.clk(clk), .reset(reset), ._reports_out(_reports_out),\n",
        " ._reports_out_vld(_reports_out_vld), ._reports_out_rdy(_reports_out_rdy)",
        input_connections(Placement),
        xls_scheduler_ram_v:application_ports(Bindings), MailboxPorts, xls_actor_observation:ports(Direct), ");\n",
        xls_scheduler_ram_v:instances(Bindings, "clk"), "endmodule\n"],
    ok = file:write_file(filename:join(Stage, "mixed_topology_wrapper.v"), Wrapper),
    %% Each disconnected copy has the same transcript as the closed CPU graph;
    %% RTL checks both ports independently and stalls only the first copy.
    Reports = case Placement of {components, _} -> cpu(); _ -> cpu(Placement) end,
    ok = write_commands(Placement, Stage),
    Expected = [{report, I, 80 * I + 30} || I <- lists:seq(0, 31)],
    Expected = Reports,
    ok = file:write_file(filename:join(Stage, "cpu.term"), io_lib:format("~p.~n", [Reports])),
    file:write_file(filename:join(Stage, "expected.hex"), [frame_hex(R) || R <- Reports]).

%% Selects the effect-window ownership partition exercised by the test.
-spec window_policy(term()) -> global | weak_components.
window_policy({components, Policy}) -> Policy;
window_policy(_) -> global.

%% Encodes a complete actor frame as scoreboard hexadecimal.
-spec frame_hex({'configure',term()} | {'kick',term()} | {'pulse',term()} | {'work',term()} | {'report',term(),term()} | {'result',term(),term()} | {'cell',term(),term(),term(),term()}) -> [[any()] | char()].
frame_hex(Report) ->
    Payload = hls_codec:align(hls_mixed_collector:pack(Report), 32),
    %% XLS's struct flattening puts Header above its 96-bit payload. Within
    %% Header, op is the low byte; this differs from axis::bits_from_frame.
    Width = bit_size(Payload),
    Value = hls_codec:unsigned(Payload),
    Header = (Width div 32) bsl 24 bor hls_mixed_collector:pack_tag(report),
    io_lib:format("~32.16.0b~n", [(Header bsl 96) bor Value]).

%% Test-only CPU realization of this closed fixture. Identical recipient sets
%% from one source share a fanout process, preserving aliased-port ordering.
-doc "Runs the bounded fixture through native actors and collects all reports.".
-spec cpu() -> [{report, non_neg_integer(), integer()}].
cpu() -> cpu(direct).

-doc "Runs the bounded fixture through native actors and collects all reports.".
-spec cpu(term()) -> [{report, non_neg_integer(), integer()}].
cpu(Mode) ->
    %% Keep linked actors and their EXIT messages inside one fixture owner.
    %% A fresh result reference also isolates repeated calls by the same test.
    Host = self(),
    Reference = make_ref(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Reports = cpu_run(Mode),
        Host ! {Reference, Reports}
    end),
    receive
        {Reference, Reports} ->
            receive
                {'DOWN', Monitor, process, Pid, normal} -> Reports;
                {'DOWN', Monitor, process, Pid, Reason} -> error({cpu_fixture_failed, Reason})
            end;
        {'DOWN', Monitor, process, Pid, Reason} -> error({cpu_fixture_failed, Reason})
    after 5000 ->
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end,
        error(cpu_fixture_timeout)
    end.

%% Deploys the CPU topology, drives the scenario and closes it after collection.
-spec cpu_run('coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {term(),term()}}}) -> [any()].
cpu_run(Mode) ->
    {Plan, _} = fixture(Mode),
    #{actors := Exact, families := [Family], startup := Startup, routes := Routes0} = Plan,
    #{id := FamilyId, module := Module, shape := [W, H], mailbox_capacity := FamilyCapacity} = Family,
    Actors = [{Id, M, Capacity} || #{id := Id, module := M, mailbox_capacity := Capacity} <- Exact] ++
        [{{FamilyId, X, Y}, Module, FamilyCapacity} || X <- lists:seq(0, W-1), Y <- lists:seq(0, H-1)],
    Routes = Routes0 ++ lists:append([hls_topology:routes_for_instance(Plan, FamilyId, [X, Y])
        || X <- lists:seq(0, W-1), Y <- lists:seq(0, H-1)]),
    Pids = maps:from_list([begin
        {ok, Pid} = hls_statem:start_link(M, [], [{mailbox_capacity, Capacity}]),
        {Id, Pid}
    end || {Id, M, Capacity} <- Actors]),
    Host = self(),
    Keys = lists:usort([{Source, Recipients} || #{source := {Source, _}, recipients := Recipients} <- Routes]),
    Routers = maps:from_list([{Key, spawn_link(fun() -> forward(Recipients, Pids, Host) end)}
        || Key = {_, Recipients} <- Keys]),
    try
        maps:foreach(fun(Id, Pid) ->
            Outputs = maps:from_list([{Port, maps:get({Id, Recipients}, Routers)}
                || #{source := {Source, Port}, recipients := Recipients} <- Routes, Source =:= Id]),
            ok = hls_statem:connect(Pid, Outputs)
        end, Pids),
        %% All initial entries are quiescent. Choose one legal across-actor
        %% startup order: configure workers before releasing the source. The
        %% CPU reference keeps declared mailbox bounds but does not emulate
        %% transport backpressure; RTL independently tests concurrent startup.
        {SourceStartup, WorkerStartup} = lists:partition(fun(#{target := Id}) ->
            Id =:= source
        end, Startup),
        queue_startup(WorkerStartup, Pids),
        lists:foreach(fun(#{target := Id}) ->
            [{phase, active}, {message_queue_len, 0}] =
                hls_debug:info({hls_statem, maps:get(Id, Pids)}, [phase, message_queue_len])
        end, WorkerStartup),
        queue_startup(SourceStartup, Pids),
        Reports = case Mode of
            {ingress, _} -> [begin
                %% Independent logical reference: each round sends exactly two
                %% commands per worker. RTL additionally tests spatial selection
                %% and rejection using the external packet stream below.
                Workers = [maps:get(Id, Pids) ||
                    Id <- [extra | [{workers, X, Y} || X <- [0, 1], Y <- [0, 1]]]],
                lists:foreach(fun(Sequence) ->
                    lists:foreach(fun(Pid) -> hls_statem:cast(Pid, {work, Sequence}) end, Workers),
                    case Sequence rem 2 of
                        0 -> lists:foreach(fun(_) ->
                            lists:foreach(fun(Pid) ->
                                hls_statem:cast(Pid, {pulse, 0}),
                                {phase, active} = hls_debug:info({hls_statem, Pid}, phase)
                            end, Workers)
                        end, lists:seq(1, 8));
                        1 -> ok
                    end
                end, [2 * Round, 2 * Round + 1]),
                [Report] = receive_reports(1, []),
                receive {mixed_ack, {kick, Next}} when Next =:= Round + 1 -> ok
                after 1000 -> error(missing_cpu_ack) end,
                Report
            end || Round <- lists:seq(0, 31)];
            _ ->
                Values = receive_reports(32, []),
                await_cpu_source(maps:get(source, Pids), 100),
                Values
        end,
        maps:foreach(fun(Id, Pid) ->
            ExpectedPhase = final_phase(Id),
            [{phase, ExpectedPhase}, {message_queue_len, 0}, {postponed, 0}, {reserved, 0}] =
                hls_debug:info({hls_statem, Pid}, [phase, message_queue_len, postponed, reserved])
        end, Pids),
        Reports
    after
        maps:foreach(fun(_, Pid) -> unlink(Pid), exit(Pid, kill) end, Routers),
        maps:foreach(fun(_, Pid) -> hls_statem:stop(Pid) end, Pids)
    end.

%% Delivers the declared startup messages before normal fixture traffic.
-spec queue_startup([any()],map()) -> 'ok'.
queue_startup(Startup, Pids) ->
    lists:foreach(fun(#{target := Id, messages := Messages}) ->
        lists:foreach(fun(Message) -> hls_statem:cast(maps:get(Id, Pids), Message) end, Messages)
    end, Startup).

%% Waits for the source actor to reach its expected terminal phase.
-spec await_cpu_source(term(),byte()) -> 'ok'.
await_cpu_source(Pid, Attempts) ->
    case hls_debug:info({hls_statem, Pid}, phase) of
        {phase, done} -> ok;
        _ when Attempts > 0 -> await_cpu_source(Pid, Attempts - 1);
        Actual -> error({cpu_source_incomplete, Actual})
    end.

%% Reports whether a fixture actor has completed its scenario.
-spec final_phase(term()) -> 'active' | 'done' | 'reporting'.
final_phase(source) -> done;
final_phase(collector) -> reporting;
final_phase(_) -> active.

%% Relays fixture messages while retaining their source identity.
-spec forward([any()],map(),pid()) -> no_return().
forward(Recipients, Pids, Host) ->
    receive {'$gen_cast', Message} ->
        lists:foreach(fun
            ({actor, Id}) -> hls_statem:cast(maps:get(Id, Pids), Message);
            ({external, reports}) -> Host ! {mixed_report, Message};
            ({external, acks}) -> Host ! {mixed_ack, Message}
        end, Recipients),
        forward(Recipients, Pids, Host)
    end.

%% Collects the requested number of CPU reports with a bounded wait.
-spec receive_reports(byte(),[any()]) -> [any()].
receive_reports(0, Acc) -> lists:reverse(Acc);
receive_reports(N, Acc) ->
    receive {mixed_report, Report} -> receive_reports(N-1, [Report | Acc])
    after 1000 -> error({missing_cpu_reports, N})
    end.


%% Declares the fixture's external command and acknowledgment ports.
-spec input_ports('coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {term(),term()}}}) -> [1 .. ((1 bsl 8) - 1)].
input_ports({components, _}) ->
    "  output wire [127:0] _reports_peer_out, output wire _reports_peer_out_vld, input wire _reports_peer_out_rdy,\n";
input_ports({ingress, _}) ->
    "  input wire [193:0] _commands_in, input wire _commands_in_vld, output wire _commands_in_rdy,\n"
    "  output wire [127:0] _acks_out, output wire _acks_out_vld, input wire _acks_out_rdy,\n";
input_ports(_) -> [].

%% Connects external command streams to the generated wrapper.
-spec input_connections('coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {term(),term()}}}) -> [1 .. ((1 bsl 8) - 1)].
input_connections({components, _}) ->
    ", ._reports_peer_out(_reports_peer_out), ._reports_peer_out_vld(_reports_peer_out_vld), ._reports_peer_out_rdy(_reports_peer_out_rdy)";
input_connections({ingress, _}) ->
    ", ._commands_in(_commands_in), ._commands_in_vld(_commands_in_vld), ._commands_in_rdy(_commands_in_rdy)"
    ", ._acks_out(_acks_out), ._acks_out_vld(_acks_out_vld), ._acks_out_rdy(_acks_out_rdy)";
input_connections(_) -> [].

%% Writes the bounded host command sequence used by the RTL driver.
-spec write_commands('coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {'components',term()} | {'ingress','coalesced' | 'direct' | 'one' | 'two' | {term(),term()}}},atom() | binary() | [atom() | [any()] | char()]) -> 'ok' | {'error',atom()}.
write_commands({ingress, _}, Stage) ->
    %% Round numbers fence the host stream on feedback, rather than simulator
    %% time. Start round zero with reset release, racing declared startup.
    Packets = lists:append([round_packets(Round) || Round <- lists:seq(0, 31)]),
    file:write_file(filename:join(Stage, "commands.json"), json:encode([
        #{round => Round, bits => iolist_to_binary(io_lib:format("~49.16.0b", [Bits]))}
        || {Round, Bits} <- Packets]));
write_commands(_, _) -> ok.

%% Builds the packets belonging to one externally commanded fixture round.
-spec round_packets(integer()) -> [{integer(),integer()}].
round_packets(Round) ->
    Full = [0, 0, 6, 5],
    Op = hls_mixed_worker:pack_tag(work),
    Poison = 999,
    Burst = [packet(0, Full, hls_mixed_worker:pack_tag(pulse), 1, 0) || _ <- lists:seq(1, 8)],
    Invalid = [packet(3, Full, Op, 1, Poison),
        packet(0, Full, 255, 1, Poison), packet(0, Full, Op, 0, Poison),
        packet(0, [6, 5, 0, 0], Op, 1, Poison),
        packet(0, [2, 2, 2, 2], Op, 1, Poison),
        packet(0, [7, 6, 65535, 65535], Op, 1, Poison)],
    %% Alternate multicast and individually addressed family points. The
    %% singleton shares target ALL but must not receive target FAMILY.
    Second = case Round rem 2 of
        0 -> [packet(1, Full, Op, 1, 2 * Round + 1)];
        1 -> [packet(1, [X, Y, X, Y], Op, 1, 2 * Round + 1)
            || X <- [1, 3], Y <- [1, 4]]
    end,
    [{Round, Bits} || Bits <- [packet(0, Full, Op, 1, 2 * Round)] ++ Burst ++ Invalid ++
        Second ++ [packet(2, [5, 2, 5, 2], Op, 1, 2 * Round + 1)]].

%% Encodes one addressed command in the transport's expected word order.
-spec packet(0 | 1 | 2 | 3,[0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 65535,...],1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 255,0 | 1,integer()) -> integer().
packet(Target, [X0, Y0, X1, Y1], Op, Words, Sequence) ->
    %% DSLX struct flattening: rectangle, target, frame; the first field is MSB.
    Rectangle = (X0 bsl 48) bor (Y0 bsl 32) bor (X1 bsl 16) bor Y1,
    Header = Words bsl 24 bor Op,
    (Rectangle bsl 130) bor (Target bsl 128) bor (Header bsl 96) bor Sequence.
