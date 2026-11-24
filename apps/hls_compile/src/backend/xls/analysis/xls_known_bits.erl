-module(xls_known_bits).
-moduledoc "Conservative bitwise facts about evaluated integer values used by xls_entry_storage. A mask marks fixed bits; unsupported operations and providers remain unknown. These facts describe representation opportunities only and never permit removing an evaluation or its failure.".
%% Construct and combine integer facts before storage planning.
-export([unknown/0, literal/1, invert/1, combine/3]).
%% Restrict facts to a provider-declared value width.
-export([for_type/2]).
-export_type([bound/0]).

-doc "An unbounded two's-complement mask/value pair; value is zero outside the mask. Negative masks express known high bits before a resolved integer type clips the result.".
-opaque bound() :: {integer(), integer()}.

-doc "Returns no known bits; used for unsupported expressions and inputs.".
-spec unknown() -> bound().
unknown() -> {0, 0}.

-doc "Records an exact integer without assuming its eventual encoded width.".
-spec literal(integer()) -> bound().
literal(Value) -> {-1, Value}.

-doc "Propagates bitwise complement; no arithmetic or failure claim follows.".
-spec invert(bound()) -> bound().
invert({Mask, Value}) -> {Mask, Mask band bnot (Value)}.

-doc "Propagates band, bor or bxor for evaluated integer operands. Correlations between unknown bits are deliberately ignored.".
-spec combine('band' | 'bor' | 'bxor', bound(), bound()) -> bound().
combine('band', {A, X}, {B, Y}) ->
    Ones = X band Y,
    {Ones bor (A band bnot (X)) bor (B band bnot (Y)), Ones};
combine('bor', {A, X}, {B, Y}) ->
    Ones = X bor Y,
    {Ones bor (A band B band bnot (X) band bnot (Y)), Ones};
combine('bxor', {A, X}, {B, Y}) ->
    Mask = A band B,
    {Mask, (X bxor Y) band Mask}.

-doc "Clips numeric facts to a resolved built-in signed/unsigned integer encoding. Other providers, including floating point, receive no facts. Results use numeric bit order, not ABI stream order.".
-spec for_type(bound(), hls_type:descriptor()) ->
    #{mask := non_neg_integer(), value := non_neg_integer()}.
for_type({Mask, Value}, Type = {hls_type, hls_nums, Name, _}) when
    Name =:= u8;
    Name =:= u16;
    Name =:= u32;
    Name =:= u64;
    Name =:= uN;
    Name =:= s8;
    Name =:= s16;
    Name =:= s32;
    Name =:= s64;
    Name =:= sN
->
    Clipped = Mask band ((1 bsl hls_type:width(Type)) - 1),
    #{mask => Clipped, value => Value band Clipped};
for_type(_Bound, _Type) ->
    #{mask => 0, value => 0}.
