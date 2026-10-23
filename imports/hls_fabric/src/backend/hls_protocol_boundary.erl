-module(hls_protocol_boundary).
-moduledoc "Builds one application-facing frame stream per declared external endpoint around a fresh source network.".
-export([write/2]).

-doc "Builds hls_protocol_network from the same trusted config, then merges its independent producer streams by declared external endpoint. Round-robin arbitration holds its chosen producer throughout a stall and preserves per-sender order; there is no cross-sender chronology. Empty endpoints remain invalid; singleton endpoints add no state. Startup/host/start/fault pins pass through unchanged. Requires a fresh directory and at most 256 producers per endpoint; unsupported fan-in retains the completed network without a boundary. Returns a bound manifest with eligibility false. Compilation, application framing and progress admission remain separate.".
-spec write(map(),file:filename()) -> map().
write(Config,Directory) ->
    Network=#{externals:=Externals,boundaries:=Boundaries}=hls_protocol_network:write(Config,Directory),
    Groups=[group(E,Boundaries)||E<-Externals],
    xls_protocol_boundary:write(#{network=>Network,externals=>Groups},Directory).

%% Every producer belongs to one declared endpoint; an unused endpoint needs no arbiter.
-spec group(map(),[map()]) -> map().
group(E=#{index:=I},Boundaries) ->
    Members=[B||B=#{external_index:=J}<-Boundaries,J=:=I],N=length(Members),
    case N=<256 of
        true->E#{members=>Members,index_bits=>max(1,ceil(math:log2(max(1,N)))),
            state_bits=>case N>1 of true->2*max(1,ceil(math:log2(N)))+1;false->0 end};
        false->error({unsupported_external_fanin,I,N})
    end.
