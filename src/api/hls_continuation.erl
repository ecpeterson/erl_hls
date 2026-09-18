-module(hls_continuation).
-moduledoc "Finite continuation names shared by server and state-machine callbacks.".
-export([names/1, validate/1, require/2]).

-doc "Reads and validates the callback module's optional hls_continuations declaration.".
-spec names(module()) -> [atom()].
names(Module) ->
    validate(proplists:get_value(hls_continuations, Module:module_info(attributes), [])).

-doc "Accepts at most 255 distinct atom names, excluding reserved absence and Boolean atoms.".
-spec validate(term()) -> [atom()].
validate(Names) ->
    case is_list(Names) andalso length(Names) =< 255 andalso
            lists:all(fun(Name) -> is_atom(Name) andalso
                not lists:member(Name, [none, true, false]) end, Names) andalso
            length(Names) =:= length(lists:usort(Names)) of
        true -> Names;
        false -> error({invalid_hls_continuations, Names})
    end.

-doc "Returns a declared continuation name or rejects an unknown event.".
-spec require(term(), [atom()]) -> atom().
require(Name, Names) ->
    case lists:member(Name, Names) of
        true -> Name;
        false -> error({undeclared_hls_continuation, Name})
    end.
