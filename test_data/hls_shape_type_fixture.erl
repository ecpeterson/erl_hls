-module(hls_shape_type_fixture).
-behavior(hls_type).
-include("hls_shape_type_config.hrl").
-export_type([vector/0]).
-export([vector/0, width/2, zero/2, pack/3, unpack/3, print_type/2, transpile/3]).

-type element() :: hls_nums:u32().
-type pair(E) :: hls_vec:vector(E, ?SHAPE_COUNT).
-type vector() :: pair(element()).

vector() -> {hls_type, ?MODULE, vector, []}.
wire() -> hls_vec:vector(hls_nums:u32(), ?WIRE_COUNT).
width(vector, []) -> hls_type:width(wire()).
zero(vector, []) -> hls_type:zero(wire()).
pack(Value, vector, []) -> hls_type:pack(Value, wire()).
unpack(Bits, vector, []) -> hls_type:unpack(Bits, wire()).
print_type(vector, []) -> hls_type:print_type(wire()).
transpile(F, Args, Types) -> hls_vec:transpile(F, Args, Types).
