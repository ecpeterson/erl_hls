-module(xls_statem_continuation).
-moduledoc "Finite internal-event validation and lowering for state machines.".
-export([names/1, groups/2, normalize/4, lower/6]).

-doc "Reads the finite event vocabulary shared with hls_gs continuations.".
-spec names([hls_source:form()]) -> [atom()].
names(Forms) ->
    hls_continuation:validate(case xls_parse:find_optional_attribute(Forms, hls_continuations) of
        none -> [];
        {ok, Names} -> Names
    end).

-doc "Separates named internal steps from reduction completion clauses.".
-spec groups([erl_parse:abstract_clause()], [atom()]) -> {list(), list()}.
groups(Clauses, Names) ->
    {Steps, Reductions} = lists:partition(fun
        ({clause, _, [{atom, _, _}, _, _], _, _}) -> true;
        (_) -> false
    end, Clauses),
    Groups = xls_callback_lower:group_by(Steps, fun
        ({clause, _, [{atom, _, Name}, {atom, _, Phase}, _], _, _}) ->
            {hls_continuation:require(Name, Names), Phase}
    end),
    {Groups, Reductions}.

-doc "Appends a checked event selector to a normalized ordinary callback conclusion.".
-spec normalize(term(), [atom()], boolean(), fun((term()) -> term())) -> term().
normalize(Result, [], false, Normalize) -> Normalize(Result);
normalize(Result, Names, Calls, Normalize) ->
    {Conclusion, Name, Reply} = case Result of
        {tuple, L, [Phase, Data, {atom, _, consume} = Directive, Actions]} ->
            {R, N} = actions(Actions, Names, Calls),
            {{tuple, L, [Phase, Data, Directive]}, N, R};
        {tuple, _, [_, _, _, Actions]} -> error({invalid_hls_statem_event_actions, Actions});
        _ -> {Result, none, none}
    end,
    Code = case Name of none -> 0; _ -> index(Name, Names, 1) end,
    {From, Frame} = case Reply of none -> {{integer, 0, 0}, {integer, 0, 0}}; Pair -> Pair end,
    {xls_map, 0, {tuple, 0, [Normalize(Conclusion), From, Frame]}, fun(R) ->
        ["{ let value = ", R, "; ",
         case Reply of none -> []; _ -> "let reply = axis::pack(value.2.0 as u8, hls_bits::frame_payload(value.2.2)); " end,
         "(value.0.0, value.0.1, value.0.2, value.0.3, value.0.4, u8:", integer_to_list(Code),
         case Calls of
             false -> [];
             true -> case Reply of
                 none -> ", u64:0, zero!<axis::Frame>(), true";
                 _ -> ", value.1 as u64, reply, reply_allowed(value.1 as u64, reply.header.op)"
             end
         end, ") }"]
    end}.

%% A literal action list has at most one reply, then one named internal step.
-spec actions(term(), [atom()], boolean()) -> {none | {term(), term()}, atom()}.
actions({cons, _, {tuple, _, [{atom, _, reply}, From, Frame]}, Tail}, Names, true) ->
    {{From, Frame}, action(Tail, Names)};
actions(Actions, Names, _Calls) -> {none, action(Actions, Names)}.

%% Dynamic event lists and event types would require a general event queue.
-spec action(term(), [atom()]) -> atom().
action({nil, _}, _Names) -> none;
action({cons, _, {tuple, _, [{atom, _, next_event}, {atom, _, internal}, {atom, _, Name}]}, {nil, _}}, Names) ->
    hls_continuation:require(Name, Names);
action(Actions, _Names) -> error({invalid_hls_statem_event_actions, Actions}).

%% Zero is reserved for an absent event; declared names occupy 1 through 255.
-spec index(atom(), [atom(), ...], pos_integer()) -> pos_integer().
index(Name, [Name | _], N) -> N;
index(Name, [_ | Tail], N) -> index(Name, Tail, N + 1).

-doc "Lowers named internal callbacks using the ordinary checked conclusion path.".
-spec lower(list(), [atom()], atom(), map(), boolean(), fun((erl_parse:abstract_clause(), atom()) -> erl_parse:abstract_clause())) -> [map()].
lower(Groups, Names, DataName, Enum, Calls, Normalize) ->
    [begin
        Clauses = [begin
            {clause, L, [_Name, _Phase, Data], Guards, Body} = Normalize(C, Phase),
            {clause, L, [{var, L, '_'}, {var, L, '_'}, Data], Guards, Body}
        end || C <- Group],
        Args = [xls_pattern_lower:value_argument("event"), xls_pattern_lower:value_argument("phase"),
            xls_pattern_lower:record_argument(DataName, "data", ["(Tag::", xls_names:enum_member(DataName), ", data)"])],
        Failure = fun(Code) -> ["(phase, data, Directive::FAIL, u1:0, ", Code, ", u8:0", case Calls of true -> ", u64:0, zero!<axis::Frame>(), true"; false -> [] end, ")"] end,
        [{clause, Line, _, _, _} | _] = Clauses,
        {Body, Value} = xls_callback_lower:lower(Clauses, Args, DataName,
            fun(R) -> ["(", R, ".0, ", R, ".1.1, ", R, ".2, ", R, ".3, ", R, ".4, ", R, ".5", case Calls of true -> [", ", R, ".6, ", R, ".7, ", R, ".8"]; false -> [] end, ")"] end,
            Failure(xls_failure_sites:at(function_clause, Line)), Failure, Enum),
        #{event => index(Name, Names, 1), phase => Phase, body => xls_parse:print(Body), result => xls_parse:print(Value)}
    end || {{Name, Phase}, Group} <- Groups].
