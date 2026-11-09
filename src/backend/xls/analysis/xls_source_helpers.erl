-module(xls_source_helpers).
-moduledoc "Closes statically named pure source calls before XLS helper and failure analysis. xls_hardware_source supplies the selected actor roots; imported functions keep their own source locations and private helper scope. Built-in and explicitly exported custom providers retain provider dispatch. No source function is executed during discovery.".

%% Extend a selected local graph and retain its source dependencies.
-export([expand/2, dependencies/1, bindings/1]).
-export_type([snapshot/0]).

-doc "One include-expanded helper module and the preprocessing context used for this compilation.".
-type snapshot() :: #{
    module := module(),
    path := file:filename(),
    context := hls_source:context(),
    forms := [hls_source:form()]
}.
%% Definitions preserve each function's enclosing include filename.
-type definition() :: #{
    form := hls_source:form(), file := file:filename(), specs := [hls_source:form()]
}.
%% A parsed source module, with its value namespace and declared exports.
-type source() :: #{
    snapshot := snapshot(),
    definitions := #{{atom(), arity()} => definition()},
    exports := [{atom(), arity()}],
    imports := #{{atom(), arity()} => module()}
}.
%% The graph marks a name before visiting its body, leaving cycles for normal helper checks.
-type state() :: #{
    root := module(),
    sources := #{module() => source()},
    cache := #{file:filename() => source()},
    helpers := #{{module(), atom(), arity()} => atom()},
    forms := #{{module(), atom(), arity()} => [hls_source:form()]},
    used := #{atom() => true}
}.

-doc "Captures selected remote source calls in one analysis graph while preserving their module ownership for separate DSLX emission. Original supplies the actor's complete source for backreferences. Repeated selection reuses the captured graph; at most 64 modules and 4096 imported functions are admitted.".
-spec expand([hls_source:form()], [hls_source:form()]) -> [hls_source:form()].
expand(Selected, Original) ->
    case hls_source:find_optional_attribute(Selected, hls_source_helpers) of
        {ok, _} ->
            Selected;
        none ->
            Root = source(Original, source_context(Original)),
            #{snapshot := #{module := Module}} = Root,
            State0 = #{
                root => Module,
                sources => #{Module => Root},
                cache => #{},
                helpers => #{},
                forms => #{},
                used => maps:from_keys([N || {function, _, N, _, _} <- Original], true)
            },
            {Rewritten, State} = lists:mapfoldl(
                fun
                    ({function, A, N, Arity, Clauses}, Acc) ->
                        {Body, Next} = rewrite(Clauses, Root, root, Acc),
                        {{function, A, N, Arity, Body}, Next};
                    (Form, Acc) ->
                        {Form, Acc}
                end,
                State0,
                Selected
            ),
            Imported = lists:append([
                Fs
             || {_Key, Fs} <- lists:sort(maps:to_list(maps:get(forms, State)))
            ]),
            Dependencies = [
                maps:get(snapshot, S)
             || {M, S} <- lists:sort(maps:to_list(maps:get(sources, State))),
                M =/= Module,
                used_module(M, State)
            ],
            %% Binary metadata is opaque to generic AST walkers: retained host code
            %% must not add providers, failures, records or hardware dependencies.
            Bindings = maps:from_list([
                {{Local, Arity}, #{
                    module => M,
                    function => N,
                    arity => Arity,
                    public => lists:member(
                        {N, Arity},
                        maps:get(
                            exports,
                            maps:get(M, maps:get(sources, State))
                        )
                    )
                }}
             || {{M, N, Arity}, Local} <- maps:to_list(maps:get(helpers, State))
            ]),
            Marker =
                {attribute, 0, hls_source_helpers,
                    term_to_binary(#{dependencies => Dependencies, bindings => Bindings}, [
                        deterministic
                    ])},
            Rewritten ++ Imported ++ [Marker]
    end.

-doc "Returns imported source snapshots captured by expand/2, without rereading files or loading modules.".
-spec dependencies([hls_source:form()]) -> [snapshot()].
dependencies(Forms) ->
    case hls_source:find_optional_attribute(Forms, hls_source_helpers) of
        none -> [];
        {ok, Encoded} -> maps:get(dependencies, binary_to_term(Encoded, [safe]))
    end.

-doc "Returns source ownership for analysis-local helper identifiers. Emitters use this to restore module-qualified calls and original visibility; these identifiers are not DSLX symbols.".
-spec bindings([hls_source:form()]) ->
    #{
        {atom(), arity()} => #{
            module := module(), function := atom(), arity := arity(), public := boolean()
        }
    }.
