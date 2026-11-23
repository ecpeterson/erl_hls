-module(hls_shape_type_fixture).
-behavior(hls_type).
-include("hls_shape_type_config.hrl").
-export_type([vector/0]).
-export([vector/0, width/2, zero/2, pack/3, unpack/3, print_type/2, transpile/3]).

%% The bounded scalar element used by the custom shape provider.
-type element() :: hls_nums:u32().
%% A two-element logical vector whose element type is supplied by the caller.
-type pair(E) :: hls_vec:vector(E, ?SHAPE_COUNT).
-doc "The fixture's fixed-size logical vector descriptor.".
-type vector() :: pair(element()).

-doc "The fixture's fixed-size logical vector descriptor.".
-spec vector() -> hls_type:descriptor().
vector() -> {hls_type, ?MODULE, vector, []}.
%% Returns the separately configured wire shape used by mismatch witnesses.
-spec wire() -> hls_type:descriptor().
wire() -> hls_vec:vector(hls_nums:u32(), ?WIRE_COUNT).
-doc "Returns the packed width of the supported fixture type.".
-spec width(vector, []) -> non_neg_integer().
width(vector, []) -> hls_type:width(wire()).
-doc "Returns the canonical zero value of the supported fixture type.".
-spec zero(vector, []) -> [non_neg_integer()].
zero(vector, []) -> hls_type:zero(wire()).
-doc "Encodes a checked fixture value at its declared packed width.".
-spec pack([non_neg_integer()], vector, []) -> bitstring().
pack(Value, vector, []) -> hls_type:pack(Value, wire()).
-doc "Decodes one fixture value and returns the unused suffix.".
-spec unpack(bitstring(), vector, []) -> {[non_neg_integer()], bitstring()}.
unpack(Bits, vector, []) -> hls_type:unpack(Bits, wire()).
-doc "Renders the fixture's logical type as a DSLX type expression.".
-spec print_type(vector, []) -> iodata().
print_type(vector, []) -> hls_type:print_type(wire()).
-doc "Lowers the fixture provider's typed operation into the checked expression IR.".
-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) -> xls_clause_lower:ir().
transpile(F, Args, Types) -> hls_vec:transpile(F, Args, Types).
