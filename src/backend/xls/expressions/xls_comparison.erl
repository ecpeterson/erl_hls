%%%% Classify comparisons and finite atom domains before values become DSLX text.
-module(xls_comparison).
-moduledoc "Classifies supported Erlang comparisons and finite atom domains during helper preparation, then lowers their operands through xls_clause_lower. Integer comparisons retain source signedness and independently sized literals in structured hls_integer calls; xls_dslx renders the target syntax without deciding Erlang comparison semantics.".
%% Annotate comparison semantics before expression lowering.
-export([prepare/1, prepare/2]).
%% Lower a prepared comparison using the current clause state.
-export([lower/2]).

%% Only proven integer values select widening comparison. Unknown providers and
%% structural equality remain XLS's responsibility; this is not type inference.
-type shape() ::
    integer
    | other
    | unknown
    | {atom, atom()}
    | {enum, hls_type:descriptor()}
    | {tuple, [shape()]}
    | {array, shape()}.
%% Proven shapes of variables visible at one source point.
-type bindings() :: #{atom() => shape()}.
%% Declaration facts shared by all function bodies in one source module.
-type context() :: #{
    records := #{atom() => #{atom() => shape()}},
    signatures := #{{atom(), arity()} => {[shape()], shape()}}
}.

-doc "Marks proven integer comparisons and finite atom-domain boundaries without changing arithmetic widths or encoding atoms outside a declared domain.".
-spec prepare([hls_source:form()]) -> [hls_source:form()].
prepare(Forms) -> prepare(Forms, []).