bindings(Forms) ->
    case hls_source:find_optional_attribute(Forms, hls_source_helpers) of
        none -> #{};
        {ok, Encoded} -> maps:get(bindings, binary_to_term(Encoded, [safe]))
    end.

%% Provider source inspected for dispatch is not an imported source dependency.
-spec used_module(module(), state()) -> boolean().
used_module(Module, #{helpers := Helpers}) ->
    lists:any(fun({M, _, _}) -> M =:= Module end, maps:keys(Helpers)).

%% Synthetic forms used by source-only callers can omit the usual epp file marker.
-spec source_context([hls_source:form()]) -> hls_source:context().
source_context(Forms) ->
    case hls_source:find_optional_attribute(Forms, hls_source_context) of
        {ok, Context} ->
            Context;
        none ->
            case Forms of
                [{attribute, _, file, _} | _] ->
                    hls_source:from_forms(Forms, []);
                _ ->
                    hls_source:options(
                        atom_to_list(hls_source:find_attribute(Forms, module)) ++ ".erl", []
                    )
            end
    end.

%% Capture raw source; only selected imported function bodies are normalized later.
-spec source([hls_source:form()], hls_source:context()) -> source().
source(Forms, Context = #{directory := Directory, source_name := Filename}) ->
    Module = hls_source:find_attribute(Forms, module),
    Path = filename:absname(Filename, Directory),
    Prepared = Forms,
    Specs = lists:foldl(
        fun
            (Form = {attribute, _, spec, {Key, _}}, Acc) ->
                Acc#{Key => maps:get(Key, Acc, []) ++ [Form]};
            (_, Acc) ->
                Acc
        end,
        #{},
        Prepared
    ),
    #{
        snapshot => #{module => Module, path => Path, context => Context, forms => Forms},
        definitions => definitions(Prepared, Path, Directory, Specs, #{}),
        exports => lists:append([Keys || {attribute, _, export, Keys} <- Forms]),
        imports => maps:from_list([
            {Key, M}
         || {attribute, _, import, {M, Keys}} <- Forms, Key <- Keys
        ])
    }.

%% Include-file markers belong to the following functions, not to their callers.
-spec definitions([hls_source:form()], file:filename(), file:filename(), map(), #{
    {atom(), arity()} => definition()
}) -> #{{atom(), arity()} => definition()}.
definitions([], _File, _Directory, _Specs, Acc) ->
    Acc;
definitions([{attribute, _, file, {File, _}} | Rest], _File, Directory, Specs, Acc) ->
    definitions(Rest, filename:absname(File, Directory), Directory, Specs, Acc);
definitions([Form = {function, _, Name, Arity, _} | Rest], File, Directory, Specs, Acc) ->
    Key = {Name, Arity},
    definitions(Rest, File, Directory, Specs, Acc#{
        Key => #{form => Form, file => File, specs => maps:get(Key, Specs, [])}
    });
definitions([_ | Rest], File, Directory, Specs, Acc) ->
    definitions(Rest, File, Directory, Specs, Acc).

%% Calls remain calls, preserving eager argument evaluation and selected failures.
-spec rewrite(term(), source(), root | imported, state()) -> {term(), state()}.
rewrite({call, A, {remote, R, {atom, MA, Module}, {atom, FA, Name}}, Args}, Caller, Mode, State0) ->
    #{snapshot := #{module := Self}} = Caller,
    case Mode =:= root andalso Module =:= Self of
        true ->
            {Values, State} = rewrite(Args, Caller, Mode, State0),
            {{call, A, {remote, R, {atom, MA, Module}, {atom, FA, Name}}, Values}, State};
        false ->
            {Target, State1} = remote(Module, Name, length(Args), A, Caller, State0),
            {Values, State} = rewrite(Args, Caller, Mode, State1),
            Call =
                case Target of
                    provider -> {remote, R, {atom, MA, Module}, {atom, FA, Name}};
                    {helper, Local} -> {atom, FA, Local}
                end,
            {{call, A, Call, Values}, State}
    end;
