-module(xls_helper_modules).
-moduledoc "Preserves source helper module boundaries in generated DSLX. xls_helpers supplies a checked function graph; this module assigns qualified names, rejects circular DSLX imports and builds the extra documents finalized with the actor by xls_emitted. Generated modules belong to that actor's bundle and share its failure codebook.".

%% Restore source ownership after shared semantic analysis.
-export([qualify/2, imports/1]).
%% Build dependency documents without writing files or rendering text early.
-export([emit/3]).
-export_type([owner/0]).

-doc "A source helper's generated module identity, local function spelling and Erlang visibility within the actor bundle.".
-type owner() :: #{
    module := atom(),
    path := file:filename(),
    import := atom(),
    name := string(),
    public := boolean()
}.

-doc "Assigns module-qualified names to imported helpers while retaining local function names for actor-owned helpers. Original exported/private visibility is preserved; overloads receive an arity suffix and otherwise invalid DSLX identifiers are escaped.".
-spec qualify(#{{atom(), arity()} => xls_helpers:helper()}, [hls_source:form()]) ->
    #{{atom(), arity()} => xls_helpers:helper()}.
qualify(Helpers, Forms) ->
    Owners = owners(Forms),
    maps:map(
        fun(Key, Helper) ->
            case maps:find(Key, Owners) of
                error ->
                    Helper;
                {ok, Owner = #{module := Module, name := Name}} ->
                    Helper#{name := atom_to_list(Module) ++ "::" ++ Name, owner => Owner}
            end
        end,
        Helpers
    ).

-doc "Returns actor-scoped imports for captured source modules. The last component retains the source module spelling, so callsites use source_module::function.".
-spec imports([hls_source:form()]) -> [atom()].
imports(Forms) ->
    lists:usort([Import || #{import := Import} <- maps:values(owners(Forms))]).

%% The namespace prevents two actor closures or codebooks from overwriting each other.
-spec owners([hls_source:form()]) -> #{{atom(), arity()} => owner()}.
owners(Forms) ->
    Bindings = maps:with(
        [{N, A} || {function, _, N, A, _} <- Forms],
        xls_source_helpers:bindings(Forms)
    ),
    case map_size(Bindings) of
        0 ->
            #{};
        _ ->
            Root = hls_source:find_attribute(Forms, module),
            Namespace = identifier(Root) ++ "_helpers",
            Values = maps:values(Bindings),
            Reserved =
                ["hls_failure"] ++
                    [identifier(M) || #{module := M} <- Values] ++
                    [xls_names:import_alias(I) || I <- xls_dslx_imports:companions(Forms)],
            Named = maps:map(
                fun(
                    _,
                    #{
                        module := Module,
                        function := Name,
                        arity := Arity,
                        public := Public
                    }
                ) ->
                    Alias = identifier(Module),
                    Overloaded =
                        length([
                            ok
                         || #{module := M, function := N} <- Values,
                            M =:= Module,
                            N =:= Name
                        ]) > 1,
                    Candidate =
                        identifier(Name) ++
                            case Overloaded of
                                true -> "__" ++ integer_to_list(Arity);
                                false -> ""
                            end,
                    Function =
                        case lists:member(Candidate, Reserved) of
                            true -> escape(Name) ++ "__" ++ integer_to_list(Arity);
                            false -> Candidate
                        end,
                    #{
                        module => list_to_atom(Alias),
                        name => Function,
                        public => Public,
                        import => list_to_atom(Namespace ++ "." ++ Alias),
                        path => filename:join(Namespace, Alias ++ ".x")
                    }
                end,
                Bindings
            ),
            Symbols = [{M, N} || #{module := M, name := N} <- maps:values(Named)],
            case length(Symbols) =:= length(lists:usort(Symbols)) of
                true -> Named;
                false -> error({xls_source_helper_name_collision, Symbols})
            end
    end.

%% Valid ordinary source names stay readable; the escape prefix is reserved here.
-spec identifier(atom()) -> string().
identifier(Name) ->
    Text = atom_to_list(Name),
    case
        re:run(Text, "^[A-Za-z_][A-Za-z0-9_]*$", [{capture, none}]) =:= match andalso
            not xls_names:keyword(Text) andalso not lists:prefix("erl_escape_", Text) andalso
            not lists:prefix("XLS_FAILURE_SITE_", Text)
    of
        true -> Text;
        false -> escape(Name)
    end.

%% Hexadecimal source spelling gives a deterministic identifier without keyword collisions.
-spec escape(atom()) -> string().
escape(Name) -> "erl_escape_" ++ binary_to_list(binary:encode_hex(atom_to_binary(Name), lowercase)).

-doc "Builds one document per imported source module, with private callees before their callers. Cross-module function dependencies must also form an acyclic module import graph; DSLX rejects circular imports even without recursive functions.".
-spec emit([xls_helpers:helper()], atom(), map()) ->
    #{file:filename() => xls_emitted:module_document()}.
emit(Helpers, DataName, EnumAtoms) ->
    Imported = [H || H <- Helpers, maps:is_key(owner, H)],
    Modules = lists:usort([M || #{owner := #{module := M}} <- Imported]),
    Graph = maps:from_list([
        {M,
            lists:usort(
                lists:append([
                    calls(Clauses)
                 || #{owner := #{module := Owner}, clauses := Clauses} <- Imported,
                    Owner =:= M
                ])
            ) -- [M]}
     || M <- Modules
    ]),
    _ = lists:foldl(fun(M, Done) -> visit(M, Graph, [], Done) end, #{}, Modules),
    maps:from_list([document(M, Imported, Graph, DataName, EnumAtoms) || M <- Modules]).

%% Inspect typed helper-call nodes only; printed provider code is not metadata.
-spec calls(term()) -> [atom()].
calls({xls_helper_call, _, Name, Args}) ->
    case string:split(Name, "::") of
        [Module, _] -> [list_to_atom(Module) | calls(Args)];
        [_] -> calls(Args)
    end;
calls(Tuple) when is_tuple(Tuple) -> calls(tuple_to_list(Tuple));
calls(List) when is_list(List) -> lists:append([calls(V) || V <- List]);
calls(_) ->
    [].

%% Acyclic functions can still induce circular source-module imports.
-spec visit(atom(), #{atom() => [atom()]}, [atom()], #{atom() => true}) -> #{atom() => true}.
visit(Module, _Graph, _Path, Done) when is_map_key(Module, Done) -> Done;
visit(Module, Graph, Path, Done) ->
    case lists:member(Module, Path) of
        true ->
            error({circular_xls_source_modules, lists:reverse([Module | Path])});
        false ->
            Next = lists:foldl(
                fun(M, Acc) -> visit(M, Graph, [Module | Path], Acc) end,
                Done,
                maps:get(Module, Graph)
            ),
            Next#{Module => true}
    end.

%% Each module needs its provider imports and only the source modules it calls.
-spec document(atom(), [xls_helpers:helper()], #{atom() => [atom()]}, atom(), map()) ->
    {file:filename(), xls_emitted:module_document()}.
document(Module, Helpers, Graph, DataName, EnumAtoms) ->
    Own = [H || H = #{owner := #{module := M}} <- Helpers, M =:= Module],
    [#{owner := #{path := Path}} | _] = Own,
    Dependencies = maps:get(Module, Graph),
    SourceImports = lists:usort([
        I
     || #{owner := #{module := M, import := I}} <- Helpers,
        lists:member(M, Dependencies)
    ]),
    SupportImports = lists:usort(lists:append([Is || #{imports := Is} <- Own])),
    Preamble = [
        "// Generated source helpers; failure codes belong to the enclosing actor bundle.\n",
        xls_dslx_imports:emit([hls_failure], SupportImports ++ SourceImports),
        "\n"
    ],
    Bodies = [
        xls_helpers:emit_function(
            H#{name := N, clauses := local_calls(C, Module)},
            DataName,
            EnumAtoms
        )
     || H = #{owner := #{name := N}, clauses := C} <- Own
    ],
    {Path, #{preamble => Preamble, body => Bodies}}.

%% Same-module calls are unqualified; calls to other source modules remain remote.
-spec local_calls(term(), atom()) -> term().
local_calls({xls_helper_call, Line, Name, Args}, Module) ->
    Local =
        case string:split(Name, "::") of
            [Prefix, Function] ->
                case Prefix =:= atom_to_list(Module) of
                    true -> Function;
                    false -> Name
                end;
            [_] ->
                Name
        end,
    {xls_helper_call, Line, Local, local_calls(Args, Module)};
local_calls(Tuple, Module) when is_tuple(Tuple) ->
    list_to_tuple([local_calls(V, Module) || V <- tuple_to_list(Tuple)]);
local_calls(List, Module) when is_list(List) -> [local_calls(V, Module) || V <- List];
local_calls(Value, _) ->
    Value.
