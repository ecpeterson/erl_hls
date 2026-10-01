-module(xls_short_circuit_fixture).

%% The same clauses run on BEAM and are lowered into executable DSLX tests.
-export([
    andalso_value/3, orelse_value/3,
    skipped_andalso/3, skipped_orelse/3,
    andalso_rhs_match/3, orelse_rhs_match/3,
    andalso_lhs_match/3, orelse_lhs_match/3,
    nested_andalso/3, nested_orelse/3,
    mixed_operators/3, repeated_variable/3,
    lhs_binding/3, rhs_binding/3,
    preceding_match/3, following_match/3,
    case_on_rhs/3, inside_case/3, inside_if/3
]).

andalso_value(Left, Right, _Extra) ->
    Left andalso Right.

orelse_value(Left, Right, _Extra) ->
    Left orelse Right.

skipped_andalso(_Left, _Right, _Extra) ->
    false andalso (true = false).

skipped_orelse(_Left, _Right, _Extra) ->
    true orelse (false = true).

andalso_rhs_match(Left, Right, _Extra) ->
    Left andalso (true = Right).

orelse_rhs_match(Left, Right, _Extra) ->
    Left orelse (false = Right).

andalso_lhs_match(Left, Right, _Extra) ->
    (true = Left) andalso Right.

orelse_lhs_match(Left, Right, _Extra) ->
    (false = Left) orelse Right.

nested_andalso(Left, Right, Extra) ->
    Left andalso (Right andalso (true = Extra)).

nested_orelse(Left, Right, Extra) ->
    Left orelse (Right orelse (false = Extra)).

mixed_operators(Left, Right, Extra) ->
    (Left andalso (true = Right)) orelse (false = Extra).

repeated_variable(Left, Right, _Extra) ->
    Left andalso (Left = Right).

lhs_binding(Left, Right, _Extra) ->
    (Bound = Left) andalso Right,
    Bound.

rhs_binding(Left, Right, Extra) ->
    Left andalso ((Bound = Right) andalso (Bound =:= Extra)).

preceding_match(Left, Right, Extra) ->
    true = Extra,
    Left andalso Right.

following_match(Left, Right, Extra) ->
    Left andalso (true = Right),
    false = Extra.

case_on_rhs(Left, Right, Extra) ->
    Left andalso (case Right of
        true -> true = Extra;
        false -> false
    end).

inside_case(Left, Right, Extra) ->
    case Left of
        true -> Right andalso (true = Extra);
        false -> Right orelse (false = Extra)
    end.

inside_if(Left, Right, Extra) ->
    if
        Left =:= true -> Right andalso (true = Extra);
        true -> Right orelse (false = Extra)
    end.
