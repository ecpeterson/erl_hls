-module(xls_provider_bool).
-moduledoc "Compiler companion for hls_bool. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([print_type/2, transpile/3]).

-spec print_type(atom(), [hls_type:arg()]) -> xls_dslx:value().
-doc "Renders the provider value type; nested descriptors use compiler dispatch.".
print_type(bool, []) -> "bool".

-doc "Creates the compile-time Boolean type descriptor.".
-spec transpile(bool, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:clause_state().
transpile(bool, [], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_bool:bool()}).
