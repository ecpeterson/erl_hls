-module(hls_protocol_network).
-moduledoc "Connects ordinary DSLX owners and source-bound transport with declared startup messages. Host ingress and application admission remain separate.".
-export([write/2]).

-doc "Builds a complete sampled-clock network from the same trusted fresh-source config as hls_protocol_transport:write/2. Connects whole entry batches, capture selection and delayed release using the existing component state. Delivers declared startup records through the ordinary inbox; rejects host ingress rather than silently omitting it. External outputs remain separate ready/valid streams; they have no cross-source order. Returns the generated network manifest, with capacity/progress eligibility false. Requires a fresh directory; failed builds retain partial output.".
-spec write(map(),file:filename()) -> map().
write(Config,Output) ->
    Plan = #{bundle := #{topology := Topology}} = hls_protocol_transport:write(Config,Output),
    case maps:get(ingresses,Topology) of
        [] -> ok;
        _ -> error({unsupported_network_boundary,ingresses})
    end,
    xls_protocol_network:write(Plan,Output).
