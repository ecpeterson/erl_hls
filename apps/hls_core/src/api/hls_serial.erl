-module(hls_serial).
-moduledoc """
Wrapping counters with half-range ordering, represented by ordinary integers.

`counter(W)` occupies W bits. Packing, `wrap/2`, and `add/3` reduce modulo
2^W, including negative and arbitrary-precision host integers. `difference/3`
and `before/3` recover temporal order when the actual separation is strictly
less than 2^(W-1); exactly half a range raises `badarg` on BEAM and XLS.
Other violations of the separation bound cannot be detected from the residues.

Use these functions explicitly: ordinary Erlang operators retain their usual
integer semantics. This is not a total order for sorting arbitrary counters.

Actor code calls the arithmetic directly on BEAM. hls_type invokes host codecs; xls_type selects the compiler companion for generated operations.
""".
-behavior(hls_type).
%% Application constructor and serial arithmetic.
-export([counter/1, wrap/2, add/3, difference/3, before/3]).

%% hls_type provider callbacks.
-export([width/2, zero/2, pack/3, unpack/3]).

%% Shared type contracts.
-export_type([counter/1]).

-doc "A normalized W-bit counter; its width is supplied by the type descriptor.".
-type counter(_Width) :: non_neg_integer().

-doc "Creates a positive-width wrapping counter descriptor; invalid widths raise badarg.".
-spec counter(pos_integer()) -> hls_type:descriptor().
counter(Width) when is_integer(Width), Width > 0 ->
    {hls_type, ?MODULE, counter, [Width]};
counter(_) ->
    error(badarg).

-doc "Normalizes an integer modulo the counter's range, including negative values.".
-spec wrap(hls_type:descriptor(), integer()) -> non_neg_integer().
wrap({hls_type, ?MODULE, counter, [Width]}, Value) ->
    hls_codec:wrap_integer(Value, width(counter, [Width]), unsigned).

-doc "Adds a signed integer offset modulo the counter range; returns a normalized counter.".
-spec add(hls_type:descriptor(), integer(), integer()) -> non_neg_integer().
add(Type, Value, Offset) -> wrap(Type, Value + Offset).

-doc """
Returns Left minus Right in the open interval (-2^(W-1), 2^(W-1)).
The caller must keep actual step separations within this bound. An exactly
half-range separation is ambiguous and raises badarg on both targets.
""".
-spec difference(hls_type:descriptor(), integer(), integer()) -> integer().
difference(Type = {hls_type, ?MODULE, counter, [Width]}, Left, Right) ->
    Residue = wrap(Type, Left - Right),
    Half = 1 bsl (Width - 1),
    case Residue of
        Half -> error(badarg);
        _ when Residue < Half -> Residue;
        _ -> Residue - (Half bsl 1)
    end.

-doc "True when Left precedes Right under difference/3's half-range bound; equality is false.".
-spec before(hls_type:descriptor(), integer(), integer()) -> boolean().
before(Type, Left, Right) -> difference(Type, Left, Right) < 0.

-doc "Returns the logical and serialized counter width, rejecting invalid descriptors.".
-spec width(counter, [pos_integer()]) -> pos_integer().
width(counter, [Width]) ->
    _ = counter(Width),
    Width.

-doc "Returns the normalized zero counter.".
-spec zero(counter, [pos_integer()]) -> 0.
zero(counter, Args) ->
    _ = width(counter, Args),
    0.

-doc "Packs the low W bits of an integer in Erlang's little-endian bit syntax; rejects nonintegers.".
-spec pack(term(), counter, [pos_integer()]) -> bitstring().
pack(Value, counter, [Width]) when is_integer(Value) ->
    Normalized = wrap(counter(Width), Value),
    <<Normalized:Width/little-integer>>;
pack(_, counter, _) ->
    error(badarg).

-doc "Decodes one normalized counter and returns the untouched trailing bitstring.".
-spec unpack(bitstring(), counter, [pos_integer()]) -> {non_neg_integer(), bitstring()}.
unpack(Packed, counter, Args) ->
    Width = width(counter, Args),
    <<Value:Width/unsigned-little-integer, Rest/bitstring>> = Packed,
    {Value, Rest}.
