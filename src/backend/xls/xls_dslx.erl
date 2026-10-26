-module(xls_dslx).
-moduledoc "Structured DSLX expressions for checked compiler wiring; rendering preserves child order and lexical blocks.".
-export([ref/1, field/2, index/2, slice/3, call/2, literal/2, tuple/1,
    construct/2, construct/3, bind/2, block/2, choose/3, match/2,
    binary/3, unary/2, cast/2, render/1]).
-export_type([expr/0, binding/0, value/0, type/0, name/0, fields/0]).

-doc "A checked DSLX name or pattern spelling supplied by the compiler, without parsing emitted source.".
-type name() :: string() | binary().
-doc "A named DSLX type or a statically sized bit-vector type.".
-type type() :: name() | {bits, pos_integer()}.
-doc "Expression children retain existing clause IR leaves and structured syntax nodes.".
-type value() :: xls_clause_lower:printable().
-doc "Ordered struct fields; order is retained even when their values contain lexical blocks.".
-type fields() :: [{name(), value()}].
%% Operator atoms use DSLX spelling so no source-language operator translation occurs here.
-type binary_op() :: '+' | '-' | '*' | '/' | '%' | '++' | '&&' | '||' |
    '&' | '|' | '^' | '==' | '!=' | '<' | '<=' | '>' | '>=' | '<<' | '>>'.
%% Unary operators keep their operand grouped independently of its original syntax.
-type unary_op() :: '!' | '-' | '~'.
-doc "A named immutable binding within a lexical block.".
-type binding() :: {xls_dslx, bind, name(), value()}.
-doc "A structured expression; branch bodies and binding order remain inspectable until render/1.".
-type expr() ::
    {xls_dslx, ref, name()} |
    {xls_dslx, field, value(), name() | non_neg_integer()} |
    {xls_dslx, index, value(), value()} |
    {xls_dslx, slice, value(), non_neg_integer(), pos_integer()} |
    {xls_dslx, call, name(), [value()]} |
    {xls_dslx, literal, type(), integer()} |
    {xls_dslx, tuple, [value()]} |
    {xls_dslx, construct, type(), fields(), none | {base, value()}} |
    {xls_dslx, block, [value()], value()} |
    {xls_dslx, choose, value(), value(), value()} |
    {xls_dslx, match, value(), [{value(), value()}]} |
    {xls_dslx, binary, binary_op(), value(), value()} |
    {xls_dslx, unary, unary_op(), value()} |
    {xls_dslx, cast, value(), type()}.

-doc "References a checked local or qualified name.".
-spec ref(name()) -> expr().
ref(Name) -> {xls_dslx, ref, Name}.

-doc "Selects a named struct field or a numeric tuple member.".
-spec field(value(), name() | non_neg_integer()) -> expr().
field(Value, Name) -> {xls_dslx, field, Value, Name}.

-doc "Selects an array element using a typed index expression.".
-spec index(value(), value()) -> expr().
index(Value, Index) -> {xls_dslx, index, Value, Index}.

-doc "Selects Width bits starting at the constant numeric bit offset Start.".
-spec slice(value(), non_neg_integer(), pos_integer()) -> expr().
slice(Value, Start, Width) when Start >= 0, Width > 0 ->
    {xls_dslx, slice, Value, Start, Width}.

-doc "Calls a checked function or builtin with arguments in their original order.".
-spec call(name(), [value()]) -> expr().
call(Name, Arguments) -> {xls_dslx, call, Name, Arguments}.

-doc "Constructs an integer literal with an explicit DSLX type.".
-spec literal(type(), integer()) -> expr().
literal(Type, Integer) -> {xls_dslx, literal, Type, Integer}.

-doc "Constructs a tuple, including the required singleton comma.".
-spec tuple([value()]) -> expr().
tuple(Values) -> {xls_dslx, tuple, Values}.

-doc "Constructs a struct with ordered named fields.".
-spec construct(type(), fields()) -> expr().
construct(Type, Fields) -> {xls_dslx, construct, Type, Fields, none}.

-doc "Constructs a struct overriding the supplied base value's fields.".
-spec construct(type(), fields(), value()) -> expr().
construct(Type, Fields, Base) -> {xls_dslx, construct, Type, Fields, {base, Base}}.

-doc "Binds a value once; callers place this statement inside block/2.".
-spec bind(name(), value()) -> binding().
bind(Name, Value) -> {xls_dslx, bind, Name, Value}.

-doc "Keeps ordered statements and their result in one lexical scope; existing statement leaves are accepted.".
-spec block([value()], value()) -> expr().
block(Statements, Result) -> {xls_dslx, block, Statements, Result}.

-doc "Selects one branch without moving its bindings or failure expressions outside the branch.".
-spec choose(value(), value(), value()) -> expr().
choose(Condition, Then, Else) -> {xls_dslx, choose, Condition, Then, Else}.

-doc "Matches ordered checked patterns against one value.".
-spec match(value(), [{value(), value()}]) -> expr().
match(Value, Arms) -> {xls_dslx, match, Value, Arms}.

-doc "Combines operands with a DSLX operator, grouping the expression to preserve precedence.".
-spec binary(binary_op(), value(), value()) -> expr().
binary(Operator, Left, Right) -> {xls_dslx, binary, Operator, Left, Right}.

