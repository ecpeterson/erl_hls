-module(hls_admission_collection_dslx).
-moduledoc "Builds a two-actor collector regression with production RAMs and live progress outputs.".
-export([write/1, write/2]).

-doc "Writes the ordinary topology, its opted-in actors and a RAM/debug wiring wrapper.".
-spec write(file:filename()) -> ok.
write(Stage) -> write(Stage, true).

-doc "Selects opportunistic or exclusive epoch collection for the same physical fixture.".
-spec write(file:filename(), true | exclusive_epoch) -> ok.
write(Stage, Policy) ->
    Module = hls_projection_reduction_fixture,
    Plan = hls_topology:normalize(#{version => 1, actors => #{a => Module, b => Module}, families => #{},
        ingresses => [{commands, {rectangle, [2, 1]}, [{all, [begin_set, piece], [
            {actor, a, {at, [0, 0]}}, {actor, b, {at, [1, 0]}}]}]}],
        externals => [{result_a, out, [result]}, {result_b, out, [result]}], route_relations => [],
        routes => [{{a, out}, [{external, result_a}]}, {{b, out}, [{external, result_b}]},
            {{a, marker}, [{external, result_a}]}, {{b, marker}, [{external, result_b}]}], startup => []}),
    Groups = #{cells => #{members => [{actor, a}, {actor, b}], state_storage => block_ram,
        mailbox_storage => block_ram, admission_reductions => Policy}},
    Profile = #{name => collection_top, channel_depth => 1, actor_egress_depth => burst, scheduler_groups => Groups},
    Requirements = xls_shared_topology_dslx:artifact_requirements(Plan, Profile),
    Actor = xls_shared_parse:to_xls("test/hls_projection_reduction_fixture.erl", maps:get(Module, Requirements)),
    ok = save(Stage, "hls_projection_reduction_fixture.x", Actor),
    ok = save(Stage, "collection_top.x", xls_shared_topology_dslx:emit(Plan, Profile)),
    Bindings = xls_scheduler_ram_v:bindings(hls_scheduler_plan:normalize(Plan, Groups)),
    Wrapper = ["module collection_wrapper(input wire clk, reset,\n",
        " input wire [193:0] request, input wire request_valid, output wire request_ready,\n",
        " output wire [127:0] result_a, result_b, output wire valid_a, valid_b, input wire ready,\n",
        " output wire [183:0] observation, output wire observation_valid);\n",
        xls_scheduler_ram_v:wires(Bindings),
        "assign observation=scheduler_0_collection_debug; assign observation_valid=scheduler_0_collection_debug_vld;\n",
        "__collection_top__Top_0_next core(.clk(clk), .reset(reset),\n",
        " ._commands_in(request), ._commands_in_vld(request_valid), ._commands_in_rdy(request_ready),\n",
        " ._result_a_out(result_a), ._result_a_out_vld(valid_a), ._result_a_out_rdy(ready),\n",
        " ._result_b_out(result_b), ._result_b_out_vld(valid_b), ._result_b_out_rdy(ready)",
        xls_scheduler_ram_v:application_ports(Bindings), ");\n",
        xls_scheduler_ram_v:instances(Bindings, "clk"), "endmodule\n"],
    save(Stage, "collection_wrapper.v", Wrapper).

%% Generated regression artifacts are disposable.
-spec save(file:filename(), file:filename(), iodata()) -> ok.
save(Stage, Name, Content) ->
    Path = filename:join(Stage, Name),
    ok = filelib:ensure_dir(Path), file:write_file(Path, Content).
