-module(hls_bool).
-moduledoc """
Boolean values: true/false on BEAM, bool in XLS, and one bit on the wire.
Use `not`, `andalso`, `orelse`, guards, and patterns on both targets.
""".
-behavior(hls_type).
-compile(no_auto_import_types).
-export([bool/0, width/2, value_width/2, zero/2, pack/3, unpack/3,
    print_type/2, transpile/3]).
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
transpile(bool, [], State) ->
    xls_parse:reference(State, {phantom, type, bool()}).
