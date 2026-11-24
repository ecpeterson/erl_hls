-module(hls_domain_board_control).
-moduledoc "Builds board-local host framing around an already emitted independent domain network. The DSLX unit routes full control frames, establishes parser sessions and snapshots sparse native inspection. The RTL wrapper only connects emitted pins; PS/DMA/carrier implementation belongs to the platform shell. No actor recovery policy or link replay is introduced.".

%% Pure source generation from retained domain/network metadata.
-export([emit/2]).
-export_type([config/0, result/0]).

%% Ordered fields are the sampled DSLX and RTL pin contract.
-type ports() :: [{string(), pos_integer()}].
-doc "Role is the physical peer identity; phase is the native domain enum. Process inspection is discovered from the exact network pins, never assumed from actor count.".
-type config() :: #{role := 1 | 2, phase := hls_type:descriptor()}.
-doc "One control build unit plus its mechanical network wrapper. Dependencies are the supplied network's existing source units. State budget excludes those dependencies and the board DMA/carrier storage.".
-type result() :: #{
    top_module := string(),
    inputs := ports(),
    outputs := ports(),
    role := 1 | 2,
    inspection := none | process,
    state_bits := 723,
    state_bit_budget := 768,
    control := #{top_module := string(), inputs := ports(), outputs := ports()},
    unit := hls_artifact_bundle:unit(),
    wire_version := 1,
    bootstrap := quiescent_packet_boundary
}.

-doc "Emits files without running tools. Bank 0 is the full application frame lane; bank 1 forwards domain route 0 and endpoint route 2, while routes 3/4 provide inspection/session status. ESTABLISH requires drained/ACKed DMA banks, completed old packets and no pending/new native responses during establishment; empty mailboxes alone are insufficient. This in-band lane cannot cancel partial DMA or promise transparent reconnect. Session changes never reset actors, endpoint ownership or the carrier.".
-spec emit(hls_domain_endpoint_network:result(), config()) -> hls_generated_files:output(result()).
emit(Network = #{inputs := NetworkInputs, outputs := NetworkOutputs}, #{
    role := Role, phase := Phase
}) ->
    require(Role =:= 1 orelse Role =:= 2, role),
    require(hls_type:width(Phase) =:= 3, phase_width),
    <<Ready:3>> = hls_type:pack(ready, Phase),
    Inspection = inspection(Network),
    {Inputs, Outputs} = control_ports(),
    {ok, Template} = file:read_file(
        filename:join(
            code:priv_dir(hls_target),
            "xls/templates/domain_board_control.x.in"
        )
    ),
    Text = xls_template:render(Template, [
        {<<"@@ROLE@@">>, integer_to_list(Role)},
        {<<"@@READY@@">>, integer_to_list(Ready)},
        {<<"@@INSPECTION@@">>, atom_to_list(Inspection =:= process)},
        {<<"@@INPUTS@@">>, structure("Inputs", Inputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", Outputs)}
    ]),
    {PublicInputs, PublicOutputs} = board_ports(),
    Connections = network_connections(Network, Inspection),
    lists:foreach(
        fun({{Name, Width}, _}) ->
            require(
                lists:member({Name, Width}, NetworkInputs ++ NetworkOutputs), {network_pin, Name}
            )
        end,
        Connections
    ),
    require(
        lists:sort([P || {P, _} <- Connections]) =:= lists:sort(NetworkInputs ++ NetworkOutputs),
        complete_network_interface
    ),
    Signals = lists:usort(Inputs ++ Outputs),
    Public = PublicInputs ++ PublicOutputs,
    Wrapper = [
        "// Mechanical host/control/network composition; all synchronous control is DSLX.\n",
        "module domain_board(input wire clk,\n",
        lists:join(
            ",\n",
            [port("input", P) || P <- PublicInputs] ++
                [port("output", P) || P <- PublicOutputs]
        ),
        "\n);\n",
        [wire(P) || P <- Signals, not lists:member(P, Public)],
        case Inspection of
            none -> "assign inspect_value = 128'd0;\n";
            process -> []
        end,
        "domain_board_control host_control(.clk(clk),\n",
        lists:join(",\n", [connect(Name, Name) || {Name, _} <- Inputs ++ Outputs]),
        "\n);\n",
        maps:get(top_module, Network),
        " network(.clk(clk),\n",
        lists:join(",\n", [connect(Name, Signal) || {{Name, _}, Signal} <- Connections]),
        "\n);\nendmodule\n"
    ],
    #{imports := Support} = hls_build_support:layout([]),
    Profile = hls_build_profile:owner(hls_frame_layout:new(11)),
    Metadata = #{
        kind => <<"domain_board_control">>,
        role => Role,
        domain_index => maps:get(domain_index, Network),
        wire_version => 1,
        ready_phase => Ready,
        inspection => atom_to_binary(Inspection),
        state_bits => 723,
        state_bit_budget => 768,
        top_module => <<"domain_board">>,
        bootstrap => <<"quiescent_packet_boundary_no_pending_or_arriving_native_responses">>
    },
    #{
        files => #{
            "board_control/domain_board_control.x" => Text,
            "board_control/interface.json" => [json:encode(Metadata), "\n"],
            "board_control/control.sv" => sv_protocol_ports:emit(
                Inputs,
                Outputs,
                "domain_board_control",
                "domain_board_control_core"
            ),
            "board_control/domain_board.sv" => Wrapper
        },
        result => #{
            top_module => "domain_board",
            inputs => PublicInputs,
            outputs => PublicOutputs,
            role => Role,
            inspection => Inspection,
            state_bits => 723,
            state_bit_budget => 768,
            control => #{
                top_module => "domain_board_control", inputs => Inputs, outputs => Outputs
            },
            wire_version => 1,
            bootstrap => quiescent_packet_boundary,
            unit => #{
                role => <<".">>,
                directory => <<"board_control">>,
                source => <<"board_control/domain_board_control.x">>,
                top => <<"board_control_clock">>,
                module => <<"domain_board_control_core">>,
                output => <<"board_control/core.v">>,
                dslx_path => [unicode:characters_to_binary(P) || P <- ["board_control" | Support]],
                rtl => [
                    <<"board_control/core.v">>,
                    <<"board_control/control.sv">>,
                    <<"board_control/domain_board.sv">>
                ],
                codegen_flags => hls_build_profile:flags(Profile, sampled_clock)
            }
        }
    }.

