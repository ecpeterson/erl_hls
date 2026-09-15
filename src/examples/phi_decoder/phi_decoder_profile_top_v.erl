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

-doc "Renders a decoder-only wrapper at a shard count or profile configuration.".
-spec to_verilog(pos_integer() | map()) -> binary().
to_verilog(ProfileOptions) ->
    to_verilog(ProfileOptions, #{}).

-doc "Renders optional always-ready mailbox observation aliases inside the shell.".
to_verilog(ProfileOptions, Options) ->
    Config = #{planes := Planes} = phi_decoder_profile:normalize(ProfileOptions),
    Plan = #{groups := Groups} = phi_decoder_profile_topology_dslx:scheduler_plan(Config),
    Bindings = xls_scheduler_ram_v:bindings(Plan),
    {DebugWires, DebugPorts} = case xls_scheduler_observation:enabled(Options) of
        false -> {[], []};
        true -> {xls_scheduler_observation:wires(Plan), xls_scheduler_observation:ports(Plan)}
    end,
    Replacements = [
        {<<"@EVENT_PORTS@">>, iolist_to_binary([event_ports(P) || P <- Planes])},
        {<<"@INACTIVE_PLANES@">>, iolist_to_binary([
            io_lib:format("    assign ~s_decoder_event = 128'd0;~n"
                "    assign ~s_decoder_event_valid = 1'b0;~n", [P, P])
            || P <- [x, z] -- Planes
        ])},
        {<<"@PROFILE_READS@">>, iolist_to_binary([
            read_count(Kind, Ram, [Index
                || {#{index := Index}, #{module := M}} <- lists:zip(Bindings, Groups),
                   M =:= Module])
            || {Kind, Module} <- [{source, phi_syndrome_replay_cell}, {phi, phi_halo_cell}],
               Ram <- [state, mailbox]
        ])},
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

event_ports(Plane) ->
    [io_lib:format(",\n        ._~s_decoder_events_out~s(~s_decoder_event~s)",
        [Plane, Suffix, Plane, Signal])
        || {Suffix, Signal} <- [{"", ""}, {"_vld", "_valid"}, {"_rdy", "_ready"}]].

%% Internal observation aliases disappear when unused during synthesis.
read_count(Kind, Ram, Indexes) ->
    Terms = [io_lib:format("{31'd0, scheduler_~B_~s_rd_en}", [Index, Ram])
        || Index <- Indexes],
    io_lib:format("    wire [31:0] profile_~s_~s_reads = ~s;~n",
        [Kind, Ram, lists:join(" + ", Terms)]).

template() ->
    Priv = code:priv_dir(erl_hls),
    Path = filename:join([
        Priv, "rtl", "phi_decoder_profile_top.template.v"
    ]),
    {ok, Template} = file:read_file(Path),
    Template.
