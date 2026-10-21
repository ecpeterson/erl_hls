-module(xls_ir_control_dslx).
-moduledoc "Generates source-lowered and reference circuits for finite-width scalar cancellation proofs.".
-export([write/1]).

-doc "Writes fresh DSLX fixture directories for signed/unsigned add/sub/xor and one incorrect predicate. Uses the production classifier and clause lowering; no serialized IR is edited.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    [fixture(Stage, Width, Op, Signed, false) || Width <- [1,2,8,12,32,64,699],
        Op <- ['+', '-', 'bxor'], Signed <- [false, true]],
    fixture(Stage, 32, '+', false, true),
    ok.

%% Every complete result includes the arithmetic value and four equality/inequality predicates.
-spec fixture(file:filename(), pos_integer(), atom(), boolean(), boolean()) -> ok.
fixture(Stage, Width, Op, Signed, Wrong) ->
    Kind = case Signed of true -> "sN"; false -> "uN" end,
    Name = case Wrong of true -> "negative"; false ->
        Kind ++ integer_to_list(Width) ++ "_" ++ atom_to_list(Op) end,
    Dir = filename:join(Stage, Name),
    ok = file:make_dir(Dir),
    Type = [Kind, "[", integer_to_list(Width), "]"],
    Symbol = case Op of '+' -> "+"; '-' -> "-"; 'bxor' -> "^" end,
    Reference = ["let t = a ", Symbol, " b;\n",
        "(t, hls_integer::equal(t, a), hls_integer::equal(a, t), ",
        "!hls_integer::equal(t, a), !hls_integer::equal(a, t))"],
    Body = "T = A " ++ atom_to_list(Op) ++ " B, Alias = T, {T, T =:= A, A =:= Alias, T =/= A, A =/= Alias}",
    SourceType = ["hls_nums:", Kind, "(", integer_to_list(Width), ")"],
    Spec = lists:flatten(["-spec f(", SourceType, ", ", SourceType, ") -> {",
        SourceType, ", boolean(), boolean(), boolean(), boolean()}."]),
    [_, {function, _, _, _, [Clause]}] = xls_comparison:prepare([parse(Spec), parse("f(A, B) -> " ++ Body ++ ".")]),
    #{body := Statements, result := Result} = xls_parse:clause_outcome(Clause, ["a", "b"], state, #{}),
    Candidate = case Wrong of false -> xls_parse:print([Statements, Result]); true ->
        ["let t = a + b; (t, !hls_integer::equal(b, u1:0), hls_integer::equal(b, u1:0), ",
            "!hls_integer::equal(b, u1:0), !hls_integer::equal(b, u1:0))"] end,
    ok = file:write_file(filename:join(Dir, "reference.x"), module(Type, Reference), [exclusive]),
    ok = file:write_file(filename:join(Dir, "candidate.x"), module(Type, Candidate), [exclusive]),
    file:write_file(filename:join(Dir, "case.json"), json:encode(#{width => Width, signed => Signed,
        operation => Op, rejecting => Wrong}), [exclusive]).

%% Emit only the final DSLX boundary; expressions above remain structured until this call.
-spec module(iodata(), iodata()) -> iodata().
module(Type, Body) -> ["import hls_integer;\npub fn probe(a: ", Type, ", b: ", Type,
    ") -> (", Type, ", bool, bool, bool, bool) {\n", Body, "\n}\n"].

%% Source terms enter the same preparation path as real compiler inputs.
-spec parse(string()) -> hls_source:form().
parse(Source) -> {ok, Tokens, _} = erl_scan:string(Source), {ok, Form} = erl_parse:parse_form(Tokens), Form.