%% Only a complete passive inspection triplet enables route 3.
-spec inspection(hls_domain_endpoint_network:result()) -> none | process.
inspection(#{domain_index := Index, inputs := Inputs, outputs := Outputs}) ->
    Prefix = prefix(Index),
    Present =
        [
            lists:member(P, Inputs)
         || P <- [
                {Prefix ++ "inspect_address", 32},
                {Prefix ++ "inspect_incarnation", 64}
            ]
        ] ++
            [lists:member({Prefix ++ "app_inspect_value", 128}, Outputs)],
    case Present of
        [false, false, false] -> none;
        [true, true, true] -> process;
        _ -> erlang:error({domain_board_control, incomplete_inspection})
    end.

%% Exact widths prevent private metadata from being silently dropped at the board boundary.
-spec network_connections(hls_domain_endpoint_network:result(), none | process) ->
    [{{string(), pos_integer()}, string()}].
network_connections(#{domain_index := Index, outputs := Outputs}, Inspection) ->
    P = prefix(Index),
    DomainInputs =
        [
            {"transport_reset", 1, "transport_reset"},
            {"transport_session", 64, "transport_session"},
            {"domain_reset", 1, "1'b0"}
        ] ++
            lane("management", "domain", input) ++ lane("application", "application", input),
    DomainOutputs =
        lane("management", "domain", output) ++ lane("application", "application", output) ++
            [
                {"wire_fault", 1, "domain_wire_fault"},
                {"transport_session_observed", 64, "domain_session"},
                {"transport_attached", 1, "domain_attached"},
                {"domain_phase", 3, "domain_phase"},
                {"domain_current", 64, "domain_current"}
            ],
    Diagnostics = [
        {Pin, ""}
     || Pin = {Name, _} <- Outputs,
        re:run(Name, "^" ++ P ++ "app_remote_[0-9]+_(fault|free)$", [{capture, none}]) =:= match
    ],
    InspectionPins =
        case Inspection of
            none ->
                [];
            process ->
                [
                    {{P ++ "inspect_address", 32}, "inspect_address"},
                    {{P ++ "inspect_incarnation", 64}, "inspect_incarnation"},
                    {{P ++ "app_inspect_value", 128}, "inspect_value"}
                ]
        end,
    [
        {{"reset", 1}, "reset"},
        {{"carrier_fault", 1}, "(|carrier_fault)"},
        {{"endpoint_transport_reset", 1}, "transport_reset"},
        {{"endpoint_transport_session", 64}, "transport_session"},
        {{"endpoint_transport_session_observed", 64}, "endpoint_session"},
        {{"endpoint_transport_attached", 1}, "endpoint_attached"},
        {{"endpoint_wire_fault", 1}, "endpoint_wire_fault"}
    ] ++
        [{{P ++ Name, Width}, Signal} || {Name, Width, Signal} <- DomainInputs ++ DomainOutputs] ++
        [
            {{"endpoint_" ++ Name, Width}, Signal}
         || {Name, Width, Signal} <-
                lane("management", "endpoint", input) ++
                    lane("management", "endpoint", output)
        ] ++
        [
            {Pin, Name}
         || Pin = {Name, _} <- carrier_inputs() ++ carrier_outputs(),
            Name =/= "carrier_fault",
            Name =/= "carrier_armed"
        ] ++
        [{{"router_fault", 1}, "router_fault"}] ++ Diagnostics ++ InspectionPins.

%% A full frame includes route and header; the control switch never strips them.
-spec lane(string(), string(), input | output) -> [{string(), pos_integer(), string()}].
lane(Name, Signal, input) ->
    [
        {Name ++ Suffix, Width, Signal ++ Suffix}
     || {Suffix, Width} <-
            [{"_word", 32}, {"_valid", 1}, {"_last", 1}, {"_output_ready", 1}]
    ];
lane(Name, Signal, output) ->
    [
        {Name ++ Suffix, Width, Signal ++ Suffix}
     || {Suffix, Width} <-
            [{"_ready", 1}, {"_output_word", 32}, {"_output_valid", 1}, {"_output_last", 1}]
    ].

%% Both management recipients remain live when the carrier/router faults.
-spec control_ports() -> {ports(), ports()}.
control_ports() ->
    {
        [
            {"reset", 1},
            {"host_word", 32},
            {"host_valid", 1},
            {"host_last", 1},
            {"host_output_ready", 1},
            {"domain_ready", 1},
            {"domain_output_word", 32},
            {"domain_output_valid", 1},
            {"domain_output_last", 1},
            {"endpoint_ready", 1},
            {"endpoint_output_word", 32},
            {"endpoint_output_valid", 1},
            {"endpoint_output_last", 1},
            {"domain_session", 64},
            {"endpoint_session", 64},
            {"domain_current", 64},
            {"domain_phase", 3},
            {"domain_attached", 1},
            {"endpoint_attached", 1},
            {"domain_wire_fault", 1},
            {"endpoint_wire_fault", 1},
            {"router_fault", 1},
            {"carrier_fault", 8},
            {"carrier_armed", 1},
            {"inspect_value", 128}
        ],
        [
            {"host_ready", 1},
            {"host_output_word", 32},
            {"host_output_valid", 1},
            {"host_output_last", 1},
            {"domain_word", 32},
            {"domain_valid", 1},
            {"domain_last", 1},
            {"domain_output_ready", 1},
            {"endpoint_word", 32},
            {"endpoint_valid", 1},
            {"endpoint_last", 1},
            {"endpoint_output_ready", 1},
            {"transport_reset", 1},
            {"transport_session", 64},
            {"inspect_address", 32},
            {"inspect_incarnation", 64}
        ]
    }.

%% The platform shell sees exactly two host lanes and one atomic physical carrier.
-spec board_ports() -> {ports(), ports()}.
board_ports() ->
    {
        [{"reset", 1}] ++
            [
                {Signal, Width}
             || {_, Width, Signal} <-
                    lane("host", "host", input) ++
                        lane("application", "application", input)
            ] ++ carrier_inputs(),
        [
            {Signal, Width}
         || {_, Width, Signal} <-
                lane("host", "host", output) ++
                    lane("application", "application", output)
        ] ++ carrier_outputs()
    }.

%% Packet input is one complete 1024-bit DATA/ACK packet with exact valid word count.
-spec carrier_inputs() -> ports().
carrier_inputs() ->
    [
        {"carrier_fault", 8},
        {"carrier_armed", 1},
        {"packet_tx_ready", 1},
        {"packet_rx", 1024},
        {"packet_rx_words", 6},
        {"packet_rx_valid", 1}
    ].

%% No packet/route state is introduced by the mechanical wrapper.
-spec carrier_outputs() -> ports().
carrier_outputs() ->
    [
        {"packet_tx", 1024},
        {"packet_tx_words", 6},
        {"packet_tx_valid", 1},
        {"packet_rx_ready", 1}
    ].

%% Domain prefixes come from checked emitted metadata, not the physical role number.
-spec prefix(non_neg_integer()) -> string().
prefix(Index) -> "domain_" ++ integer_to_list(Index) ++ "_".

%% Struct order and widths are shared with the sampled-port RTL adapter.
-spec structure(string(), ports()) -> iodata().
structure(Name, Fields) ->
    [
        "// Named sampled pins; field order matches the mechanical adapter.\n",
        "pub struct ",
        Name,
        " {\n",
        [
            [
                N,
                ": ",
                case W of
                    1 -> "bool";
                    _ -> ["bits[", integer_to_list(W), "]"]
                end,
                ",\n"
            ]
         || {N, W} <- Fields
        ],
        "}\n"
    ].

%% Empty connections deliberately leave source diagnostics available only to their native owner.
-spec connect(string(), string()) -> iodata().
connect(Name, Signal) -> [".", Name, "(", Signal, ")"].

%% Scalars use ordinary Verilog scalar syntax.
-spec port(string(), {string(), pos_integer()}) -> iodata().
port(Direction, {Name, Width}) -> [Direction, " wire ", range(Width), Name].

%% Internal wires are exactly those consumed by control and native network ports.
-spec wire({string(), pos_integer()}) -> iodata().
wire({Name, Width}) -> ["wire ", range(Width), Name, ";\n"].

%% Preserve all generated widths without narrowing.
-spec range(pos_integer()) -> iodata().
range(1) -> "";
range(Width) -> ["[", integer_to_list(Width - 1), ":0] "].

%% Reject incomplete source interfaces before any tool invocation.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> erlang:error({domain_board_control, Reason}).
