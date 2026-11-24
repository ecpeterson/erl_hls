-module(hls_domain_endpoints_stream).
-moduledoc "Emits one bounded metadata-only management parser for independent TX/RX mailbox endpoints. Static direction and native codecs come from endpoint builds; board composition separately wires local lifecycle, payloads, cold resets and transport-session establishment. No peer lifecycle wire or application scheduler is introduced.".

%% Pure generation of the standalone parser and mechanical sampled-pin adapter.
-export([emit/1]).
-export_type([config/0, result/0]).

%% Ordered finite pin widths are shared by generated DSLX and the RTL adapter.
-type ports() :: [{string(), pos_integer()}].
-doc "Static endpoint IDs/directions and shared native codecs. The default management route is {0,2}. Optional top_module is a simple HDL identifier naming the adapter, core prefix and artifact directory; its default is endpoint_management.".
-type config() :: #{
    endpoints := [hls_domain_endpoint_wire:endpoint(), ...],
    codecs := hls_domain_endpoint_wire:codecs(),
    management_route => hls_fabric:route(),
    top_module => string()
}.
-doc "Standalone parser pins/interface/build unit. packet_words includes route/header; state_bit_budget excludes endpoint and carrier storage, which this parser neither owns nor resets.".
-type result() :: #{
    inputs := ports(),
    outputs := ports(),
    top_module := string(),
    core_module := string(),
    interface := hls_domain_endpoint_wire:interface(),
    state_bit_budget := pos_integer(),
    payload_words := 14,
    packet_words := 16,
    unit := hls_artifact_bundle:unit()
}.

-doc "Returns files and metadata without writing files or invoking tools. One receive and one response slot use 1159 declared bits. Selected endpoint results are captured on the command issue edge; pins must be connected without added command/observation latency. TX bind asserts prior exact RX confirmation and drives receiver evidence only on that bind edge. Parser/session reset never drives endpoint reset.".
-spec emit(config()) -> hls_generated_files:output(result()).
emit(#{endpoints := Endpoints, codecs := Codecs} = Config) ->
    Top = maps:get(top_module, Config, "endpoint_management"),
    ok = identifier(Top),
    Core = Top ++ "_core",
    SourcePath = Top ++ "/" ++ Top ++ ".x",
    AdapterPath = Top ++ "/management.sv",
    Interface = hls_domain_endpoint_wire:load(#{
        kind => domain_endpoint_management,
        management_route => maps:get(management_route, Config, {0, 2}),
        endpoints => Endpoints,
        response_tag => 129,
        codecs => maps:with([operation, status, binding], Codecs)
    }),
    #{
        management_route := {Source, Destination},
        codecs := #{status := Status, binding := Binding}
    } = Interface,
    Fields = binding_fields(Binding),
    {ExternalInputs, ExternalOutputs} = external_ports(),
    Inputs = ExternalInputs ++ lists:append([observed_ports(E, Fields, Status) || E <- Endpoints]),
    Outputs = ExternalOutputs ++ lists:append([command_ports(E, Fields) || E <- Endpoints]),
    {ok, Template} = file:read_file(
        filename:join(
            code:priv_dir(hls_target),
            "xls/templates/domain_endpoint_management.x.in"
        )
    ),
    Text = xls_template:render(Template, [
        {<<"@@STATUS_BITS@@">>, n(hls_type:width(Status))},
        {<<"@@INVALID@@">>, literal(invalid, Status)},
        {<<"@@ROUTE@@">>, n((Source bsl 16) bor Destination)},
        {<<"@@INPUTS@@">>, structure("Inputs", Inputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", Outputs)},
        {<<"@@BINDING_FIELDS@@">>, [[atom_to_list(F), ": u64, "] || F <- Fields]},
        {<<"@@DECODE_BINDING@@">>, [
            [atom_to_list(F), ": value[", n(I * 64), "+:u64],\n"]
         || {I, F} <- lists:enumerate(0, Fields)
        ]},
        {<<"@@PACK_BINDING@@">>,
            lists:join(
                " ++ ",
                [["observed.binding.", atom_to_list(F)] || F <- lists:reverse(Fields)]
            )},
        {<<"@@OBSERVATION@@">>, observation(Endpoints, Fields)},
        {<<"@@COMMANDS@@">>, [commands(E, Fields) || E <- Endpoints]}
    ]),
    StateBits = 2 * (64 + 14 * 32) + 36 + 1 + 32 + 64 + 2,
    true = StateBits =< 2048,
    #{imports := Support} = hls_build_support:layout([]),
    Profile = hls_build_profile:owner(hls_frame_layout:new(14)),
    #{
        files => #{
            SourcePath => Text,
            AdapterPath => sv_protocol_ports:emit(Inputs, Outputs, Top, Core)
        },
        result => #{
            inputs => Inputs,
            outputs => Outputs,
            top_module => Top,
            core_module => Core,
            interface => Interface,
            state_bit_budget => StateBits,
            payload_words => 14,
            packet_words => 16,
            unit => #{
                role => <<".">>,
                directory => b(Top),
                source => b(SourcePath),
                top => <<"endpoint_management_clock">>,
                module => b(Core),
                output => b(Top ++ "/core.v"),
                dslx_path => [b(P) || P <- [Top | Support]],
                rtl => [b(Top ++ "/core.v"), b(AdapterPath)],
                codegen_flags => hls_build_profile:flags(Profile, sampled_clock)
            }
        }
    }.

