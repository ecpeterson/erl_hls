-module(hls_supervisor_stream).
-moduledoc "Adds an independent framed parent-management lane to the raw supervised-child stream composition. Lifecycle and restart policy remain compiled Erlang; this emitter supplies bounded packet handling and stateless top-level connectivity.".

%% Portable parent stream and final pin adapter.
-export([emit/1]).

%% Port names are compiler-controlled HDL identifiers with finite widths.
-type ports() :: [{string(), pos_integer()}].

-doc "Emits a two-buffer parent parser, wrapper, retained runtime interface and external-tool build unit. The raw composition must be protocol_supervisor_stream_raw; child stream pins pass through unchanged. Transport replacement clears only this parser, never supervisor or child state.".
-spec emit(hls_protocol_supervisor:result()) -> map().
emit(#{
    codecs := Codecs,
    inputs := RawInputs,
    outputs := RawOutputs,
    frame_payload_words := Words,
    children := Children
}) ->
    {ExternalInputs, ExternalOutputs} = external_ports(),
    {Commands, Observations} = core_ports(Codecs),
    ParserInputs = ExternalInputs ++ [{"observed_" ++ N, W} || {N, W} <- Observations],
    ParserOutputs = ExternalOutputs ++ [{"command_" ++ N, W} || {N, W} <- Commands],
    Inputs =
        [P || P = {N, _} <- RawInputs, not lists:keymember(N, 1, Commands), N =/= "reset"] ++
            ExternalInputs,
    Outputs = RawOutputs ++ ExternalOutputs,
    {ok, Template} = file:read_file(
        filename:join(
            code:priv_dir(hls_target),
            "xls/templates/supervisor_management.x.in"
        )
    ),
    Text = xls_template:render(Template, [
        {<<"@@OPERATION_BITS@@">>, integer_to_binary(hls_type:width(maps:get(operation, Codecs)))},
        {<<"@@FAULT_BITS@@">>, integer_to_binary(hls_type:width(maps:get(fault, Codecs)))},
        {<<"@@STATUS_BITS@@">>, integer_to_binary(hls_type:width(maps:get(status, Codecs)))},
        {<<"@@ACTION_BITS@@">>, integer_to_binary(hls_type:width(maps:get(action, Codecs)))},
        {<<"@@SLOT_STATUS_BITS@@">>,
            integer_to_binary(hls_type:width(maps:get(supervisor_status, Codecs)))},
        {<<"@@CHILD_PHASE_BITS@@">>,
            integer_to_binary(hls_type:width(maps:get(child_phase, Codecs)))},
        {<<"@@INPUTS@@">>, structure("Inputs", ParserInputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", ParserOutputs)}
    ]),
    #{imports := Support} = hls_build_support:layout([]),
    Profile = hls_build_profile:owner(hls_frame_layout:new(Words)),
    #{
        files => #{
            "supervisor_management/supervisor_management.x" => Text,
            "supervisor_management/management.sv" => sv_protocol_ports:emit(
                ParserInputs,
                ParserOutputs,
                "supervisor_management",
                "supervisor_management_core"
            ),
            "supervisor/protocol_supervisor_stream.sv" => wrapper(
                Inputs,
                Outputs,
                RawInputs,
                RawOutputs,
                ParserInputs,
                ParserOutputs,
                Commands,
                Observations
            )
        },
        inputs => Inputs,
        outputs => Outputs,
        interface => #{
            kind => supervisor_management,
            management_route => {0, 0},
            codecs => Codecs,
            slots => maps:from_list([{Id, Index} || #{id := Id, index := Index} <- Children])
        },
        %% Packet/receive metadata, fixed command/result fields and session state; no child payload storage.
        state_bit_budget => 2 * (64 + 1024) + (2 + 32 + 2) + 1 + 32 + 3 +
            3 * 32 + 2 + 1 + 32 + 64 + 64 + 2 +
            lists:sum([
                hls_type:width(maps:get(K, Codecs))
             || K <- [status, action, supervisor_status, child_phase]
            ]),
        unit => #{
            role => <<".">>,
            directory => <<"supervisor_management">>,
            source => <<"supervisor_management/supervisor_management.x">>,
            top => <<"supervisor_management_clock">>,
            module => <<"supervisor_management_core">>,
            output => <<"supervisor_management/core.v">>,
            dslx_path => [
                unicode:characters_to_binary(P)
             || P <- ["supervisor_management", "supervisor" | Support]
            ],
            rtl => [
                <<"supervisor_management/core.v">>,
                <<"supervisor_management/management.sv">>,
                <<"supervisor/protocol_supervisor_stream.sv">>
            ],
            codegen_flags => hls_build_profile:flags(Profile, sampled_clock)
        }
    }.

