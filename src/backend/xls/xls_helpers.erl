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

%% A reachable helper with concrete input/result types and its source clauses.
-type helper() :: #{name := string(), clauses := [erl_parse:abstract_clause(), ...],
    arguments := [xls_literal_types:type()], argument_records := [none | {record, atom()}],
    result := xls_literal_types:type()}.

-doc "Finds reachable local helpers, checks concrete signatures and recursion, and returns rewritten roots plus dependency-ordered helpers.".
-spec prepare([hls_source:form()], [{atom(), arity()}]) ->
    {[hls_source:form()], [helper()]}.
prepare(Forms0, Roots) ->
    Module = xls_parse:find_attribute(Forms0, module),
    Forms = localize(xls_binary_lower:prepare(Forms0), Module),
    Definitions = definitions(Forms, undefined, #{}),
    Context = #{definitions => Definitions, roots => Roots, forms => Forms,
        data => xls_parse:state(Forms), tags => xls_parse:find_tags(Forms)},
    Calls = lists:append([local_calls(maps:get(clauses, maps:get(Root, Definitions)))
        || Root <- Roots, maps:is_key(Root, Definitions)]),
    Helpers = reachable(Calls, Context, #{}),
    Rewritten = [case Form of
        {function, Line, Name, Arity, Clauses} ->
            case lists:member({Name, Arity}, Roots) of
                true -> {function, Line, Name, Arity,
                    xls_literal_types:clauses(rewrite(Clauses, Helpers), unknown, Forms)};
                false -> Form
            end;
        _ -> Form
    end || Form <- Forms],
    {Rewritten, [Helper#{clauses := xls_literal_types:clauses(
            rewrite(maps:get(clauses, Helper), Helpers), maps:get(result, Helper), Forms)}
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
        local_calls(maps:get(clauses, maps:get(Key, Helpers)))]),
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
    reachable(local_calls(maps:get(clauses, Helper)) ++ Rest,
        Context, Seen#{Key => Helper}).

%% Resolve a reachable helper's one concrete signature and preserve its shape.
-spec prepare_helper({atom(), arity()}, map(), map()) -> helper().
prepare_helper(Key = {Name, Arity}, #{file := File, line := Line,
        clauses := Clauses}, Context = #{forms := Forms}) ->
    Origin = {File, Line, Key},
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
        clauses => Clauses, arguments => [type(T, Context, Origin) || T <- Args],
        argument_records => [argument_record(T) || T <- Args],
        result => type(Result, Context, Origin)}.

%% Keep tuple fields available to literal lowering; provider types are opaque.
-spec type(erl_parse:abstract_type(), map(), term()) -> xls_literal_types:type().
type({ann_type, _, [_Name, Type]}, Context, Origin) -> type(Type, Context, Origin);
type({type, _, boolean, []}, _Context, _Origin) -> {provider, hls_bool:bool()};
type({type, _, tuple, Fields}, Context, Origin) when is_list(Fields) ->
    {tuple, [type(T, Context, Origin) || T <- Fields]};
type({type, _, record, [{atom, _, Name}]},
        #{data := Data, tags := Tags, forms := Forms}, Origin) ->
    Struct = xls_names:record_type(Name),
    case {Name =:= Data, lists:member(Name, Tags)} of
        {true, _} -> {dslx, ["(Tag, ", Struct, ")"]};
        {false, true} -> {dslx, ["(Tag, ", Struct, ", bits[",
            integer_to_list(xls_parse:record_width(xls_parse:find_record(Forms, Name))),
            "])"]};
        _ -> error({undeclared_xls_helper_record, Origin, Name})
    end;
type({remote_type, _, _} = Type, _Context, Origin) ->
    try
        Descriptor = hls_type:descriptor(Type),
        _ = hls_type:print_type(Descriptor),
        {provider, Descriptor}
    catch error:Reason -> error({unsupported_xls_helper_type, Origin, Type, Reason})
    end;
type(Type, _Context, Origin) -> error({unsupported_xls_helper_type, Origin, Type}).

%% Attach argument contracts before flattening can separate literals from uses.
-spec rewrite(term(), #{{atom(), arity()} => helper()}) -> term().
rewrite({call, Line, {atom, _, Name}, Args}, Helpers) ->
    #{name := Emitted, arguments := Types} = maps:get({Name, length(Args)}, Helpers),
    {xls_helper_call, Line, Emitted, [
        {xls_expected, Line, Type, rewrite(Arg, Helpers)}
        || {Arg, Type} <- lists:zip(Args, Types)]};
rewrite(Tuple, Helpers) when is_tuple(Tuple) ->
    list_to_tuple([rewrite(X, Helpers) || X <- tuple_to_list(Tuple)]);
rewrite(List, Helpers) when is_list(List) -> [rewrite(X, Helpers) || X <- List];
rewrite(Value, _Helpers) -> Value.

-doc "Emits dependency-ordered helper definitions with concrete signatures and selected failures.".
-spec emit([helper()], atom(), map()) -> iolist().
emit(Helpers, DataName, EnumAtoms) ->
    [emit_helper(H, DataName, EnumAtoms) || H <- Helpers].

%% Keep the common irrefutable helper compact. Patterned or guarded clauses
%% share callback selection, including function_clause versus body failures.
-spec emit_helper(helper(), atom(), map()) -> iolist().
emit_helper(#{name := Name, clauses := Clauses = [{clause, Line, _, _, _} | _],
        arguments := Types, argument_records := Records, result := ResultType}, DataName, EnumAtoms) ->
    Type = xls_literal_types:format(ResultType),
    Arguments = ["argument_" ++ integer_to_list(I) || I <- lists:seq(1, length(Types))],
    Body = case plain_head(Clauses) of
        true ->
            [Clause] = Clauses,
            #{body := Computation, result := Result, failure := Failure} =
                xls_parse:clause_outcome(Clause, Arguments, DataName, EnumAtoms),
            [Computation, "(", Result, ", ", Failure, ")"];
        false ->
            Inputs = [case Record of
                none -> xls_pattern_lower:value_argument(Argument);
                {record, RecordName} -> xls_pattern_lower:record_argument(
                    RecordName, [Argument, ".1"], Argument)
            end || {Argument, Record} <- lists:zip(Arguments, Records)],
            Failed = fun(Code) -> ["(zero!<", Type, ">(), ", Code, ")"] end,
            {Computation, Result} = xls_callback_lower:lower(Clauses, Inputs,
                DataName, fun(Value) -> ["(", Value, ", hls_failure::NONE)"] end,
                Failed(xls_failure_sites:at(function_clause, Line)), Failed, EnumAtoms),
            [Computation, Result]
    end,
    ["fn ", Name, "(", lists:join(", ", [[A, ": ", xls_literal_types:format(T)]
        || {A, T} <- lists:zip(Arguments, Types)]), ") -> (", Type,
        ", hls_failure::Code) {  // L", integer_to_list(erl_anno:line(Line)), "\n",
        xls_parse_io:indent(xls_parse:print(Body), 2), "}\n\n"].

plain_head([{clause, _, Parameters, [], _}]) ->
    Names = [N || {var, _, N} <- Parameters, N =/= '_'],
    lists:all(fun({var, _, _}) -> true; (_) -> false end, Parameters)
        andalso length(Names) =:= length(lists:usort(Names));
plain_head(_) -> false.

argument_record({ann_type, _, [_Name, Type]}) -> argument_record(Type);
argument_record({type, _, record, [{atom, _, Name}]}) -> {record, Name};
argument_record(_) -> none.
