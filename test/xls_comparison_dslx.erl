-module(xls_comparison_dslx).
-moduledoc "BEAM-derived mixed-width comparison probes for interpreter, JIT and RTL.".
-export([write/1]).

-doc "Writes all six comparisons for four signedness pairings at each width pair.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    lists:foreach(fun({W, V}) -> write_pair(Stage, W, V) end,
        [{1, 1}, {3, 8}, {8, 8}, {8, 9}, {32, 8}, {64, 32}, {65, 64}, {128, 65}]),
    write_actor(Stage).

%% Small pairs are exhaustive in RTL; interpreter/JIT use the boundary corpus.
-spec write_pair(file:filename(), pos_integer(), pos_integer()) -> ok.
write_pair(Stage, W, V) ->
    Bounds = [{A, B} || A <- boundaries(W), B <- boundaries(V)],
    Cases = case W + V =< 16 of
        true -> [{A, B} || A <- lists:seq(0, (1 bsl W) - 1), B <- lists:seq(0, (1 bsl V) - 1)];
        false -> Bounds ++ [{N * 137 rem (1 bsl W), N * 193 rem (1 bsl V)} || N <- lists:seq(0, 255)]
    end,
    Functions = [function(W, V, S, T) || S <- [u, s], T <- [u, s]],
    Source = ["import hls_failure;\nimport hls_integer;\n", Functions,
        io_lib:format("pub fn probe(x: bits[~B], y: bits[~B]) -> bits[24] {\n", [W, V]),
        lists:join(" ++ ", [["cmp_", atom_to_list(S), atom_to_list(T), "(x, y)"]
            || S <- [u, s], T <- [u, s]]), "\n}\n",
        "#[test]\nfn beam_boundaries() {\n let cases = [\n",
        [io_lib:format("(bits[~B]:~B, bits[~B]:~B, bits[24]:~B),\n",
            [W, A, V, B, oracle(W, V, A, B)]) || {A, B} <- Bounds],
        io_lib:format(
            "];\n for (i, ()): (u32, ()) in u32:0..u32:~B {\n"
            "let (a,b,expected) = cases[i]; assert_eq(probe(a,b), expected);\n} (())\n}\n",
            [length(Bounds)]), literals(W)],
    Prefix = filename:join(Stage, "cmp_" ++ integer_to_list(W) ++ "_" ++ integer_to_list(V)),
    ok = file:write_file(Prefix ++ ".x", Source),
    ok = file:write_file(Prefix ++ ".mem", [io_lib:format("~*.16.0b\n",
        [(W + V + 24 + 3) div 4, (A bsl (V + 24)) bor (B bsl 24) bor oracle(W, V, A, B)])
        || {A, B} <- Cases]),
    file:write_file(Prefix ++ ".count", integer_to_list(length(Cases))).

%% Run source classification and ordinary expression lowering, not a handwritten
%% stand-in. Casts belong only at the typed inputs; every comparison is Erlang.
-spec function(pos_integer(), pos_integer(), u | s, u | s) -> iolist().
function(W, V, S, T) ->
    Body = lists:flatten(io_lib:format("probe(A, B) -> {~s}.",
        [lists:join(", ", ["A " ++ atom_to_list(Op) ++ " B" || Op <- operators()])])),
    Spec = lists:flatten(io_lib:format("-spec probe(hls_nums:~sN(~B), hls_nums:~sN(~B)) -> {boolean(), boolean(), boolean(), boolean(), boolean(), boolean()}.",
        [S, W, T, V])),
    #{body := Statements, result := Result} = outcome(Spec, Body,
        [io_lib:format("(x as ~sN[~B])", [S, W]), io_lib:format("(y as ~sN[~B])", [T, V])]),
    [io_lib:format("fn cmp_~s~s(x: bits[~B], y: bits[~B]) -> bits[6] {\n", [S, T, W, V]),
        xls_parse:print(Statements), lists:join(" ++ ", [["(", Result, ".", integer_to_list(I), " as u1)"]
            || I <- lists:seq(0, 5)]), "\n}\n"].