%% Parent transport sessions are independent of each child's application and management lanes.
-spec external_ports() -> {ports(), ports()}.
external_ports() ->
    {
        [
            {"reset", 1},
            {"parent_transport_reset", 1},
            {"parent_transport_session", 64},
            {"parent_management_word", 32},
            {"parent_management_valid", 1},
            {"parent_management_last", 1},
            {"parent_management_output_ready", 1}
        ],
        [
            {"parent_management_ready", 1},
            {"parent_management_output_word", 32},
            {"parent_management_output_valid", 1},
            {"parent_management_output_last", 1},
            {"parent_transport_session_observed", 64},
            {"parent_transport_attached", 1},
            {"parent_wire_fault", 1}
        ]
    }.

%% Raw parent pins stay private; only the parser can issue lifecycle/grant commands.
-spec core_ports(#{atom() => hls_type:descriptor()}) -> {ports(), ports()}.
core_ports(Codecs) ->
    W = fun(K) -> hls_type:width(maps:get(K, Codecs)) end,
    {
        [
            {"management_valid", 1},
            {"management_op", W(operation)},
            {"expected", 64},
            {"target", 64},
            {"transition", 64},
            {"management_fault", W(fault)},
            {"grant_valid", 1},
            {"grant_epoch", 64},
            {"grant_first", 64},
            {"grant_last", 64},
            {"slot_valid", 1},
            {"slot_operation", 2},
            {"slot_epoch", 64},
            {"slot_index", 32},
            {"slot_expected", 64}
        ],
        [
            {"management_ready", 1},
            {"management_response_valid", 1},
            {"domain_status", W(status)},
            {"domain_action", W(action)},
            {"domain_phase", W(phase)},
            {"domain_current", 64},
            {"domain_previous", 64},
            {"domain_target", 64},
            {"domain_transition", 64},
            {"domain_fault", W(fault)},
            {"grant_response_valid", 1},
            {"grant_accepted", 1},
            {"supervisor_phase", W(supervisor_phase)},
            {"supervisor_reason", W(supervisor_reason)},
            {"grant_next", 64},
            {"slot_ready", 1},
            {"slot_response_valid", 1},
            {"slot_status", W(supervisor_status)},
            {"slot_result_index", 32},
            {"slot_phase", W(child_phase)},
            {"slot_target", 64}
        ]
    }.

%% Named struct order is the sampled pin ABI; no behavioral expressions are generated here.
-spec structure(string(), ports()) -> iodata().
structure(Name, Fields) ->
    [
        "pub struct ",
        Name,
        " {\n",
        [[N, ": bits[", integer_to_list(W), "],\n"] || {N, W} <- Fields],
        "}\n"
    ].

%% Mechanical wiring leaves each child stream and its packet ownership independent.
-spec wrapper(ports(), ports(), ports(), ports(), ports(), ports(), ports(), ports()) -> iodata().
wrapper(
    Inputs, Outputs, RawInputs, RawOutputs, ParserInputs, ParserOutputs, Commands, Observations
) ->
    true = length(Inputs ++ Outputs) =:= length(lists:usort([N || {N, _} <- Inputs ++ Outputs])),
    [
        "// Wiring only; packet handling and lifecycle policy are compiled DSLX/Erlang.\n",
        "module protocol_supervisor_stream(input wire clk,\n",
        lists:join(",\n", [port("input", P) || P <- Inputs] ++ [port("output", P) || P <- Outputs]),
        "\n);\n",
        [[port("wire", {"command_" ++ N, W}), ";\n"] || {N, W} <- Commands],
        "protocol_supervisor_stream_raw tree(.clk(clk),\n",
        lists:join(
            ",\n",
            [
                connection(
                    N,
                    case lists:keymember(N, 1, Commands) of
                        true -> "command_" ++ N;
                        false -> N
                    end
                )
             || {N, _} <- RawInputs
            ] ++
                [connection(N, N) || {N, _} <- RawOutputs]
        ),
        "\n);\n",
        "supervisor_management management(.clk(clk),\n",
        lists:join(
            ",\n",
            [
                connection(
                    N,
                    case lists:prefix("observed_", N) of
                        true -> lists:nthtail(length("observed_"), N);
                        false -> N
                    end
                )
             || {N, _} <- ParserInputs
            ] ++
                [connection(N, N) || {N, _} <- ParserOutputs]
        ),
        "\n);\nendmodule\n",
        case lists:all(fun({N, _}) -> lists:keymember(N, 1, RawOutputs) end, Observations) of
            true -> [];
            false -> error(missing_supervisor_observation)
        end
    ].

%% Named associations avoid any dependence on textual declaration order.
-spec connection(string(), string()) -> iodata().
connection(Name, Value) -> [".", Name, "(", Value, ")"].

%% Scalars and vectors retain exact widths; wire declarations have no direction keyword.
-spec port(string(), {string(), pos_integer()}) -> iodata().
port("wire", {N, 1}) -> ["wire ", N];
port("wire", {N, W}) -> ["wire [", integer_to_list(W - 1), ":0] ", N];
port(D, {N, 1}) -> [D, " wire ", N];
port(D, {N, W}) -> [D, " wire [", integer_to_list(W - 1), ":0] ", N].