rewrite(
    {call, A, {atom, F, Name}, Args},
    Caller = #{snapshot := #{module := Module}, definitions := Definitions, imports := Imports},
    imported,
    State0
) ->
    Key = {Name, length(Args)},
    case maps:find(Key, Definitions) of
        {ok, _} ->
            {Local, State1} = import_function(Module, Name, length(Args), A, Caller, State0),
            {Values, State} = rewrite(Args, Caller, imported, State1),
            {{call, A, {atom, F, Local}, Values}, State};
        error ->
            case maps:find(Key, Imports) of
                {ok, _} ->
                    error({unsupported_xls_source_helper, {Module, Name, length(Args)}, imports});
                error ->
                    error({undefined_xls_source_helper, {Module, Name, length(Args)}, A})
            end
    end;
rewrite(Tuple, Caller, Mode, State0) when is_tuple(Tuple) ->
    {Values, State} = rewrite(tuple_to_list(Tuple), Caller, Mode, State0),
    {list_to_tuple(Values), State};
rewrite(List, Caller, Mode, State0) when is_list(List) ->
    lists:mapfoldl(fun(Item, Acc) -> rewrite(Item, Caller, Mode, Acc) end, State0, List);
rewrite(Value, _Caller, _Mode, State) ->
    {Value, State}.

%% Built-in companions and Erlang expression primitives never become source imports.
-spec remote(module(), atom(), arity(), erl_anno:anno(), source(), state()) ->
    {provider | {helper, atom()}, state()}.
