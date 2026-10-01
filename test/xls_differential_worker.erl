%% BEAM execution is the oracle; this worker does not interpret the generator's AST.
-module(xls_differential_worker).
-export([main/0]).

main() ->
    [RequestPath] = init:get_plain_arguments(),
    {ok, Bytes} = file:read_file(RequestPath),
    Request = json:decode(Bytes),
    Output = maps:get(<<"output">>, Request),
    Result = try prepare(Request)
    catch Class:Reason:Stack ->
        #{status => error, class => Class, reason => text(Reason), stack => text(Stack),
            location => location(Stack)}
    end,
    ok = file:write_file(Output, json:encode(Result)),
    halt().

prepare(#{<<"source">> := Source, <<"dslx">> := Dslx, <<"cases">> := Cases}) ->
    case compile:file(binary_to_list(Source), [binary, return_errors, return_warnings]) of
        {ok, Module, Beam, _Warnings} ->
            {module, Module} = code:load_binary(Module, binary_to_list(Source), Beam),
            Results = [oracle(Module, Case) || Case <- Cases],
            lower(Source, Dslx, Cases, Results);
        Error -> #{status => invalid_source, reason => text(Error)}
    end.

lower(Source, Dslx, Cases, Results) ->
    {ok, Forms0} = epp:parse_file(binary_to_list(Source), [], []),
    Roots = [{binary_to_existing_atom(maps:get(<<"name">>, C)), 3} || C <- Cases],
    {Forms, Helpers} = xls_helpers:prepare(Forms0, Roots),
    Declarations = ["enum Tag : u8 { STATE = 1 }\n",
        xls_dslx_imports:emit([hls_failure, hls_bits], xls_dslx_imports:from_forms(Forms)),
        [[xls_parse:struct_from_record(Record), xls_parse:bitsfromstruct_from_record(Record)]
            || Record = {attribute, _, record, _} <- Forms]],
    Functions = [function(Case, Forms) || Case <- Cases],
    ok = file:write_file(Dslx, [Declarations, xls_helpers:emit(Helpers, state, #{}),
        Functions, dispatcher(Cases), [test(C, R) || {C, R} <- lists:zip(Cases, Results)]]),
    #{status => ok, cases => Results}.

oracle(Module, #{<<"name">> := Name, <<"width">> := Width,
        <<"signed">> := Signed, <<"inputs">> := Inputs}) ->
    Function = binary_to_existing_atom(Name),
    Values = [begin
        [X, Y, A, B, C] = [integer(V, Width, Signed) || V <- Input],
        try apply(Module, Function, [X, Y, [A, B, C]]) of
            Value when is_integer(Value) -> Value band ((1 bsl Width) - 1);
            Value -> error({noninteger_oracle_result, Value})
        catch
            error:{badmatch, _} -> 2 bsl 32;
            error:{case_clause, _} -> 4 bsl 32;
            error:function_clause -> 1 bsl 32;
            error:if_clause -> 5 bsl 32;
            error:badarith -> 13 bsl 32;
            error:badarg -> 14 bsl 32
        end
    end || Input <- Inputs],
    #{name => Name, expected => Values}.

integer(Value, Width, true) when Value >= (1 bsl (Width - 1)) -> Value - (1 bsl Width);
integer(Value, _Width, _Signed) -> Value.

function(#{<<"name">> := Name, <<"width">> := Width, <<"signed">> := Signed}, Forms) ->
    [Clause] = xls_parse:find_function(Forms, binary_to_existing_atom(Name), 3),
    #{body := Body, result := Value, failure := Failure} =
        xls_parse:clause_outcome(Clause, ["x", "y", "values"], state, #{}),
    Type = type(Width, Signed),
    ["fn ", Name, "(x: ", Type, ", y: ", Type, ", values: ", Type, "[3]) -> bits[36] {\n",
        xls_parse:print(Body), "let code = ", xls_parse:print(Failure), ";\n",
        "(hls_failure::kind(code) as u4) ++ ",
        "if code != hls_failure::NONE { u32:0 } else { (",
        xls_parse:print(Value), " as uN[", integer_to_list(Width), "]) as u32 }\n}\n"].

dispatcher(Cases) ->
    ["pub fn probe(mode: u32, x: u32, y: u32, a: u32, b: u32, c: u32) -> bits[36] {\n",
        "match mode {\n", [begin
            Type = type(W, S),
            ["u32:", integer_to_list(I), " => ", N, "(x as ", Type, ", y as ", Type,
                ", [a as ", Type, ", b as ", Type, ", c as ", Type, "]),\n"]
        end || {I, #{<<"name">> := N, <<"width">> := W, <<"signed">> := S}} <- lists:enumerate(0, Cases)],
        "_ => bits[36]:0\n}\n}\n"].

test(#{<<"name">> := Name, <<"inputs">> := Inputs, <<"width">> := Width,
        <<"signed">> := Signed}, #{expected := Expected}) ->
    Type = type(Width, Signed),
    ["#[test]\nfn check_", Name, "() {\nlet cases = [\n",
        [["(", lists:join(", ", [["u32:", integer_to_list(V)] || V <- Input]),
            ", bits[36]:", integer_to_list(Value), "),\n"]
            || {Input, Value} <- lists:zip(Inputs, Expected)],
        "];\nfor (i, ()): (u32, ()) in u32:0..u32:", integer_to_list(length(Inputs)), " {\n",
        "let (x, y, a, b, c, expected) = cases[i];\n",
        "assert_eq(", Name, "(x as ", Type, ", y as ", Type, ", [a as ", Type,
        ", b as ", Type, ", c as ", Type, "]), expected);\n} (())\n}\n"].

type(Width, true) -> xls_nums:signed_type(Width);
type(Width, false) -> xls_nums:unsigned_type(Width).
text(Value) -> iolist_to_binary(io_lib:format("~tp", [Value])).

location([{Module, Function, Args, _} | _]) when is_list(Args) ->
    [Module, Function, length(Args)];
location([{Module, Function, Arity, _} | _]) -> [Module, Function, Arity];
location(_) -> null.
