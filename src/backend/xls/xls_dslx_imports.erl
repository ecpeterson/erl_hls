-module(xls_dslx_imports).
-moduledoc false.

-export([from_forms/1, emit/2]).

%% Discover declarations from syntax, not from the text emitted by transpile/3.
%% Walking type arguments also finds providers nested inside hls_lists:list/2.
-spec from_forms([erl_parse:abstract_form()]) -> [atom()].
from_forms(Forms) ->
    Uses = uses(Forms),
    Providers = lists:usort([Module || {provider, Module, _Name} <- Uses]),
    OperatorImports = [hls_integer || {operator, 'rem'} <- Uses],
    lists:usort(OperatorImports ++ lists:append([imports(Module,
        lists:usort([Name || {provider, M, Name} <- Uses, M =:= Module])) || Module <- Providers])).

uses({remote_type, _, [{atom, _, Module}, {atom, _, Name}, Args]}) ->
    [{provider, Module, Name} | uses(Args)];
uses({call, _, {remote, _, {atom, _, Module}, {atom, _, Name}}, Args}) ->
    [{provider, Module, Name} | uses(Args)];
uses({op, _, 'rem', Left, Right}) ->
    [{operator, 'rem'} | uses([Left, Right])];
uses(Tuple) when is_tuple(Tuple) ->
    uses(tuple_to_list(Tuple));
uses(List) when is_list(List) ->
    lists:append([uses(Item) || Item <- List]);
uses(_) ->
    [].

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
