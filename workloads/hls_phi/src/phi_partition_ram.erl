-module(phi_partition_ram).
-moduledoc """
Phi partition build drivers use this Verilog wrapper after XLS core generation. It binds scheduler RAM and observation ports around the emitted device core, without implementing a board pinout.

Physical 1R1W RAM shell and passive observations for one private device.
""".
%% Partition RAM shell output.
-export([write/4]).

-doc "Writes the RAM shell, actor projection and normalized group count beside generated device source. Tiles require constant bindings from hls_partition_tile:constants/2.".
-spec write(file:filename(), non_neg_integer(), map(), #{module() => xls_emitted:artifact()}) ->
    non_neg_integer().
write(Stage, Device, Local = #{schedulers := Groups}, Artifacts) ->
    {Plan, Specs} = hls_partition_tile:planning(Local),
    Layout = maps:get(frame_layout, Local, hls_frame_layout:default()),
    Schedule = hls_scheduler_plan:normalize(Plan, Specs, Layout),
    Projection = hls_partition_tile:projection(
        Local,
        xls_scheduler_debug:projection(Plan, Specs, Artifacts, #{
            mailbox_debug => true,
            frame_payload_words => hls_frame_layout:payload_words(Layout)
        })
    ),
    Prefix = "phi_device_" ++ integer_to_list(Device),
    ok = file:write_file(filename:join(Stage, Prefix ++ "_actors.json"), json:encode(Projection)),
    ok = file:write_file(
        filename:join(Stage, Prefix ++ "_schedule.term"),
        io_lib:format("~w.~n", [{Plan, Specs}])
    ),
    ok = file:write_file(
        filename:join(Stage, Prefix ++ "_ram.v"), wrapper(Prefix, Schedule, Local)
    ),
    length(Groups).

%% RAM and observation port layout is owned by the public scheduler helpers.
-spec wrapper(string(), hls_scheduler_plan:plan(), map()) -> iolist().
wrapper(Name, Schedule, Local) ->
    Bindings = xls_scheduler_ram_v:bindings(
        Schedule, maps:get(frame_layout, Local, hls_frame_layout:default())
    ),
    Ports =
        hls_partition_links:ports(Local) ++
            [
                {"_app_in", 33, in}, {"_app_out", 33, out}
            ],
    [
        "module ",
        Name,
        "_ram(input wire clk, reset,\n",
        "    output wire [4:0] _scheduler_probe,\n",
        lists:join(",\n", [port(P) || P <- Ports]),
        ");\n",
        xls_scheduler_ram_v:wires(Bindings),
        xls_scheduler_observation:wires(Schedule),
        scheduler_probe(Bindings),
        "    ",
        case Local of
            #{tile := true} -> "phi_tile";
            _ -> Name
        end,
        " dut(.clk(clk), .reset(reset)",
        [
            [
                ",\n        ._",
                N,
                "(",
                integer_to_list(W),
                "'h",
                integer_to_list(V, 16),
                "), ._",
                N,
                "_vld(1'b1), ._",
                N,
                "_rdy()"
            ]
         || {N, W, V} <- constants(Local)
        ],
        [
            [",\n        .", P, "(", P, "), .", P, "_vld(", P, "_vld), .", P, "_rdy(", P, "_rdy)"]
         || {P, _, _} <- Ports
        ],
        xls_scheduler_ram_v:application_ports(Bindings),
        xls_scheduler_observation:ports(Schedule),
        "\n    );\n",
        xls_scheduler_ram_v:instances(Bindings, "clk"),
        "endmodule\n"
    ].

%% Summarize requests at the physical scheduler-memory boundary without changing readiness.
-spec scheduler_probe([map()]) -> iolist().
scheduler_probe(Bindings) ->
    Indices = [maps:get(index, Binding) || Binding <- Bindings],
    Signal = fun(Suffix) ->
        case [["scheduler_", integer_to_list(Index), Suffix] || Index <- Indices] of
            [] -> "1'b0";
            Terms -> lists:join(" | ", Terms)
        end
    end,
    [
        "    assign _scheduler_probe = {",
        Signal("_mailbox_debug_vld"),
        ", ",
        Signal("_mailbox_wr_en"),
        ", ",
        Signal("_mailbox_rd_en"),
        ", ",
        Signal("_state_wr_en"),
        ", ",
        Signal("_state_rd_en"),
        "};\n"
    ].

%% Public application/link ports retain their widths and ready/valid contract.
-spec port({string(), pos_integer(), in | out}) -> iolist().
port({Name, Width, Direction}) ->
    {Data, Ready} =
        case Direction of
            in -> {"input", "output"};
            out -> {"output", "input"}
        end,
    [
        "    ",
        Data,
        " wire [",
        integer_to_list(Width - 1),
        ":0] ",
        Name,
        ", ",
        Data,
        " wire ",
        Name,
        "_vld, ",
        Ready,
        " wire ",
        Name,
        "_rdy"
    ].

%% A tile must never elaborate with floating configuration inputs.
-spec constants(map()) -> [{string(), pos_integer(), non_neg_integer()}].
constants(#{tile := true, tile_constants := Constants}) -> Constants;
constants(#{tile := true}) -> error(missing_tile_configuration);
constants(_) -> [].
