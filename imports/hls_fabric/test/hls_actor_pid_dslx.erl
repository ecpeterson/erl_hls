-module(hls_actor_pid_dslx).
-moduledoc false.
-export([fixture/0, write/1]).

%% This fixture has one family and one singleton-addressable ingress. The
%% private gateway maps physical endpoint/slot pairs back to that ingress;
%% it does not assume arbitrary topology multicast targets are single actors.
fixture() ->
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cells => #{module => hls_actor_pid_fixture, shape => [2, 2]}},
        ingresses => [{commands, {rectangle, [2, 2]}, [
            {work, [work], [{family, cells, {embed, [1, 1], [0, 0]}}]}]}],
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{cells, out}, [{external, reports}]}], startup => []}),
    Specs = maps:from_list([{Name, #{members => [{family, cells, {interleaved, I, 2}}],
        state_storage => block_ram, mailbox_storage => block_ram}}
        || {Name, I} <- [{even, 0}, {odd, 1}]]),
    {Plan, Specs, #{even => 7, odd => 8}}.

-doc "Writes generated DSLX and the matching oracle or wrapper files into the test stage.".
-spec write(atom() | binary() | [atom() | [any()] | char()]) -> 'ok'.
write(Stage) ->
    {Plan, Specs, Endpoints} = fixture(),
    Options = #{mailbox_debug => true},
    Actor = xls_scheduler_actor:to_artifact("test/hls_actor_pid_fixture.erl", Options),
    Artifacts = #{hls_actor_pid_fixture => Actor},
    Scheduler = hls_scheduler_plan:normalize(Plan, Specs),
    Bindings = xls_scheduler_ram_v:bindings(Scheduler),
    Profile = Options#{name => actor_pid_topology, channel_depth => 1,
        actor_egress_depth => burst, scheduler_groups => Specs},
    ok = xls_emitted:write(Actor, filename:join(Stage, "hls_actor_pid_fixture.x")),
    Files = [{"actor_pid_topology.x", xls_fabric_topology_dslx:emit(Plan, Profile)},
        {"actor_pid_addresses.x", addresses(Scheduler, Endpoints)},
        {"actor_pid.x", gateway(Scheduler, addressed)},
        {"actor_pid_baseline.x", gateway(Scheduler, baseline)},
        {"actor_pid_wrapper.v", wrapper(Scheduler, Bindings, addressed)},
        {"actor_pid_baseline_wrapper.v", wrapper(Scheduler, Bindings, baseline)},
        {"actors.json", json:encode(xls_scheduler_debug:projection(Plan, Specs, Artifacts, Options))}],
    lists:foreach(fun({Name, Data}) ->
        ok = file:write_file(filename:join(Stage, Name), Data)
    end, Files),
    {ok, _} = file:copy("test/xls/actor_pid_ingress.x", filename:join(Stage, "actor_pid_ingress.x")),
    ok.

addresses(Scheduler, Endpoints) ->
    Placements = hls_scheduler_plan:placements(Scheduler),
    ["// Generated from the same normalized scheduler placement as host descriptors.\n",
        "pub const WORK = u8:", integer_to_list(hls_actor_pid_fixture:pack_tag(work)), ";\n\n",
        "pub fn destination(endpoint: u16, slot: u32) -> (bool, u16, u16) {\n",
        "  match (endpoint, slot) {\n",
        [io_lib:format("    (u16:~B, u32:~B) => (true, u16:~B, u16:~B),\n", [maps:get(Group, Endpoints), Slot, X, Y])
            || {{family, cells, [X, Y]}, #{id := Group, slot := Slot}} <- lists:sort(maps:to_list(Placements))],
        "    _ => (false, u16:0, u16:0),\n  }\n}\n"].

gateway(#{groups := Groups}, Kind) ->
    RamMembers = lists:append([xls_scheduler_ram_dslx:parameters(
        ["scheduler_", integer_to_list(I), "_"], "hls_actor_pid_fixture::")
        || {I, _} <- lists:enumerate(0, Groups)]),
    RamNames = lists:append([xls_scheduler_ram_dslx:names(["scheduler_", integer_to_list(I), "_"])
        || {I, _} <- lists:enumerate(0, Groups)]),
    Observation = #{mailbox_debug => true, schedulers => [#{stem => ["scheduler_", integer_to_list(I)],
        slot_count => Slots} || {I, #{slot_count := Slots}} <- lists:enumerate(0, Groups)]},
    Members = RamMembers ++ xls_scheduler_observation:arguments(Observation),
    Names = RamNames ++ xls_scheduler_observation:names(Observation),
    {InputName, InputType, Adapter, InputPort} = case Kind of
        addressed -> {"routed_in", "axis::Beat", [
            "    let (commands_p, commands_c) = chan<hls_spatial_router::SpatialFrame, u32:1>(\"commands\");\n",
            "    spawn actor_pid_ingress::AddressedIngress(routed_in, commands_p);\n"], "commands_c"};
        baseline -> {"commands_in", "hls_spatial_router::SpatialFrame", [], "commands_in"}
    end,
    Input = [InputName, ": chan<", InputType, "> in"],
    ["// Generated private actor-PID fixture: one addressed cast ingress.\n",
        "import axis;\nimport hls_spatial_router;\nimport hls_actor_pid_fixture;\nimport actor_pid_topology;\n",
        case Kind of addressed -> "import actor_pid_ingress;\n"; baseline -> [] end, "\n",
        "pub proc Top {\n",
        [["  ", Member, ";\n"] || Member <- Members],
        "  ", Input, ";\n  reports_out: chan<axis::Frame> out;\n",
        "  config(\n", [["      ", Member, ",\n"] || Member <- Members],
        "      ", Input, ", reports_out: chan<axis::Frame> out) {\n", Adapter,
        "    spawn actor_pid_topology::Top(\n", [["      ", Name, ",\n"] || Name <- Names],
        "      ", InputPort, ", reports_out);\n",
        "    (", lists:join(", ", Names ++ [InputName, "reports_out"]), ")\n  }\n",
        "  init { () }\n  next(state: ()) { state }\n}\n"].

wrapper(Scheduler, Bindings, Kind) ->
    {Module, Input, Width} = case Kind of
        addressed -> {"actor_pid", "_routed_in", 33};
        baseline -> {"actor_pid_baseline", "_commands_in", 194}
    end,
    ["// Physical scheduler RAMs and the public application ports only.\n",
        "module ", Module, "_wrapper(input wire clk, reset,\n",
        "    input wire [", integer_to_list(Width-1), ":0] ", Input, ", input wire ", Input, "_vld, output wire ", Input, "_rdy,\n",
        "    output wire [127:0] _reports_out, output wire _reports_out_vld, input wire _reports_out_rdy);\n",
        xls_scheduler_ram_v:wires(Bindings), xls_scheduler_observation:wires(Scheduler),
        "    ", Module, " dut(.clk(clk), .reset(reset),\n",
        "        .", Input, "(", Input, "), .", Input, "_vld(", Input, "_vld), .", Input, "_rdy(", Input, "_rdy),\n",
        "        ._reports_out(_reports_out), ._reports_out_vld(_reports_out_vld), ._reports_out_rdy(_reports_out_rdy)",
        xls_scheduler_ram_v:application_ports(Bindings), xls_scheduler_observation:ports(Scheduler),
        "\n    );\n", xls_scheduler_ram_v:instances(Bindings, "clk"), "endmodule\n"].
