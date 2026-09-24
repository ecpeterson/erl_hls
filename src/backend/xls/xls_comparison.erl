%%%% Classify integer comparisons before source values become untyped DSLX text.
-module(xls_comparison).
-moduledoc false.
-export([prepare/1, emit/2]).

%% Only proven integer values select widening comparison. Unknown providers and
%% structural equality remain XLS's responsibility; this is not type inference.
-type shape() :: integer | other | unknown | {tuple, [shape()]} | {array, shape()}.
%% Proven shapes of variables visible at one source point.
-type bindings() :: #{atom() => shape()}.
%% Declaration facts shared by all function bodies in one source module.
-type context() :: #{records := #{atom() => #{atom() => shape()}},
    signatures := #{{atom(), arity()} => {[shape()], shape()}}}.

-doc "Marks comparisons of proven integers without changing arithmetic widths or structural equality.".
-spec prepare([hls_source:form()]) -> [hls_source:form()].
prepare(Forms) ->
    Context = #{records => maps:from_list([{Name, maps:from_list([
        {xls_parse:record_field_name(Field), shape(Type)}
        || {typed_record_field, Field, Type} <- Fields])}
        || {attribute, _, record, {Name, Fields}} <- Forms]),
        signatures => maps:from_list([{Key, {[shape(A) || A <- Args], shape(Result)}}
            || {attribute, _, spec, {Key, [{type, _, 'fun',
                [{type, _, product, Args}, Result]}]}} <- Forms])},
    [case Form of
        {function, Line, Name, Arity, Clauses} ->
            {Types, _} = signature({Name, Arity}, Context),
            {function, Line, Name, Arity, [element(1, clause(C, Types, #{}, Context))
                || C <- Clauses]};
        _ -> Form
    end || Form <- Forms].

%% Concrete provider declarations identify integer values without inspecting
%% emitted type strings. Other providers may have noninteger live values.
-spec shape(erl_parse:abstract_type()) -> shape().
shape({ann_type, _, [_, Type]}) -> shape(Type);
shape({remote_type, _, [{atom, _, hls_nums}, {atom, _, Name}, _]}) ->
    case lists:member(Name, [u8, u16, u32, u64, uN, s8, s16, s32, s64, sN]) of
        true -> integer;
        false -> other
    end;
shape({remote_type, _, [{atom, _, hls_serial}, {atom, _, counter}, _]}) -> integer;
shape({remote_type, _, [{atom, _, hls_fixed}, {atom, _, Kind}, _]})
        when Kind =:= signed; Kind =:= unsigned -> integer;
shape({remote_type, _, [{atom, _, Module}, {atom, _, Name}, [Element, _]]})
        when (Module =:= hls_vec andalso Name =:= vector);
             (Module =:= hls_lists andalso Name =:= list) -> {array, shape(Element)};
shape({type, _, tuple, Elements}) when is_list(Elements) -> {tuple, [shape(T) || T <- Elements]};
shape({type, _, boolean, []}) -> other;
shape({remote_type, _, [{atom, _, hls_bool}, _, _]}) -> other;
shape(_) -> unknown.

%% Missing or overloaded signatures provide no numeric evidence.
-spec signature({atom(), arity()}, context()) -> {[shape()], shape()}.
signature(Key = {_, Arity}, #{signatures := Signatures}) ->
    maps:get(Key, Signatures, {lists:duplicate(Arity, unknown), unknown}).

%% Head patterns refine the signature, then guards and body share those facts.
-spec clause(erl_parse:abstract_clause(), [shape()], bindings(), context()) ->
    {erl_parse:abstract_clause(), shape(), bindings()}.
clause({clause, Line, Patterns, Guards, Body}, Types, Outer, Context) ->
    Bound = lists:foldl(fun({P, T}, Env) -> pattern(P, T, Env, Context) end,
        Outer, lists:zip(Patterns, Types)),
    TypedGuards = [element(1, expressions(G, Bound, Context)) || G <- Guards],
    {TypedBody, Result, After} = expressions(Body, Bound, Context),
    {{clause, Line, Patterns, TypedGuards, TypedBody}, Result, After}.

%% Bindings take effect left to right; the last expression supplies the result.
-spec expressions([term()], bindings(), context()) -> {[term()], shape(), bindings()}.
expressions(Values, Env, Context) ->
    {Typed, {Result, After}} = lists:mapfoldl(fun(Value, {_, Before}) ->
        {Next, Type, Bound} = expression(Value, Before, Context),
        {Next, {Type, Bound}}
    end, {unknown, Env}, Values),
    {Typed, Result, After}.

%% Propagate just enough source shape to distinguish numeric and structural
%% equality. Opaque syntax is traversed but contributes no result-type claim.
-spec expression(term(), bindings(), context()) -> {term(), shape(), bindings()}.
expression({var, _, Name} = E, Env, _) -> {E, maps:get(Name, Env, unknown), Env};
expression({Kind, _, _} = E, Env, _) when Kind =:= integer; Kind =:= char -> {E, integer, Env};
expression({atom, _, _} = E, Env, _) -> {E, other, Env};
expression({match, Line, Pattern, Value}, Env, Context) ->
    {Typed, Type, Bound} = expression(Value, Env, Context),
    {{match, Line, Pattern, Typed}, Type, pattern(Pattern, Type, Bound, Context)};
expression({op, Line, Op, Left, Right}, Env, Context) ->
    {A, AT, AE} = expression(Left, Env, Context),
    {B, BT, BE} = expression(Right, AE, Context),
    Node = case {comparison(Op), AT, BT} of
        {true, integer, integer} -> {xls_integer_compare, Line, Op, A, B};
        {true, integer, Known} when Known =/= unknown ->
            error({unsupported_xls_comparison, Line, Op, AT, BT});
        {true, Known, integer} when Known =/= unknown ->
            error({unsupported_xls_comparison, Line, Op, AT, BT});
        _ -> {op, Line, Op, A, B}
    end,
    %% Short-circuit right-side bindings cannot escape the expression.
    After = case Op of 'andalso' -> AE; 'orelse' -> AE; _ -> BE end,
    {Node, operator_shape(Op), After};
expression({op, Line, Op, Value}, Env, Context) ->
    {Typed, _, After} = expression(Value, Env, Context),
    {{op, Line, Op, Typed}, operator_shape(Op), After};
expression({tuple, Line, Values}, Env, Context) ->
    {Pairs, After} = lists:mapfoldl(fun(Value, Before) ->
        {Next, Type, Bound} = expression(Value, Before, Context),
        {{Next, Type}, Bound}
    end, Env, Values),
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
expression({record_field, Line, Value, Name, Field = {atom, _, Slot}}, Env, Context) ->
    {Typed, _, After} = expression(Value, Env, Context),
    {{record_field, Line, Typed, Name, Field}, field(Name, Slot, Context), After};
expression({call, Line, Target, Args}, Env, Context) ->
    {Typed, _, After} = expressions(Args, Env, Context),
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
expression(Value, Env, _) -> {Value, unknown, Env}.

%% Integer operations require integer operands; Boolean operators yield atoms.
-spec operator_shape(atom()) -> shape().
operator_shape(Op) ->
    case lists:member(Op, ['+', '-', '*', 'div', 'rem', 'band', 'bor', 'bxor', 'bnot', 'bsl', 'bsr']) of
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
type_ast(Value) -> Value.

%% Only public operations with a known live-value contract contribute facts.
-spec call_shape(term(), [term()], context()) -> shape().
call_shape({atom, _, Name}, Args, Context) -> element(2, signature({Name, length(Args)}, Context));
call_shape({remote, _, {atom, _, M}, {atom, _, F}}, [Type | _], _)
        when (M =:= hls_nums andalso F =:= wrap);
             (M =:= hls_type andalso (F =:= as orelse F =:= zero));
             (M =:= hls_serial andalso (F =:= wrap orelse F =:= add orelse F =:= difference)) ->
    type_argument(Type);
call_shape(_, _, _) -> unknown.

%% Branch exports are useful only when every arm proves the same shape.
-spec branches([erl_parse:abstract_clause()], [shape()], bindings(), context()) ->
    {[erl_parse:abstract_clause()], shape(), bindings()}.
branches(Clauses, Types, Env, Context) ->
    Results = [clause(C, Types, Env, Context) || C <- Clauses],
    [First | Rest] = Results,
    After = lists:foldl(fun({_, _, Next}, Acc) ->
        maps:filter(fun(Name, Type) -> maps:get(Name, Next, unknown) =:= Type end, Acc)
    end, element(3, First), Rest),
    Result = element(2, First),
    Joined = case lists:all(fun({_, T, _}) -> T =:= Result end, Rest) of
        true -> Result; false -> unknown
    end,
    {[C || {C, _, _} <- Results], Joined, After}.

%% Pattern projections use declared fields even without a callback signature.
-spec pattern(term(), shape(), bindings(), context()) -> bindings().
pattern({var, _, '_'}, _, Env, _) -> Env;
pattern({var, _, Name}, Type, Env, _) ->
    case maps:is_key(Name, Env) of true -> Env; false -> Env#{Name => Type} end;
pattern({match, _, A, B}, Type, Env, Context) ->
    pattern(B, Type, pattern(A, Type, Env, Context), Context);
pattern({record, _, Name, Fields}, _, Env, Context) ->
    lists:foldl(fun({record_field, _, {atom, _, Slot}, P}, Acc) ->
        pattern(P, field(Name, Slot, Context), Acc, Context)
    end, Env, Fields);
pattern({tuple, _, Patterns}, {tuple, Types}, Env, Context) when length(Patterns) =:= length(Types) ->
    lists:foldl(fun({P, T}, Acc) -> pattern(P, T, Acc, Context) end,
        Env, lists:zip(Patterns, Types));
pattern({bin, _, Segments}, _, Env, Context) ->
    lists:foldl(fun({bin_element, _, P, _, Types}, Acc) ->
        Type = case Types =/= default andalso
                lists:any(fun(T) -> lists:member(T, [binary, bytes, bitstring, bits, float]) end, Types) of
            true -> other; false -> integer
        end,
        pattern(P, Type, Acc, Context)
    end, Env, Segments);
pattern({cons, _, Head, Tail}, Type = {array, Element}, Env, Context) ->
    pattern(Tail, Type, pattern(Head, Element, Env, Context), Context);
pattern(_, _, Env, _) -> Env.

%% Unknown records/fields are diagnosed by the ordinary declaration checker.
-spec field(atom(), atom(), context()) -> shape().
field(Name, Slot, #{records := Records}) ->
    maps:get(Slot, maps:get(Name, Records, #{}), unknown).

-doc "Emits a mathematical integer comparison; literals retain sufficient independent width.".
-spec emit(atom(), [xls_parse:printable()]) -> xls_parse:printable().
emit(Op, [Left, Right]) ->
    Function = case Op of '<' -> "less"; '=<' -> "less_equal";
        '>' -> "less"; '>=' -> "less_equal";
        '=:=' -> "equal"; '=/=' -> "equal" end,
    Args = case Op of '>' -> [Right, Left]; '>=' -> [Right, Left]; _ -> [Left, Right] end,
    Negation = case Op of '=/=' -> "!"; _ -> [] end,
    [Negation, "hls_integer::", Function, "(",
        lists:join(", ", [literal(A) || A <- Args]), ")"].

%% A literal's mathematical value must not inherit its neighbor's narrow type.
-spec literal(xls_parse:printable()) -> xls_parse:printable().
literal({static, integer, N}) -> xls_binary_lower:integer_literal(N);
literal(Value) -> Value.
