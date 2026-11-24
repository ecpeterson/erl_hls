-module(hls_domain_channel_binding).
-moduledoc "Finite binding admission shared by independently clocked endpoints. This pure helper validates a host proposal; it neither observes the peer nor grants transport authority. Scalar arguments keep the imported hardware function independent of record namespaces.".

%% Imported and endpoint helpers must use the same ordered atom codec.
-include_lib("hls_runtime/include/hls_domain_channel_endpoints.hrl").

%% Shared source-compiled identity rule.
-export([advance/8]).

-doc "Accepts a strictly later generation in the retained nonzero namespace only when both incarnations advance. Gaps permit reconciliation after only one endpoint consumed a prior bind. Zero identities reject and generation exhaustion never wraps. Returns accepted, invalid, stale or exhausted using the common endpoint-status codec. Cold-reset namespace exclusion is external.".
-spec advance(
    hls_nums:u64(),
    hls_nums:u64(),
    hls_nums:u64(),
    hls_nums:u64(),
    hls_nums:u64(),
    hls_nums:u64(),
    hls_nums:u64(),
    hls_nums:u64()
) -> ?HLS_DOMAIN_ENDPOINT_STATUS.
advance(
    Namespace,
    Generation,
    Source,
    Destination,
    OldNamespace,
    OldGeneration,
    OldSource,
    OldDestination
) ->
    case Namespace =/= 0 andalso Source =/= 0 andalso Destination =/= 0 of
        false ->
            invalid;
        true ->
            case
                (OldNamespace =:= 0 orelse Namespace =:= OldNamespace) andalso
                    Source > OldSource andalso Destination > OldDestination
            of
                false ->
                    stale;
                true ->
                    case OldGeneration =:= ((1 bsl 64) - 1) of
                        true ->
                            exhausted;
                        false ->
                            case Generation > OldGeneration of
                                true -> accepted;
                                false -> stale
                            end
                    end
            end
    end.
