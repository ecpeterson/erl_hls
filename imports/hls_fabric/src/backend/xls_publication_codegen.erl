-module(xls_publication_codegen).
-moduledoc "Shares payloads whose equality is established by compact entry-effect storage.".
-export([plan/1, helpers/1]).

-doc "Finds homogeneous batches with identical stored fields and only constant-field differences. Unrecognized layouts remain serial.".
-spec plan(map()) -> map().
plan(Spec = #{entries := Entries}) ->
    Layout = maps:get(frame_layout, Spec, hls_frame_layout:default()),
    Layouts = lists:append([Ls || #{layouts := Ls} <- Entries]),
    Shared = lists:filtermap(fun(L) -> shared_layout(L, Layout) end, Layouts),
    Mask = lists:foldl(fun(#{values := Values}, Acc) ->
        [Base | _] = Values,
        lists:foldl(fun(Value, M) -> M bor (Value bxor Base) end, Acc, Values)
    end, 0, Shared),
    Positions = [Bit || Bit <- lists:seq(0, hls_frame_layout:frame_bits(Layout) - 1), Mask band (1 bsl Bit) =/= 0],
    #{positions => Positions, layouts => Shared}.

%% Equality requires the same tag and matching field type/storage provenance.
-spec shared_layout(map(), hls_frame_layout:layout()) -> false | {true, map()}.
shared_layout(#{layout := Id, storage := #{effects := [First, _ | _] = Effects}}, Layout) ->
    case lists:all(fun(Effect) -> compatible(First, Effect) end, Effects) of
        true -> {true, #{layout => Id, values => [constant_frame(E, Layout) || E <- Effects]}};
        false -> false
    end;
shared_layout(_, _) -> false.

%% Constants may vary; every live field must reuse the identical stored slice.
-spec compatible(map(), map()) -> boolean().
compatible(#{tag := Tag, fields := Left}, #{tag := Tag, fields := Right}) ->
    length(Left) =:= length(Right) andalso
        lists:all(fun({A, B}) -> same_field(A, B) end, lists:zip(Left, Right));
compatible(_, _) -> false.

%% Type identity prevents confusing equally wide but differently encoded values.
-spec same_field(map(), map()) -> boolean().
same_field(#{name := N, type := T, constant := _}, #{name := N, type := T, constant := _}) -> true;
same_field(#{name := N, type := T, offset := O}, #{name := N, type := T, offset := O}) -> true;
same_field(_, _) -> false.

%% Match the record's physical bitstream, frame word padding and low wire header.
%% Dynamic fields are zero only for calculating differences between equal values.
-spec constant_frame(map(), hls_frame_layout:layout()) -> non_neg_integer().
constant_frame(#{fields := Fields}, Layout) ->
    Stream = << <<(field_bits(F))/bitstring>> || F <- Fields >>,
    %% Equal-tag batches share the same header; only payload differences survive XOR.
    hls_frame_layout:pack_integer(Layout, 0, Stream).

%% The entry storage planner already serialized constants with the field codec.
-spec field_bits(map()) -> bitstring().
field_bits(#{constant := Bits}) -> Bits;
field_bits(#{type := Type}) -> <<0:(hls_type:width(Type))>>.

-doc "Emits narrow constant patches and a lossless frame reconstructor for shared scheduler publication.".
-spec helpers(map()) -> iodata().
helpers(Spec) ->
    #{positions := Positions, layouts := Layouts} = plan(Spec),
    Width = max(1, length(Positions)),
    ["// Only constant differences are retained separately from the common frame.\n",
     "pub type PublicationPatch = bits[", n(Width), "];\n",
     "// The flag establishes equality of every frame bit outside the patch.\n",
     "pub fn publication_patch(scheduled: ScheduledEffects, index: u8) -> (PublicationPatch, bool) {\n",
     "  match scheduled.effects.layout {\n",
     [["    u8:", n(Id), " => match index {\n",
       [["      u8:", n(I), " => (PublicationPatch:", n(compact(Value, Positions)), ", true),\n"]
        || {I, Value} <- lists:enumerate(0, Values)],
       "      _ => (PublicationPatch:0, false),\n    },\n"]
      || #{layout := Id, values := Values} <- Layouts],
     "    _ => (PublicationPatch:0, false),\n  }\n}\n\n",
     "// Apply the selected constant-field difference; all other bits are unchanged.\n",
     "pub fn publication_frame(base: axis::Frame, difference: PublicationPatch) -> axis::Frame {\n",
     "  let raw = axis::bits_from_frame(base);\n",
     "  axis::frame_from_bits(raw ^ (", lists:join(" | ", ["bits[axis::FRAME_BITS]:0" |
       [["(((difference >> u32:", n(I), ") as u1) as bits[axis::FRAME_BITS]) << u32:", n(Bit)]
        || {I, Bit} <- lists:enumerate(0, Positions)]]), "))\n}\n\n"].

%% Gather only the union of varying bits, in ascending physical-bit order.
-spec compact(non_neg_integer(), [non_neg_integer()]) -> non_neg_integer().
compact(Value, Positions) ->
    lists:foldl(fun({I, Bit}, Acc) -> Acc bor (((Value bsr Bit) band 1) bsl I) end,
        0, lists:enumerate(0, Positions)).

%% Render nonnegative constants in the generated DSLX.
-spec n(non_neg_integer()) -> string().
n(Value) -> integer_to_list(Value).
