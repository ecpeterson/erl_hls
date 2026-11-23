-module(hls_companion_provider).
-moduledoc "Minimal custom type/function provider for companion import and nested codec tests.".
-behaviour(hls_type).

%% Fixture type and saturating arithmetic.
-export([scalar/0, combine/3]).
%% Host codecs and compiler provider callbacks.
-export([width/2, zero/2, pack/3, unpack/3, print_type/2, dslx_imports/0, transpile/3]).
-export_type([scalar/0]).

-doc "Signed 32-bit fixed-point raw value used in the nested record fixture.".
-type scalar() :: hls_fixed:signed(32, 16).

-doc "Constructs the fixture's scalar type.".
-spec scalar() -> hls_type:descriptor().
scalar() -> {hls_type, ?MODULE, scalar, []}.

-doc "Adds three bounded fixed-point raw values, saturating to the scalar range.".
-spec combine(scalar(), scalar(), scalar()) -> scalar().
combine(A, B, C) -> hls_fixed:saturate(hls_fixed:signed(32, 16), A + B + C).

-doc "Returns the scalar wire width.".
-spec width(scalar, []) -> 32.
width(scalar, []) -> 32.

-doc "Returns the scalar zero.".
-spec zero(scalar, []) -> 0.
zero(scalar, []) -> 0.

-doc "Packs one checked scalar using the shared fixed-point codec.".
-spec pack(scalar(), scalar, []) -> bitstring().
pack(Value, scalar, []) -> hls_type:pack(Value, hls_fixed:signed(32, 16)).

-doc "Consumes one scalar and returns the unconsumed stream.".
-spec unpack(bitstring(), scalar, []) -> {scalar(), bitstring()}.
unpack(Bits, scalar, []) -> hls_type:unpack(Bits, hls_fixed:signed(32, 16)).

-doc "Names the custom companion's scalar alias.".
-spec print_type(scalar, []) -> string().
print_type(scalar, []) -> "hls_companion_provider::Scalar".

-doc "Declares the companion needed by this fixture provider.".
-spec dslx_imports() -> [atom()].
dslx_imports() -> [hls_companion_provider].

-doc "Lowers type construction and the fixture's one qualified arithmetic call.".
-spec transpile(atom(), [xls_clause_lower:ir()], xls_clause_lower:clause_state()) -> xls_clause_lower:ir().
transpile(scalar, [], State) ->
    xls_clause_lower:reference(State, {phantom, type, scalar()});
transpile(combine, [A, B, C], _State) ->
    ["hls_companion_provider::combine(", A, ", ", B, ", ", C, ")"].
