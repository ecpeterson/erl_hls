-module(xls_known_bits_tests).
-moduledoc "Finite known-bit algebra and compiler integration witnesses; these do not prove arbitrary source analyses or temporal behavior.".
-include_lib("eunit/include/eunit.hrl").

%% All 81 canonical four-bit cubes and every admitted operand pair cover the transfer rules.
-spec exhaustive_algebra_test() -> ok.
exhaustive_algebra_test() ->
    Cubes = [{M, V} || M <- lists:seq(0, 15), V <- lists:seq(0, 15), V band M =:= V],
    Type = {hls_type, hls_nums, uN, [4]},
    lists:foreach(fun({M, V}) ->
        A = cube(M, V), Values = members(M, V),
        lists:foreach(fun(X) -> check(bnot(X), xls_known_bits:for_type(xls_known_bits:invert(A), Type)) end, Values),
        lists:foreach(fun({N, W}) ->
            B = cube(N, W),
            lists:foreach(fun(Op) ->
                Bound = xls_known_bits:for_type(xls_known_bits:combine(Op, A, B), Type),
                lists:foreach(fun({X, Y}) -> check(apply(erlang, Op, [X, Y]), Bound) end,
                    [{X, Y} || X <- Values, Y <- members(N, W)])
            end, ['band', 'bor', 'bxor'])
        end, Cubes)
    end, Cubes).

%% Construct a cube through the public algebra, without forging its opaque representation.
-spec cube(non_neg_integer(), non_neg_integer()) -> xls_known_bits:bound().
cube(Mask, Value) ->
    xls_known_bits:combine('bor', xls_known_bits:literal(Value),
        xls_known_bits:combine('band', xls_known_bits:unknown(), xls_known_bits:literal(bnot(Mask)))).

%% Enumerate admitted four-bit values independently from the implementation.
-spec members(non_neg_integer(), non_neg_integer()) -> [non_neg_integer()].
members(Mask, Value) -> [X || X <- lists:seq(0, 15), X band Mask =:= Value].

%% Every asserted fixed bit must agree with concrete Erlang arithmetic.
-spec check(integer(), map()) -> ok.
check(Value, #{mask := Mask, value := Known}) -> ?assertEqual(Known, Value band Mask).

%% Unknown providers and arithmetic do not inherit integer representation assumptions.
-spec unsupported_and_identity_test() -> ok.
unsupported_and_identity_test() ->
    ?assertEqual(#{mask => 0, value => 0}, xls_known_bits:for_type(xls_known_bits:literal(0), hls_nums:float32())),
    Expr = {op, 0, 'band', {var, 0, 'X'}, {integer, 0, 15}},
    ?assertNotEqual(xls_entry_storage:origin(Expr, #{}), xls_entry_storage:origin(Expr, #{})),
    ?assertEqual(#{mask => 31, value => 24},
        xls_known_bits:for_type(xls_known_bits:literal(-8), hls_nums:sN(5))).

%% Actual entry plans store 30 of 58 message bits once for two aliased effects.
-spec compression_and_freshness_test() -> ok.
compression_and_freshness_test() ->
    File = "test/xls_known_bits_fixture.erl",
    {Spec, Facts} = xls_message_facts:from_file(File, []),
    [#{layouts := [#{storage := Storage}]}] = maps:get(entries, Spec),
    ?assertEqual(30, xls_entry_storage:width(Storage)),
    #{effects := [A, B], stores := Stores} = Storage,
    ?assertEqual(maps:get(fields, A), maps:get(fields, B)),
    ?assertEqual(4, length(Stores)),
    [#{fields := Fields}] = maps:get(schemas, xls_message_facts:on_ports(Facts, [first, second])),
    [Opaque] = [F || F = #{name := opaque} <- Fields],
    ?assertMatch(#{domain := unknown}, Opaque),
    ok = xls_message_facts:validate(File, [], Facts),
    {_, Plan} = xls_statem_plan:from_file(File, []),
    ok = xls_statem_plan:validate(File, [], Plan),
    ?assertEqual(xls_statem_codegen:emit(Spec), xls_statem_codegen:emit(element(1, xls_message_facts:from_file(File, [])))).

%% Source execution and its independently generated packer check all frame-bound bits.
-spec frame_bounds_and_failure_test() -> ok.
frame_bounds_and_failure_test() ->
    File = "test/xls_known_bits_fixture.erl",
    {_, Facts} = xls_message_facts:from_file(File, []),
    Bound = xls_message_facts:frame_bits(Facts, [first, second]),
    lists:foreach(fun({V, S, Signed}) ->
        Cell = {cell, V, S, Signed, 1},
        {Cell, Actions} = xls_known_bits_fixture:active(enter, active, Cell),
        lists:foreach(fun({cast, _, Message}) ->
            Stream = xls_known_bits_fixture:pack(Message), N = bit_size(Stream),
            <<Payload:96/little>> = <<Stream/bitstring, 0:(96-N)>>,
            Frame = (Payload bsl 32) bor (xls_known_bits_fixture:pack_tag(packet) bsl 24) bor 2,
            check(Frame, Bound)
        end, Actions)
    end, [{V, S, Signed} || V <- [0, 1, 16#1234, 16#ffff], S <- lists:seq(0,31), Signed <- lists:seq(-16,15)]),
    ?assertError(badarith, xls_known_bits_fixture:active(enter, active, {cell, 1, 0, 0, 0})).

%% Aliases intersect partial masks and finite literals; an unknown producer clears the bound.
-spec aliased_port_join_test() -> ok.
aliased_port_join_test() ->
    {ok, Original} = file:read_file("test/xls_known_bits_fixture.erl"),
    File = filename:join("_build", "known_bits_join_" ++ integer_to_list(erlang:unique_integer([positive])) ++ ".erl"),
    Cases = [{"Cell#cell.value", unknown},
        {"16#8040", {16#f0d0, 16#8040}},
        {"(Cell#cell.value band 16#00ff) bor 16#8000", {16#f000, 16#8000}}],
    try
        lists:foreach(fun({Expression, Expected}) ->
            Changed = binary:replace(Original, <<"{cast, second, Alias}">>,
                iolist_to_binary(["{cast, second, Alias#packet{coded = ", Expression, "}}"])),
            ok = file:write_file(File, Changed),
            {_, Facts} = xls_message_facts:from_file(File, []),
            #{schemas := [#{fields := Fields}]} = xls_message_facts:on_ports(Facts, [first, second]),
            [Domain] = [D || #{name := coded, domain := D} <- Fields],
            case Expected of
                unknown -> ?assertEqual(unknown, Domain);
                {Mask, Value} -> ?assertEqual({bits, hls_type:pack(Mask, hls_nums:u16()),
                    hls_type:pack(Value, hls_nums:u16())}, Domain)
            end,
            case Expected of
                unknown -> ok;
                _ ->
                    Bad = Facts#{alternatives := []},
                    ?assertError(stale_message_facts, xls_message_facts:validate(File, [], Bad))
            end
        end, Cases)
    after file:delete(File) end.
