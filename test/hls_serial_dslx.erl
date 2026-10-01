-module(hls_serial_dslx).
-moduledoc "BEAM-derived vectors for serial arithmetic and a public wrapping-counter service.".
-export([write/1]).

-doc "Writes semantic probes, exhaustive small-width RTL vectors, and actor transactions.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    lists:foreach(fun(W) -> write_width(Stage, W) end, [1, 3, 8, 9, 32, 64, 65]),
    write_actor(Stage).

%% Keep interpreted/JIT cases bounded; exhaust byte inputs in the RTL testbench.
-spec write_width(file:filename(), pos_integer()) -> ok.
write_width(Stage, W) ->
    OW = 4 * (W + 1),
    Bounds = boundaries(W),
    Cases = case W =< 8 of
        true -> [{A, B} || A <- lists:seq(0, (1 bsl W) - 1),
            B <- lists:seq(0, (1 bsl W) - 1)] ++ Bounds;
        false -> Bounds ++ [{N * 137 rem (1 bsl W), N * 193 rem (1 bsl W)}
            || N <- lists:seq(0, 255)]
    end,
    Source = ["import hls_serial;\nimport hls_failure;\n",
        [operation(Op, W) || Op <- [add, difference, before, wrap]],
        io_lib:format("pub fn probe(x: sN[~B], y: uN[~B]) -> bits[~B] {\n"
            " let (a, af) = op_add(x, y);\n let (d, df) = op_difference(x, y);\n"
            " let (b, bf) = op_before(x, y);\n let (w, wf) = op_wrap(x, y);\n"
            " a ++ (af as u1) ++ d ++ (df as u1) ++ b ++ (bf as u1) ++ w ++ (wf as u1)\n}\n",
            [W + 2, W + 1, OW]),
        literal(W),
        "#[test]\nfn beam_boundaries() {\n let cases = [\n",
        [io_lib:format(" (sN[~B]:~B, uN[~B]:~B, bits[~B]:~B),\n",
            [W + 2, A, W + 1, B, OW, oracle(W, A, B)]) || {A, B} <- Bounds],
        io_lib:format(
            " ];\n for (i, ()): (u32, ()) in u32:0..u32:~B {\n"
            "  let (a, b, expected) = cases[i];\n assert_eq(probe(a, b), expected);\n } (())\n}\n",
            [length(Bounds)])],
    Prefix = filename:join(Stage, "serial" ++ integer_to_list(W)),
    ok = file:write_file(Prefix ++ ".x", Source),
    ok = file:write_file(Prefix ++ ".mem", [
        io_lib:format("~*.16.0b\n", [(W + 2 + W + 1 + OW + 3) div 4,
            ((A band ((1 bsl (W + 2)) - 1)) bsl (W + 1 + OW)) bor
                (B bsl OW) bor oracle(W, A, B)]) || {A, B} <- Cases]),
    ok = file:write_file(Prefix ++ ".count", integer_to_list(length(Cases))).

%% Lower real Erlang provider calls; no hand-written stand-in for transpilation.
-spec operation(atom(), pos_integer()) -> iolist().
operation(Op, W) ->
    Args = case Op of wrap -> "X"; _ -> "X, Y" end,
    Source = lists:flatten(io_lib:format("probe(X, Y) -> "
        "hls_serial:~s(hls_serial:counter(~B), ~s).", [Op, W, Args])),
    #{body := Body, result := Result, failed := Failed} = outcome(Source, ["x", "y"]),
    [io_lib:format("fn op_~s(x: sN[~B], y: uN[~B]) -> (uN[~B], bool) {\n",
        [Op, W + 2, W + 1, W]), xls_parse:print(Body),
        "let failed = ", xls_parse:print(Failed), ";\n",
        "(if failed { uN[", integer_to_list(W), "]:0 } else { (",
        xls_parse:print(Result), ") as uN[", integer_to_list(W), "] }, failed)\n}\n"].

%% Huge signed constants must normalize before reaching DSLX's literal typer.
-spec literal(pos_integer()) -> iolist().
literal(W) ->
    Value = -(1 bsl 1000) + 7,
    Source = lists:flatten(io_lib:format("probe() -> "
        "hls_serial:add(hls_serial:counter(~B), ~B, -2).", [W, Value])),
    #{body := Body, result := Result} = outcome(Source, []),
    ["#[test]\nfn large_literal() {\n", xls_parse:print(Body),
        io_lib:format("assert_eq(~s, uN[~B]:~B);\n}\n",
            [xls_parse:print(Result), W, hls_serial:add(hls_serial:counter(W), Value, -2)])].

