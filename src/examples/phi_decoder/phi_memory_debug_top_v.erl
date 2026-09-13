%%%% phi_memory_debug_top_v
%%%%
%%%% Verilog boundary wrapper for one generated phi-memory scheduler plan.

-module(phi_memory_debug_top_v).
-moduledoc """
Renders the Verilog wrapper which connects every shared scheduler RAM port to
one simple 1R1W memory, attaches the independently compiled host serializer,
and attaches the passive debug monitor.

The monitor-only and application-only shells share one application template.
The latter exposes optional always-ready mailbox samples for post-codegen
composition with physical queries and the boundary monitor.
""".

-export([to_verilog/0, to_verilog/1, application/2]).

-doc "Renders the checked wrapper for the default scheduler profile.".
-spec to_verilog() -> binary().
to_verilog() ->
    to_verilog(2).

-doc "Renders a wrapper for one phi scheduler profile.".
-spec to_verilog(1 | 2 | {phi_shards, pos_integer()}) -> binary().
to_verilog(Profile) ->
    render("phi_memory_debug_top.template.v", Profile, #{}).

-doc "Renders only the application, ready for topology_debug.py to attach all debug services.".
-spec application(1 | 2 | {phi_shards, pos_integer()}, map()) -> binary().
application(Profile, Options) ->
    render("phi_memory_top.template.v", Profile, Options).

render(Shell, Profile, Options) ->
    Plan = phi_noise_topology_dslx:scheduler_plan(Profile),
    Bindings = xls_scheduler_ram_v:bindings(Plan),
    {DebugWires, DebugPorts} = case xls_scheduler_observation:enabled(Options) of
        true -> {xls_scheduler_observation:wires(Plan), xls_scheduler_observation:ports(Plan)};
        false -> {[], []}
    end,
    Template = template("phi_memory_application.template.v"),
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
    Application = lists:foldl(
        fun({Pattern, Replacement}, Source) ->
            binary:replace(Source, Pattern, Replacement, [global])
        end,
        Template,
        Replacements
    ),
    binary:replace(template(Shell), <<"@APPLICATION@">>, Application).

template(Name) ->
    Priv = code:priv_dir(erl_hls),
    Path = filename:join([Priv, "rtl", Name]),
    {ok, Template} = file:read_file(Path),
    Template.
