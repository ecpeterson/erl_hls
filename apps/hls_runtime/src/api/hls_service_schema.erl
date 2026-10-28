-module(hls_service_schema).
-moduledoc "Retained service request/reply contracts embedded by hls_pack. CPU adapters and device proxies read BEAM attributes here without source analysis or compiler modules.".
%% Runtime schema lookup.
-export([from_module/1]).
%% Retained service contract.
-export_type([contract/0]).

-doc "Allowed reply tags by call request, plus supported cast tags.".
-type contract() :: #{
    calls := #{atom() => [atom(), ...]},
    casts := [atom()],
    pending_calls => 1..((1 bsl 8) - 1),
    continuations => [atom()]
}.

%% Embedded by hls_pack, so a deployed proxy needs neither source nor compiler
%% analysis. CPU-only modules without the transform retain the ordinary adapter.
-doc "Returns the embedded service contract, or none for an untransformed CPU-only module.".
-spec from_module(module()) -> {ok, contract()} | none.
from_module(Module) ->
    case proplists:get_value(hls_service_contract, Module:module_info(attributes)) of
        [Contract] -> {ok, Contract};
        undefined -> none
    end.