-doc "Applies a unary DSLX operator to a grouped operand.".
-spec unary(unary_op(), value()) -> expr().
unary(Operator, Value) -> {xls_dslx, unary, Operator, Value}.

-doc "Converts a value using the target DSLX type's cast semantics.".
-spec cast(value(), type()) -> expr().
cast(Value, Type) -> {xls_dslx, cast, Value, Type}.

-doc "Renders a retained expression or existing clause leaf; no lowering or source parsing occurs here.".
-spec render(value()) -> iodata() | char().
render({xls_dslx, ref, Name}) -> Name;
render({xls_dslx, field, Value, Name}) -> [postfix(Value), ".", member(Name)];
render({xls_dslx, index, Value, Index}) -> [postfix(Value), "[", render(Index), "]"];
render({xls_dslx, slice, Value, Start, Width}) ->
    [postfix(Value), "[", integer_to_list(Start), ":", integer_to_list(Start + Width), "]"];
render({xls_dslx, call, Name, Arguments}) ->
    [Name, "(", join([render(Value) || Value <- Arguments]), ")"];
render({xls_dslx, literal, Type, Integer}) ->
    [type(Type), ":", integer_to_list(Integer)];
render({xls_dslx, tuple, [Value]}) -> ["(", render(Value), ",)"];
render({xls_dslx, tuple, Values}) -> ["(", join([render(Value) || Value <- Values]), ")"];
render({xls_dslx, construct, Type, Fields, Base}) ->
    Members = [[Name, ": ", render(Value), ",\n"] || {Name, Value} <- Fields],
    Spread = case Base of none -> []; {base, Value} -> ["..", render(Value), "\n"] end,
    [type(Type), " {\n", xls_parse_io:indent([Members, Spread], 2), "}"];
render({xls_dslx, bind, Name, Value}) -> ["let ", Name, " = ", render(Value), ";\n"];
render({xls_dslx, block, Statements, Result}) ->
    ["{\n", xls_parse_io:indent([render(Statements), render(Result), "\n"], 2), "}"];
render({xls_dslx, choose, Condition, Then, Else}) ->
    ["if ", render(Condition), " ", branch(Then), " else ", branch(Else)];
render({xls_dslx, match, Value, Arms}) ->
    ["match ", render(Value), " {\n", xls_parse_io:indent(
        [[render(Pattern), " => ", render(Body), ",\n"] || {Pattern, Body} <- Arms], 2), "}"];
render({xls_dslx, binary, Operator, Left, Right}) ->
    ["(", operand(Left), " ", atom_to_list(Operator), " ", operand(Right), ")"];
render({xls_dslx, unary, Operator, Value}) -> [atom_to_list(Operator), "(", render(Value), ")"];
render({xls_dslx, cast, Value, Type}) -> ["(", operand(Value), " as ", type(Type), ")"];
render(Value) when is_binary(Value); is_integer(Value) -> Value;
render(Values) when is_list(Values) -> [render(Value) || Value <- Values];
render(Value) -> xls_clause_lower:print(Value).

%% Native type names remain leaves; widths are compiler-checked constants.
-spec type(type()) -> iodata().
type({bits, Width}) -> ["bits[", integer_to_list(Width), "]"];
type(Name) -> Name.

%% Tuple member numbers are syntax positions, never runtime integer literals.
-spec member(name() | non_neg_integer()) -> iodata().
member(Index) when is_integer(Index) -> integer_to_list(Index);
member(Name) -> Name.

%% Parenthesize opaque leaves before postfix access so provider casts remain intact.
-spec postfix(value()) -> iodata().
postfix({xls_dslx, ref, _} = Value) -> render(Value);
postfix({xls_dslx, field, _, _} = Value) -> render(Value);
postfix({xls_dslx, index, _, _} = Value) -> render(Value);
postfix({xls_dslx, slice, _, _, _} = Value) -> render(Value);
postfix({xls_dslx, call, _, _} = Value) -> render(Value);
postfix({xls_dslx, cast, _, _} = Value) -> render(Value);
postfix({xls_dslx, binary, _, _, _} = Value) -> render(Value);
postfix(Value) -> ["(", render(Value), ")"].

%% Existing scalar nodes and opaque snippets may contain operators of lower precedence.
-spec operand(value()) -> iodata() | char().
operand({xls_dslx, choose, _, _, _} = Value) -> ["(", render(Value), ")"];
operand({xls_dslx, match, _, _} = Value) -> ["(", render(Value), ")"];
operand({xls_dslx, _, _} = Value) -> render(Value);
operand({xls_dslx, _, _, _} = Value) -> render(Value);
operand({xls_dslx, _, _, _, _} = Value) -> render(Value);
operand(Value) -> ["(", render(Value), ")"].

%% A branch's existing lexical scope is sufficient; bare expressions get one scope.
-spec branch(value()) -> iodata().
branch({xls_dslx, block, _, _} = Value) -> render(Value);
branch(Value) -> render(block([], Value)).

%% Commas do not change the ordered expression list.
-spec join([iodata()]) -> iodata().
join(Values) -> lists:join(", ", Values).
