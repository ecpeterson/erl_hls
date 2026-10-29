-module(xls_binary_lower).
-moduledoc "Prepares supported Erlang size BIFs and lowers fixed-width binary construction and patterns for xls_clause_lower and xls_pattern_lower. BIF resolution respects local functions and no_auto_import; resulting values use xls_dslx while source evaluation and failure order remain in the clause state.".
%% Resolve source size BIFs before helper and clause lowering.
-export([prepare/1]).
%% Lower binary values and pattern subjects into the shared clause state.
-export([construct/2, pattern/2]).
%% Size signed source literals for binary and comparison consumers.
-export([integer_literal/1]).

%% Auto-imported size BIFs are not local helpers. Respect definitions and
%% no_auto_import; explicitly qualified erlang calls always name the BIF.
-doc "Resolves supported size BIFs while respecting local definitions and no_auto_import.".
-spec prepare([hls_source:form()]) -> [tuple()].
prepare(Forms) ->
    Options = lists:flatten([
        case O of
            L when is_list(L) -> L;
            _ -> [O]
        end
     || {attribute, _, compile, O} <- Forms
    ]),
    Disabled =
        [{Name, Arity} || {function, _, Name, Arity, _} <- Forms] ++
            lists:append([Keys || {no_auto_import, Keys} <- Options]),
    Enabled =
        case lists:member(no_auto_import, Options) of
            true -> [];
            false -> [{bit_size, 1}, {byte_size, 1}] -- Disabled
        end,
    size_bifs(Forms, Enabled).

size_bifs({call, Line, {remote, _, {atom, _, erlang}, {atom, _, Name}}, [Value]}, Enabled) when
    Name =:= bit_size; Name =:= byte_size
->
    {xls_bit_size, Line, Name, size_bifs(Value, Enabled)};
size_bifs({call, Line, {atom, _, Name}, [Value]} = Call, Enabled) when
    Name =:= bit_size; Name =:= byte_size
->
    case lists:member({Name, 1}, Enabled) of
        true -> {xls_bit_size, Line, Name, size_bifs(Value, Enabled)};
        false -> size_bifs_tuple(Call, Enabled)
    end;
size_bifs(Tuple, Enabled) when is_tuple(Tuple) -> size_bifs_tuple(Tuple, Enabled);
size_bifs(List, Enabled) when is_list(List) -> [size_bifs(X, Enabled) || X <- List];
size_bifs(Value, _) ->
    Value.

size_bifs_tuple(Tuple, Enabled) ->
    list_to_tuple([size_bifs(X, Enabled) || X <- tuple_to_list(Tuple)]).

%% Erlang's bit-type normalizer owns defaults, aliases and conflicting flags.
%% This boundary restricts sizes to constant integer expressions. Every later
%% consumer sees bit widths, never a mixture of sizes and units.
segments(Elements) -> lists:append([segment(E) || E <- Elements]).

segment({bin_element, Line, Value, Size, Types}) ->
    case erl_bits:set_bit_type(Size, Types) of
        {ok, DefaultSize, {bittype, Kind, Unit, Sign, Endian}} when
            (Kind =:= integer orelse Kind =:= binary), Endian =/= native
        ->
            Width =
                case DefaultSize of
                    all -> all;
                    N when is_integer(N) -> N * Unit;
                    Expr -> constant_size(Expr, Line) * Unit
                end,
            Segment = #{
                line => Line,
                value => Value,
                kind => Kind,
                width => Width,
                unit => Unit,
                sign => Sign,
                endian => Endian
            },
            case Value of
                {string, _, Chars} when Kind =:= integer ->
                    [Segment#{value := {integer, Line, C}} || C <- Chars];
                {string, _, _} ->
                    unsupported(Line, {string_segment_type, Kind});
                _ ->
                    [Segment]
            end;
        {ok, _, {bittype, _, _, _, native}} ->
            unsupported(Line, native_endian);
        {ok, _, {bittype, Kind, _, _, _}} ->
            unsupported(Line, {segment_type, Kind});
        {error, Reason} ->
            unsupported(Line, Reason)
    end.

%% Segment capacities require a nonnegative static integer, before hardware typing.
-spec constant_size(erl_parse:abstract_expr(), erl_anno:location()) -> non_neg_integer().
constant_size(Expr, Line) ->
    case xls_static_integer:eval(Expr) of
        {ok, Width} when Width >= 0 -> Width;
        _ -> unsupported(Line, {nonconstant_or_negative_size, Expr})
    end.

-doc "Lowers fixed-width binary construction, preserving evaluation order and recording payload failures.".
-spec construct(erl_parse:abstract_expr(), xls_clause_lower:clause_state()) ->
    xls_clause_lower:clause_state().
construct({bin, _, Elements}, State) ->
    {Parts, Evaluated} = lists:mapfoldl(fun construct_segment/2, State, segments(Elements)),
    xls_clause_lower:instr(Evaluated, ["(", lists:join(" ++ ", Parts ++ ["bits[0]:0"]), ",)"]).

%% Evaluate one normalized segment before encoding it and recording length failures.
-spec construct_segment(
    #{
        value := erl_parse:abstract_expr(),
        kind := integer | binary,
        width := non_neg_integer() | all,
        unit := pos_integer(),
        line := erl_anno:anno(),
        sign := signed | unsigned,
        endian := big | little
    },
    xls_clause_lower:clause_state()
) ->
    {xls_clause_lower:printable(), xls_clause_lower:clause_state()}.
