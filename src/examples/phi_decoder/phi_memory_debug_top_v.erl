%%%% phi_memory_debug_top_v
%%%%
%%%% Verilog boundary wrapper for one generated phi-memory scheduler plan.

-module(phi_memory_debug_top_v).
-moduledoc """
Renders the Verilog wrapper which connects every shared scheduler RAM port to
one simple 1R1W memory, attaches the independently compiled host serializer,
and attaches the passive debug monitor.

The fixed shell lives in `priv/rtl/phi_memory_debug_top.template.v`; only the
scheduler-dependent wires, gateway ports, and RAM instances are generated.
""".

-export([to_verilog/0, to_verilog/1]).

-doc "Renders the checked wrapper for the default scheduler profile.".
-spec to_verilog() -> binary().
to_verilog() ->
    to_verilog(2).

-doc "Renders a wrapper for one phi scheduler profile.".
-spec to_verilog(1 | 2 | {phi_shards, pos_integer()}) -> binary().
to_verilog(Profile) ->
    Plan = phi_noise_topology_dslx:scheduler_plan(Profile),
    Bindings = xls_scheduler_ram_v:bindings(Plan),
    Template = template(),
    Replacements = [
        {<<"@SCHEDULER_WIRES@">>, iolist_to_binary(
            xls_scheduler_ram_v:wires(Bindings)
        )},
        {<<"@APPLICATION_RAM_PORTS@">>, iolist_to_binary(
            xls_scheduler_ram_v:application_ports(Bindings)
        )},
        {<<"@SCHEDULER_RAMS@">>, iolist_to_binary(
            xls_scheduler_ram_v:instances(Bindings, "aclk")
        )}
    ],
    lists:foldl(
        fun({Pattern, Replacement}, Source) ->
            binary:replace(Source, Pattern, Replacement, [global])
        end,
        Template,
        Replacements
    ).

template() ->
    Priv = code:priv_dir(erl_hls),
    Path = filename:join([Priv, "rtl", "phi_memory_debug_top.template.v"]),
    {ok, Template} = file:read_file(Path),
    Template.
