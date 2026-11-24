-module(hls_domain_channels_stream).
-moduledoc "Frames inspect/bind/fence commands for a fixed set of mailbox channels. hls_protocol_domains supplies checked endpoint bindings and independent framed actor domains; this management-only adapter selects metadata and cannot carry application payload or reset channel ownership.".

%% Internal source composition and retained management interface.
-export([emit/1]).
-export_type([result/0]).

%% Sampled fields preserve explicit finite HDL widths.
-type ports() :: [{string(), pos_integer()}].
-doc "One management parser's files, public composite pins, retained host interface and portable build unit. Files may be omitted when retaining only metadata.".
-type result() :: #{
    files => hls_generated_files:files(),
    inputs := ports(),
    outputs := ports(),
    interface := #{
        kind := domain_channel_management,
        management_route := {0, 0},
        channels := [non_neg_integer()],
        codecs := #{status := hls_type:descriptor()}
    },
    state_bit_budget := pos_integer(),
    packet_words := 14,
    unit := hls_artifact_bundle:unit()
}.

-doc "Wraps protocol_domains_stream_raw with an independent session-bound management lane. Exact requested endpoint incarnations are checked on each bind edge; responses capture the actual selected channel result. One receive and one transmit buffer bound storage independently of channel count; only metadata selection scales with crossings. Transport replacement clears the parser, never domains or channel tombstones.".
-spec emit(hls_protocol_domains:result()) -> result().
emit(#{
    domains := Domains,
    crossings := Crossings,
    inputs := RawInputs,
    outputs := RawOutputs,
    channel := #{codecs := #{status := Status}},
    frame_payload_words := Words
}) ->
    {ExternalInputs, ExternalOutputs} = external_ports(),
    Commands = command_ports(Crossings),
    Observations = [
        {observed(Index, Name), Width}
     || #{index := Index} <- Crossings,
        {Name, Width} <- observation_ports(Status)
    ],
    ParserInputs = ExternalInputs ++ Observations,
    ParserOutputs = ExternalOutputs ++ Commands,
    Inputs =
        [P || P = {N, _} <- RawInputs, N =/= "reset", not lists:keymember(N, 1, Commands)] ++
            ExternalInputs,
    Hidden = [P || P = {N, _} <- RawOutputs, private_lifecycle(N, Domains)],
    Outputs = [P || P = {N, _} <- RawOutputs, not lists:keymember(N, 1, Hidden)] ++ ExternalOutputs,
    {ok, Template} = file:read_file(
        filename:join(code:priv_dir(hls_target), "xls/templates/domain_channel_management.x.in")
    ),
    Text = xls_template:render(Template, [
        {<<"@@STATUS_BITS@@">>, integer_to_list(hls_type:width(Status))},
        {<<"@@OK@@">>, literal(ok, Status)},
        {<<"@@INVALID@@">>, literal(invalid, Status)},
        {<<"@@STALE@@">>, literal(stale, Status)},
        {<<"@@INPUTS@@">>, structure("Inputs", ParserInputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", ParserOutputs)},
        {<<"@@OBSERVATION@@">>, observation(Crossings)},
        {<<"@@COMMANDS@@">>, commands(Crossings)}
    ]),
    #{imports := Support} = hls_build_support:layout([]),
    Profile = hls_build_profile:owner(hls_frame_layout:new(Words)),
    #{
        files => #{
            "channel_management/channel_management.x" => Text,
            "channel_management/management.sv" => sv_protocol_ports:emit(
                ParserInputs,
                ParserOutputs,
                "channel_management",
                "channel_management_core"
            ),
            "channel_management/protocol_domains_stream.sv" => wrapper(
                Inputs,
                Outputs,
                RawInputs,
                RawOutputs,
                ParserInputs,
                ParserOutputs,
                Commands,
                Hidden,
                Crossings
            )
        },
        inputs => Inputs,
        outputs => Outputs,
        interface => #{
            kind => domain_channel_management,
            management_route => {0, 0},
            channels => [I || #{index := I} <- Crossings],
            codecs => #{status => Status}
        },
        %% Receive adds stage/length/bad/full; transmit adds valid/position; session adds two flags.
        state_bit_budget => 2 * (64 + 14 * 32) + 36 + 1 + 32 + 64 + 2,
        packet_words => 14,
        unit => #{
            role => <<".">>,
            directory => <<"channel_management">>,
            source => <<"channel_management/channel_management.x">>,
            top => <<"channel_management_clock">>,
            module => <<"channel_management_core">>,
            output => <<"channel_management/core.v">>,
            dslx_path => [unicode:characters_to_binary(P) || P <- ["channel_management" | Support]],
            rtl => [
                <<"channel_management/core.v">>,
                <<"channel_management/management.sv">>,
                <<"channel_management/protocol_domains_stream.sv">>
            ],
            codegen_flags => hls_build_profile:flags(Profile, sampled_clock)
        }
    }.

