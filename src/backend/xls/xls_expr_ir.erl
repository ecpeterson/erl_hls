-module(xls_expr_ir).
-moduledoc "Structured scalar expressions within the existing clause IR. Bindings retain arithmetic provenance until DSLX rendering; snippets are opaque leaves, never parsed back into operations.".
-export([remember/3, resolve/2, definition/2, render/1]).
-export_type([expr/0, definitions/0]).

-doc "Arithmetic nodes require same-width integer operands, enforced by DSLX typing. Integer comparisons retain the frontend's numeric-kind evidence and may compare different widths. Width inference is still XLS's responsibility; this is not a complete typed SSA IR.".
-type expr() :: {xls_bits_binary, '+' | '-' | 'bxor', xls_clause_lower:printable(), xls_clause_lower:printable()} |
    {xls_integer_comparison, '<' | '=<' | '>' | '>=' | '=:=' | '=/=',
        xls_clause_lower:printable(), xls_clause_lower:printable()}.

%% Only known node definitions and aliases authorize inspection; other expressions remain opaque.
-type definition() :: expr() | {alias, xls_clause_lower:printable()} | opaque.

-doc "Clause-local definitions keyed by compiler-allocated binding identities; branch-local tables never escape a join.".
-type definitions() :: #{xls_clause_lower:printable() => definition()}.

-doc "Records one emitted binding without evaluating or duplicating it. Aliases retain their original identity; unknown snippets are opaque. Rebinding an identity to itself discards knowledge conservatively.".
-spec remember(xls_clause_lower:printable(), xls_clause_lower:printable(), definitions()) -> definitions().
remember(Place, Node = {xls_bits_binary, _, _, _}, Definitions) -> Definitions#{Place => Node};
remember(Place, Node = {xls_integer_comparison, _, _, _}, Definitions) -> Definitions#{Place => Node};
remember(Place, Value, Definitions) ->
    Definition = case maps:is_key(Value, Definitions) of
        false -> opaque;
        true -> case resolve(Value, Definitions) of Place -> opaque; Original -> {alias, Original} end
    end,
    Definitions#{Place => Definition}.

-doc "Returns the canonical binding identity through already-compressed aliases. Unknown leaves retain their identity; arithmetic is not expanded or equated by rendered text.".
-spec resolve(xls_clause_lower:printable(), definitions()) -> xls_clause_lower:printable().
resolve(Value, Definitions) ->
    case maps:get(Value, Definitions, opaque) of
        {alias, Original} -> Original;
        _ -> Value
    end.

-doc "Returns a retained arithmetic/comparison node or opaque, following binding aliases within the current clause.".
-spec definition(xls_clause_lower:printable(), definitions()) -> expr() | opaque.
definition(Value, Definitions) -> maps:get(resolve(Value, Definitions), Definitions, opaque).

-doc "Renders a structured node once. Operands remain IR values; the enclosing renderer recursively renders them. Numeric comparisons keep their existing widening and signedness semantics.".
-spec render(expr()) -> xls_clause_lower:printable().
render({xls_bits_binary, Op, Left, Right}) ->
    Symbol = case Op of '+' -> " + "; '-' -> " - "; 'bxor' -> " ^ " end,
    [Left, Symbol, Right];
render({xls_integer_comparison, Op, Left, Right}) -> xls_comparison:emit(Op, [Left, Right]).