%% Generated module and directory identities cannot contain HDL fragments or path separators.
-spec identifier(string()) -> ok.
identifier(Name) ->
    match = re:run(Name, "^[a-zA-Z_][a-zA-Z0-9_]*$", [{capture, none}]),
    ok.

%% Bundle metadata uses portable UTF-8 names and relative paths.
-spec b(string()) -> binary().
b(Value) -> unicode:characters_to_binary(Value).

%% The native record provider packs these complete little-endian fields in declaration order.
-spec binding_fields(hls_type:descriptor()) -> [atom()].
binding_fields({hls_type, hls_record, endpoint_binding, Fields}) ->
    Names = [Name || {Name, Type} <- Fields, Type =:= hls_nums:u64()],
    [namespace, generation, source_incarnation, destination_incarnation] = Names,
    4 = length(Fields),
    Names.

%% The out-of-band session handshake belongs to deployment, not peer packet traffic.
-spec external_ports() -> {ports(), ports()}.
external_ports() ->
    {
        [
            {"reset", 1},
            {"endpoint_transport_reset", 1},
            {"endpoint_transport_session", 64},
            {"endpoint_management_word", 32},
            {"endpoint_management_valid", 1},
            {"endpoint_management_last", 1},
            {"endpoint_management_output_ready", 1}
        ],
        [
            {"endpoint_management_ready", 1},
            {"endpoint_management_output_word", 32},
            {"endpoint_management_output_valid", 1},
            {"endpoint_management_output_last", 1},
            {"endpoint_transport_session_observed", 64},
            {"endpoint_transport_attached", 1},
            {"endpoint_wire_fault", 1}
        ]
    }.

%% Only retained endpoint metadata enters selection; local lifecycle stays at each raw endpoint.
-spec observed_ports(hls_domain_endpoint_wire:endpoint(), [atom()], hls_type:descriptor()) ->
    ports().
