-module(hls_logical_dslx).
-export([write/1]).

write(Stage) ->
    ok = file:write_file(filename:join(Stage, "service.x"),
        xls_parse:to_xls("test/hls_logical_fixture.erl")),
    ok = codecs(Stage),
    ok = transactions(Stage).

codecs(Stage) ->
    Types = [hls_bool:bool()] ++ [Type || Width <- [1, 3, 7, 9, 17, 33, 65, 127],
        Type <- [hls_nums:uN(Width), hls_nums:sN(Width)]] ++
        [hls_vec:vector(hls_vec:vector(hls_nums:sN(5), 2), 4),
         hls_vec:vector(hls_bool:bool(), 4)],
    Values = lists:usort([0, 1, 2, 3, 7, 15, 16, 127, 128, 255,
        16#0807060504030201, 16#fedcba9876543210] ++
        [(1 bsl N) + Offset || N <- [9, 17, 33, 65, 127], Offset <- [-1, 0, 1]] ++
        [(1 bsl 128) - 1]),
    Cases = [{Kind, Raw, normalized(Type, Raw)} || {Kind, Type} <- lists:enumerate(0, Types),
        Raw <- Values],
    Body = ["pub fn probe(raw: bits[128], kind: u8) -> bits[128] {\n match kind {\n",
        [io_lib:format("  u8:~B => { let decoded = ~s; (~s) as bits[128] },\n",
            [Kind, hls_type:dslx_from_bits(Type, ["raw[0+:",
                "bits[", integer_to_list(hls_type:width(Type)), "]]"]),
             hls_type:dslx_to_bits(Type, "decoded")])
            || {Kind, Type} <- lists:enumerate(0, Types)],
        "  _ => bits[128]:0,\n }\n}\n",
        "#[test]\nfn host_wire_vectors() {\n",
        [io_lib:format(" assert_eq(probe(bits[128]:~B, u8:~B), bits[128]:~B);\n",
            [Raw, Kind, Expected]) || {Kind, Raw, Expected} <- Cases], "}\n"],
    ok = file:write_file(filename:join(Stage, "codecs.x"), Body),
    ok = file:write_file(filename:join(Stage, "codecs.mem"),
        [io_lib:format("~2.16.0b ~32.16.0b ~32.16.0b\n", [Kind, Raw, Expected])
            || {Kind, Raw, Expected} <- Cases]).

normalized(Type, Raw) ->
    Width = hls_type:width(Type),
    {Value, <<>>} = hls_type:unpack(<<Raw:Width/little>>, Type),
    binary:decode_unsigned(hls_type:pack(Value, Type), little).

transactions(Stage) ->
    Requests = [{read, 0}] ++ lists:append([
        [{step, true, N rem 8, hls_nums:wrap(hls_nums:sN(9), N * 137)},
         {step, false, 7, -256}, {read, 0},
         {bundle, [true, N rem 2 =:= 0, false, true],
            [[-16, 15], [-1, hls_nums:wrap(hls_nums:sN(5), N)], [0, 1], [7, -8]]}]
        || N <- lists:seq(0, 127)]) ++ [{reset, 0}, {read, 0}],
    {_, Inputs, Outputs, _} = lists:foldl(fun(Request, {State, In, Out, Tx}) ->
        {Next, Reply} = case element(1, Request) of
            reset -> {noreply, Updated} = hls_logical_fixture:handle_cast(Request, State),
                {Updated, none};
            _ -> {reply, Response, Updated} = hls_logical_fixture:handle_call(Request, State),
                {Updated, Response}
        end,
        %% Noncanonical padding is ignored on both sides. Vary it without
        %% changing the logical input, also on signed negative values.
        Raw = case Request of
            {step, _, _, _} when Tx rem 2 =:= 1 ->
                <<A, B, C, D>> = hls_logical_fixture:pack(Request),
                <<(A bor 16#fe), (B bor 16#f8), C, (D bxor 16#fe)>>;
            _ -> hls_logical_fixture:pack(Request)
        end,
        Expected = case Reply of none -> []; _ -> frame(Reply, Tx) end,
        {Next, [In, frame(element(1, Request), Raw, Tx)], [Out, Expected], (Tx + 1) rem 256}
    end, {hls_logical_fixture:init([]), [], [], 0}, Requests),
    ok = file:write_file(filename:join(Stage, "requests.mem"), Inputs),
    ok = file:write_file(filename:join(Stage, "replies.mem"), Outputs).

frame(Message, Tx) -> frame(element(1, Message), hls_logical_fixture:pack(Message), Tx).
frame(Tag, Packed, Tx) ->
    Words = [Word || <<Word:32/little>> <= Packed],
    Header = (hls_logical_fixture:pack_tag(Tag) bsl 24) bor (Tx bsl 8) bor length(Words),
    [io_lib:format("~9.16.0b\n", [Word bor case Last of true -> 1 bsl 32; false -> 0 end])
        || {Word, Last} <- [{Header, false}] ++
            [{Word, I =:= length(Words)} || {I, Word} <- lists:enumerate(Words)]].
