-module(hls_statem_reply_dslx).
-moduledoc "Builds singleton and two-actor retained-call regression designs.".
-export([write/1]).

-doc "Writes both designs and a wrapper using the dedicated actor interfaces.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Events = xls_parse:to_xls("test/hls_statem_event_fixture.erl"),
    {ok, EventTests} = file:read_file("test_data/xls_statem_event_semantics.inc.x"),
    ok = save(Stage, "statem_events.x", [Events, EventTests]),
    Reduction = xls_parse:to_xls("test/hls_statem_reduction_reply_fixture.erl"),
    {ok, ReductionTests} = file:read_file("test_data/xls_statem_reduction_reply_semantics.inc.x"),
    ok = save(Stage, "statem_reduction_replies.x", [Reduction, ReductionTests]),
    Actor = xls_parse:to_xls("test/hls_statem_reply_fixture.erl"),
    ok = save(Stage, "hls_statem_reply_fixture.x", Actor),
    {ok, ReplyTests} = file:read_file("test_data/xls_statem_reply_semantics.inc.x"),
    ok = save(Stage, "statem_direct.x", [Actor, ReplyTests]),
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cells => #{module => hls_statem_reply_fixture, shape => [2, 1]}},
        ingresses => [{commands, {rectangle, [2, 1]}, [{all,
            [wait, read, release, duplicate, explode], [{family, cells, {embed, [1, 1], [0, 0]}}]}]}],
        externals => [{replies, out, [report]}], routes => [],
        route_relations => [{{cells, reply}, [{external, replies}]}], startup => []}),
    Profile = #{name => statem_topology, channel_depth => 1, actor_egress_depth => 0},
    ok = save(Stage, "statem_topology.x", xls_topology_dslx:emit(Plan, Profile)),
    Wrapper = ["module statem_topology_wrapper(input wire clk, reset,\n",
        " input wire [193:0] request, input wire request_valid, output wire request_ready,\n",
        " output wire [127:0] reply, output wire reply_valid, input wire reply_ready);\n",
        "__statem_topology__Top_0_next dut(.clk(clk), .reset(reset),\n",
        " ._commands_in(request), ._commands_in_vld(request_valid), ._commands_in_rdy(request_ready),\n",
        " ._replies_out(reply), ._replies_out_vld(reply_valid), ._replies_out_rdy(reply_ready)",
        ");\n",
        "endmodule\n"],
    save(Stage, "statem_topology_wrapper.v", Wrapper).

%% Keep generated probes separate from reviewed source fixtures.
-spec save(file:filename(), file:filename(), iodata()) -> ok.
save(Stage, Name, Content) -> file:write_file(filename:join(Stage, Name), Content).