%% Parse one ordinary Erlang clause with supplied hardware argument expressions.
-spec outcome(string(), [xls_parse:printable()]) -> map().
outcome(Source, Arguments) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, {function, _, _, _, [Clause]}} = erl_parse:parse_form(Tokens),
    xls_parse:clause_outcome(Clause, Arguments, state, #{}).

%% Preserve each operation's failure independently; values after failure are ignored.
-spec oracle(pos_integer(), integer(), non_neg_integer()) -> non_neg_integer().
oracle(W, A, B) ->
    Type = hls_serial:counter(W),
    lists:foldl(fun(Op, Acc) ->
        {Value, Failed} = try
            Result = case Op of
                wrap -> hls_serial:wrap(Type, A);
                _ -> hls_serial:Op(Type, A, B)
            end,
            {case Result of true -> 1; false -> 0; _ -> Result end, 0}
        catch error:badarg -> {0, 1}
        end,
        (Acc bsl (W + 1)) bor (((Value band ((1 bsl W) - 1)) bsl 1) bor Failed)
    end, 0, [add, difference, before, wrap]).

%% Exercise both sides of zero/half-range/rollover, including wider signed inputs.
-spec boundaries(pos_integer()) -> [{integer(), non_neg_integer()}].
boundaries(W) ->
    Modulus = 1 bsl W,
    Half = Modulus div 2,
    Values = lists:usort([0, 1, Half - 1, Half, Half + 1, Modulus - 1,
        Modulus, Modulus + 1, 2 * Modulus - 1]),
    [{A, B} || A <- lists:usort([-Modulus - 1, -Modulus, -1 | Values]), B <- Values].

%% Drive the actual framed actor through rollover, skipped faults and recovery.
-spec write_actor(file:filename()) -> ok.
write_actor(Stage) ->
    ok = file:write_file(filename:join(Stage, "service.x"),
        xls_parse:to_xls("test/hls_serial_fixture.erl")),
    Requests = [{inspect, 0, true}, {advance, 1}, {advance, 1}, {advance, 1},
        {inspect, 16#fffffffe, true}, {advance, -3}, {inspect, 1, true},
        {inspect, 16#7ffffffe, false}, {inspect, 16#7ffffffe, true},
        {load, 16#fffffffe}, {advance, 3}, {inspect, 1, true},
        {inspect, 2, true}, {inspect, 0, true}],
    {_, In, Out, _} = lists:foldl(fun(Request, {State, Inputs, Outputs, Tx}) ->
        {Reply, Next} = case element(1, Request) of
            load -> {noreply, Loaded} = hls_serial_fixture:handle_cast(Request, State),
                {none, Loaded};
            _ -> try hls_serial_fixture:handle_call(Request, State) of
                {reply, Response, Updated} -> {Response, Updated}
            catch error:badarg -> {badarg, {clock, 0}}
            end
        end,
        Expected = case Reply of
            none -> [];
            badarg -> frame(1, <<14:32/little>>, Tx);
            _ -> frame(Reply, Tx)
        end,
        {Next, [Inputs, frame(Request, Tx)], [Outputs, Expected], Tx + 1}
    end, {hls_serial_fixture:init([]), [], [], 0}, Requests),
    ok = file:write_file(filename:join(Stage, "requests.mem"), In),
    file:write_file(filename:join(Stage, "replies.mem"), Out).

%% Encode a typed actor message using its generated public packer and wire tag.
-spec frame(tuple(), non_neg_integer()) -> iolist().
frame(Message, Tx) ->
    frame(hls_serial_fixture:pack_tag(element(1, Message)),
        hls_serial_fixture:pack(Message), Tx).

%% Pad only the whole frame, and mark its final payload word with TLAST.
-spec frame(non_neg_integer(), bitstring(), non_neg_integer()) -> iolist().
frame(Tag, Packed, Tx) ->
    Words = [Word || <<Word:32/little>> <= hls_codec:align(Packed, 32)],
    Header = (Tag bsl 24) bor (Tx bsl 8) bor length(Words),
    [io_lib:format("~9.16.0b\n", [Word bor case Last of true -> 1 bsl 32; false -> 0 end])
        || {Word, Last} <- [{Header, false}] ++
            [{Word, I =:= length(Words)} || {I, Word} <- lists:enumerate(Words)]].
