-module(hls_protocol_network).
-moduledoc "Connects ordinary DSLX owners and source-bound transport with declared startup messages. Host commands enter ordinary inbox slots; application admission remains separate.".
-export([write/2, emit/3]).
-export_type([result/0]).

-doc "The emitted network manifest and its unchanged transport descriptor. Consumers retain the descriptor in memory rather than reading transport.etf back.".
-type result() :: #{network := map(), transport := map()}.

-doc "Builds a sampled-clock DSLX network from hls_protocol_transport's trusted fresh-source config. Connects ordinary owners, whole entry batches, captures, declared startup and optional rectangle host input. Host commands retire only on source consume; malformed accepted commands fault until reset. Optional activation => explicit_start holds internal receives until a registered start handshake. Startup and host setup continue while stopped; start requires their consumption, no offered host command and no observed fault. Setup requiring internal feedback belongs after start. automatic is the default. inspection => process exposes a passive addressed metadata port; none is the default. native_actors selects a nonempty proper subset and exposes canonical raw crossing ports, retaining global identities. These require common clock/reset, ordered lossless delivery and stable offers until handshake; no framed network or independent reset protocol is supplied. Process inspection with a partition is currently rejected. arithmetic_groups selects disjoint source-compatible native scalar-completion groups through the fresh transport builder; omitted groups keep local completion. Each group has one combinational source callback and a round-robin cursor, feeding the existing registered owner action. External streams have no cross-source order. Returns an executable manifest with capacity/progress eligibility false. Requires a fresh directory; failed builds retain partial output.".
-spec write(map(),file:filename()) -> map().
write(Config,Output) ->
    Options = #{inspection := Inspection} = modes(maps:with([activation, inspection], Config)),
    ok = inspection(maps:is_key(native_actors, Config), Inspection),
    #{network := Network} = emit(hls_protocol_transport:plan(Config), Options, Output),
    Network.

-doc "Emits a planned transport and composes its source receivers into a network. Config supplies activation and inspection only; source and placement are already fixed in Build. Returns named network/transport descriptors. Requires the unchanged in-process plan and a fresh directory; partial I/O failures are retained.".
-spec emit(hls_protocol_transport:build(), map(), file:filename()) -> result().
emit(Build,Config,Output) ->
    #{activation := Activation, inspection := Inspection} = modes(Config),
    #{fabric := Fabric} = hls_protocol_transport:descriptor(Build),
    ok = inspection(maps:is_key(crossings, Fabric), Inspection),
    Plan = hls_protocol_transport:emit(Build,Output),
    Network = xls_protocol_network:write(Plan#{activation=>Activation,inspection=>Inspection},Output),
    #{transport => Plan, network => Network}.

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
