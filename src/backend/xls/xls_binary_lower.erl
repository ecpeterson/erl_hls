-module(xls_binary_lower).
-moduledoc false.
-export([prepare/1, construct/2, pattern/2, integer_literal/1]).

%% Auto-imported size BIFs are not local helpers. Respect definitions and
%% no_auto_import; explicitly qualified erlang calls always name the BIF.
-spec prepare([erl_parse:abstract_form()]) -> [tuple()].
prepare(Forms) ->
    Options = lists:flatten([case O of L when is_list(L) -> L; _ -> [O] end
        || {attribute, _, compile, O} <- Forms]),
    Disabled = [{Name, Arity} || {function, _, Name, Arity, _} <- Forms] ++
        lists:append([Keys || {no_auto_import, Keys} <- Options]),
    Enabled = case lists:member(no_auto_import, Options) of
        true -> [];
        false -> [{bit_size, 1}, {byte_size, 1}] -- Disabled
    end,
    size_bifs(Forms, Enabled).

size_bifs({call, Line, {remote, _, {atom, _, erlang}, {atom, _, Name}}, [Value]}, Enabled)
        when Name =:= bit_size; Name =:= byte_size ->
    {xls_bit_size, Line, Name, size_bifs(Value, Enabled)};
size_bifs({call, Line, {atom, _, Name}, [Value]} = Call, Enabled)
        when Name =:= bit_size; Name =:= byte_size ->
    case lists:member({Name, 1}, Enabled) of
        true -> {xls_bit_size, Line, Name, size_bifs(Value, Enabled)};
        false -> size_bifs_tuple(Call, Enabled)
    end;
size_bifs(Tuple, Enabled) when is_tuple(Tuple) -> size_bifs_tuple(Tuple, Enabled);
size_bifs(List, Enabled) when is_list(List) -> [size_bifs(X, Enabled) || X <- List];
size_bifs(Value, _) -> Value.

size_bifs_tuple(Tuple, Enabled) ->
    list_to_tuple([size_bifs(X, Enabled) || X <- tuple_to_list(Tuple)]).

%% Erlang's bit-type normalizer owns defaults, aliases and conflicting flags.
%% This boundary restricts sizes to constant integer expressions. Every later
%% consumer sees bit widths, never a mixture of sizes and units.
segments(Elements) -> lists:append([segment(E) || E <- Elements]).

