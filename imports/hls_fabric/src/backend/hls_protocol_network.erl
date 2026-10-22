-module(hls_protocol_network).
-moduledoc "Connects ordinary DSLX owners and source-bound transport for source-initialized networks. Startup messages, host ingress and application admission remain separate.".
-export([write/2]).

-doc "Builds a complete sampled-clock network from the same trusted fresh-source config as hls_protocol_transport:write/2. Connects whole entry batches, capture selection and delayed release without extra storage. Rejects declared startup messages or ingress rather than silently omitting them. External outputs remain separate ready/valid streams; they have no cross-source order. Returns the generated network manifest, with capacity/progress eligibility false. Requires a fresh directory; failed builds retain partial output.".
-spec write(map(),file:filename()) -> map().
write(Config,Output) ->
    Plan = #{bundle := #{topology := Topology}} = hls_protocol_transport:write(Config,Output),
    lists:foreach(fun(Key) ->
        case maps:get(Key,Topology) of
            [] -> ok;
            _ -> error({unsupported_network_boundary,Key})
        end
    end,[startup,ingresses]),
    xls_protocol_network:write(Plan,Output).
