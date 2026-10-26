-module(xls_message_bits).
-moduledoc "Known-bit algebra for the ordinary entry frame ABI. Fields are physical stream bitstrings; padding and header construction match hls_bits::frame_payload and axis::pack. Consumers must establish source and route provenance before using a bound.".
-export([frame/2, frame/3, join/1, join_cases/1]).

-doc "Constructs an ordinary emitted-frame bound with the default three-word capacity. Fields are checked physical ABI streams; does not cover arbitrary frames or retained replies.".
-spec frame(hls_nums:u8(), [map()]) -> #{mask := non_neg_integer(), value := non_neg_integer()}.
frame(Tag, Fields) -> frame(Tag, Fields, hls_frame_layout:default()).

-doc "Constructs an emitted-frame bound using the selected capacity. Rejects over-capacity schemas; all header and zero padding bits remain known.".
-spec frame(hls_nums:u8(), [map()], hls_frame_layout:layout()) ->
    #{mask := non_neg_integer(), value := non_neg_integer()}.
frame(Tag, Fields, Layout) ->
    Parts = [field(F) || F <- Fields],
    MaskStream = << <<M/bitstring>> || {M, _} <- Parts >>,
    ValueStream = << <<V/bitstring>> || {_, V} <- Parts >>,
    hls_frame_layout:bounds(Layout, Tag, MaskStream, ValueStream).

-doc "Joins nonempty alternative bounds of the same bit layout, retaining only bits known and equal in every alternative. Values contain zero in unknown positions.".
-spec join([#{mask := non_neg_integer(), value := non_neg_integer()}, ...]) ->
    #{mask := non_neg_integer(), value := non_neg_integer()}.
join([First | Rest]) -> lists:foldl(fun merge/2, First, Rest).

%% Keep stream order until the complete payload is padded and converted to the
%% little-endian numeric DSLX frame representation; sub-byte fields must not be
%% reversed separately or rounded to whole bytes.
-spec field(map()) -> {bitstring(), bitstring()}.
field(#{type := Type, domain := {bits, Mask, Value}}) ->
    N = hls_type:width(Type), N = bit_size(Mask), N = bit_size(Value),
    {Mask, Value};
field(#{type := Type, domain := unknown}) ->
    N = hls_type:width(Type), {<<0:N>>, <<0:N>>};
field(#{type := Type, domain := {values, Values}}) ->
    N = hls_type:width(Type),
    Bound = join([begin N = bit_size(B), <<V:N>> = B,
        #{mask => (1 bsl N) - 1, value => V} end || B <- Values]),
    #{mask := M, value := V} = Bound,
    {<<M:N>>, <<V:N>>}.

%% A bit differing between alternatives is unknown even when both know it.
-spec merge(map(), map()) -> map().
merge(#{mask := A, value := X}, #{mask := B, value := Y}) ->
    M = A band B band bnot(X bxor Y),
    #{mask => M, value => X band M}.

-doc "Joins nonempty producer case sets by physical operation byte. Unknown sources make the complete result unknown; silent sources add no alternatives. Inputs must cover every alias on the consumer lane. A case constrains values only when that operation is emitted, never receiver acceptance.".
-spec join_cases([unknown | [map()], ...]) -> unknown | [map()].
join_cases(Sources = [_ | _]) ->
    case lists:member(unknown, Sources) of
        true -> unknown;
        false ->
            Cases = lists:append(Sources),
            [begin
                Bound = join([maps:with([mask, value], C) || C = #{op := O} <- Cases, O =:= Op]),
                Bound#{op => Op}
            end || Op <- lists:usort([Op || #{op := Op} <- Cases])]
    end.
