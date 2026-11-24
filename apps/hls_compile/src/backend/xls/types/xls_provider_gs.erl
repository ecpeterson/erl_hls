-module(xls_provider_gs).
-moduledoc "Compiler companion for hls_gs. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([print_type/2, transpile/3]).

-doc "Renders the fixed hardware representation of a retained handle.".
-spec print_type(from, []) -> string().
print_type(from, []) -> "u64".

-doc "Lowers the retained-handle type constructor for compound collection descriptors.".
-spec transpile(from, [], xls_clause_lower:clause_state()) -> xls_clause_lower:clause_state().
transpile(from, [], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_gs:from()}).
