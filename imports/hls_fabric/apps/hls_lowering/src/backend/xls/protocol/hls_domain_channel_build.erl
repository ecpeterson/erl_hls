-module(hls_domain_channel_build).
-moduledoc "Compiles the shared Erlang mailbox-channel ownership kernel and adds one retained payload register. The domain-group composer connects source/destination lifecycle observations and public data/credit streams; this emitter supplies no process-link or restart policy.".

%% Typed source emission for the enclosing partition-domain builder.
-export([emit/1]).
-export_type([result/0]).

%% Named sampled fields retain the same order in DSLX and the mechanical RTL adapter.
-type ports() :: [{string(), pos_integer()}].
-doc "Channel pins, source-derived atom codecs and declared state cost; these do not establish mapped area or physical timing.".
-type result() :: #{
    inputs := ports(),
    outputs := ports(),
    codecs := #{atom() := hls_type:descriptor()},
    frame_payload_words := hls_frame_layout:words(),
    controller_words := hls_frame_layout:words(),
    storage_bits := pos_integer()
}.

-doc "Emits a one-packet crossing with explicit binding and exact returned-credit ownership. The shared kernel lives outside endpoint resets; cold reset requires exclusion of the old transport namespace. Data/credit streams must retain stable offers until handshake and preserve payload integrity. Native destination capture still checks canonical source frames. Requires at least twenty payload words for the compiled control interface.".
-spec emit(hls_frame_layout:words()) -> hls_generated_files:output(result()).
emit(Words) when Words >= 20 ->
    Source = hls_source:library_file(hls_fabric, "runtime/domain/hls_domain_channel.erl"),
    {ok, Parsed} = hls_source:parse_file(Source),
    Forms = hls_records:resolve(Parsed),
    Input = maps:from_list(hls_records:fields(hls_records:find(Forms, channel_input))),
    Output = maps:from_list(hls_records:fields(hls_records:find(Forms, channel_output))),
    Codecs = #{operation => maps:get(op, Input), status => maps:get(status, Output)},
    true = hls_records:width(hls_records:find(Forms, channel_input)) =< Words * 32,
    true = hls_records:width(hls_records:find(Forms, channel_output)) =< Words * 32,
    Artifact = xls_parse:to_artifact(Source, #{frame_payload_words => Words}),
    FrameBits = 32 + Words * 32,
    {Inputs, Outputs} = ports(FrameBits, hls_type:width(maps:get(status, Codecs))),
    {ok, Template} = file:read_file(
        filename:join(code:priv_dir(hls_lowering), "xls/templates/domain_channel.x.in")
    ),
    Kernel = xls_template:render(Template, [
        {<<"@@INPUTS@@">>, structure("Inputs", Inputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", Outputs)},
        {<<"@@FRAME_BITS@@">>, integer_to_list(FrameBits)},
        {<<"@@TICK@@">>, literal(tick, maps:get(operation, Codecs))},
        {<<"@@BIND@@">>, literal(bind, maps:get(operation, Codecs))},
        {<<"@@FENCE@@">>, literal(fence, maps:get(operation, Codecs))}
    ]),
    Metadata = hls_records:width(hls_records:find(Forms, channel_state)),
    #{
        files => hls_generated_files:merge([
            hls_generated_files:prefix("channel", xls_emitted:dependencies(Artifact)),
            #{
                "channel/channel_controller.x" => xls_emitted:bytes(Artifact),
                "channel/domain_channel.x" => Kernel,
                "channel/domain_channel.sv" => sv_protocol_ports:emit(
                    Inputs, Outputs, "domain_channel", "domain_channel_core"
                )
            }
        ]),
        result => #{
            inputs => Inputs,
            outputs => Outputs,
            codecs => Codecs,
            frame_payload_words => Words,
            controller_words => Words,
            storage_bits => Metadata + 32 + FrameBits + 8
        }
    }.

%% Data and acknowledgement channels advance independently of application ingress.
-spec ports(pos_integer(), pos_integer()) -> {ports(), ports()}.
ports(FrameBits, StatusBits) ->
    {
        [
            {"reset", 1},
            {"bind_request", 1},
            {"fence", 1},
            {"expected_generation", 64},
            {"source_incarnation", 64},
            {"destination_incarnation", 64},
            {"source_live", 1},
            {"destination_live", 1},
            {"source_valid", 1},
            {"source_slot", 8},
            {"source_frame", FrameBits},
            {"data_tx_ready", 1},
            {"data_valid", 1},
            {"data_generation", 64},
            {"data_sequence", 32},
            {"data_slot", 8},
            {"data_frame", FrameBits},
            {"destination_ready", 1},
            {"ack_tx_ready", 1},
            {"credit_valid", 1},
            {"credit_generation", 64},
            {"credit_sequence", 32}
        ],
        [
            {"source_ready", 1},
            {"tx_valid", 1},
            {"tx_generation", 64},
            {"tx_sequence", 32},
            {"tx_slot", 8},
            {"tx_frame", FrameBits},
            {"data_ready", 1},
            {"data_drop", 1},
            {"destination_valid", 1},
            {"destination_slot", 8},
            {"destination_frame", FrameBits},
            {"ack_valid", 1},
            {"ack_generation", 64},
            {"ack_sequence", 32},
            {"credit_ready", 1},
            {"credit_drop", 1},
            {"generation", 64},
            {"bound_source_incarnation", 64},
            {"bound_destination_incarnation", 64},
            {"packet_sequence", 32},
            {"status", StatusBits},
            {"active", 1},
            {"fault", 1}
        ]
    }.

%% Struct order is the external sampled-pin packing order.
-spec structure(string(), ports()) -> iodata().
structure(Name, Fields) ->
    [
        "pub struct ",
        Name,
        " {\n",
        [[N, ": bits[", integer_to_list(W), "],\n"] || {N, W} <- Fields],
        "}\n"
    ].

%% Atom values follow the ordinary type provider rather than hand-written tags.
-spec literal(atom(), hls_type:descriptor()) -> iodata().
literal(Value, Descriptor) ->
    Width = hls_type:width(Descriptor),
    <<Bits:Width>> = hls_type:pack(Value, Descriptor),
    ["uN[", integer_to_list(Width), "]:", integer_to_list(Bits)].