observed_ports(#{id := Id}, Fields, Status) ->
    Prefix = prefix(Id) ++ "observed_",
    [{Prefix ++ "bound_" ++ atom_to_list(F), 64} || F <- Fields] ++
        [
            {Prefix ++ "packet_sequence", 32},
            {Prefix ++ "status", hls_type:width(Status)},
            {Prefix ++ "active", 1},
            {Prefix ++ "fault", 1}
        ].

%% Requested binding fields match raw endpoint pins; only TX needs explicit receiver evidence.
-spec command_ports(hls_domain_endpoint_wire:endpoint(), [atom()]) -> ports().
command_ports(#{id := Id, kind := Kind}, Fields) ->
    Prefix = prefix(Id),
    [{Prefix ++ "bind_request", 1}, {Prefix ++ "fence", 1}] ++
        [{Prefix ++ atom_to_list(F), 64} || F <- Fields] ++
        case Kind of
            rx ->
                [];
            tx ->
                [{Prefix ++ "receiver_" ++ atom_to_list(F), 64} || F <- Fields] ++
                    [{Prefix ++ "receiver_active", 1}]
        end.

%% Unknown IDs produce an invalid zero-metadata response without pulsing any endpoint.
-spec observation([hls_domain_endpoint_wire:endpoint()], [atom()]) -> iodata().
observation(Endpoints, Fields) ->
    [
        "match endpoint {\n",
        [
            [
                "u32:",
                n(Id),
                " => Observation { known: true, binding: Binding {\n",
                [
                    [
                        atom_to_list(F),
                        ": io.",
                        prefix(Id),
                        "observed_bound_",
                        atom_to_list(F),
                        ",\n"
                    ]
                 || F <- Fields
                ],
                "}, sequence: io.",
                prefix(Id),
                "observed_packet_sequence,\n",
                [
                    [atom_to_list(F), ": io.", prefix(Id), "observed_", atom_to_list(F), ",\n"]
                 || F <- [status, active, fault]
                ],
                "},\n"
            ]
         || #{id := Id} <- Endpoints
        ],
        "_ => zero!<Observation>(),\n}"
    ].

%% An explicit host TX bind is the sole receiver-confirmation pulse; it never samples remote readiness.
-spec commands(hls_domain_endpoint_wire:endpoint(), [atom()]) -> iodata().
commands(#{id := Id, kind := Kind}, Fields) ->
    Prefix = prefix(Id),
    Selected = ["issue && endpoint == u32:", n(Id)],
    Bind = ["bind_enabled && endpoint == u32:", n(Id)],
    [
        Prefix,
        "bind_request: ",
        Bind,
        ",\n",
        Prefix,
        "fence: fence_enabled && endpoint == u32:",
        n(Id),
        ",\n",
        [
            [
                Prefix,
                atom_to_list(F),
                ": if ",
                Selected,
                " { requested.",
                atom_to_list(F),
                " } else { u64:0 },\n"
            ]
         || F <- Fields
        ],
        case Kind of
            rx ->
                [];
            tx ->
                [
                    [
                        [
                            Prefix,
                            "receiver_",
                            atom_to_list(F),
                            ": if ",
                            Bind,
                            " { requested.",
                            atom_to_list(F),
                            " } else { u64:0 },\n"
                        ]
                     || F <- Fields
                    ],
                    Prefix,
                    "receiver_active: ",
                    Bind,
                    ",\n"
                ]
        end
    ].

%% Stable endpoint IDs generate distinct legal pin identifiers without a runtime lookup table.
-spec prefix(hls_nums:u32()) -> string().
prefix(Id) -> "endpoint_" ++ n(Id) ++ "_".

%% Struct order is the mechanical sampled-pin packing order.
-spec structure(string(), ports()) -> iodata().
structure(Name, Fields) ->
    [
        "pub struct ",
        Name,
        " {\n",
        [
            [Field, ": bits[", n(Width), "],\n"]
         || {Field, Width} <- Fields
        ],
        "}\n"
    ].

%% Native atoms retain their source-derived encodings rather than a second enum table.
-spec literal(atom(), hls_type:descriptor()) -> iodata().
literal(Value, Descriptor) ->
    Width = hls_type:width(Descriptor),
    <<Bits:Width>> = hls_type:pack(Value, Descriptor),
    ["uN[", n(Width), "]:", n(Bits)].

%% Numbers here are static dimensions and checked identities, never runtime source expressions.
-spec n(non_neg_integer()) -> string().
n(Value) -> integer_to_list(Value).
