-module(hls_protocol_network).
-moduledoc "Connects ordinary DSLX owners and source-bound transport with declared startup messages. Host commands enter ordinary inbox slots; application admission remains separate.".
-export([write/2, write/3, emit/1, emit/2]).
-export_type([result/0]).

-doc "The emitted network manifest and its unchanged transport descriptor. Consumers retain the descriptor in memory rather than reading transport.etf back.".
-type result() :: #{network := map(), transport := map()}.

-doc "Builds a sampled-clock DSLX network from hls_protocol_transport's trusted fresh-source config. Connects ordinary owners, whole entry batches, captures, declared startup and optional rectangle host input. Host commands retire only on source consume; malformed accepted commands fault until reset. Optional activation => explicit_start holds internal receives until a registered start handshake. Startup and host setup continue while stopped; start requires their consumption, no offered host command and no observed fault. Setup requiring internal feedback belongs after start. automatic is the default. inspection => process exposes a passive addressed metadata port; none is the default. native_actors selects a nonempty proper subset and exposes canonical raw crossing ports, retaining global identities. These require common clock/reset, ordered lossless delivery and stable offers until handshake; no framed network or independent reset protocol is supplied. Process inspection with a partition is currently rejected. arithmetic_groups selects disjoint source-compatible native scalar-completion groups through the fresh transport builder; omitted groups keep local completion. Each group has one combinational source callback and a round-robin cursor, feeding the existing registered owner action. External streams have no cross-source order. Returns an executable manifest with capacity/progress eligibility false. Requires a fresh directory. Generation failures create no output; I/O failures retain partial output.".
-spec write(map() | file:filename(), file:filename()) -> map().
write(Config, Directory) ->
    #{network := Network} = hls_generated_files:write(emit(Config), Directory),
    Network.

-doc "Writes emit/2's planned network to a fresh directory and returns its named network/transport result. Generation precedes output creation; I/O failures retain partial output.".
-spec write(hls_protocol_transport:build(), map(), file:filename()) -> result().
write(Build, Options, Directory) ->
    hls_generated_files:write(emit(Build, Options), Directory).

-doc "Generates a network bundle without writing output. Accepts a trusted source config map or a filename containing one map; source paths remain relative to the caller. Preparation loads sources and invokes their trusted constructors. Returns relative filenames with IO data and named network/transport descriptors.".
-spec emit(map() | file:filename()) -> hls_generated_files:output().
emit(Config) when is_map(Config) ->
    Options = #{inspection := Inspection} = modes(maps:with([activation, inspection], Config)),
    ok = inspection(maps:is_key(native_actors, Config), Inspection),
    emit(hls_protocol_transport:plan(Config), Options);
emit(Filename) -> emit(hls_source_config:read(Filename)).

-doc "Generates a planned transport and connected network without writing output or rereading source. Options supplies activation and inspection only; the unchanged in-process Build fixes sources and placement. Returns relative filenames with IO data and named network/transport descriptors. Template reads remain.".
-spec emit(hls_protocol_transport:build(), map()) -> hls_generated_files:output().
emit(Build, Options) ->
    #{activation := Activation, inspection := Inspection} = modes(Options),
    #{fabric := Fabric} = hls_protocol_transport:descriptor(Build),
    ok = inspection(maps:is_key(crossings, Fabric), Inspection),
    #{files := TransportFiles, result := Plan} = hls_protocol_transport:emit(Build),
    #{files := NetworkFiles, result := Network} =
        xls_protocol_network:emit(Plan#{activation => Activation, inspection => Inspection}, TransportFiles),
    #{files => hls_generated_files:merge([TransportFiles, NetworkFiles]),
      result => #{transport => Plan, network => Network}}.

%% Check configuration before source work, then check the actual cut at the emission boundary.
-spec inspection(boolean(), none | process) -> ok.
inspection(true, process) -> error(partition_inspection_unavailable);
inspection(_, _) -> ok.

%% Reject renderer options that could imply changing the already planned source or placement.
-spec modes(map()) -> #{activation := automatic | explicit_start, inspection := none | process}.
modes(Options) ->
    case maps:keys(maps:without([activation, inspection], Options)) of
        [] -> ok;
        Unknown -> error({unsupported_network_options, lists:sort(Unknown)})
    end,
    #{activation => activation(maps:get(activation, Options, automatic)),
      inspection => hls_protocol_inspection:mode(maps:get(inspection, Options, none))}.

%% Reject unknown modes before reading sources or creating a partial output tree.
-spec activation(term()) -> automatic | explicit_start.
activation(automatic) -> automatic;
activation(explicit_start) -> explicit_start;
activation(Other) -> error({unsupported_protocol_activation,Other}).
