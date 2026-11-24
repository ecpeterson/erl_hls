-module(hls_bool).
-moduledoc """
Boolean values: true/false on BEAM, bool in XLS, and one bit on the wire.
Use `not`, `andalso`, `orelse`, guards, and patterns on both targets.

Actor declarations use this provider through hls_type; the compiler companion supplies the XLS form of supported operations.
""".
-behavior(hls_type).
-compile(no_auto_import_types).
%% Application type constructor.
-export([bool/0]).

%% hls_type provider callbacks.
-export([width/2, value_width/2, zero/2, pack/3, unpack/3]).
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
