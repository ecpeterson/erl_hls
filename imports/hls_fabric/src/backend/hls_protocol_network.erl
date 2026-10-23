-module(hls_protocol_network).
-moduledoc "Connects ordinary DSLX owners and source-bound transport with declared startup messages. Host commands enter ordinary inbox slots; application admission remains separate.".
-export([write/2]).

-doc "Builds a sampled-clock DSLX network from hls_protocol_transport's trusted fresh-source config. Connects ordinary owners, whole entry batches, captures, declared startup and optional rectangle host input. Host commands retire only on source consume; malformed accepted commands fault until reset. Optional activation => explicit_start holds internal receives until a registered start handshake. Startup and host setup continue while stopped; start requires their consumption, no offered host command and no observed fault. Setup requiring internal feedback belongs after start. automatic is the default. inspection => process exposes a passive addressed metadata port; none is the default. native_actors selects a nonempty proper subset and exposes canonical raw crossing ports, retaining global identities. These require common clock/reset, ordered lossless delivery and stable offers until handshake; no framed network or independent reset protocol is supplied. Process inspection with a partition is currently rejected. arithmetic_groups selects disjoint source-compatible native scalar-completion groups through the fresh transport builder; omitted groups keep local completion. Each group has one combinational source callback and a round-robin cursor, feeding the existing registered owner action. External streams have no cross-source order. Returns an executable manifest with capacity/progress eligibility false. Requires a fresh directory; failed builds retain partial output.".
-spec write(map(),file:filename()) -> map().
write(Config,Output) ->
    Activation = activation(maps:get(activation,Config,automatic)),
    Inspection = hls_protocol_inspection:mode(maps:get(inspection,Config,none)),
    case {maps:is_key(native_actors,Config),Inspection} of
        {true,process}->error(partition_inspection_unavailable);
        _->ok
    end,
    Plan = hls_protocol_transport:write(maps:without([activation,inspection],Config),Output),
    xls_protocol_network:write(Plan#{activation=>Activation,inspection=>Inspection},Output).

%% Reject unknown modes before reading sources or creating a partial output tree.
-spec activation(term()) -> automatic | explicit_start.
activation(automatic) -> automatic;
activation(explicit_start) -> explicit_start;
activation(Other) -> error({unsupported_protocol_activation,Other}).
