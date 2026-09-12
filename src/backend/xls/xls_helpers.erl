%%%% xls_helpers
%%%%
%%%% Collect the local function graph reachable from hardware callbacks. Calls
%%%% remain calls: XLS owns inlining. Its parser requires callees before
%%%% callers, so dependency ordering also diagnoses recursive definitions.
%%%% Specs give each helper a concrete value type; its second result carries
%%%% failure kind through the same selected-outcome path used by case expressions.

-module(xls_helpers).
-moduledoc false.

-export([prepare/2, emit/3]).

-type helper() :: #{name := string(), clause := erl_parse:af_clause(),
    arguments := [iodata()], result := iodata()}.

-spec prepare([erl_parse:abstract_form()], [{atom(), arity()}]) ->
    {[erl_parse:abstract_form()], [helper()]}.
prepare(Forms0, Roots) ->
    Module = xls_parse:find_attribute(Forms0, module),
    Forms = localize(Forms0, Module),
    Definitions = definitions(Forms, undefined, #{}),
    Context = #{definitions => Definitions, roots => Roots, forms => Forms,
        data => xls_parse:state(Forms), tags => xls_parse:find_tags(Forms)},
    Calls = lists:append([local_calls(maps:get(clauses, maps:get(Root, Definitions)))
        || Root <- Roots, maps:is_key(Root, Definitions)]),
    Helpers = reachable(Calls, Context, #{}),
    Rewritten = [case Form of
        {function, Line, Name, Arity, Clauses} ->
            case lists:member({Name, Arity}, Roots) of
                true -> {function, Line, Name, Arity, rewrite(Clauses, Helpers)};
                false -> Form
            end;
        _ -> Form
    end || Form <- Forms],
    {Rewritten, [Helper#{clause := rewrite(maps:get(clause, Helper), Helpers)}
        || Key <- dependency_order(Helpers), Helper <- [maps:get(Key, Helpers)]]}.

dependency_order(Helpers) ->
    {_, Reversed} = lists:foldl(fun(Key, Acc) ->
        visit(Key, [], Helpers, Acc)
    end, {#{}, []}, lists:sort(maps:keys(Helpers))),
    lists:reverse(Reversed).

visit(Key, _Path, _Helpers, {Done, _} = Acc) when is_map_key(Key, Done) -> Acc;
visit(Key, Path, Helpers, Acc) ->
    case lists:member(Key, Path) of
        true -> error({recursive_xls_helpers, lists:reverse([Key | Path])});
        false -> ok
    end,
    Dependencies = lists:usort([Callee || {Callee, _} <-
        local_calls(maps:get(clause, maps:get(Key, Helpers)))]),
    {Done, Reversed} = lists:foldl(fun(Callee, Next) ->
        visit(Callee, [Key | Path], Helpers, Next)
    end, Acc, Dependencies),
    {Done#{Key => true}, [Key | Reversed]}.

%% Qualified calls to this module name the same definition graph. Other
%% remote calls continue through their provider's transpile/3 implementation.
localize({call, Line, {remote, _, {atom, _, Module}, {atom, _, Name}}, Args}, Module) ->
    {call, Line, {atom, Line, Name}, localize(Args, Module)};
localize(Tuple, Module) when is_tuple(Tuple) ->
    list_to_tuple([localize(X, Module) || X <- tuple_to_list(Tuple)]);
localize(List, Module) when is_list(List) -> [localize(X, Module) || X <- List];
localize(Value, _Module) -> Value.

definitions([], _File, Acc) -> Acc;
definitions([{attribute, _, file, {File, _}} | Rest], _File, Acc) ->
    definitions(Rest, File, Acc);
definitions([{function, Line, Name, Arity, Clauses} | Rest], File, Acc) ->
    definitions(Rest, File, Acc#{{Name, Arity} =>
        #{file => File, line => Line, clauses => Clauses}});
definitions([_ | Rest], File, Acc) -> definitions(Rest, File, Acc).

local_calls({call, Line, {atom, _, Name}, Args}) ->
    [{{Name, length(Args)}, Line} | local_calls(Args)];
local_calls(Tuple) when is_tuple(Tuple) -> local_calls(tuple_to_list(Tuple));
local_calls(List) when is_list(List) -> lists:append([local_calls(X) || X <- List]);
local_calls(_) -> [].

reachable([], _Context, Seen) -> Seen;
reachable([{Key, _CallLine} | Rest], Context, Seen) when is_map_key(Key, Seen) ->
    reachable(Rest, Context, Seen);
reachable([{Key, CallLine} | Rest], Context = #{definitions := Definitions,
        roots := Roots}, Seen) ->
    case lists:member(Key, Roots) of
        true -> error({xls_helper_calls_callback, CallLine, Key});
        false -> ok
    end,
    Definition = case maps:find(Key, Definitions) of
        {ok, Value} -> Value;
        error -> error({undefined_xls_helper, CallLine, Key})
    end,
    Helper = prepare_helper(Key, Definition, Context),
    %% Mark before following edges: a cyclic definition graph is finite too.
    reachable(local_calls(maps:get(clause, Helper)) ++ Rest,
        Context, Seen#{Key => Helper}).

prepare_helper(Key = {Name, Arity}, #{file := File, line := Line,
        clauses := Clauses}, Context = #{forms := Forms}) ->
    Origin = {File, Line, Key},
    Clause = case Clauses of
        [C = {clause, _, Parameters, [], _}] ->
            Names = [N || {var, _, N} <- Parameters, N =/= '_'],
            case lists:all(fun({var, _, _}) -> true; (_) -> false end, Parameters)
                    andalso length(Names) =:= length(lists:usort(Names)) of
                true -> C;
                false -> error({unsupported_xls_helper_head, Origin})
            end;
        _ -> error({unsupported_xls_helper_head, Origin})
    end,
    Specs = [Types || {attribute, _, spec, {K, Types}} <- Forms, K =:= Key],
    {Args, Result} = case Specs of
        [[{type, _, 'fun', [{type, _, product, A}, R]}]]
                when length(A) =:= Arity -> {A, R};
        [] -> error({missing_xls_helper_spec, Origin});
        _ -> error({unsupported_xls_helper_spec, Origin})
    end,
    Spelling = atom_to_list(Name),
    case re:run(Spelling, "^[A-Za-z_][A-Za-z0-9_]*$", [{capture, none}]) of
        match -> ok;
        nomatch -> error({unsupported_xls_helper_name, Origin})
    end,
    #{name => "hls_local_" ++ Spelling ++ "__" ++ integer_to_list(Arity),
        clause => Clause, arguments => [type(T, Context, Origin) || T <- Args],
        result => type(Result, Context, Origin)}.

type({ann_type, _, [_Name, Type]}, Context, Origin) -> type(Type, Context, Origin);
type({type, _, boolean, []}, _Context, _Origin) -> "bool";
type({type, _, tuple, Fields}, Context, Origin) when is_list(Fields) ->
    ["(", [[type(T, Context, Origin), ", "] || T <- Fields], ")"];
type({type, _, record, [{atom, _, Name}]},
        #{data := Data, tags := Tags, forms := Forms}, Origin) ->
    Struct = string:titlecase(lists:delete($_, atom_to_list(Name))),
    case {Name =:= Data, lists:member(Name, Tags)} of
        {true, _} -> ["(Tag, ", Struct, ")"];
        {false, true} -> ["(Tag, ", Struct, ", bits[",
            integer_to_list(xls_parse:record_width(xls_parse:find_record(Forms, Name))),
            "])"];
        _ -> error({undeclared_xls_helper_record, Origin, Name})
    end;
type({remote_type, _, _} = Type, _Context, Origin) ->
    try hls_type:print_type(hls_type:descriptor(Type)) of
        Printed -> Printed
    catch error:Reason -> error({unsupported_xls_helper_type, Origin, Type, Reason})
    end;
type(Type, _Context, Origin) -> error({unsupported_xls_helper_type, Origin, Type}).

rewrite({call, Line, {atom, _, Name}, Args}, Helpers) ->
    #{name := Emitted} = maps:get({Name, length(Args)}, Helpers),
    {xls_helper_call, Line, Emitted, rewrite(Args, Helpers)};
rewrite(Tuple, Helpers) when is_tuple(Tuple) ->
    list_to_tuple([rewrite(X, Helpers) || X <- tuple_to_list(Tuple)]);
rewrite(List, Helpers) when is_list(List) -> [rewrite(X, Helpers) || X <- List];
rewrite(Value, _Helpers) -> Value.

-spec emit([helper()], atom(), map()) -> iolist().
emit(Helpers, DataName, EnumAtoms) ->
    [emit_helper(H, DataName, EnumAtoms) || H <- Helpers].

emit_helper(#{name := Name, clause := Clause = {clause, Line, _, _, _},
        arguments := Types, result := Type}, DataName, EnumAtoms) ->
    Arguments = ["argument_" ++ integer_to_list(I) || I <- lists:seq(1, length(Types))],
    #{body := Body, result := Result, failure := Failure} =
        xls_parse:clause_outcome(Clause, Arguments, DataName, EnumAtoms),
    ["fn ", Name, "(", lists:join(", ", [[A, ": ", T]
        || {A, T} <- lists:zip(Arguments, Types)]), ") -> (", Type,
        ", hls_failure::Code) {  // L", integer_to_list(erl_anno:line(Line)), "\n",
        xls_parse_io:indent(xls_parse:print([Body,
            "(", Result, ", ", Failure, ")"]), 2), "}\n\n"].
