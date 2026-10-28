-module(hls_bool).
-moduledoc """
Boolean values: true/false on BEAM, bool in XLS, and one bit on the wire.
Use `not`, `andalso`, `orelse`, guards, and patterns on both targets.

Actor declarations use this provider through hls_type; its transpile callback supplies the XLS form of supported operations.
""".
-behavior(hls_type).
-compile(no_auto_import_types).
%% Application type constructor.
-export([bool/0]).

%% hls_type provider callbacks.
-export([width/2, value_width/2, zero/2, pack/3, unpack/3, print_type/2, transpile/3]).
%% Shared type contracts.
-export_type([bool/0]).

-type bool() :: erlang:boolean().

-spec bool() -> hls_type:descriptor().
bool() -> {hls_type, ?MODULE, bool, []}.

width(bool, []) -> 1.
value_width(bool, []) -> 1.
zero(bool, []) -> false.
pack(false, bool, []) -> <<0:1>>;
pack(true, bool, []) -> <<1:1>>;
pack(_, bool, []) -> error(badarg).
unpack(<<Bit:1, Rest/bitstring>>, bool, []) -> {Bit =:= 1, Rest}.
print_type(bool, []) -> "bool".
-doc "Creates the compile-time Boolean type descriptor.".
-spec transpile(bool, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) ->
    xls_clause_lower:clause_state().
transpile(bool, [], State) ->
    xls_clause_lower:reference(State, {phantom, type, bool()}).
