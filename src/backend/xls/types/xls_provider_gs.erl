-module(xls_provider_gs).
-moduledoc "Compiler companion for hls_gs. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([print_type/2]).

-doc "Renders the fixed hardware representation of a retained handle.".
-spec print_type(from, []) -> string().
print_type(from, []) -> "u64".
