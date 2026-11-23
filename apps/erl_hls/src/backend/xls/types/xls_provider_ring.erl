-module(xls_provider_ring).
-moduledoc "Compiler companion for hls_ring. Shared field layouts compose element codecs; the static DSLX library owns bounded cursor operations.".
-behaviour(xls_type).
%% Compiler provider callbacks.
-export([print_type/2, dslx_imports/1, dslx_codec/2, transpile/3]).

-doc "Renders a ring with its concrete element type and static capacity.".
-spec print_type(ring, [hls_type:arg()]) -> xls_dslx:value().
print_type(ring, [T, N]) ->
    _ = hls_ring:ring(T, N),
    ["hls_ring::Ring<", xls_type:print_type(T), ", u32:", integer_to_list(N), ">"].

-doc "Declares the bounded cursor implementation and nested stream codec support.".
-spec dslx_imports([atom()]) -> [atom()].
dslx_imports(_) -> [hls_ring, hls_bits].

-doc "Composes the same field and element codecs as the runtime provider.".
-spec dslx_codec(ring, [hls_type:arg()]) -> xls_type:codec().
dslx_codec(ring, [T, N]) ->
    xls_struct_codec:codec(
        print_type(ring, [T, N]),
        hls_field_layout:layout(hls_ring:fields(T, N), stream)
    ).

-doc "Lowers cursor operations with source-located badarg failures; no scheduling is implicit.".
-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_type:result().
transpile(ring, [{phantom, type, T}, {static, integer, N}], State) ->
    xls_clause_lower:reference(State, {phantom, type, hls_ring:ring(T, N)});
transpile(Name, Args, _State) when
    Name =:= rewind;
    Name =:= at_end;
    Name =:= next;
    Name =:= current;
    Name =:= replace;
    Name =:= full;
    Name =:= begin_insert;
    Name =:= insert_step;
    Name =:= empty;
    Name =:= front;
    Name =:= pop;
    Name =:= append;
    Name =:= back;
    Name =:= replace_back
->
    {fallible, badarg, ["hls_ring::", atom_to_list(Name), "(", lists:join(", ", Args), ")"]}.
