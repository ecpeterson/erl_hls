-module(hls_protocol_domain).
-moduledoc """
Compiles one closed source-protocol network behind a reset/incarnation boundary.
The runtime lifecycle kernel is ordinary Erlang compiled through its own
service adapter. This composer adds physical completion observations and
whole-network gates, not another lifecycle algorithm. Instantiate separate emitted
cores for independent domains; crossing links require a separate recovery policy.
""".

%% Checked source composition and portable external-tool input.
-export([emit/1, emit/2, write/2, write_stream/2]).
-export_type([result/0, codecs/0]).

-doc "Retained lifecycle field descriptors resolved from the compiled kernel; host codecs need no compiler or source lookup.".
-type codecs() :: #{
    operation := hls_type:descriptor(),
    phase := hls_type:descriptor(),
    status := hls_type:descriptor(),
    action := hls_type:descriptor(),
    fault := hls_type:descriptor()
}.

-doc "Named clock ports and the exact underlying network. This boundary establishes neither native fit nor distributed progress.".
-type result() :: #{
    network := hls_protocol_network:manifest(),
    stream => hls_domain_stream:plan(),
    transport => map(),
    runtime_interface => map(),
    inputs := [{string(), pos_integer()}],
    outputs := [{string(), pos_integer()}],
    codecs := codecs(),
    frame_payload_words := hls_frame_layout:words(),
    startup := silent_source_initialization,
    fence := no_future_external_transfer,
    eligible := false
}.

-doc "Renders a closed whole-network recovery domain. Requires rectangle ingress, automatic network execution, no crossing placement and no declared startup messages. Initialization may not publish effects; an attempted setup publication fails closed in hardware. Readiness waits for successful init/entry/internal callbacks. Application incarnation identities gate ingress; egress is tagged by the current incarnation. Accepted prior output is irrevocable. This first composition uses at least ten frame payload words for the compiled control adapter; no host framing or distributed reset is implied.".
-spec emit(hls_source_config:network() | file:filename()) -> hls_generated_files:output(result()).
emit(Config) -> compose(Config, raw).

-doc "Renders the raw domain and optionally retains checked framed actor bindings for a surrounding composer. The stream mode checks unique addressed ingress and external ports without introducing a second actor network.".
-spec emit(hls_source_config:network() | file:filename(), raw | stream) ->
    hls_generated_files:output(result()).
emit(Config, Mode) -> compose(Config, Mode).

%% Framed endpoints add addressing restrictions only when explicitly requested.
-spec compose(hls_source_config:network() | file:filename(), raw | stream) ->
    hls_generated_files:output(result()).
compose(Config0, Mode) when is_map(Config0) ->
    Config = hls_source_config:validate(network, Config0#{
        frame_payload_words => max(10, maps:get(frame_payload_words, Config0, 3))
    }),
    automatic = maps:get(activation, Config, automatic),
    false = maps:is_key(native_actors, Config),
    Build = hls_protocol_transport:plan(Config),
    #{bundle := #{topology := #{startup := []}}} = hls_protocol_transport:descriptor(Build),
    Framing =
        case Mode of
            raw -> #{};
            stream -> #{stream => hls_domain_stream:bind(hls_protocol_transport:descriptor(Build))}
        end,
    NetworkPlan = hls_protocol_network:plan(Build, #{activation => automatic, inspection => none}),
    #{files := NetworkFiles, result := #{network := Network}} = hls_protocol_network:emit(
        NetworkPlan
    ),
    #{
        native_indices := Actors,
        ingress := Ingress,
        inputs := NetworkInputs,
        outputs := NetworkOutputs
    } = Network,
    true = Ingress =/= none,
    Words = maps:get(frame_payload_words, Config),
    Source = hls_source:library_file(hls_runtime, "runtime/hls_domain_lifecycle.erl"),
    Codecs = codecs(Source),
    Controller = xls_parse:to_artifact(Source, #{frame_payload_words => Words}),
    {Inputs, Outputs} = ports(NetworkInputs, NetworkOutputs, Codecs),
    Files = hls_generated_files:merge([
        NetworkFiles,
        hls_generated_files:prefix("domain", xls_emitted:dependencies(Controller)),
        #{
            "domain/domain_controller.x" => xls_emitted:bytes(Controller),
            "domain/domain_codes.x" => constants(Codecs),
            "domain/domain.x" => render(Actors, Inputs, Outputs, NetworkInputs, NetworkOutputs),
            "domain/protocol_domain.sv" => sv_protocol_ports:emit(
                Inputs,
                Outputs,
                "protocol_domain",
                "protocol_domain_core"
            )
        }
    ]),
    #{
        files => Files,
        result => Framing#{
            network => Network,
            inputs => Inputs,
            outputs => Outputs,
            codecs => Codecs,
            frame_payload_words => Words,
            startup => silent_source_initialization,
            fence => no_future_external_transfer,
            eligible => false
        }
    };
