-module(hls_domain_endpoint_build).
-moduledoc "Emits an independently clocked mailbox TX or RX endpoint from its native Erlang ownership kernel. One retained application frame and slot accompany the source service; controller framing is independently sized. This emitter supplies no board composition, carrier integrity checks, remote liveness or retry policy.".

%% Pure source emission; external tools consume the returned files separately.
-export([emit/2, emit/3]).
-export_type([direction/0, result/0]).

-doc "The source-publication owner or the destination-capture owner of one directed channel.".
-type direction() :: tx | rx.

%% Field order is shared by the sampled DSLX interface and mechanical RTL adapter.
-type ports() :: [{string(), pos_integer()}].

%% Record providers preserve the exact native operation, status and packet encodings.
-type codecs() :: #{
    operation := hls_type:descriptor(),
    status := hls_type:descriptor(),
    input := hls_type:descriptor(),
    output := hls_type:descriptor(),
    binding := hls_type:descriptor(),
    packet := hls_type:descriptor()
}.

%% Widths describe declared storage, excluding a separately retained carrier packet.
-type state_budget() :: #{
    kernel_bits := pos_integer(),
    failure_bits := 32,
    payload_bits := pos_integer(),
    slot_bits := 8,
    total_bits := pos_integer(),
    payload_registers := 1,
    payload_readers := 1,
    writers := 1,
    retention := outside_local_domain_reset
}.

%% Source and emitted identities support inspection without claiming RTL equivalence.
-type source_service() :: #{
    module := module(),
    source := binary(),
    input_record := atom(),
    output_record := atom(),
    state_record := atom(),
    failure_sites := [xls_failure_sites:site()],
    dslx_sha256 := binary(),
    dependency_sha256 := #{binary() => binary()}
}.

-doc "Endpoint pins, exact codecs, separate application/controller capacities and declared state cost. The reset pin is cold-only; local_ready and local_incarnation retire ownership through the native kernel. Each dependency directory needs its own controller support profile. No mapped area, timing or recovery progress is established.".
-type result() :: #{
    direction := direction(),
    inputs := ports(),
    outputs := ports(),
    codecs := codecs(),
    frame_payload_words := hls_frame_layout:words(),
    frame_bits := pos_integer(),
    controller_words := hls_frame_layout:words(),
    controller_minimum_words := hls_frame_layout:words(),
    controller_input_bits := pos_integer(),
    controller_output_bits := pos_integer(),
    controller_frame_bits := pos_integer(),
    controller_profile := hls_frame_layout:descriptor(),
    storage_bits := pos_integer(),
    state_budget := state_budget(),
    source_service := source_service(),
    cold_reset_pin := string(),
    local_ready_pin := string(),
    local_incarnation_pin := string(),
    dependency_directory := string(),
    clock_proc := string(),
    top_module := string(),
    core_module := string()
}.

%% Resolved declarations are private build inputs, never supplied by a bundle consumer.
-type declarations() :: #{
    source := file:filename(),
    module := module(),
    input := atom(),
    output := atom(),
    service := atom(),
    input_bits := pos_integer(),
    output_bits := pos_integer(),
    kernel_bits := pos_integer(),
    minimum_words := hls_frame_layout:words(),
    codecs := codecs()
}.

-doc "Emits TX or RX with the smallest controller profile admitting its source messages, independently of application-frame words. Retains one frame/slot until another kernel-authorized capture or cold reset; local retirement never clears storage. TX requires host-confirmed RX binding, and RX acknowledges only after native capture. Carrier offers must preserve whole-packet integrity and stable ownership until acceptance.".
-spec emit(direction(), hls_frame_layout:words()) -> hls_generated_files:output(result()).
emit(Direction, DataWords) -> build(Direction, DataWords, minimum).

