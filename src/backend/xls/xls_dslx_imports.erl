-module(xls_dslx_imports).
-moduledoc false.

-export([from_forms/1, emit/2]).

%% Discover declarations from syntax, not from the text emitted by transpile/3.
%% Walking type arguments also finds providers nested inside hls_lists:list/2.
-spec from_forms([erl_parse:abstract_form()]) -> [atom()].
from_forms(Forms) ->
    Uses = uses(Forms),
    Providers = lists:usort([Module || {provider, Module, _Name} <- Uses]),
    OperatorImports = [hls_integer || {operator, _} <- Uses] ++
        [hls_patterns || {pattern, tail} <- Uses] ++
        [hls_bits || bit_syntax <- Uses],
    lists:usort(OperatorImports ++ lists:append([imports(Module,
        lists:usort([Name || {provider, M, Name} <- Uses, M =:= Module])) || Module <- Providers])).

uses({xls_bit_size, _, _, Value}) -> [bit_syntax | uses(Value)];
uses({bin, _, Elements}) -> [bit_syntax | uses(Elements)];
uses({clause, _, Patterns, Guards, Body}) ->
    pattern_uses(Patterns) ++ uses([Guards, Body]);
uses({match, _, Pattern, Value}) ->
    pattern_uses(Pattern) ++ uses(Value);
uses({remote_type, _, [{atom, _, Module}, {atom, _, Name}, Args]}) ->
    [{provider, Module, Name} | uses(Args)];
uses({call, _, {remote, _, {atom, _, Module}, {atom, _, Name}}, Args}) ->
    [{provider, Module, Name} | uses(Args)];
uses({op, _, Op, Left, Right}) when Op =:= 'rem'; Op =:= 'bsl'; Op =:= 'bsr' ->
    [{operator, Op} | uses([Left, Right])];
uses(Tuple) when is_tuple(Tuple) ->
    uses(tuple_to_list(Tuple));
uses(List) when is_list(List) ->
    lists:append([uses(Item) || Item <- List]);
uses(_) ->
    [].

pattern_uses({bin, _, Elements}) -> [bit_syntax | pattern_uses(Elements)];
pattern_uses({cons, _, Head, {var, _, Name}}) when Name =/= '_' ->
    [{pattern, tail} | pattern_uses(Head)];
pattern_uses({cons, _, Head, {match, _, Left, Right}}) ->
    [{pattern, tail} | pattern_uses([Head, Left, Right])];
pattern_uses(Tuple) when is_tuple(Tuple) -> pattern_uses(tuple_to_list(Tuple));
pattern_uses(List) when is_list(List) -> lists:append([pattern_uses(P) || P <- List]);
pattern_uses(_) -> [].

imports(Module, Names) ->
    _ = code:ensure_loaded(Module),
    case erlang:function_exported(Module, dslx_imports, 1) of
        true -> validate(Module, Module:dslx_imports(Names));
        false ->
            case erlang:function_exported(Module, dslx_imports, 0) of
                true -> validate(Module, Module:dslx_imports());
                false -> []
            end
    end.

validate(Provider, Imports) when is_list(Imports) ->
    lists:foreach(fun(Import) ->
        case valid_import(Import) of
            true -> ok;
            false -> error({invalid_dslx_import, Provider, Import})
        end
    end, Imports),
    Imports;
validate(Provider, Imports) ->
    error({invalid_dslx_imports, Provider, Imports}).

valid_import(Import) when is_atom(Import) ->
    re:run(atom_to_list(Import),
        "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*$",
        [{capture, none}]) =:= match;
valid_import(_) ->
    false.

%% Runtime imports retain their established order; companions are sorted and
%% deduplicated, including declarations that name a runtime module themselves.
-spec emit([atom()], [atom()]) -> iolist().
emit(Runtime, Companions) ->
    [["import ", atom_to_list(Module), ";\n"]
        || Module <- Runtime ++ (lists:usort(Companions) -- Runtime)].
