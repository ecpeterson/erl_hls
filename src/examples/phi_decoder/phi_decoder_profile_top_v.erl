%%%% phi_decoder_profile_top_v
%%%%
%%%% Verilog wrapper for the decoder-only profiling topology.

-module(phi_decoder_profile_top_v).
-moduledoc """
Renders the decoder-only Verilog shell and its scheduler-owned RAMs.

The shell deliberately exposes only the two phi event streams.  Scheduler RAM
plumbing is derived from the same normalized physical profile that emits the
DSLX topology, keeping profiling fixtures independent of scheduler widths.
""".

-export([to_verilog/0, to_verilog/1, to_verilog/2]).

-doc "Renders the checked three-shard decoder-only wrapper.".
-spec to_verilog() -> binary().
to_verilog() ->
    to_verilog(3).

-doc "Renders a decoder-only wrapper for the selected shards per phi plane.".
-spec to_verilog(pos_integer()) -> binary().
to_verilog(ShardCount) ->
    to_verilog(ShardCount, #{}).

-doc "Renders optional always-ready mailbox observation aliases inside the shell.".
to_verilog(ShardCount, Options) ->
    Plan = phi_decoder_profile_topology_dslx:scheduler_plan(ShardCount),
    Bindings = xls_scheduler_ram_v:bindings(Plan),
    {DebugWires, DebugPorts} = case xls_scheduler_observation:enabled(Options) of
        false -> {[], []};
        true -> {xls_scheduler_observation:wires(Plan), xls_scheduler_observation:ports(Plan)}
    end,
    Replacements = [
        {<<"@SCHEDULER_WIRES@">>, iolist_to_binary(
            [xls_scheduler_ram_v:wires(Bindings), DebugWires]
        )},
        {<<"@APPLICATION_RAM_PORTS@">>, iolist_to_binary(
            [xls_scheduler_ram_v:application_ports(Bindings), DebugPorts]
        )},
        {<<"@SCHEDULER_RAMS@">>, iolist_to_binary(
            xls_scheduler_ram_v:instances(Bindings, "aclk")
        )}
    ],
    lists:foldl(
        fun({Pattern, Replacement}, Source) ->
            binary:replace(Source, Pattern, Replacement, [global])
        end,
        template(),
        Replacements
    ).

template() ->
    Priv = code:priv_dir(erl_hls),
    Path = filename:join([
        Priv, "rtl", "phi_decoder_profile_top.template.v"
    ]),
    {ok, Template} = file:read_file(Path),
    Template.