-doc "Also preserves framework-owned callback tags; only record fields and concrete helper types gain finite-atom encodings.".
-spec prepare([hls_source:form()], [{atom(), arity()}]) -> [hls_source:form()].
prepare(Forms, Roots) ->
    Context = #{
        records => maps:from_list([
            {Name,
                maps:from_list([
                    {hls_records:field_name(Field), shape(Type, Forms)}
                 || {typed_record_field, Field, Type} <- Fields
                ])}
         || {attribute, _, record, {Name, Fields}} <- Forms
        ]),
        signatures => maps:from_list([
            {Key,
                callback_signature(
                    Key, {[shape(A, Forms) || A <- Args], shape(Result, Forms)}, Roots
                )}
         || {attribute, _, spec, {Key, [{type, _, 'fun', [{type, _, product, Args}, Result]}]}} <-
                Forms
        ])
    },
    [
        case Form of
            {function, Line, Name, Arity, Clauses} ->
                {Types, Result} = signature({Name, Arity}, Context),
                {function, Line, Name, Arity, [
                    begin
                        {Typed, Actual, _} = clause(C, Types, #{}, Context),
                        compatible(Result, Actual, Line),
                        Typed
                    end
                 || C <- Clauses
                ]};
            _ ->
                Form
        end
     || Form <- Forms
    ].

%% Callback tag/phase encodings belong to their behaviour lowerer, not to a
%% source atom union's compact codebook. Typed record fields remain independent.
-spec callback_signature({atom(), arity()}, {[shape()], shape()}, [{atom(), arity()}]) ->
    {[shape()], shape()}.
callback_signature(Key, {Args, Result} = Signature, Roots) ->
    case lists:member(Key, Roots) of
        true -> {[callback_shape(A) || A <- Args], callback_shape(Result)};
        false -> Signature
    end.

%% Erase only framework-owned atom encodings, retaining numeric comparison facts.
-spec callback_shape(shape()) -> shape().
callback_shape({enum, _}) -> unknown;
callback_shape({tuple, Fields}) -> {tuple, [callback_shape(T) || T <- Fields]};
callback_shape(Type) -> Type.

%% Enum domains come from source declarations, never from a module-global atom map.
-spec shape(term(), [hls_source:form()]) -> shape().
shape({ann_type, _, [_, Type]}, Forms) ->
    shape(Type, Forms);
shape({type, _, tuple, Fields}, Forms) when is_list(Fields) ->
    {tuple, [shape(T, Forms) || T <- Fields]};
shape(Type, Forms) ->
    case hls_atom_types:descriptor(Type, Forms) of
        {ok, Descriptor} -> {enum, Descriptor};
        none -> shape(Type)
    end.

%% Concrete provider declarations identify integer values without inspecting
%% emitted type strings. Other providers may have noninteger live values.
-spec shape(erl_parse:abstract_type()) -> shape().
shape({ann_type, _, [_, Type]}) ->
    shape(Type);
shape({remote_type, _, [{atom, _, hls_nums}, {atom, _, Name}, _]}) ->
    case lists:member(Name, [u8, u16, u32, u64, uN, s8, s16, s32, s64, sN]) of
        true -> integer;
        false -> other
    end;
shape({remote_type, _, [{atom, _, hls_serial}, {atom, _, counter}, _]}) ->
    integer;
shape({remote_type, _, [{atom, _, hls_fixed}, {atom, _, Kind}, _]}) when
    Kind =:= signed; Kind =:= unsigned
->
    integer;
shape({remote_type, _, [{atom, _, Module}, {atom, _, Name}, [Element, _]]}) when
    (Module =:= hls_vec andalso Name =:= vector);
    (Module =:= hls_lists andalso Name =:= list)
->
    {array, shape(Element)};
shape({type, _, tuple, Elements}) when is_list(Elements) -> {tuple, [shape(T) || T <- Elements]};
shape({type, _, boolean, []}) ->
    other;
shape({remote_type, _, [{atom, _, hls_bool}, _, _]}) ->
    other;
shape(_) ->
    unknown.

%% Missing or overloaded signatures provide no numeric evidence.
-spec signature({atom(), arity()}, context()) -> {[shape()], shape()}.
signature(Key = {_, Arity}, #{signatures := Signatures}) ->
    maps:get(Key, Signatures, {lists:duplicate(Arity, unknown), unknown}).

%% Head patterns refine the signature, then guards and body share those facts.
-spec clause(erl_parse:abstract_clause(), [shape()], bindings(), context()) ->
    {erl_parse:abstract_clause(), shape(), bindings()}.
clause({clause, Line, Patterns, Guards, Body}, Types, Outer, Context) ->
    Bound = lists:foldl(
        fun({P, T}, Env) -> pattern(P, T, Env, Context) end,
        Outer,
        lists:zip(Patterns, Types)
    ),
    TypedPatterns = [typed_pattern(P, T, Context) || {P, T} <- lists:zip(Patterns, Types)],
    TypedGuards = [
        [
            begin
                {TypedGuard, GuardType, _} = expression(G, Bound, Context),
                case contains_enum(GuardType) of
                    true -> error({unsupported_xls_enum_guard, Line});
                    false -> TypedGuard
                end
            end
         || G <- Alternative
        ]
     || Alternative <- Guards
    ],
    {TypedBody, Result, After} = expressions(Body, Bound, Context),
    {{clause, Line, TypedPatterns, TypedGuards, TypedBody}, Result, After}.

%% Bindings take effect left to right; the last expression supplies the result.
-spec expressions([term()], bindings(), context()) -> {[term()], shape(), bindings()}.
expressions(Values, Env, Context) ->
    {Typed, {Result, After}} = lists:mapfoldl(
        fun(Value, {_, Before}) ->
            {Next, Type, Bound} = expression(Value, Before, Context),
            {Next, {Type, Bound}}
        end,
        {unknown, Env},
        Values
    ),
    {Typed, Result, After}.

%% Propagate just enough source shape to distinguish numeric and structural
%% equality. Opaque syntax is traversed but contributes no result-type claim.
-spec expression(term(), bindings(), context()) -> {term(), shape(), bindings()}.
expression({var, _, Name} = E, Env, _) ->
    {E, maps:get(Name, Env, unknown), Env};
expression({Kind, _, _} = E, Env, _) when Kind =:= integer; Kind =:= char -> {E, integer, Env};
expression({atom, _, Atom} = E, Env, _) ->
    {E, {atom, Atom}, Env};
expression({match, Line, Pattern, Value}, Env, Context) ->
    {Typed, Type, Bound} = expression(Value, Env, Context),
    {
        {match, Line, typed_pattern(Pattern, Type, Context), Typed},
        Type,
        pattern(Pattern, Type, Bound, Context)
    };
expression({op, Line, Op, Left, Right}, Env, Context) ->
    {A, AT, AE} = expression(Left, Env, Context),
    {B, BT, BE} = expression(Right, AE, Context),
    HasEnums = contains_enum(AT) orelse contains_enum(BT),
    Node =
        case {comparison(Op), AT, BT} of
            _ when HasEnums ->
                enum_operator(Op, Line),
                compatible(AT, BT, Line),
                {op, Line, Op, comparison_expected(A, BT, Line), comparison_expected(B, AT, Line)};
            {true, integer, integer} ->
                {xls_integer_compare, Line, Op, A, B};
            {true, integer, Known} when Known =/= unknown ->
                error(
                    {unsupported_xls_comparison, Line, Op, diagnostic_shape(AT),
                        diagnostic_shape(BT)}
                );
            {true, Known, integer} when Known =/= unknown ->
                error(
                    {unsupported_xls_comparison, Line, Op, diagnostic_shape(AT),
                        diagnostic_shape(BT)}
                );
            _ ->
                {op, Line, Op, A, B}
        end,
    %% Short-circuit right-side bindings cannot escape the expression.
    After =
        case Op of
            'andalso' -> AE;
            'orelse' -> AE;
            _ -> BE
        end,
    {Node, operator_shape(Op), After};
expression({op, Line, Op, Value}, Env, Context) ->
    {Typed, Type, After} = expression(Value, Env, Context),
    case contains_enum(Type) of
        true -> error({unsupported_xls_enum_operator, Line, Op});
        false -> ok
    end,
    {{op, Line, Op, Typed}, operator_shape(Op), After};
expression({tuple, Line, Values}, Env, Context) ->
    {Pairs, After} = lists:mapfoldl(
        fun(Value, Before) ->
            {Next, Type, Bound} = expression(Value, Before, Context),
            {{Next, Type}, Bound}
        end,
        Env,
        Values
    ),
    {Typed, Types} = lists:unzip(Pairs),
    {{tuple, Line, Typed}, {tuple, Types}, After};
expression({block, Line, Body}, Env, Context) ->
    {Typed, Type, After} = expressions(Body, Env, Context),
    {{block, Line, Typed}, Type, After};
expression({'case', Line, Subject, Clauses}, Env, Context) ->
    {Typed, Type, Bound} = expression(Subject, Env, Context),
    {Branches, Result, After} = branches(Clauses, [Type], Bound, Context),
    {{'case', Line, Typed, Branches}, Result, After};
expression({'if', Line, Clauses}, Env, Context) ->
    {Branches, Result, After} = branches(Clauses, [], Env, Context),
    {{'if', Line, Branches}, Result, After};
expression({record, Line, Name, Fields}, Env, Context) ->
    {Typed, After} = record_fields(Name, Fields, Env, Context),
    {{record, Line, Name, Typed}, unknown, After};
expression({record, Line, Base, Name, Fields}, Env, Context) ->
    {Input, _, Before} = expression(Base, Env, Context),
    {Typed, After} = record_fields(Name, Fields, Before, Context),
    {{record, Line, Input, Name, Typed}, unknown, After};
expression({record_field, Line, Value, Name, Field = {atom, _, Slot}}, Env, Context) ->
    {Typed, _, After} = expression(Value, Env, Context),
    {{record_field, Line, Typed, Name, Field}, field(Name, Slot, Context), After};
expression({call, Line, Target, Args}, Env, Context) ->
    Expected =
        case Target of
            {atom, _, Name} -> element(1, signature({Name, length(Args)}, Context));
            _ -> lists:duplicate(length(Args), unknown)
        end,
    {Typed, After} = lists:mapfoldl(
        fun({Arg, Type}, Before) ->
            {Value, Actual, Bound} = expression(Arg, Before, Context),
            case Target of
                {remote, _, _, _} ->
                    case contains_enum(Actual) of
                        true -> error({unsupported_xls_enum_provider_call, Line, Target});
                        false -> ok
                    end;
                _ ->
                    ok
            end,
            {expected(Value, Type, Actual, Line), Bound}
        end,
        Env,
        lists:zip(Args, Expected)
    ),
    {{call, Line, Target, Typed}, call_shape(Target, Args, Context), After};
expression({xls_bit_size, Line, Name, Value}, Env, Context) ->
    {Typed, _, After} = expression(Value, Env, Context),
    {{xls_bit_size, Line, Name, Typed}, integer, After};
expression(Tuple, Env, Context) when is_tuple(Tuple) ->
    {Typed, _, After} = expressions(tuple_to_list(Tuple), Env, Context),
    {list_to_tuple(Typed), unknown, After};
expression(List, Env, Context) when is_list(List) ->
    {Typed, _, After} = expressions(List, Env, Context),
    {Typed, unknown, After};
expression(Value, Env, _) ->
    {Value, unknown, Env}.

%% A field assignment is a typed boundary just like a helper argument.
-spec record_fields(atom(), [tuple()], bindings(), context()) -> {[tuple()], bindings()}.
record_fields(Name, Fields, Env, Context) ->
    lists:mapfoldl(
        fun({record_field, Line, Field = {atom, _, Slot}, Value}, Before) ->
            {Typed, Actual, After} = expression(Value, Before, Context),
            Checked = expected(Typed, field(Name, Slot, Context), Actual, Line),
            {{record_field, Line, Field, Checked}, After}
        end,
        Env,
        Fields
    ).

%% Preserve existing numeric diagnostics for known noninteger atom values.
-spec diagnostic_shape(shape()) -> shape().
diagnostic_shape({atom, _}) -> other;
diagnostic_shape(Type) -> Type.

%% Atom equality uses the declared domain. Erlang atom ordering is lexical and
%% must not accidentally become declaration-code ordering.
-spec contains_enum(shape()) -> boolean().
contains_enum({enum, _}) -> true;
contains_enum({tuple, Fields}) -> lists:any(fun contains_enum/1, Fields);
contains_enum({array, Element}) -> contains_enum(Element);
contains_enum(_) -> false.

%% Structural equality may contain enum fields; context reaches corresponding
%% tuple literals without changing unrelated numeric literal-width inference.
-spec comparison_expected(term(), shape(), erl_anno:location()) -> term().
comparison_expected(Value, Shape, Line) ->
    case contains_enum(Shape) of
        true -> {xls_expected, Line, literal_context(Shape), Value};
        false -> Value
    end.

%% Carry only enum requirements into matching tuple literal positions.
-spec literal_context(shape()) -> unknown | xls_literal_types:type() | {tuple, [term()]}.
literal_context({enum, Descriptor}) -> {provider, Descriptor};
literal_context({tuple, Fields}) -> {tuple, [literal_context(T) || T <- Fields]};
literal_context(_) -> unknown.

%% Bits are an encoding only; arithmetic and lexical ordering remain unsupported.
-spec enum_operator(atom(), erl_anno:location()) -> ok.
enum_operator(Op, _) when Op =:= '=:='; Op =:= '=/=' -> ok;
enum_operator(Op, Line) when Op =:= '<'; Op =:= '=<'; Op =:= '>'; Op =:= '>=' ->
    error({unsupported_xls_enum_ordering, Line, Op});
enum_operator(Op, Line) ->
    error({unsupported_xls_enum_operator, Line, Op}).

%% An expected domain also reaches earlier atom bindings in literal typing.
-spec expected(term(), shape(), shape(), erl_anno:location()) -> term().
expected(Value, Type = {enum, Descriptor}, Actual, Line) ->
    compatible(Type, Actual, Line),
    {xls_expected, Line, {provider, Descriptor}, Value};
expected(Value, Expected, Actual, Line) ->
    compatible(Expected, Actual, Line),
    Value.

%% Different codebooks are not interchangeable merely because their widths fit.
-spec compatible(shape(), shape(), erl_anno:location()) -> ok.
compatible({tuple, Expected}, {tuple, Actual}, Line) when length(Expected) =:= length(Actual) ->
    lists:foreach(fun({E, A}) -> compatible(E, A, Line) end, lists:zip(Expected, Actual));
compatible({enum, Type}, {enum, Type}, _) ->
    ok;
compatible({enum, Type}, {atom, Atom}, Line) ->
    _ = xls_literal_types:encode_atom(Line, Atom, Type),
    ok;
compatible({atom, Atom}, {enum, Type}, Line) ->
    _ = xls_literal_types:encode_atom(Line, Atom, Type),
    ok;
compatible({enum, _}, unknown, _) ->
    ok;
compatible({enum, Type}, Actual, Line) ->
    error({incompatible_xls_enum, Line, Type, Actual});
compatible(unknown, {enum, _}, _) ->
    ok;
compatible(Expected, {enum, Type}, Line) ->
    error({incompatible_xls_enum, Line, Expected, Type});
compatible(_, _, _) ->
    ok.

%% Patterns have no later expression consumer; their declared subject types
%% supply the encoding directly, including nested record and tuple fields.
-spec typed_pattern(term(), shape(), context()) -> term().
typed_pattern({atom, Line, Atom}, {enum, Type}, _) ->
    xls_literal_types:encode_atom(Line, Atom, Type);
typed_pattern({match, Line, A, B}, Type, Context) ->
    {match, Line, typed_pattern(A, Type, Context), typed_pattern(B, Type, Context)};
typed_pattern({record, Line, Name, Fields}, _, Context) ->
    {record, Line, Name, [
        {record_field, FL, Field, typed_pattern(P, field(Name, Slot, Context), Context)}
     || {record_field, FL, Field = {atom, _, Slot}, P} <- Fields
    ]};
typed_pattern({tuple, Line, Patterns}, {tuple, Types}, Context) when
    length(Patterns) =:= length(Types)
->
    {tuple, Line, [typed_pattern(P, T, Context) || {P, T} <- lists:zip(Patterns, Types)]};
typed_pattern(Pattern, _, _) ->
    Pattern.

%% Integer operations require integer operands; Boolean operators yield atoms.
-spec operator_shape(atom()) -> shape().
operator_shape(Op) ->
    case
        lists:member(Op, ['+', '-', '*', 'div', 'rem', 'band', 'bor', 'bxor', 'bnot', 'bsl', 'bsr'])
    of
        true -> integer;
        false -> other
    end.

%% Keep this list independent of Erlang's nonexact numeric equality operators.
-spec comparison(atom()) -> boolean().
comparison(Op) -> lists:member(Op, ['<', '=<', '>', '>=', '=:=', '=/=']).

%% Type constructors used as expression arguments have the remote-type shape
%% after this mechanical conversion. No provider code is executed by this pass.
-spec type_argument(term()) -> shape().
type_argument(Type) -> shape(type_ast(Type)).

%% Preserve nested provider constructors for collections.
-spec type_ast(term()) -> term().
type_ast({call, Line, {remote, _, M, F}, Args}) ->
    {remote_type, Line, [M, F, [type_ast(A) || A <- Args]]};
type_ast(Value) ->
    Value.

%% Only public operations with a known live-value contract contribute facts.
-spec call_shape(term(), [term()], context()) -> shape().
call_shape({atom, _, Name}, Args, Context) ->
    element(2, signature({Name, length(Args)}, Context));
call_shape({remote, _, {atom, _, M}, {atom, _, F}}, [Type | _], _) when
    (M =:= hls_nums andalso F =:= wrap);
    (M =:= hls_type andalso (F =:= as orelse F =:= zero));
    (M =:= hls_serial andalso (F =:= wrap orelse F =:= add orelse F =:= difference))
->
    type_argument(Type);
call_shape(_, _, _) ->
    unknown.

%% Branch exports are useful only when every arm proves the same shape.
-spec branches([erl_parse:abstract_clause()], [shape()], bindings(), context()) ->
    {[erl_parse:abstract_clause()], shape(), bindings()}.
branches(Clauses, Types, Env, Context) ->
    Results = [clause(C, Types, Env, Context) || C <- Clauses],
    [First | Rest] = Results,
    After = lists:foldl(
        fun({_, _, Next}, Acc) ->
            maps:filter(fun(Name, Type) -> maps:get(Name, Next, unknown) =:= Type end, Acc)
        end,
        element(3, First),
        Rest
    ),
    Result = element(2, First),
    Joined =
        lists:foldl(fun({_, T, _}, Acc) -> join_shape(Acc, T) end, Result, Rest),
    {[C || {C, _, _} <- Results], Joined, After}.

%% Branches with distinct enum codebooks are unsafe even when their bit widths
%% happen to agree. Literal atoms may join a compatible declared enum domain.
-spec join_shape(shape(), shape()) -> shape().
join_shape(Type, Type) ->
    Type;
join_shape({enum, _} = Type, Other) ->
    compatible(Type, Other, 0),
    Type;
join_shape(Other, {enum, _} = Type) ->
    compatible(Type, Other, 0),
    Type;
join_shape(_, _) ->
    unknown.

%% Pattern projections use declared fields even without a callback signature.
-spec pattern(term(), shape(), bindings(), context()) -> bindings().
pattern({var, _, '_'}, _, Env, _) ->
    Env;
pattern({var, Line, Name}, Type, Env, _) ->
    case maps:find(Name, Env) of
        {ok, Existing} ->
            compatible(Type, Existing, Line),
            Env;
        error ->
            Env#{Name => Type}
    end;
pattern({match, _, A, B}, Type, Env, Context) ->
    pattern(B, Type, pattern(A, Type, Env, Context), Context);
pattern({record, _, Name, Fields}, _, Env, Context) ->
    lists:foldl(
        fun({record_field, _, {atom, _, Slot}, P}, Acc) ->
            pattern(P, field(Name, Slot, Context), Acc, Context)
        end,
        Env,
        Fields
    );
pattern({tuple, _, Patterns}, {tuple, Types}, Env, Context) when
    length(Patterns) =:= length(Types)
->
    lists:foldl(
        fun({P, T}, Acc) -> pattern(P, T, Acc, Context) end,
        Env,
        lists:zip(Patterns, Types)
    );
pattern({bin, _, Segments}, _, Env, Context) ->
    lists:foldl(
        fun({bin_element, _, P, _, Types}, Acc) ->
            Type =
                case
                    Types =/= default andalso
                        lists:any(
                            fun(T) -> lists:member(T, [binary, bytes, bitstring, bits, float]) end,
                            Types
                        )
                of
                    true -> other;
                    false -> integer
                end,
            pattern(P, Type, Acc, Context)
        end,
        Env,
        Segments
    );
pattern({cons, _, Head, Tail}, Type = {array, Element}, Env, Context) ->
    pattern(Tail, Type, pattern(Head, Element, Env, Context), Context);
pattern(_, _, Env, _) ->
    Env.

%% Unknown records/fields are diagnosed by the ordinary declaration checker.
-spec field(atom(), atom(), context()) -> shape().
field(Name, Slot, #{records := Records}) ->
    maps:get(Slot, maps:get(Name, Records, #{}), unknown).

-doc "Lowers a mathematical integer comparison to structured DSLX helper calls, preserving widening and signedness. Literals retain sufficient independent width.".
-spec lower(atom(), [xls_clause_lower:printable()]) -> xls_dslx:expr().
lower(Op, [Left, Right]) ->
    Function =
        case Op of
            '<' -> "less";
            '=<' -> "less_equal";
            '>' -> "less";
            '>=' -> "less_equal";
            '=:=' -> "equal";
            '=/=' -> "equal"
        end,
    Args =
        case Op of
            '>' -> [Right, Left];
            '>=' -> [Right, Left];
            _ -> [Left, Right]
        end,
    Call = xls_dslx:call("hls_integer::" ++ Function, [literal(A) || A <- Args]),
    case Op of
        '=/=' -> xls_dslx:unary('!', Call);
        _ -> Call
    end.

%% A literal's mathematical value must not inherit its neighbor's narrow type.
-spec literal(xls_clause_lower:printable()) -> xls_clause_lower:printable().
literal({static, integer, N}) -> xls_binary_lower:integer_literal(N);
literal(Value) -> Value.