%% The parser has its own transport session, independent of every actor's two lanes.
-spec external_ports() -> {ports(), ports()}.
external_ports() ->
    {
        [
            {"reset", 1},
            {"channel_transport_reset", 1},
            {"channel_transport_session", 64},
            {"channel_management_word", 32},
            {"channel_management_valid", 1},
            {"channel_management_last", 1},
            {"channel_management_output_ready", 1}
        ],
        [
            {"channel_management_ready", 1},
            {"channel_management_output_word", 32},
            {"channel_management_output_valid", 1},
            {"channel_management_output_last", 1},
            {"channel_transport_session_observed", 64},
            {"channel_transport_attached", 1},
            {"channel_wire_fault", 1}
        ]
    }.

%% Exactly one selected command is driven; all unselected channels continue ordinary data/credit ticks.
-spec command_ports([hls_protocol_domains:crossing()]) -> ports().
command_ports(Crossings) ->
    [
        {channel(I) ++ Name, Width}
     || #{index := I} <- Crossings,
        {Name, Width} <- [{"bind_request", 1}, {"fence", 1}, {"expected_generation", 64}]
    ].

%% The selected row contains current endpoint identities and the actual retained channel binding.
-spec observation_ports(hls_type:descriptor()) -> ports().
observation_ports(Status) ->
    [
        {"current_source", 64},
        {"current_destination", 64},
        {"generation", 64},
        {"source", 64},
        {"destination", 64},
        {"packet_sequence", 32},
        {"status", hls_type:width(Status)},
        {"active", 1},
        {"fault", 1}
    ].

%% Missing link IDs produce an invalid response without inventing a channel or issuing a command.
-spec observation([hls_protocol_domains:crossing()]) -> iodata().
observation(Crossings) ->
    [
        "match channel {\n",
        [
            [
                "u32:",
                n(I),
                " => Observation { known: true,\n",
                [
                    [Name, ": io.", observed(I, Name), ",\n"]
                 || Name <-
                        [
                            "current_source",
                            "current_destination",
                            "generation",
                            "source",
                            "destination",
                            "packet_sequence",
                            "status",
                            "active",
                            "fault"
                        ]
                ],
                "},\n"
            ]
         || #{index := I} <- Crossings
        ],
        "_ => zero!<Observation>(),\n}"
    ].

%% Exact-pair qualification precedes the bind pulse; fence names only the exact channel generation.
-spec commands([hls_protocol_domains:crossing()]) -> iodata().
commands(Crossings) ->
    [
        [
            channel(I),
            "bind_request: bind_enabled && channel == u32:",
            n(I),
            ",\n",
            channel(I),
            "fence: fence_enabled && channel == u32:",
            n(I),
            ",\n",
            channel(I),
            "expected_generation: pair(packet, u32:4),\n"
        ]
     || #{index := I} <- Crossings
    ].

