-module(hls_mixed_topology_dslx).
-export([fixture/1, write/2, cpu/0]).

fixture(Placement) ->
    Workers = [{{workers, X, Y}, 2 * X + Y} || X <- [0, 1], Y <- [0, 1]] ++ [{extra, 4}],
    Plan = hls_topology:normalize(#{version => 1,
        actors => #{source => hls_mixed_source, collector => hls_mixed_collector,
            extra => hls_mixed_worker},
        families => #{workers => #{module => hls_mixed_worker, shape => [2, 2]}},
        ingresses => [], externals => [{reports, out, [report]}],
        routes => [{{source, Port}, queued, [{actor, Id} || {Id, _} <- Workers]}
            || Port <- [first, second]] ++ [
                {{extra, Port}, [{actor, collector}]} || Port <- [result_a, result_b]] ++ [
                {{collector, report}, [{external, reports}]},
                {{collector, feedback}, [{actor, source}]}],
        route_relations => [{{workers, Port}, [{actor, collector}]} || Port <- [result_a, result_b]],
        startup => [{source, [{kick, 0}]}] ++ [{Id, [{configure, I}]} || {Id, I} <- Workers]}),
    Specs = case Placement of
        direct -> #{};
        one -> #{workers => group([{family, workers}])};
        two -> #{even => group([{family, workers, {interleaved, 0, 2}}]),
            odd => group([{family, workers, {interleaved, 1, 2}}])};
        coalesced -> #{workers => group([{actor, extra}, {family, workers}])}
    end,
    {Plan, Specs}.

group(Members) -> #{members => Members, state_storage => block_ram, mailbox_storage => block_ram}.

write(Placement, Stage) ->
    {Plan, Specs} = fixture(Placement),
    Options = #{direct_actor_debug => true, mailbox_debug => map_size(Specs) > 0},
    Profile = maps:merge(#{name => mixed_topology, channel_depth => 1,
        actor_egress_depth => 0, scheduler_groups => Specs}, Options),
    Requirements = xls_topology_dslx:artifact_requirements(Plan, Profile),
    Artifacts = maps:map(fun(Module, Requirement) ->
        xls_parse:to_xls(filename:join("test", atom_to_list(Module) ++ ".erl"), Requirement)
    end, Requirements),
    maps:foreach(fun(Module, Artifact) ->
        ok = file:write_file(filename:join(Stage, atom_to_list(Module) ++ ".x"), Artifact)
    end, Artifacts),
    ok = file:write_file(filename:join(Stage, "mixed_topology.x"), xls_topology_dslx:emit(Plan, Profile)),
    ok = file:write_file(filename:join(Stage, "actors.json"),
        json:encode(xls_scheduler_debug:projection(Plan, Specs, Artifacts, Options))),
    Scheduler = hls_scheduler_plan:normalize(Plan, Specs),
    Bindings = xls_scheduler_ram_v:bindings(Scheduler),
    Direct = xls_actor_observation:bindings(Plan, Specs),
    {MailboxWires, MailboxPorts} = case map_size(Specs) of
        0 -> {[], []};
        _ -> {xls_scheduler_observation:wires(Scheduler), xls_scheduler_observation:ports(Scheduler)}
    end,
    Wrapper = ["module mixed_topology_wrapper(input wire clk, reset,\n",
        "  output wire [127:0] _reports_out, output wire _reports_out_vld, input wire _reports_out_rdy);\n",
        xls_scheduler_ram_v:wires(Bindings), MailboxWires, xls_actor_observation:wires(Direct),
        "mixed_topology dut(.clk(clk), .reset(reset), ._reports_out(_reports_out),\n",
        " ._reports_out_vld(_reports_out_vld), ._reports_out_rdy(_reports_out_rdy)",
        xls_scheduler_ram_v:application_ports(Bindings), MailboxPorts, xls_actor_observation:ports(Direct), ");\n",
        xls_scheduler_ram_v:instances(Bindings, "clk"), "endmodule\n"],
    ok = file:write_file(filename:join(Stage, "mixed_topology_wrapper.v"), Wrapper),
    Reports = cpu(),
    Expected = [{report, I, 80 * I + 30} || I <- lists:seq(0, 31)],
    Expected = Reports,
    ok = file:write_file(filename:join(Stage, "cpu.term"), io_lib:format("~p.~n", [Reports])),
    file:write_file(filename:join(Stage, "expected.hex"), [frame_hex(R) || R <- Reports]).

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
cpu() ->
    %% Keep linked actors and their EXIT messages inside one fixture owner.
    %% A fresh result reference also isolates repeated calls by the same test.
    Host = self(),
    Reference = make_ref(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Reports = cpu_run(),
        Host ! {Reference, Reports}
    end),
    receive
        {Reference, Reports} ->
            receive
                {'DOWN', Monitor, process, Pid, normal} -> Reports;
                {'DOWN', Monitor, process, Pid, Reason} -> error({cpu_fixture_failed, Reason})
            end;
        {'DOWN', Monitor, process, Pid, Reason} -> error({cpu_fixture_failed, Reason})
    after 30000 ->
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end,
        error(cpu_fixture_timeout)
    end.

cpu_run() ->
    {Plan, _} = fixture(direct),
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
        Reports = receive_reports(32, []),
        await_cpu_source(maps:get(source, Pids), 1000),
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

queue_startup(Startup, Pids) ->
    lists:foreach(fun(#{target := Id, messages := Messages}) ->
        lists:foreach(fun(Message) -> hls_statem:cast(maps:get(Id, Pids), Message) end, Messages)
    end, Startup).

await_cpu_source(Pid, Attempts) ->
    case hls_debug:info({hls_statem, Pid}, phase) of
        {phase, done} -> ok;
        _ when Attempts > 0 -> await_cpu_source(Pid, Attempts - 1);
        Actual -> error({cpu_source_incomplete, Actual})
    end.

final_phase(source) -> done;
final_phase(collector) -> reporting;
final_phase(_) -> active.

forward(Recipients, Pids, Host) ->
    receive {'$gen_cast', Message} ->
        lists:foreach(fun
            ({actor, Id}) -> hls_statem:cast(maps:get(Id, Pids), Message);
            ({external, reports}) -> Host ! {mixed_report, Message}
        end, Recipients),
        forward(Recipients, Pids, Host)
    end.

receive_reports(0, Acc) -> lists:reverse(Acc);
receive_reports(N, Acc) ->
    receive {mixed_report, Report} -> receive_reports(N-1, [Report | Acc])
    after 10000 -> error({missing_cpu_reports, N})
    end.