-doc "Emits with an explicit controller payload capacity while retaining the separate application-frame width. Rejects a controller smaller than any declared service message before source compilation. Each returned endpoint directory must resolve axis/hls_bits against its own frame_config.x, not an application or peer endpoint profile. Cold reset requires exclusion of the forgotten transport namespace.".
-spec emit(direction(), hls_frame_layout:words(), hls_frame_layout:words()) ->
    hls_generated_files:output(result()).
emit(Direction, DataWords, ControllerWords) -> build(Direction, DataWords, ControllerWords).

%% All frame-profile selection happens before compiling the unchanged native source.
-spec build(direction(), hls_frame_layout:words(), minimum | hls_frame_layout:words()) ->
    hls_generated_files:output(result()).
build(Direction, DataWords, Requested) ->
    DataLayout = hls_frame_layout:new(DataWords),
    Decl =
        #{
            source := Source,
            input := Input,
            output := Output,
            input_bits := InputBits,
            output_bits := OutputBits,
            kernel_bits := KernelBits,
            minimum_words := Minimum,
            codecs := Codecs
        } = declarations(Direction),
    ControllerWords = controller_words(Requested, Minimum),
    ControllerLayout = hls_frame_layout:new(ControllerWords),
    Artifact = xls_parse:to_artifact(Source, #{frame_payload_words => ControllerWords}),
    FrameBits = hls_frame_layout:frame_bits(DataLayout),
    {Inputs, Outputs} = ports(Direction, FrameBits, hls_type:width(maps:get(status, Codecs))),
    Name = "endpoint_" ++ atom_to_list(Direction),
    {ok, Template} = file:read_file(
        filename:join(code:priv_dir(hls_lowering), "xls/templates/" ++ Name ++ ".x.in")
    ),
    Wrapper = xls_template:render(Template, [
        {<<"@@INPUTS@@">>, structure("Inputs", Inputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", Outputs)},
        {<<"@@FRAME_BITS@@">>, integer_to_list(FrameBits)},
        {<<"@@INPUT_TYPE@@">>, xls_names:record_type(Input)},
        {<<"@@INPUT_CODEC@@">>, xls_names:record_codec(Input)},
        {<<"@@OUTPUT_CODEC@@">>, xls_names:record_codec(Output)},
        {<<"@@INPUT_TAG@@">>, xls_names:enum_member(Input)},
        {<<"@@BINDING_TYPE@@">>, xls_names:record_type(endpoint_binding)},
        {<<"@@PACKET_TYPE@@">>, xls_names:record_type(endpoint_packet)},
        {<<"@@TICK@@">>, literal(tick, maps:get(operation, Codecs))},
        {<<"@@BIND@@">>, literal(bind, maps:get(operation, Codecs))},
        {<<"@@FENCE@@">>, literal(fence, maps:get(operation, Codecs))}
    ]),
    Budget = #{
        kernel_bits => KernelBits,
        failure_bits => 32,
        payload_bits => FrameBits,
        slot_bits => 8,
        total_bits => KernelBits + 32 + FrameBits + 8,
        payload_registers => 1,
        payload_readers => 1,
        writers => 1,
        retention => outside_local_domain_reset
    },
    #{
        files => hls_generated_files:merge([
            hls_generated_files:prefix(Name, xls_emitted:dependencies(Artifact)),
            #{
                Name ++ "/" ++ Name ++ "_controller.x" => xls_emitted:bytes(Artifact),
                Name ++ "/" ++ Name ++ ".x" => Wrapper,
                Name ++ "/frame_config.x" => xls_frame_layout:config(ControllerLayout),
                Name ++ "/" ++ Name ++
                    ".sv" => sv_protocol_ports:emit(
                        Inputs, Outputs, Name, Name ++ "_core"
                    )
            }
        ]),
        result => #{
            direction => Direction,
            inputs => Inputs,
            outputs => Outputs,
            codecs => Codecs,
            frame_payload_words => DataWords,
            frame_bits => FrameBits,
            controller_words => ControllerWords,
            controller_minimum_words => Minimum,
            controller_input_bits => InputBits,
            controller_output_bits => OutputBits,
            controller_frame_bits => hls_frame_layout:frame_bits(ControllerLayout),
            controller_profile => hls_frame_layout:descriptor(ControllerLayout),
            storage_bits => maps:get(total_bits, Budget),
            state_budget => Budget,
            source_service => source_service(Decl, Artifact),
            cold_reset_pin => "reset",
            local_ready_pin => "local_ready",
            local_incarnation_pin => "local_incarnation",
            dependency_directory => Name,
            clock_proc => Name ++ "_clock",
            top_module => Name,
            core_module => Name ++ "_core"
        }
    }.

