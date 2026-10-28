-module(sv_protocol_ports).
-moduledoc "Renders the named-pin SystemVerilog adapter for XLS sampled-clock interfaces. Protocol transport, network, boundary and bridge renderers use this mechanical shell; it contains no transport behavior or storage.".

%% Pure named-pin wrapper rendering.
-export([emit/2, emit/4]).

%% Exclusive wrapper output.
-export([write/3, write/5]).

-doc "Writes a fresh Verilog adapter that packs inputs and unpacks outputs in DSLX struct order. The supplied checked field names must be Verilog identifiers. Command-valid and observation-ready are tied high so one XLS tick equals one hardware clock; per-recipient stalls are fields inside that tick. Reset is both the XLS register reset and sampled output-qualification input.".
-spec write([{string(), pos_integer()}], [{string(), pos_integer()}], file:filename()) -> ok.
write(Inputs, Outputs, Path) ->
    write(Inputs, Outputs, Path, "protocol_fabric", "protocol_fabric_core").

-doc "Writes the same stateless sampled-pin adapter with explicit checked top/core identifiers. The core must implement the one-stage, always-enabled clock interface; all behavior remains DSLX.".
-spec write(
    [{string(), pos_integer()}], [{string(), pos_integer()}], file:filename(), string(), string()
) -> ok.
write(Inputs, Outputs, Path, Top, Core) ->
    file:write_file(Path, emit(Inputs, Outputs, Top, Core), [exclusive]).

-doc "Returns the default transport pin adapter as Verilog bytes without writing files.".
-spec emit([{string(), pos_integer()}], [{string(), pos_integer()}]) -> iodata().
emit(Inputs, Outputs) -> emit(Inputs, Outputs, "protocol_fabric", "protocol_fabric_core").

-doc "Returns stateless sampled-pin wiring with explicit top/core names. Validates Verilog identifiers; the core owns the one-stage always-enabled clock behavior.".
-spec emit([{string(), pos_integer()}], [{string(), pos_integer()}], string(), string()) ->
    iodata().
emit(Inputs, Outputs, Top, Core) ->
    lists:foreach(
        fun({Name, _}) -> match = re:run(Name, "^[a-zA-Z_][a-zA-Z0-9_]*$", [{capture, none}]) end, [
            {Top, 1}, {Core, 1} | Inputs ++ Outputs
        ]
    ),
    Source = [
        "// Pin packing only; all behavior is compiled from DSLX.\nmodule ",
        Top,
        "(input wire clk,\n",
        lists:join(",\n", [port("input", F) || F <- Inputs] ++ [port("output", F) || F <- Outputs]),
        "\n);\n",
        "wire [",
        integer_to_list(lists:sum([W || {_, W} <- Outputs]) - 1),
        ":0] observations;\n",
        "assign {",
        lists:join(",", [N || {N, _} <- Outputs]),
        "}=observations;\n",
        Core,
        " core(.clk(clk),.reset(reset),._commands({",
        lists:join(",", [N || {N, _} <- Inputs]),
        "}),\n",
        "._commands_vld(1'b1),._commands_rdy(),._observations(observations),._observations_vld(),._observations_rdy(1'b1));\nendmodule\n"
    ],
    Source.

%% A one-bit field is scalar; larger fields retain their exact elaborated width.
-spec port(string(), {string(), pos_integer()}) -> iolist().
port(Direction, {Name, 1}) -> [Direction, " wire ", Name];
port(Direction, {Name, W}) -> [Direction, " wire [", integer_to_list(W - 1), ":0] ", Name].
