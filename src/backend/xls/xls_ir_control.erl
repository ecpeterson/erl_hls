-module(xls_ir_control).
-moduledoc "Automatic cancellation on structured clause expressions, before DSLX rendering. This pass never reads or rewrites serialized XLS IR.".
-export([simplify/2]).

-doc "Simplifies integer eq/ne between a same-width add/sub/xor result and one of its operands to a zero comparison. Follows clause-local binding aliases, preserves subtraction order, and leaves all other nodes unchanged. DSLX enforces arithmetic operand types; original arithmetic statements and failure checks remain evaluated.".
-spec simplify(xls_expr_ir:expr(), xls_expr_ir:definitions()) -> xls_expr_ir:expr().
simplify(Node = {xls_integer_comparison, Op, Left, Right}, Definitions)
        when Op =:= '=:='; Op =:= '=/=' ->
    case cancel(Left, Right, Definitions) of
        none -> case cancel(Right, Left, Definitions) of
            none -> Node;
            {remaining, Value} -> {xls_integer_comparison, Op, Value, {static, integer, 0}}
        end;
        {remaining, Value} -> {xls_integer_comparison, Op, Value, {static, integer, 0}}
    end;
simplify(Node, _) -> Node.

%% The numeric comparison identifies one operand of the retained same-width arithmetic node.
-spec cancel(xls_parse:printable(), xls_parse:printable(), xls_expr_ir:definitions()) ->
    none | {remaining, xls_parse:printable()}.
cancel(Result, Common, Definitions) ->
    Identity = xls_expr_ir:resolve(Common, Definitions),
    case xls_expr_ir:definition(Result, Definitions) of
        {xls_bits_binary, Op, Left, Right} ->
            A = xls_expr_ir:resolve(Left, Definitions),
            B = xls_expr_ir:resolve(Right, Definitions),
            case {Op, A, B} of
                {_, Identity, _} -> {remaining, Right};
                {Commutative, _, Identity} when Commutative =:= '+'; Commutative =:= 'bxor' ->
                    {remaining, Left};
                _ -> none
            end;
        _ -> none
    end.