%% Every source message, including unsupported casts, contributes to the minimum profile.
-spec declarations(direction()) -> declarations().
declarations(Direction) ->
    {Module, Input, Output, Service} = names(Direction),
    Source = hls_source:library_file(
        hls_fabric, "runtime/domain/" ++ atom_to_list(Module) ++ ".erl"
    ),
    {ok, Parsed} = hls_source:parse_file(Source),
    Forms = hls_records:resolve(Parsed),
    InputFields = maps:from_list(hls_records:fields(hls_records:find(Forms, Input))),
    OutputFields = maps:from_list(hls_records:fields(hls_records:find(Forms, Output))),
    Maximum = lists:max([
        hls_records:width(hls_records:find(Forms, Name))
     || Name <- hls_actor_source:tags(Forms)
    ]),
    #{
        source => Source,
        module => Module,
        input => Input,
        output => Output,
        service => Service,
        input_bits => hls_records:width(hls_records:find(Forms, Input)),
        output_bits => hls_records:width(hls_records:find(Forms, Output)),
        kernel_bits => hls_records:width(hls_records:find(Forms, Service)),
        minimum_words => (Maximum + 31) div 32,
        codecs => #{
            operation => maps:get(op, InputFields),
            status => maps:get(status, OutputFields),
            input => descriptor(Forms, Input),
            output => descriptor(Forms, Output),
            binding => maps:get(binding, InputFields),
            packet => maps:get(packet, OutputFields)
        }
    }.

%% Endpoints share the wire declarations but compile only their own service closure.
-spec names(direction()) -> {module(), atom(), atom(), atom()}.
names(tx) ->
    {hls_domain_channel_tx, endpoint_tx_input, endpoint_tx_output, endpoint_tx_service};
names(rx) ->
    {hls_domain_channel_rx, endpoint_rx_input, endpoint_rx_output, endpoint_rx_service}.

%% The ordinary record provider is the codec authority for the complete service messages.
-spec descriptor([hls_source:form()], atom()) -> hls_type:descriptor().
descriptor(Forms, Name) ->
    {hls_type, hls_record, Name, hls_records:fields(hls_records:find(Forms, Name))}.

%% A requested controller profile cannot silently inflate application frame capacity.
-spec controller_words(minimum | hls_frame_layout:words(), hls_frame_layout:words()) ->
    hls_frame_layout:words().
controller_words(minimum, Minimum) ->
    Minimum;
controller_words(Words, Minimum) ->
    _ = hls_frame_layout:new(Words),
    case Words >= Minimum of
        true -> Words;
        false -> error({endpoint_controller_too_narrow, Words, Minimum})
    end.

%% Keep generated-source provenance and its failure-code allocation beside the public pins.
-spec source_service(declarations(), xls_emitted:artifact()) -> source_service().
source_service(
    #{
        source := Source,
        module := Module,
        input := Input,
        output := Output,
        service := Service
    },
    Artifact
) ->
    #{
        module => Module,
        source => unicode:characters_to_binary(Source),
        input_record => Input,
        output_record => Output,
        state_record => Service,
        failure_sites => xls_emitted:sites(Artifact),
        dslx_sha256 => hls_generated_files:hash(xls_emitted:bytes(Artifact)),
        dependency_sha256 => maps:from_list([
            {unicode:characters_to_binary(Name), hls_generated_files:hash(Bytes)}
         || {Name, Bytes} <- maps:to_list(xls_emitted:dependencies(Artifact))
        ])
    }.

