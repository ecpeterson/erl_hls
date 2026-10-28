-module(xls_provider_type).
-moduledoc "Compiler companion for hls_type. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([transpile/3]).

-doc "Lowers a type ascription; rejects host-only normalization and exact-packing operations.".
-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:ir().
transpile(as, [{phantom, type, Descriptor}, Value], _State) ->
    ["(", Value, " as ", xls_type:print_type(Descriptor), ")"];
transpile(Operation, _Args, _State) when
    Operation =:= normalize;
    Operation =:= pack_exact
->
    error({host_only_type_operation, Operation}).