compose(Filename, Mode) ->
    compose(hls_source_config:read(Filename), Mode).

-doc "Writes a fresh portable domain source bundle for the ordinary external XLS driver. Source compilation precedes output creation; support snapshot or I/O failures retain partial evidence. No simulation, synthesis or hardware attachment runs here.".
-spec write(hls_source_config:network() | file:filename(), file:filename()) -> map().
write(Config, Directory) -> write_bundle(Config, Directory, raw).

-doc "Writes the closed network with independent framed management/application lanes and retained runtime actor schemas. Ordinary source calls use bounded reply slots; the generated endpoint preserves incarnation admission and output-retirement order without simulator protocol logic.".
-spec write_stream(hls_source_config:network() | file:filename(), file:filename()) -> map().
write_stream(Config, Directory) -> write_bundle(Config, Directory, stream).

%% Both entry points retain the same raw domain; only the selected physical endpoint differs.
-spec write_bundle(hls_source_config:network() | file:filename(), file:filename(), raw | stream) ->
    map().
write_bundle(Config, Directory, Mode) ->
    Generated = #{result := Result = #{frame_payload_words := Words}} = compose(Config, Mode),
    {Extra, StreamInfo} =
        case Mode of
            raw ->
                {#{}, #{}};
            stream ->
                #{files := SF} = SG = hls_domain_stream:emit(Result),
                {SF, maps:without([files], SG)}
        end,
    Final = Generated#{files := hls_generated_files:merge([maps:get(files, Generated), Extra])},
    _ = hls_generated_files:write(Final, Directory),
    #{libraries := Libraries, imports := Support} = hls_build_support:layout([]),
    ok = hls_artifact_bundle:snapshot(Directory, Libraries),
    ok = hls_compile:configure_support(Directory, hls_frame_layout:new(Words)),
    Profile = hls_build_profile:owner(hls_frame_layout:new(Words)),
    Unit = #{
        role => <<".">>,
        directory => <<"domain">>,
        source => <<"domain/domain.x">>,
        top => <<"domain_clock">>,
        module => <<"protocol_domain_core">>,
        output => <<"domain/core.v">>,
        dslx_path => [
            unicode:characters_to_binary(P)
         || P <-
                ["domain", "network", "actors", "dslx" | Support]
        ],
        codegen_flags => hls_build_profile:flags(Profile, sampled_clock),
        rtl => [<<"domain/core.v">>, <<"domain/protocol_domain.sv">>]
    },
    Runtime =
        case Mode of
            raw ->
                Result;
            stream ->
                maps:merge(maps:get(stream, Result), #{
                    codecs => maps:get(codecs, Result),
                    frame_payload_words => Words,
                    transport => StreamInfo
                })
        end,
    ok = file:write_file(filename:join(Directory, "domain/interface.etf"), term_to_binary(Runtime)),
    Selected =
        case Mode of
            raw ->
                Unit;
            stream ->
                Unit#{
                    source := <<"domain/domain_stream.x">>,
                    top := <<"domain_stream_clock">>,
                    module := <<"domain_stream_core">>,
                    output := <<"domain/stream_core.v">>,
                    rtl := [<<"domain/stream_core.v">>, <<"domain/domain_stream.sv">>]
                }
        end,
    hls_artifact_bundle:finish(Directory, [Selected], #{kind => domain, backend => source_protocol}).

%% Public management is separate from the incarnation-tagged application input.
-spec ports([xls_protocol_network:packed_port()], [xls_protocol_network:packed_port()], codecs()) ->
    {[{string(), pos_integer()}], [{string(), pos_integer()}]}.
ports(Inputs, Outputs, Codecs) ->
    Management = [
        {"reset", 1},
        {"transport_fault", 1},
        {"management_valid", 1},
        {"management_op", hls_type:width(maps:get(operation, Codecs))},
        {"expected", 64},
        {"target", 64},
        {"transition", 64},
        {"management_fault", hls_type:width(maps:get(fault, Codecs))},
        {"incarnation", 64}
    ],
    Status = [
        {"management_response_valid", 1},
        {"management_ready", 1},
        {"domain_status", hls_type:width(maps:get(status, Codecs))},
        {"domain_action", hls_type:width(maps:get(action, Codecs))},
        {"domain_phase", hls_type:width(maps:get(phase, Codecs))},
        {"domain_current", 64},
        {"domain_previous", 64},
        {"domain_target", 64},
        {"domain_transition", 64},
        {"domain_fault", hls_type:width(maps:get(fault, Codecs))},
        {"domain_source_fault", 16},
        {"domain_source_actor", 32},
        {"domain_admission", 1},
        {"domain_initialized", 1},
        {"domain_rejected", 1}
    ],
    {
        Management ++
            [{binary_to_list(N), W} || #{name := N, width := W} <- Inputs, N =/= <<"reset">>],
        Status ++ [{"app_" ++ binary_to_list(N), W} || #{name := N, width := W} <- Outputs]
    }.

%% Heterogeneous actor fields are the only template specialization; transitions stay compiled Erlang.
-spec render(
    [non_neg_integer()],
    [{string(), pos_integer()}],
    [{string(), pos_integer()}],
    [xls_protocol_network:packed_port()],
    [xls_protocol_network:packed_port()]
) -> binary().
render(Actors, Inputs, Outputs, NetworkInputs, NetworkOutputs) ->
    {ok, Template} = file:read_file(
        filename:join(
            code:priv_dir(hls_lowering),
            "xls/templates/protocol_domain.x.in"
        )
    ),
    xls_template:render(Template, [
        {<<"@@IMPORTS@@">>, [["import receiver_", integer_to_list(I), ";\n"] || I <- Actors]},
        {<<"@@INPUTS@@">>, structure("Inputs", Inputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", Outputs)},
        {<<"@@NETWORK_INPUTS@@">>, [
            network_input(binary_to_list(N), W)
         || #{name := N, width := W} <- NetworkInputs, N =/= <<"reset">>
        ]},
        {<<"@@NETWORK_OUTPUTS@@">>, [
            network_output(binary_to_list(N), W)
         || #{name := N, width := W} <- NetworkOutputs
        ]},
        {<<"@@INITIALIZED@@">>,
            lists:join(" && ", [
                [
                    "receiver_",
                    integer_to_list(I),
                    "::local_inbox_initialized(s.network.actor_",
                    integer_to_list(I),
                    ", reset_network)"
                ]
             || I <- Actors
            ])},
        {<<"@@SETUP_OUTPUT@@">>,
            lists:join(" || ", [
                [
                    "s.network.actor_",
                    integer_to_list(I),
                    ".owner.outbox.index < s.network.actor_",
                    integer_to_list(I),
                    ".owner.outbox.count"
                ]
             || I <- Actors
            ])},
        {<<"@@FAULT_ACTOR@@">>,
            lists:foldr(
                fun(I, Rest) ->
                    Name = "net.output.actor_" ++ integer_to_list(I) ++ "_failure",
                    ["if ", Name, " != u16:0 { u32:", integer_to_list(I), " } else { ", Rest, " }"]
                end,
                "u32:0",
                Actors
            )},
        {<<"@@FAULT@@">>,
            lists:foldr(
                fun(I, Rest) ->
                    Name = "net.output.actor_" ++ integer_to_list(I) ++ "_failure",
                    ["if ", Name, " != u16:0 { ", Name, " } else { ", Rest, " }"]
                end,
                "u16:0",
                Actors
            )}
    ]).

%% Resolve the actual record layouts once at source composition, retaining self-contained codecs.
-spec codecs(file:filename()) -> codecs().
codecs(Source) ->
    {ok, Parsed} = hls_source:parse_file(Source),
    Forms = hls_records:resolve(Parsed),
    Input = maps:from_list(hls_records:fields(hls_records:find(Forms, domain_input))),
    Output = maps:from_list(hls_records:fields(hls_records:find(Forms, domain_output))),
    State = maps:from_list(hls_records:fields(hls_records:find(Forms, domain_state))),
    Fault = maps:get(fault, Input),
    Fault = maps:get(fault, State),
    #{
        operation => maps:get(op, Input),
        phase => maps:get(phase, State),
        status => maps:get(status, Output),
        action => maps:get(action, Output),
        fault => Fault
    }.

%% Public constants let the boundary and finite formal fixture share the kernel's atom encodings.
-spec constants(codecs()) -> iodata().
constants(Codecs) ->
    [
        [
            "// Codes for ",
            atom_to_list(Kind),
            ", resolved from the source record type.\n",
            "pub const ",
            string:uppercase(atom_to_list(Kind)),
            "_COUNT = u32:",
            integer_to_list(length(Members)),
            ";\n",
            [constant(Kind, Member, Descriptor) || Member <- Members]
        ]
     || {Kind, Descriptor = {hls_type, hls_enum, enum, [Members]}} <- lists:sort(
            maps:to_list(Codecs)
        )
    ].

%% Packing delegates member order and width to the ordinary host type provider.
-spec constant(atom(), atom(), hls_type:descriptor()) -> iodata().
constant(Kind, Member, Descriptor) ->
    Width = hls_type:width(Descriptor),
    <<Code:Width>> = hls_type:pack(Member, Descriptor),
    Name = string:uppercase(atom_to_list(Kind) ++ "_" ++ atom_to_list(Member)),
    ["pub const ", Name, " = uN[", integer_to_list(Width), "]:", integer_to_list(Code), ";\n"].

%% Struct declaration order also defines the shared sampled-port packing.
-spec structure(string(), [{string(), pos_integer()}]) -> iodata().
structure(Name, Fields) ->
    [
        "pub struct ",
        Name,
        " {\n",
        [[N, ": bits[", integer_to_list(W), "],\n"] || {N, W} <- Fields],
        "}\n"
    ].

%% Commands require a matching incarnation; downstream readiness is closed during replacement.
-spec network_input(string(), pos_integer()) -> iodata().
network_input("ingress_valid", _) ->
    "ingress_valid: admitted && io.ingress_valid,\n";
network_input(Name, Width) ->
    Value =
        case lists:suffix("_ready", Name) of
            true -> ["if ready { io.", Name, " } else { bits[", integer_to_list(Width), "]:0 }"];
            false -> ["io.", Name]
        end,
    [Name, ": ", Value, ",\n"].

%% Stale ingress is consumed only at this envelope boundary, never by the actor network.
-spec network_output(string(), pos_integer()) -> iodata().
network_output("ingress_ready", _) ->
    "app_ingress_ready: !io.reset && (!admitted || net.output.ingress_ready),\n";
network_output(Name, Width) ->
    [
        "app_",
        Name,
        ": if ready { net.output.",
        Name,
        " } else { bits[",
        integer_to_list(Width),
        "]:0 },\n"
    ].
