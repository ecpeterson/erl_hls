-module(xls_publication_codegen_tests).
-include_lib("eunit/include/eunit.hrl").

%% A partial-byte constant crosses a byte boundary in the dense wire record.
-spec dense_constant_patch_test() -> ok.
dense_constant_patch_test() ->
    Effects = [effect([live(key, 3, 0), constant(member, 7, V), live(value, 11, 3)])
        || V <- [1, 17, 9]],
    #{positions := Positions, layouts := [#{values := Values}]} =
        xls_publication_codegen:plan(spec([layout(0, Effects)])),
    ?assertEqual([33, 34], Positions),
    %% ERTS writes the three key bits before the seven member bits, then value.
    ?assertEqual([(V bsl 32) bor 1 || V <- [16#4000, 16#4004, 16#4002]], Values).

%% The member field uses its packed little-endian bytes, including beyond byte 0.
-spec multibyte_constant_patch_test() -> ok.
multibyte_constant_patch_test() ->
    Effects = [effect([live(key, 32, 0), constant(member, 16, V), live(value, 3, 32)])
        || V <- [1, 257]],
    #{positions := [72], layouts := [#{values := Values}]} =
        xls_publication_codegen:plan(spec([layout(0, Effects)])),
    ?assertEqual([(1 bsl 64) bor 2, (257 bsl 64) bor 2], Values).

%% Empty records still carry their tag, and identical frames need no patch bits.
-spec empty_message_batch_test() -> ok.
empty_message_batch_test() ->
    #{positions := [], layouts := [#{values := [0, 0]}]} =
        xls_publication_codegen:plan(spec([layout(0, [effect([]), effect([])])])),
    ok.

%% Same widths do not establish equality: field sources, codecs and tags matter.
-spec unequal_sources_stay_serial_test() -> ok.
unequal_sources_stay_serial_test() ->
    A = effect([live(key, 32, 0), constant(member, 8, 1)]),
    Variants = [effect([live(key, 32, 32), constant(member, 8, 2)]),
        effect([constant(key, 32, 0), constant(member, 8, 2)]),
        A#{tag := another},
        effect([#{name => key, type => hls_nums:s32(), offset => 0}, constant(member, 8, 2)])],
    lists:foreach(fun(B) ->
        ?assertEqual(#{positions => [], layouts => []},
            xls_publication_codegen:plan(spec([layout(0, [A, B])])))
    end, Variants).

%% Empty, singleton and heterogeneous layouts must coexist with shared ones.
-spec serial_fallback_and_union_test() -> ok.
serial_fallback_and_union_test() ->
    A = effect([constant(member, 8, 1)]),
    B = effect([constant(member, 8, 3)]),
    C = effect([constant(member, 8, 5)]),
    Plan = xls_publication_codegen:plan(spec([layout(0, []), layout(1, [A]),
        layout(2, [A, B]), layout(3, [A, C])])),
    ?assertEqual([33, 34], maps:get(positions, Plan)),
    ?assertEqual([2, 3], [Id || #{layout := Id} <- maps:get(layouts, Plan)]).

%% Construct the same checked effect-storage shapes passed to the backend.
-spec spec([map()]) -> map().
spec(Layouts) -> #{entries => [#{layouts => Layouts}]}.

%% Retain only the layout identity and lossless field-storage description.
-spec layout(non_neg_integer(), [map()]) -> map().
layout(Id, Effects) -> #{layout => Id, storage => #{effects => Effects}}.

%% Output port does not affect frame equality; recipient conflicts are checked later.
-spec effect([map()]) -> map().
effect(Fields) -> #{tag => message, port => output, fields => Fields}.

%% Represent one previously evaluated typed field at a compact storage offset.
-spec live(atom(), pos_integer(), non_neg_integer()) -> map().
live(Name, Width, Offset) -> #{name => Name, type => hls_nums:uN(Width), offset => Offset}.

%% Use the independent ERTS codec, including dense partial-byte packing.
-spec constant(atom(), pos_integer(), non_neg_integer()) -> map().
constant(Name, Width, Value) ->
    Type = hls_nums:uN(Width),
    #{name => Name, type => Type, constant => hls_type:pack(Value, Type)}.
