-module(xls_codegen_fixture).
-moduledoc "Loads intentional compiler-warning fixtures for differential BEAM witnesses.".
-export([load/1]).
-doc "Loads a fixture without treating its deliberately failed/discarded expressions as build errors.".
-spec load(file:filename()) -> module().
load(Path) ->
    {ok, Module, Beam, _Warnings} = compile:file(Path, [binary, return_errors, return_warnings]),
    {module, Module} = code:load_binary(Module, Path, Beam),
    Module.
