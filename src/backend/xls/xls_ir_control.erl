-module(xls_ir_control).
-moduledoc "Exact finite-width control identities for optimized, single-function XLS IR. Unrecognized nodes remain byte-identical; application names and reachable-state assumptions play no role.".
-export([rewrite/1, write/2]).
-export_type([change/0]).

-doc "One cancelled arithmetic dependency, including its finite width and retained comparison node.".
-type change() :: #{comparison := binary(), operation := binary(), width := pos_integer(),
    arithmetic := binary(), common := binary(), remaining := binary()}.

%% Parsed arithmetic values retain only the fields needed for cancellation.
-type arithmetic() :: #{binary() => {pos_integer(), binary(), binary(), binary()}}.

-doc "Rewrites eq/ne(add(x,y),x), eq/ne(sub(x,y),x), and eq/ne(xor(x,y),x) to a comparison of y with zero at the same width. Equality arguments and commutative operands may be reversed. Requires one valid, optimized function, no procs or blocks, and no reserved hls_control_zero_ prefix; all other text is retained. These are total modular bit-vector identities, including overflow and width one.".
-spec rewrite(binary()) -> {binary(), [change()]}.
rewrite(Source) ->
    {match, [_]} = re:run(Source, <<"^(?:top )?fn ">>, [multiline, global, {capture, first, binary}]),
    nomatch = re:run(Source, <<"^(?:top )?(?:proc|block) ">>, [multiline]),
    nomatch = re:run(Source, <<"hls_control_zero_">>),
    Lines = binary:split(Source, <<"\n">>, [global]),
    Values = arithmetic(Lines, #{}),
    {match, IdMatches} = re:run(Source, <<"\\bid=([0-9]+)">>, [global, {capture, [1], binary}]),
    NextId = 1 + lists:max([binary_to_integer(Id) || [Id] <- IdMatches]),
    {Reversed, Changes, _} = lists:foldl(fun(Line, Acc) -> line(Line, Values, Acc) end,
        {[], [], NextId}, Lines),
    {iolist_to_binary(lists:join(<<"\n">>, lists:reverse(Reversed))), lists:reverse(Changes)}.

-doc "Writes a fresh rewritten IR file and adjacent JSON audit. Refuses existing outputs. The audit binds original/replacement bytes and each cancelled node; it is not a proof of the compiler or a native timing result.".
-spec write(file:filename(), file:filename()) -> ok.
write(Input, Output) ->
    false = filelib:is_file(Output),
    false = filelib:is_file(Output ++ ".json"),
    {ok, Source} = file:read_file(Input),
    {Bytes, Changes} = rewrite(Source),
    ok = file:write_file(Output, Bytes, [exclusive]),
    Audit = #{input => list_to_binary(Input), output => list_to_binary(Output),
        input_sha256 => hash(Source), output_sha256 => hash(Bytes), changes => Changes,
        assumption => <<"Same-width modular bit vectors; arbitrary values; exactly one optimized function.">>},
    file:write_file(Output ++ ".json", json:encode(Audit), [exclusive]).

%% Index only exact same-width binary arithmetic node syntax. XLS validates types.
-spec arithmetic([binary()], arithmetic()) -> arithmetic().
arithmetic([], Values) -> Values;
arithmetic([Line | Rest], Values) ->
    Pattern = <<"^  (?:ret )?([A-Za-z_][A-Za-z0-9_.]*): bits\\[([0-9]+)\\] = (add|sub|xor)\\(([A-Za-z_][A-Za-z0-9_.]*), ([A-Za-z_][A-Za-z0-9_.]*), id=">>,
    Next = case re:run(Line, Pattern, [{capture, all_but_first, binary}]) of
        {match, [Name, Width, Op, A, B]} ->
            Values#{Name => {binary_to_integer(Width), Op, A, B}};
        nomatch -> Values
    end,
    arithmetic(Rest, Next).

%% A new zero literal precedes the original comparison, whose identity is retained.
-spec line(binary(), arithmetic(), {[iodata()], [change()], pos_integer()}) ->
    {[iodata()], [change()], pos_integer()}.
line(Line, Values, {Lines, Changes, Id}) ->
    Pattern = <<"^(  (?:ret )?)([A-Za-z_][A-Za-z0-9_.]*): bits\\[1\\] = (eq|ne)\\(([A-Za-z_][A-Za-z0-9_.]*), ([A-Za-z_][A-Za-z0-9_.]*), (id=.*)\\)$">>,
    case re:run(Line, Pattern, [{capture, all_but_first, binary}]) of
        {match, [Prefix, Name, Compare, A, B, Attributes]} ->
            case cancel(A, B, Values) of
                none -> {[Line | Lines], Changes, Id};
                {Width, Op, Arithmetic, Common, Remaining} ->
                    Zero = <<"hls_control_zero_", (integer_to_binary(Id))/binary>>,
                    false = maps:is_key(Zero, Values),
                    Literal = ["  ", Zero, ": bits[", integer_to_binary(Width),
                        "] = literal(value=0, id=", integer_to_binary(Id), ")\n"],
                    New = [Literal, Prefix, Name, ": bits[1] = ", Compare, "(",
                        Remaining, ", ", Zero, ", ", Attributes, ")"],
                    Change = #{comparison => Name, operation => Op, width => Width,
                        arithmetic => Arithmetic, common => Common, remaining => Remaining},
                    {[New | Lines], [Change | Changes], Id + 1}
            end;
        nomatch -> {[Line | Lines], Changes, Id}
    end.

%% Equality and inequality are symmetric; subtraction itself is not.
-spec cancel(binary(), binary(), arithmetic()) ->
    none | {pos_integer(), binary(), binary(), binary(), binary()}.
cancel(A, B, Values) ->
    case operand(A, B, Values) of
        none -> operand(B, A, Values);
        Found -> Found
    end.

%% Cancellation relies only on bijectivity of modular add/sub/xor in one operand.
-spec operand(binary(), binary(), arithmetic()) ->
    none | {pos_integer(), binary(), binary(), binary(), binary()}.
operand(Node, Common, Values) ->
    case maps:find(Node, Values) of
        {ok, {Width, Op, Common, Remaining}} -> {Width, Op, Node, Common, Remaining};
        {ok, {Width, Op, Remaining, Common}} when Op =:= <<"add">>; Op =:= <<"xor">> ->
            {Width, Op, Node, Common, Remaining};
        _ -> none
    end.

%% Content digests bind the transform to exact inputs and outputs.
-spec hash(binary()) -> binary().
hash(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
