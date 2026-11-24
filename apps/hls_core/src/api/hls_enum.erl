-module(hls_enum).
-moduledoc """
Finite atom values with a compact wire encoding. Source record and helper types
use ordinary atom unions; hls_records resolves them to this provider. Member
order in the declaration determines codes starting at zero. The first member
is the zero/default value. Reordering members changes the encoding contract.

Host codecs reject unlisted atoms and unused codes. XLS retains the encoded
bits, including unused codes, so ordinary wildcard clauses can reject malformed
hardware input without constructing an invalid target-language enum.
""".
-behaviour(hls_type).

%% Explicit descriptors for host codecs and retained layout metadata.
-export([enum/1]).
%% hls_type provider callbacks.
-export([width/2, zero/2, pack/3, unpack/3]).

-doc "Builds a descriptor for a nonempty ordered set of distinct atoms.".
-spec enum([atom(), ...]) -> hls_type:descriptor().
enum(Members) ->
    case
        Members =/= [] andalso lists:all(fun is_atom/1, Members) andalso
            length(lists:usort(Members)) =:= length(Members)
    of
        true -> {hls_type, ?MODULE, enum, [Members]};
        false -> error({invalid_hls_enum, Members})
    end.

-doc "Returns the smallest positive width that holds every member code.".
-spec width(enum, [[atom(), ...]]) -> pos_integer().
width(enum, [Members]) ->
    _ = enum(Members),
    max(1, bit_width(length(Members) - 1)).

%% Count bits without floating point at a representation boundary.
-spec bit_width(non_neg_integer()) -> non_neg_integer().
bit_width(0) -> 0;
bit_width(N) -> 1 + bit_width(N bsr 1).

-doc "Returns the first declared member, whose wire encoding is zero.".
-spec zero(enum, [[atom(), ...]]) -> atom().
zero(enum, [Members = [First | _]]) ->
    _ = enum(Members),
    First.

-doc "Packs a listed atom; unlisted atoms and nonatoms are rejected.".
-spec pack(atom(), enum, [[atom(), ...]]) -> bitstring().
pack(Value, enum, [Members]) ->
    Width = width(enum, [Members]),
    case lists:keyfind(Value, 1, lists:zip(Members, lists:seq(0, length(Members) - 1))) of
        {Value, Code} -> <<Code:Width>>;
        false -> error({invalid_hls_enum_value, Value, Members})
    end.

-doc "Decodes one atom and retains trailing bits; unused integer codes are rejected.".
-spec unpack(bitstring(), enum, [[atom(), ...]]) -> {atom(), bitstring()}.
unpack(Bits, enum, [Members]) ->
    Width = width(enum, [Members]),
    <<Code:Width, Rest/bitstring>> = Bits,
    case Code < length(Members) of
        true -> {lists:nth(Code + 1, Members), Rest};
        false -> error({invalid_hls_enum_code, Code, Members})
    end.