%% Lifecycle observations stay inside the composite; the retained host interface uses framed status.
-spec private_lifecycle(string(), [hls_protocol_domains:domain()]) -> boolean().
private_lifecycle(Name, Domains) ->
    lists:any(
        fun(#{index := I}) ->
            lists:member(
                Name,
                [domain(I) ++ "domain_phase", domain(I) ++ "domain_current"]
            )
        end,
        Domains
    ).

%% An externally visible packet is immutable; this wrapper only connects independently generated units.
-spec wrapper(
    ports(),
    ports(),
    ports(),
    ports(),
    ports(),
    ports(),
    ports(),
    ports(),
    [hls_protocol_domains:crossing()]
) -> iodata().
wrapper(
    Inputs, Outputs, RawInputs, RawOutputs, ParserInputs, ParserOutputs, Commands, Hidden, Crossings
) ->
    Names = [N || {N, _} <- Inputs ++ Outputs],
    true = length(Names) =:= length(lists:usort(Names)),
    [
        "// Mechanical management and domain wiring; no application payload enters management.\n",
        "module protocol_domains_stream(input wire clk,\n",
        lists:join(",\n", [port("input", P) || P <- Inputs] ++ [port("output", P) || P <- Outputs]),
        "\n);\n",
        [[port("wire", P), ";\n"] || P <- Commands ++ Hidden],
        "protocol_domains_stream_raw domains(.clk(clk),\n",
        lists:join(",\n", [connection(N, N) || {N, _} <- RawInputs ++ RawOutputs]),
        "\n);\n",
        "channel_management management(.clk(clk),\n",
        lists:join(
            ",\n",
            [connection(N, observation_binding(N, Crossings)) || {N, _} <- ParserInputs] ++
                [connection(N, N) || {N, _} <- ParserOutputs]
        ),
        "\n);\nendmodule\n"
    ].

%% Current identities come from the domains; binding identities come from the channel's own kernel.
-spec observation_binding(string(), [hls_protocol_domains:crossing()]) -> string().
observation_binding(Name, Crossings) ->
    Bindings = lists:append([
        [
            {observed(I, "current_source"), domain(Source) ++ "domain_current"},
            {observed(I, "current_destination"), domain(Destination) ++ "domain_current"},
            {observed(I, "source"), channel(I) ++ "bound_source_incarnation"},
            {observed(I, "destination"), channel(I) ++ "bound_destination_incarnation"}
        ] ++
            [
                {observed(I, Field), channel(I) ++ Field}
             || Field <-
                    ["generation", "packet_sequence", "status", "active", "fault"]
            ]
     || #{index := I, source_domain := Source, destination_domain := Destination} <- Crossings
    ]),
    proplists:get_value(Name, Bindings, Name).

%% Named struct fields preserve sampled-pin order without introducing behavior.
-spec structure(string(), ports()) -> iodata().
structure(Name, Fields) ->
    ["pub struct ", Name, " {\n", [[N, ": bits[", n(W), "],\n"] || {N, W} <- Fields], "}\n"].

%% Atom encoding is derived from the exact emitted kernel record type.
-spec literal(atom(), hls_type:descriptor()) -> iodata().
literal(Value, Descriptor) ->
    Width = hls_type:width(Descriptor),
    <<Bits:Width>> = hls_type:pack(Value, Descriptor),
    ["uN[", n(Width), "]:", n(Bits)].

%% Numeric build identities never depend on application atom spelling.
-spec channel(non_neg_integer()) -> string().
channel(Index) -> "ch_" ++ n(Index) ++ "_".

%% Domain indices address independent physical interfaces.
-spec domain(non_neg_integer()) -> string().
domain(Index) -> "domain_" ++ n(Index) ++ "_".

%% Parser observation names cannot collide with external stream pins.
-spec observed(non_neg_integer(), string()) -> string().
observed(Index, Name) -> "observed_" ++ channel(Index) ++ Name.

%% Decimal text is confined to checked widths and indices.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).

%% Scalar wires preserve ordinary ready/valid spelling.
-spec port(string(), {string(), pos_integer()}) -> iodata().
port("wire", {Name, 1}) -> ["wire ", Name];
port("wire", {Name, Width}) -> ["wire [", n(Width - 1), ":0] ", Name];
port(Direction, {Name, 1}) -> [Direction, " wire ", Name];
port(Direction, {Name, Width}) -> [Direction, " wire [", n(Width - 1), ":0] ", Name].

%% Named port connections do not depend on declaration order.
-spec connection(string(), iodata()) -> iodata().
connection(Name, Value) -> [".", Name, "(", Value, ")"].
