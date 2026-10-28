-module(xls_provider_vec).
-moduledoc "Compiler companion for hls_vec. xls_type selects these lowering and rendering callbacks; host operations and wire codecs remain in the runtime provider.".
-behaviour(xls_type).

%% Compiler provider callbacks.
-export([print_type/2, dslx_imports/1, dslx_codec/2, transpile/3]).

-spec print_type(atom(), [hls_type:arg()]) -> xls_dslx:value().
-doc "Renders the provider value type; nested descriptors use compiler dispatch.".
print_type(vector, Args) -> xls_provider_lists:print_type(list, Args).

-spec dslx_imports([atom()]) -> [atom()].
-doc "Declares the DSLX support modules needed by the selected operations and types.".
dslx_imports(Names) ->
    xls_provider_lists:dslx_imports(Names) ++ [hls_vec || lists:member(dot, Names)].

-spec dslx_codec(atom(), [hls_type:arg()]) -> xls_type:codec().
-doc "Converts wire bits and DSLX values using the provider encoding, including nested padding.".
dslx_codec(vector, Args) -> xls_provider_lists:dslx_codec(list, Args).

-doc "Lowers vector descriptors, checked element access and dot products with a static accumulator type.".
-spec transpile(vector | nth | set | dot, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:ir()
    | xls_clause_lower:clause_state()
    | {fallible, badarg, xls_clause_lower:ir()}.
transpile(vector, [{phantom, type, Subtype}, {static, integer, Size}], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_vec:vector(Subtype, Size)});
transpile(nth, Args, State) ->
    xls_provider_lists:transpile(nth, Args, State);
transpile(set, Args, State) ->
    xls_provider_lists:transpile(set, Args, State);
transpile(dot, [{phantom, type, AccumulatorType}, Left, Right], _State) ->
    [
        "hls_vec::dot<u32:",
        integer_to_list(hls_type:value_width(AccumulatorType)),
        ">(",
        Left,
        ", ",
        Right,
        ")"
    ].
