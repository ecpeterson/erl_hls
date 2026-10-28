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
-doc "Renders the fixture wire shape through the built-in compiler provider.".
-spec print_type(vector, []) -> xls_dslx:value().
print_type(vector, []) -> xls_type:print_type(wire()).
-doc "Delegates fixture vector operations through normal compiler provider dispatch.".
-spec transpile(vector | nth | set | dot, [xls_clause_lower:ir()], xls_clause_lower:clause_state()) -> xls_type:result().
transpile(F, Args, Types) -> xls_type:transpile(hls_vec, F, Args, Types).
