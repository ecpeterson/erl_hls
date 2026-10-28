-module(xls_hardware_source).
-moduledoc "Selects the local-function, record and type closure reachable from hardware callback roots before semantic validation. State-machine/server preparation and interface analysis use this source-only pass without invoking providers; the original module remains authoritative for BEAM compilation and source identity.".
%% Select explicit callback roots or the complete state-machine callback surface.
-export([select/2, statem/2]).

%% Functions and local type aliases are identified by name and arity.
-type key() :: {atom(), arity()}.
%% Record and alias dependencies share a finite declaration graph.
-type declaration() :: {record, atom()} | {type, key()}.

-doc "Selects state-machine callbacks and their transitive function/type dependencies without interpreting providers. Complete clauses and ordered source locations are retained.".
-spec statem([hls_source:form()], [atom()]) -> [hls_source:form()].
statem(Forms, Phases) ->
    select(Forms, [{init, 1}, {reduce, 3} | [{Phase, 3} || Phase <- Phases]]).

-doc "Retains roots, statically called local helpers and required record/type declarations. This is syntactic reachability, not validation: missing definitions, unsupported operations and recursion remain for the normal lowerer to reject. Does not invoke type providers or modify retained forms.".
-spec select([hls_source:form()], [key()]) -> [hls_source:form()].
select(Forms, Roots) ->
    Module = hls_source:find_attribute(Forms, module),
    Definitions = maps:from_list([
        {{Name, Arity}, Clauses}
     || {function, _, Name, Arity, Clauses} <- Forms
    ]),
    Functions = functions(Roots, Definitions, Module, #{}),
    Selected = [F || F <- Forms, function_form(F, Functions)],
    Values = [F || F <- Selected, is_function_or_spec(F)],
    Declarations = maps:from_list([
        {Key, F}
     || F <- Forms,
        Key <- [declaration_key(F)],
        Key =/= none
    ]),
    Executable = [F || F <- Selected, declaration_key(F) =:= none],
    Required = declarations(
        [{record, N} || N <- hls_records:wire_names(Executable)] ++
            references(Values),
        Declarations,
        #{}
    ),
    [F || F <- Selected, declaration_form(F, Required)].

%% Resolve only known local definitions. Unknown calls remain in their caller
%% for the existing undefined-helper or unsupported-expression diagnostic.
-spec functions([key()], #{key() => term()}, atom(), #{key() => true}) -> #{key() => true}.
functions([], _Definitions, _Module, Seen) ->
    Seen;
functions([Key | Rest], Definitions, Module, Seen) when is_map_key(Key, Seen) ->
    functions(Rest, Definitions, Module, Seen);
functions([Key | Rest], Definitions, Module, Seen) ->
    Calls =
        case maps:find(Key, Definitions) of
            {ok, Clauses} -> calls(Clauses, Module);
            error -> []
        end,
    functions(Calls ++ Rest, Definitions, Module, Seen#{Key => true}).

%% Qualified self calls and unqualified local definitions describe the same
%% graph. BIF shadowing is still resolved by xls_binary_lower after selection.
-spec calls(term(), atom()) -> [key()].
calls({call, _, {atom, _, Name}, Args}, Module) ->
    [{Name, length(Args)} | calls(Args, Module)];
calls({call, _, {remote, _, {atom, _, Module}, {atom, _, Name}}, Args}, Module) ->
    [{Name, length(Args)} | calls(Args, Module)];
calls(Tuple, Module) when is_tuple(Tuple) -> calls(tuple_to_list(Tuple), Module);
calls(List, Module) when is_list(List) -> lists:append([calls(X, Module) || X <- List]);
calls(_, _) ->
    [].

%% Specifications belong to their retained functions; behaviour declarations
%% describe host APIs and cannot contribute imports to an actor implementation.
-spec function_form(hls_source:form(), #{key() => true}) -> boolean().
function_form({function, _, Name, Arity, _}, Keys) -> is_map_key({Name, Arity}, Keys);
function_form({attribute, _, spec, {Key, _}}, Keys) -> is_map_key(Key, Keys);
function_form({attribute, _, callback, _}, _) -> false;
function_form(_, _) -> true.

%% Only executable roots and their signatures seed private value types.
-spec is_function_or_spec(hls_source:form()) -> boolean().
is_function_or_spec({function, _, _, _, _}) -> true;
is_function_or_spec({attribute, _, spec, _}) -> true;
is_function_or_spec(_) -> false.

%% Both ordinary and opaque local aliases can lead to nested record types.
-spec declaration_key(hls_source:form()) -> declaration() | none.
declaration_key({attribute, _, record, {Name, _}}) ->
    {record, Name};
declaration_key({attribute, _, Kind, {Name, _, Vars}}) when Kind =:= type; Kind =:= opaque ->
    {type, {Name, length(Vars)}};
declaration_key(_) ->
    none.

%% Preserve metadata such as compile flags, actor contracts and include/context
%% markers; only unrelated record/type declarations are removed here.
-spec declaration_form(hls_source:form(), #{declaration() => true}) -> boolean().
declaration_form(Form, Required) ->
    case declaration_key(Form) of
        none -> true;
        Key -> is_map_key(Key, Required)
    end.

%% Cycles terminate here but remain present for semantic layout/type checks.
-spec declarations(
    [declaration()],
    #{declaration() => hls_source:form()},
    #{declaration() => true}
) -> #{declaration() => true}.
declarations([], _Definitions, Seen) ->
    Seen;
declarations([Key | Rest], Definitions, Seen) when is_map_key(Key, Seen) ->
    declarations(Rest, Definitions, Seen);
declarations([Key | Rest], Definitions, Seen) ->
    Dependencies =
        case maps:find(Key, Definitions) of
            {ok, Form} -> references(Form);
            error -> []
        end,
    declarations(Dependencies ++ Rest, Definitions, Seen#{Key => true}).

%% Resolved record descriptors and raw Erlang record syntax use one record
%% walker; alias arguments are also traversed for parameterized local types.
-spec references(term()) -> [declaration()].
references(Term) ->
    [{record, N} || N <- hls_records:references(Term)] ++ aliases(Term).

%% A remote type belongs to a provider, not to the local alias namespace.
-spec aliases(term()) -> [declaration()].
aliases({user_type, _, Name, Args}) -> [{type, {Name, length(Args)}} | aliases(Args)];
aliases(Tuple) when is_tuple(Tuple) -> aliases(tuple_to_list(Tuple));
aliases(List) when is_list(List) -> lists:append([aliases(X) || X <- List]);
aliases(_) -> [].