%% Constants outside an operand's representable range must not narrow to it.
-spec literals(pos_integer()) -> iolist().
literals(W) ->
    High = 1 bsl W,
    Source = lists:flatten(io_lib:format("probe(A) -> {A < ~B, A > -~B, A =:= ~B, A =/= -~B}.",
        [High, High, High, High])),
    Spec = lists:flatten(io_lib:format("-spec probe(hls_nums:sN(~B)) -> {boolean(), boolean(), boolean(), boolean()}.", [W])),
    #{body := Statements, result := Result} = outcome(Spec, Source, ["x"]),
    ["#[test]\nfn wide_literals() {\nlet x = sN[", integer_to_list(W), "]:0;\n",
        xls_parse:print(Statements), "assert_eq(", Result, ", (true, true, false, true));\n}\n"].

%% Parse a real concrete source signature to classify both arguments.
-spec outcome(string(), string(), [xls_parse:printable()]) -> map().
outcome(Spec, Source, Args) ->
    [_, {function, _, _, _, [Clause]}] = xls_comparison:prepare([form(Spec), form(Source)]),
    xls_parse:clause_outcome(Clause, Args, state, #{}).

%% Parse the single declaration used by each source probe.
-spec form(string()) -> erl_parse:abstract_form().
form(Text) ->
    {ok, Tokens, _} = erl_scan:string(Text),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.

%% Evaluate the comparisons on independently decoded BEAM integers.
-spec oracle(pos_integer(), pos_integer(), non_neg_integer(), non_neg_integer()) -> non_neg_integer().
oracle(W, V, A, B) ->
    lists:foldl(fun({S, T, Op}, Acc) ->
        X = decode(W, S, A), Y = decode(V, T, B),
        Bit = case erlang:Op(X, Y) of true -> 1; false -> 0 end,
        (Acc bsl 1) bor Bit
    end, 0, [{S, T, Op} || S <- [u, s], T <- [u, s], Op <- operators()]).

%% A two's-complement sign bit has negative weight.
-spec decode(pos_integer(), u | s, non_neg_integer()) -> integer().
decode(W, s, Bits) when Bits >= (1 bsl (W - 1)) -> Bits - (1 bsl W);
decode(_, _, Bits) -> Bits.

%% Keep result packing and comparison generation in the same public order.
-spec operators() -> [atom()].
operators() -> ['<', '=<', '>', '>=', '=:=', '=/='].

%% Cover both sign transitions and both ends of the unsigned range.
-spec boundaries(pos_integer()) -> [non_neg_integer()].
boundaries(W) -> lists:usort([0, 1, (1 bsl (W - 1)) - 1, 1 bsl (W - 1), (1 bsl W) - 1]).

%% Exercise classification after real callback/helper rewrites, and the record
%% type whose name previously collided with the callback's Value binding.
-spec write_actor(file:filename()) -> ok.
write_actor(Stage) ->
    ok = file:write_file(filename:join(Stage, "service.x"),
        xls_parse:to_xls("test/xls_comparison_fixture.erl")),
    Requests = [{request, A, B} || A <- [-128, -1, 0, 1, 127], B <- [0, 1, 127, 128, 255, 511]],
    {In, Out, _} = lists:foldl(fun(Request, {Inputs, Outputs, Tx}) ->
        {reply, Reply, _} = xls_comparison_fixture:handle_call(Request, xls_comparison_fixture:init([])),
        {[Inputs, frame(Request, Tx)], [Outputs, frame(Reply, Tx)], Tx + 1}
    end, {[], [], 0}, Requests),
    ok = file:write_file(filename:join(Stage, "requests.mem"), In),
    file:write_file(filename:join(Stage, "replies.mem"), Out).

%% Public codec payloads use the ordinary framed transport's final-word marker.
-spec frame(tuple(), non_neg_integer()) -> iolist().
frame(Message, Tx) ->
    Tag = xls_comparison_fixture:pack_tag(element(1, Message)),
    Packed = hls_codec:align(xls_comparison_fixture:pack(Message), 32),
    Words = [Word || <<Word:32/little>> <= Packed],
    Header = (Tag bsl 24) bor (Tx bsl 8) bor length(Words),
    [io_lib:format("~9.16.0b\n", [Word bor case Last of true -> 1 bsl 32; false -> 0 end])
        || {Word, Last} <- [{Header, false}] ++
            [{Word, I =:= length(Words)} || {I, Word} <- lists:enumerate(Words)]].