construct_segment(#{value := Expr, kind := Kind} = Segment, State) ->
    ValueExpr = constant_expression(Expr),
    Evaluated = xls_clause_lower:statement_from_statement(ValueExpr, State),
    Value = xls_clause_lower:reference(Evaluated),
    case Kind of
        integer ->
            {encode_integer(Value, Segment), Evaluated};
        binary ->
            #{width := Width, unit := Unit, line := Line} = Segment,
            {Part, Predicate} =
                case Width of
                    all when Unit =:= 1 -> {["(", Value, ").0"], none};
                    all ->
                        {["(", Value, ").0"], [
                            "hls_bits::length(",
                            Value,
                            ") % u32:",
                            integer_to_list(Unit),
                            " != u32:0"
                        ]};
                    0 ->
                        {slice(Value, 0, 0), none};
                    _ ->
                        {slice(Value, 0, Width), [
                            "hls_bits::length(",
                            Value,
                            ") < u32:",
                            integer_to_list(Width)
                        ]}
                end,
            Checked =
                case Predicate of
                    none ->
                        Evaluated;
                    _ ->
                        xls_clause_lower:add_failure(
                            [
                                "hls_failure::check(",
                                Predicate,
                                ", ",
                                xls_failure_sites:at(badarg, Line),
                                ")"
                            ],
                            Evaluated
                        )
                end,
            {Part, Checked}
    end.

encode_integer(Value, #{width := Width, endian := Endian}) ->
    Bits =
        case Value of
            {static, integer, N} ->
                [
                    "bits[",
                    integer_to_list(Width),
                    "]:",
                    integer_to_list(N band ((1 bsl Width) - 1))
                ];
            _ ->
                ["(", Value, " as bits[", integer_to_list(Width), "])"]
        end,
    endian(Endian, to_stream, Bits).

%% Projections remain well typed even when the fixed input is too short.
%% The length predicate rejects those placeholder values before selecting a
%% clause; an assignment instead reports the ordinary badmatch failure.
-doc "Returns a binary pattern's length predicate and field projections for subsequent matching.".
-spec pattern(erl_parse:abstract_expr(), xls_clause_lower:printable()) ->
    {{erl_anno:anno(), xls_dslx:value()}, [
        {erl_parse:abstract_expr(), xls_dslx:value(), integer | bits}
    ]}.
pattern({bin, Line, Elements}, Value) ->
    {Parts, Offset, Tail} = pattern_segments(segments(Elements), Value, 0),
    Predicate =
        case Tail of
            none ->
                ["hls_bits::length(", Value, ") == u32:", integer_to_list(Offset)];
            Unit ->
                [
                    "hls_bits::length(",
                    Value,
                    ") >= u32:",
                    integer_to_list(Offset),
                    " && (hls_bits::length(",
                    Value,
                    ") - u32:",
                    integer_to_list(Offset),
                    ") % u32:",
                    integer_to_list(Unit),
                    " == u32:0"
                ]
        end,
    {{Line, Predicate}, Parts}.

pattern_segments([], _Value, Offset) ->
    {[], Offset, none};
pattern_segments([#{kind := binary, width := all, value := Pattern, unit := Unit}], Value, Offset) ->
    {
        [{Pattern, ["hls_bits::tail<u32:", integer_to_list(Offset), ">(", Value, ")"], bits}],
        Offset,
        Unit
    };
pattern_segments([#{width := all, line := Line} | _], _Value, _Offset) ->
    unsupported(Line, unsized_nonfinal_pattern_segment);
pattern_segments(
    [
        #{
            value := Pattern,
            kind := Kind,
            width := Width,
            sign := Sign,
            endian := Endian
        }
        | Rest
    ],
    Value,
    Offset
) ->
    Raw = slice(Value, Offset, Width),
    {Projection, Mode} =
        case Kind of
            binary ->
                {["(", Raw, ",)"], bits};
            integer ->
                Type =
                    case Sign of
                        signed -> "sN";
                        unsigned -> "uN"
                    end,
                {
                    [
                        "(",
                        endian(Endian, from_stream, Raw),
                        " as ",
                        Type,
                        "[",
                        integer_to_list(max(1, Width)),
                        "])"
                    ],
                    integer
                }
        end,
    {Parts, End, Tail} = pattern_segments(Rest, Value, Offset + Width),
    {[{constant_expression(Pattern), Projection, Mode} | Parts], End, Tail}.

%% Preserve successful integer folding for binary values and patterns.
-spec constant_expression(erl_parse:abstract_expr()) -> erl_parse:abstract_expr().
constant_expression(Expr) ->
    case xls_static_integer:eval(Expr) of
        {ok, N} -> {integer, element(2, Expr), N};
        error -> Expr
    end.

slice(Value, Offset, Width) ->
    [
        "hls_bits::segment<u32:",
        integer_to_list(Offset),
        ", u32:",
        integer_to_list(Width),
        ">(",
        Value,
        ")"
    ].

endian(big, _Direction, Bits) -> Bits;
endian(little, Direction, Bits) -> ["hls_bits::", atom_to_list(Direction), "(", Bits, ")"].

-doc "Returns a signed DSLX literal with enough independent width for the integer, including its sign. Numeric comparison and pattern lowering use it without truncating to another operand's type.".
-spec integer_literal(integer()) -> xls_dslx:expr().
integer_literal(N) ->
    Width = length(integer_to_list(abs(N), 2)) + 1,
    xls_dslx:literal("sN[" ++ integer_to_list(Width) ++ "]", N).

unsupported(Line, Reason) -> error({unsupported_xls_bit_syntax, Line, Reason}).
