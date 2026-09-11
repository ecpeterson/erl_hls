-module(xls_dslx_imports).
-moduledoc false.

-export([from_forms/1, emit/2]).

%% Discover declarations from syntax, not from the text emitted by transpile/3.
%% Walking type arguments also finds providers nested inside hls_lists:list/2.
-spec from_forms([erl_parse:abstract_form()]) -> [atom()].
from_forms(Forms) ->
    Providers = lists:usort(providers(Forms)),
    lists:usort(lists:append([imports(Module) || Module <- Providers])).

providers({remote_type, _, [{atom, _, Module}, _Name, Args]}) ->
    [Module | providers(Args)];
providers({call, _, {remote, _, {atom, _, Module}, _Name}, Args}) ->
    [Module | providers(Args)];
providers(Tuple) when is_tuple(Tuple) ->
    providers(tuple_to_list(Tuple));
providers(List) when is_list(List) ->
    lists:append([providers(Item) || Item <- List]);
providers(_) ->
    [].

imports(Module) ->
    _ = code:ensure_loaded(Module),
    case erlang:function_exported(Module, dslx_imports, 0) of
        true -> validate(Module, Module:dslx_imports());
        false -> []
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