%% Only local lifecycle and host-confirmed receiver binding cross the management boundary.
-spec ports(direction(), pos_integer(), pos_integer()) -> {ports(), ports()}.
ports(tx, FrameBits, StatusBits) ->
    {
        common_inputs() ++ binding_ports("receiver_") ++
            [
                {"receiver_active", 1},
                {"source_valid", 1},
                {"source_slot", 8},
                {"source_frame", FrameBits},
                {"data_tx_ready", 1},
                {"credit_valid", 1}
            ] ++ packet_ports("credit_"),
        [
            {"source_ready", 1}, {"source_take", 1}, {"tx_valid", 1}
        ] ++ packet_ports("tx_") ++
            [
                {"tx_slot", 8},
                {"tx_frame", FrameBits},
                {"credit_ready", 1},
                {"credit_drop", 1}
            ] ++ common_outputs(StatusBits)
    };
ports(rx, FrameBits, StatusBits) ->
    {
        common_inputs() ++ [{"data_valid", 1}] ++ packet_ports("data_") ++
            [
                {"data_slot", 8},
                {"data_frame", FrameBits},
                {"destination_ready", 1},
                {"ack_tx_ready", 1}
            ],
        [
            {"data_ready", 1},
            {"data_take", 1},
            {"data_drop", 1},
            {"destination_valid", 1},
            {"destination_take", 1},
            {"destination_slot", 8},
            {"destination_frame", FrameBits},
            {"ack_valid", 1}
        ] ++ packet_ports("ack_") ++ common_outputs(StatusBits)
    }.

%% Reset is exclusively cold reset; local retirement is an ordinary kernel observation.
-spec common_inputs() -> ports().
common_inputs() ->
    [{"reset", 1}, {"bind_request", 1}, {"fence", 1}] ++ binding_ports("") ++
        [{"local_ready", 1}, {"local_incarnation", 64}].

%% Passive metadata comes from retained service state, even on a terminal source failure.
-spec common_outputs(pos_integer()) -> ports().
common_outputs(StatusBits) ->
    binding_ports("bound_") ++
        [
            {"packet_sequence", 32},
            {"status", StatusBits},
            {"active", 1},
            {"fault", 1},
            {"failure", 32}
        ].

%% Every binding field is explicit; no packet identity is truncated to a generation alone.
-spec binding_ports(string()) -> ports().
binding_ports(Prefix) ->
    [
        {Prefix ++ Field, 64}
     || Field <- [
            "namespace", "generation", "source_incarnation", "destination_incarnation"
        ]
    ].

%% Acknowledgements carry the complete identity of the captured publication.
-spec packet_ports(string()) -> ports().
packet_ports(Prefix) -> binding_ports(Prefix) ++ [{Prefix ++ "sequence", 32}].

%% Struct order is the external sampled-pin packing order.
-spec structure(string(), ports()) -> iodata().
structure(Name, Fields) ->
    [
        "// Ordered sampled pins; reset means cold reset of retained endpoint storage.\n",
        "pub struct ",
        Name,
        " {\n",
        [[N, ": bits[", integer_to_list(W), "],\n"] || {N, W} <- Fields],
        "}\n"
    ].

%% Native atom codes come from the type provider, never a hand-assigned enum table.
-spec literal(atom(), hls_type:descriptor()) -> iodata().
literal(Value, Descriptor) ->
    Width = hls_type:width(Descriptor),
    <<Bits:Width>> = hls_type:pack(Value, Descriptor),
    ["uN[", integer_to_list(Width), "]:", integer_to_list(Bits)].
