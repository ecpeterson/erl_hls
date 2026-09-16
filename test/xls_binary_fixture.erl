%% BEAM supplies the oracle for construction, matching and exception kinds.
-module(xls_binary_fixture).
-compile([export_all, nowarn_export_all]).
-hls_data(unused).
-hls_tags([]).
-record(unused, {}).

probes() -> [{make, bits}, {mixed, bits}, {literal, bits}, {concat, bits},
    {prefix, bits}, {unit, bits}, {tail, bits}, {empty, bits}, {signed, integer},
    {unsigned, integer}, {bound, integer}, {repeated, integer}, {too_short, integer},
    {too_long, integer}, {assignment, integer}, {helper, integer}, {helper_miss, integer},
    {guard, integer}, {impossible_literal, integer}, {negative_literal, integer},
    {same_bits, integer}, {different_bits, integer}, {bad_prefix, bits},
    {bad_binary, bits}, {skipped_failure, bits}, {first_failure, bits},
    {zero_segment_failure, bits}, {constant_size, bits}, {zero_match, integer},
    {overlong_tail, integer}, {aligned_tail, bits}, {unaligned_tail, integer}, {sizes, integer}, {size_guard, integer}, {wire, bits}, {constant_value, bits},
    {string_unit, bits}, {constant_pattern, integer}].

make(X, _) -> <<X:3, 5:5, X:16/little>>.
mixed(X, _) -> <<X:5/signed-little, X:9/little, X:10>>.
literal(_, _) -> <<"AB", $C, -1:3, 1024:5>>.
concat(X, B) -> <<X:3, B/binary, 0:5>>.
prefix(_, B) -> <<B:2/binary>>.
unit(_, B) -> <<B:3/binary-unit:5>>.
tail(_, B) -> <<_:3, Rest/bitstring>> = B, Rest.
empty(_, B) -> <<_:24, Rest/binary>> = B, Rest.
signed(_, B) -> <<_:3, V:13/signed-little, _:8>> = B, hls_type:as(hls_nums:s32(), V).
unsigned(_, B) -> <<_:3, V:13/little, _:8>> = B, hls_type:as(hls_nums:s32(), V).
bound(X, B) -> case B of <<X:8, _:16>> -> X; _ -> hls_type:as(hls_nums:s32(), -42) end.
repeated(_, B) -> case B of
    <<V:8/signed, V:16/signed-little>> -> hls_type:as(hls_nums:s32(), V);
    _ -> hls_type:as(hls_nums:s32(), -42)
end.
too_short(X, B) -> case B of <<_:32>> -> X; _ -> hls_type:as(hls_nums:s32(), -42) end.
too_long(X, B) -> case B of <<_:8>> -> X; _ -> hls_type:as(hls_nums:s32(), -42) end.
assignment(X, B) -> <<X:8, _:16>> = B, X.
helper(_, B) -> decode(B).
helper_miss(_, B) -> only_magic(B).
guard(X, B) -> guarded(B, X).
impossible_literal(X, B) -> case B of <<256:8, _:16>> -> X; _ -> hls_type:as(hls_nums:s32(), -42) end.
negative_literal(X, B) -> case B of <<-1:8, _:16>> -> X; _ -> hls_type:as(hls_nums:s32(), -42) end.
same_bits(X, B) -> <<A:12/bits, A:12/bits>> = B, X.
different_bits(X, B) -> <<A:8/bits, A:16/bits>> = B, X.
bad_prefix(_, B) -> <<B:4/binary>>.
bad_binary(_, B) -> <<_:3, Tail/bits>> = B, <<Tail/binary>>.
skipped_failure(X, B) -> case X > 0 of true -> <<B/binary, 0:8>>; false -> <<B:4/binary>> end.
first_failure(X, B) -> _ = hls_type:as(hls_nums:s32(), 1) div X, <<B:4/binary>>.
zero_segment_failure(X, _) -> <<(hls_type:as(hls_nums:s32(), 1) div X):0>>.
constant_size(X, _) -> <<X:(2*8), X:(1 bsl 3)>>.
zero_match(X, B) -> <<0:0/signed, _:24>> = B, X.
overlong_tail(X, B) -> case B of <<_:25, _/bits>> -> X; _ -> hls_type:as(hls_nums:s32(), -42) end.
aligned_tail(_, B) -> <<_:8, Rest/binary>> = B, Rest.
unaligned_tail(X, B) -> case B of <<_:3, _/binary>> -> X; _ -> hls_type:as(hls_nums:s32(), -42) end.

-spec decode(hls_bits:bits(24)) -> hls_nums:s32().
decode(<<5:3, _:5, V:16/signed-little>>) -> hls_type:as(hls_nums:s32(), V);
decode(<<V:24>>) -> hls_type:as(hls_nums:s32(), V).
-spec only_magic(hls_bits:bits(24)) -> hls_nums:s32().
only_magic(<<"ABC">>) -> hls_type:as(hls_nums:s32(), 123).
-spec guarded(hls_bits:bits(24), hls_nums:s32()) -> hls_nums:s32().
guarded(<<A:8, _:16>>, X) when A > 0, X div X =:= 1 -> hls_type:as(hls_nums:s32(), A);
guarded(_, X) -> X.

sizes(_, B) -> <<_:3, Tail/bits>> = B, hls_type:as(hls_nums:s32(), bit_size(Tail) + erlang:byte_size(Tail)).
size_guard(X, B) -> case B of <<_:3, Tail/bits>> when bit_size(Tail) =:= 21 -> X end.

wire(_, Value) -> <<A:3, B:5, C:16/little>> = Value, <<C:16, B:5, A:3>>.
constant_value(_, _) -> <<(1 + 2):3, (1 bsl 100):16, (bnot 5):13/little>>.
string_unit(_, _) -> <<"AB":2/unit:8-little>>.
constant_pattern(X, B) -> case B of <<(1+2):8, _:16>> -> X; _ -> hls_type:as(hls_nums:s32(), -42) end.