remote(Module, Name, Arity, Line, Caller, State0) ->
    case Module =:= erlang orelse xls_type:provider(Module) =/= Module of
        true ->
            {provider, State0};
        false ->
            case resolve(Module, Caller, State0) of
                {missing, State} ->
                    {provider, State};
                {Source = #{exports := Exports}, State} ->
                    case lists:member({transpile, 3}, Exports) of
                        true ->
                            {provider, State};
                        false ->
                            case lists:member({Name, Arity}, Exports) of
                                false ->
                                    error(
                                        {unexported_xls_source_helper, {Module, Name, Arity}, Line}
                                    );
                                true ->
                                    {Local, Next} = import_function(
                                        Module, Name, Arity, Line, Source, State
                                    ),
                                    {{helper, Local}, Next}
                            end
                    end
            end
    end.

%% Search is source-relative, then follows the caller's explicit include roots.
-spec resolve(module(), source(), state()) -> {missing | source(), state()}.
resolve(Module, _Caller, State = #{root := Module, sources := Sources}) ->
    {maps:get(Module, Sources), State};
resolve(Module, #{snapshot := #{path := CallerPath, context := Context}}, State0) ->
    #{directory := Directory, includes := Includes} = Context,
    Candidates = [
        filename:join(Dir, atom_to_list(Module) ++ ".erl")
     || Dir <- [filename:dirname(CallerPath) | [filename:absname(I, Directory) || I <- Includes]]
    ],
    case lists:search(fun filelib:is_regular/1, Candidates) of
        false ->
            {missing, State0};
        {value, Path} ->
            #{sources := Sources, cache := Cache} = State0,
            case maps:find(Module, Sources) of
                {ok, #{snapshot := #{path := Prior}}} when Prior =/= Path ->
                    error({ambiguous_xls_source_module, Module, Prior, Path});
                _ ->
                    ok
            end,
            Existing =
                case maps:find(Module, Sources) of
                    {ok, BoundSource} -> {ok, BoundSource};
                    error -> maps:find(Path, Cache)
                end,
            case Existing of
                {ok, Source} ->
                    {Source, State0};
                error ->
                    case map_size(Sources) < 64 orelse is_map_key(Module, Sources) of
                        true -> ok;
                        false -> error({xls_source_helper_limit, modules, 64})
                    end,
                    ProviderContext = (maps:remove(origins, Context))#{source_name := Path},
                    Forms = hls_source:read(Path, ProviderContext),
                    Actual = hls_source:find_attribute(Forms, module),
                    case Actual =:= Module of
                        true -> ok;
                        false -> error({xls_source_module_mismatch, Module, Actual, Path})
                    end,
                    Source = source(Forms, hls_source:from_forms(Forms, [])),
                    {Source, State0#{
                        sources := Sources#{Module => Source}, cache := Cache#{Path => Source}
                    }}
            end
    end.

%% Store the name first so mutual recursion is finite and remains visible downstream.
-spec import_function(module(), atom(), arity(), erl_anno:anno(), source(), state()) ->
    {atom(), state()}.
import_function(
    Module,
    Name,
    Arity,
    Line,
    Source = #{definitions := Definitions, snapshot := #{forms := SourceForms}},
    State0 = #{helpers := Helpers}
) ->
    Key = {Module, Name, Arity},
    case maps:find(Key, Helpers) of
        {ok, Local} ->
            {Local, State0};
        error ->
            case map_size(Helpers) < 4096 of
                true -> ok;
                false -> error({xls_source_helper_limit, functions, 4096})
            end,
            Definition =
                case maps:find({Name, Arity}, Definitions) of
                    {ok, Value} -> Value;
                    error -> error({undefined_xls_source_helper, Key, Line})
                end,
            validate_function(Key, Definition, SourceForms),
            {Local, State1} = fresh(Key, State0),
            State2 = State1#{helpers := Helpers#{Key => Local}},
            #{form := Function, specs := Specs, file := File} = Definition,
            {function, A, Name, Arity, Clauses} = prepare_function(Function, SourceForms),
            {Rewritten, State3} = rewrite(Clauses, Source, imported, State2),
            RenamedSpecs = [
                {attribute, S, spec, {{Local, Arity}, Types}}
             || {attribute, S, spec, {{_OriginalName, _OriginalArity}, Types}} <- Specs
            ],
            Emitted =
                [{attribute, A, file, {File, erl_anno:line(A)}}] ++ RenamedSpecs ++
                    [{function, A, Local, Arity, Rewritten}],
            {Local, State3#{forms := (maps:get(forms, State3))#{Key => Emitted}}}
    end.

%% BIF shadowing and no_auto_import are properties of the defining module.
-spec prepare_function(hls_source:form(), [hls_source:form()]) -> hls_source:form().
prepare_function(Function, Forms) ->
    Context =
        [F || F = {attribute, _, compile, _} <- Forms] ++
            [{function, A, N, Arity, []} || {function, A, N, Arity, _} <- Forms] ++
            [
                {function, A, N, Arity, []}
             || {attribute, A, import, {_, Keys}} <- Forms, {N, Arity} <- Keys
            ],
    lists:last(xls_binary_lower:prepare(Context ++ [Function])).

%% This slice handles values with representation independent of a module-local record namespace.
-spec validate_function({module(), atom(), arity()}, definition(), [hls_source:form()]) -> ok.
validate_function(Key, #{form := Form, specs := Specs}, Forms) ->
    case hls_records:references([Form | Specs]) of
        [] -> ok;
        _ -> error({unsupported_xls_source_helper, Key, record_values})
    end,
    case local_alias([Form | Specs]) of
        true -> error({unsupported_xls_source_helper, Key, local_type_alias});
        false -> ok
    end,
    Options = lists:flatten([
        case O of
            L when is_list(L) -> L;
            _ -> [O]
        end
     || {attribute, _, compile, O} <- Forms
    ]),
    case [P || {parse_transform, P} <- Options] of
        [] -> ok;
        _ -> error({unsupported_xls_source_helper, Key, parse_transform})
    end.

%% A source alias is not a provider descriptor and must not leak into the actor's namespace.
-spec local_alias(term()) -> boolean().
local_alias({user_type, _, _, _}) -> true;
local_alias(Tuple) when is_tuple(Tuple) -> local_alias(tuple_to_list(Tuple));
local_alias(List) when is_list(List) -> lists:any(fun local_alias/1, List);
local_alias(_) -> false.

%% Readable names retain source identity; escaping unusual atoms and collisions is deterministic.
-spec fresh({module(), atom(), arity()}, state()) -> {atom(), state()}.
fresh(Key = {Module, Name, Arity}, State) ->
    Plain =
        "hls_import_" ++ atom_to_list(Module) ++ "__" ++ atom_to_list(Name) ++ "__" ++
            integer_to_list(Arity),
    Base =
        case
            length(Plain) < 200 andalso
                re:run(Plain, "^[A-Za-z_][A-Za-z0-9_]*$", [{capture, none}]) =:= match
        of
            true ->
                Plain;
            false ->
                "hls_import_" ++
                    binary_to_list(
                        binary:encode_hex(crypto:hash(sha256, term_to_binary(Key)), lowercase)
                    )
        end,
    fresh(Base, 0, State).

%% Source helpers can use any Erlang identifier without capturing a generated name.
-spec fresh(string(), non_neg_integer(), state()) -> {atom(), state()}.
fresh(Base, Suffix, State = #{used := Used}) ->
    Spelling =
        case Suffix of
            0 -> Base;
            _ -> Base ++ "__" ++ integer_to_list(Suffix)
        end,
    Name = list_to_atom(Spelling),
    case is_map_key(Name, Used) of
        true -> fresh(Base, Suffix + 1, State);
        false -> {Name, State#{used := Used#{Name => true}}}
    end.