segment({bin_element, Line, Value, Size, Types}) ->
    case erl_bits:set_bit_type(Size, Types) of
        {ok, DefaultSize, {bittype, Kind, Unit, Sign, Endian}}
                when (Kind =:= integer orelse Kind =:= binary), Endian =/= native ->
            Width = case DefaultSize of
                all -> all;
                N when is_integer(N) -> N * Unit;
                Expr -> constant_size(Expr, Line) * Unit
            end,
            Segment = #{line => Line, value => Value, kind => Kind, width => Width,
                unit => Unit, sign => Sign, endian => Endian},
            case Value of
                {string, _, Chars} when Kind =:= integer ->
                    [Segment#{value := {integer, Line, C}} || C <- Chars];
                {string, _, _} -> unsupported(Line, {string_segment_type, Kind});
                _ -> [Segment]
            end;
        {ok, _, {bittype, _, _, _, native}} -> unsupported(Line, native_endian);
        {ok, _, {bittype, Kind, _, _, _}} -> unsupported(Line, {segment_type, Kind});
        {error, Reason} -> unsupported(Line, Reason)
    end.

constant_size(Expr, Line) ->
    case constant(Expr) of
        {ok, Width} when Width >= 0 -> Width;
        _ -> unsupported(Line, {nonconstant_or_negative_size, Expr})
    end.

constant({integer, _, N}) -> {ok, N};
constant({char, _, N}) -> {ok, N};
constant({op, _, Op, A}) when Op =:= '+'; Op =:= '-'; Op =:= 'bnot' ->
    calculate(Op, [constant(A)]);
constant({op, _, Op, A, B}) when Op =:= '+'; Op =:= '-'; Op =:= '*';
        Op =:= 'div'; Op =:= 'rem'; Op =:= 'bsl'; Op =:= 'bsr';
        Op =:= 'band'; Op =:= 'bor'; Op =:= 'bxor' ->
    calculate(Op, [constant(A), constant(B)]);
constant(_) -> error.

calculate(Op, Args) ->
    case lists:all(fun({ok, _}) -> true; (_) -> false end, Args) of
        true -> try {ok, apply(erlang, Op, [N || {ok, N} <- Args])}
            catch error:badarith -> error end;
        false -> error
    end.

-spec construct(erl_parse:abstract_expression(), xls_parse:clause_state()) -> xls_parse:clause_state().
construct({bin, _, Elements}, State) ->
    {Parts, Evaluated} = lists:mapfoldl(fun construct_segment/2, State, segments(Elements)),
    xls_parse:instr(Evaluated, ["(", lists:join(" ++ ", Parts ++ ["bits[0]:0"]), ",)"]).

construct_segment(#{value := Expr, kind := Kind} = Segment, State) ->
    ValueExpr = constant_expression(Expr),
    Evaluated = xls_parse:statement_from_statement(ValueExpr, State),
    Value = xls_parse:reference(Evaluated),
    case Kind of
        integer -> {encode_integer(Value, Segment), Evaluated};
        binary ->
            #{width := Width, unit := Unit, line := Line} = Segment,
            {Part, Predicate} = case Width of
                all when Unit =:= 1 -> {["(", Value, ").0"], none};
                all -> {["(", Value, ").0"], ["hls_bits::length(", Value, ") % u32:",
                    integer_to_list(Unit), " != u32:0"]};
                0 -> {slice(Value, 0, 0), none};
                _ -> {slice(Value, 0, Width), ["hls_bits::length(", Value, ") < u32:",
                    integer_to_list(Width)]}
            end,
            Checked = case Predicate of
                none -> Evaluated;
                _ -> xls_parse:add_failure(["hls_failure::check(", Predicate, ", ",
                    xls_failure_sites:at(badarg, Line), ")"], Evaluated)
            end,
            {Part, Checked}
    end.

encode_integer(Value, #{width := Width, endian := Endian}) ->
    Bits = case Value of
        {static, integer, N} -> ["bits[", integer_to_list(Width), "]:",
            integer_to_list(N band ((1 bsl Width) - 1))];
        _ -> ["(", Value, " as bits[", integer_to_list(Width), "])"]
    end,
    endian(Endian, to_stream, Bits).

%% Projections remain well typed even when the fixed input is too short.
%% The length predicate rejects those placeholder values before selecting a
%% clause; an assignment instead reports the ordinary badmatch failure.
-spec pattern(erl_parse:af_pattern(), xls_parse:printable()) ->
    {{erl_anno:anno(), iolist()}, [{erl_parse:af_pattern(), iolist(), integer | bits}]}.
pattern({bin, Line, Elements}, Value) ->
    {Parts, Offset, Tail} = pattern_segments(segments(Elements), Value, 0),
    Predicate = case Tail of
        none -> ["hls_bits::length(", Value, ") == u32:", integer_to_list(Offset)];
        Unit -> ["hls_bits::length(", Value, ") >= u32:", integer_to_list(Offset),
            " && (hls_bits::length(", Value, ") - u32:", integer_to_list(Offset),
            ") % u32:", integer_to_list(Unit), " == u32:0"]
    end,
    {{Line, Predicate}, Parts}.

pattern_segments([], _Value, Offset) -> {[], Offset, none};
pattern_segments([#{kind := binary, width := all, value := Pattern, unit := Unit}], Value, Offset) ->
    {[{Pattern, ["hls_bits::tail<u32:", integer_to_list(Offset), ">(", Value, ")"], bits}],
        Offset, Unit};
pattern_segments([#{width := all, line := Line} | _], _Value, _Offset) ->
    unsupported(Line, unsized_nonfinal_pattern_segment);
pattern_segments([#{value := Pattern, kind := Kind, width := Width,
        sign := Sign, endian := Endian} | Rest], Value, Offset) ->
    Raw = slice(Value, Offset, Width),
    {Projection, Mode} = case Kind of
        binary -> {["(", Raw, ",)"], bits};
        integer ->
            Type = case Sign of signed -> "sN"; unsigned -> "uN" end,
            {["(", endian(Endian, from_stream, Raw), " as ", Type, "[",
                integer_to_list(max(1, Width)), "])"], integer}
    end,
    {Parts, End, Tail} = pattern_segments(Rest, Value, Offset + Width),
    {[{constant_expression(Pattern), Projection, Mode} | Parts], End, Tail}.

constant_expression(Expr) ->
    case constant(Expr) of
        {ok, N} -> {integer, element(2, Expr), N};
        error -> Expr
    end.

slice(Value, Offset, Width) ->
    ["hls_bits::segment<u32:", integer_to_list(Offset), ", u32:",
        integer_to_list(Width), ">(", Value, ")"].

endian(big, _Direction, Bits) -> Bits;
endian(little, Direction, Bits) -> ["hls_bits::", atom_to_list(Direction), "(", Bits, ")"].

integer_literal(N) ->
    ["sN[", integer_to_list(length(integer_to_list(abs(N), 2)) + 1), "]:", integer_to_list(N)].

unsupported(Line, Reason) -> error({unsupported_xls_bit_syntax, Line, Reason}).
