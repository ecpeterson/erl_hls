-module(xls_statem_gather_lower).
-moduledoc "Validates indexed gathers and lowers their typed source callbacks independently of scalar reducers.".
-export([parse_open/2, split_internal/1, analyze/3, interface/1, records/1]).

-doc "Parses a bounded numeric-member gather; its zero element is padding, not an algebraic identity.".
-spec parse_open(term(), term()) -> map().
parse_open({tuple, Line, [{atom, _, open_gather}, {atom, _, Name}, Key,
        {tuple, _, [{atom, _, members_mask}, {integer, _, Capacity}, Mask]},
        Zero = {record, _, Element, _}]}, _Context) when Capacity >= 1, Capacity =< 255 ->
    #{kind => gather, line => Line, name => Name, key_expression => Key,
      member_mask_expression => Mask, identity_expression => Zero, accumulator => record_name(Element),
      population => #{mode => members, size => Capacity, members => lists:seq(0, Capacity - 1), runtime_mask => true}};
parse_open(Action, Line) -> error({unsupported_hls_statem_open_gather, Line, Action}).

%% Prepared helper syntax marks private records as raw struct values.
-spec record_name(atom() | {value, atom()}) -> atom().
record_name({value, Name}) -> Name;
record_name(Name) -> Name.

-doc "Separates gather completion heads from scalar reduction completion heads.".
-spec split_internal([term()]) -> {[term()], [term()]}.
split_internal(Clauses) -> lists:partition(fun
    ({clause, _, [{tuple, _, [{atom, _, gather_complete} | _]}, _, _], _, _}) -> true;
    (_) -> false
end, Clauses).

-doc "Returns typed gather sites and removes only their leading contribution clauses from ordinary dispatch.".
-spec analyze([hls_source:form()], map(), interface | closed) -> map().
analyze(Forms, #{entries := Entries, cast_groups := Groups, gather_completions := Complete,
        data_name := Data, phases := Phases} = Context, Mode) ->
    Opens0 = [O#{phase => maps:get(phase, E), entry_clause => maps:get(clause, E)} || E <- Entries,
        O <- [maps:get(reduction, E, none)], is_map(O), maps:get(kind, O, reduction) == gather],
    Opens = [xls_statem_reduction_lower:collection_open(O#{id => I}, Forms, Data)
        || {I, O} <- lists:enumerate(0, Opens0)],
    {Contributions, Ordinary} = lists:unzip([split_group(G) || G <- Groups]),
    Inputs = lists:append(Contributions),
    Expected = lists:sort([{maps:get(name, O), maps:get(phase, O)} || O <- Opens]),
    CompletionGroups = xls_callback_lower:group_by(Complete, fun completion_key/1),
    case lists:sort([K || {K, _} <- CompletionGroups]) of
        Expected -> ok;
        Actual -> error({incomplete_hls_statem_gather_completions, Expected, Actual})
    end,
    lists:foreach(fun(#{name := Name, phase := Phase}) ->
        case lists:member({Name, Phase}, Expected) of true -> ok; false -> error({gather_without_open, Name, Phase}) end
    end, Inputs),
    Gather = case Opens of
        [] -> none;
        _ ->
            case maps:get(retained_calls, Context, none) of none -> ok; _ -> error(gather_retained_calls_unsupported) end,
            #{data => xls_statem_reduction_lower:collection_type(Forms, Data),
              continuations => maps:get(continuations, Context, []),
              sites => [close_site(O, Inputs, CompletionGroups, Forms, Data, Phases, Mode,
                  maps:get(continuations, Context, [])) || O <- Opens]}
    end,
    #{gathers => Gather, cast_groups => [G || G = {_, Cs} <- Ordinary, Cs =/= []]}.

%% Every schema/phase group keeps its original contribution-before-fallback priority.
-spec split_group({{atom(), atom()}, [term()]}) -> {[map()], {{atom(), atom()}, [term()]}}.
split_group({{Tag, Phase} = Key, Clauses}) ->
    {Prefix, Rest} = lists:splitwith(fun is_gather/1, Clauses),
    case lists:any(fun is_gather/1, Rest) of true -> error({nonprefix_hls_statem_gather, Key}); false -> ok end,
    {[contribution(Tag, Phase, C) || C <- Prefix], {Key, Rest}}.

%% Gather directives must directly finish a callback, with no effectful prefix.
-spec is_gather(term()) -> boolean().
is_gather({clause, _, _, _, Body}) -> case lists:last(Body) of
    {tuple, _, [_, _, {tuple, _, [{atom, _, gather} | _]}]} -> true;
    _ -> false
end.

%% Contributions preserve phase and the entire input data record.
-spec contribution(atom(), atom(), term()) -> map().
contribution(Tag, Phase, C = {clause, Line, [_Message, _, Data], _,
        [{tuple, _, [{atom, _, Phase}, {var, _, Variable},
          {tuple, _, [{atom, _, gather}, {atom, _, Name}, Key, Member, Value]}]}]}) ->
    case data_variable(Data) of Variable -> ok; _ -> error({mutating_hls_statem_gather, Line}) end,
    lists:foreach(fun(Expression) -> case total_expression(Expression) of
        true -> ok;
        false -> error({fallible_hls_statem_gather_expression, Expression})
    end end, [Key, Member, Value]),
    #{tag => Tag, phase => Phase, name => Name, mode => members, clause => C,
      key_expression => Key, member_expression => Member, value_expression => Value};
contribution(Tag, Phase, Clause) -> error({unsupported_hls_statem_gather, Tag, Phase, Clause}).

%% Contribution selection must not turn a selected-body error into ordinary clause fallthrough.
-spec total_expression(term()) -> boolean().
total_expression({Tag, _, _}) when Tag =:= var; Tag =:= integer; Tag =:= char; Tag =:= atom; Tag =:= float -> true;
total_expression({xls_typed_integer, _, _, _}) -> true;
total_expression({record, _, _, Fields}) ->
    lists:all(fun({record_field, _, _, Value}) -> total_expression(Value) end, Fields);
total_expression({record_field, _, Value, _, _}) -> total_expression(Value);
total_expression({tuple, _, Values}) -> lists:all(fun total_expression/1, Values);
total_expression({nil, _}) -> true;
total_expression({cons, _, Head, Tail}) -> total_expression(Head) andalso total_expression(Tail);
total_expression({op, _, Op, Value}) when Op =:= '+'; Op =:= '-'; Op =:= 'bnot'; Op =:= 'not' -> total_expression(Value);
total_expression({op, _, Op, Left, Right}) when Op =:= '+'; Op =:= '-'; Op =:= '*';
        Op =:= 'band'; Op =:= 'bor'; Op =:= 'bxor' -> total_expression(Left) andalso total_expression(Right);
total_expression({call, _, {remote, _, {atom, _, hls_type}, {atom, _, as}},
        [{call, _, {remote, _, {atom, _, hls_nums}, {atom, _, Name}}, Arguments}, Value]}) ->
    lists:member(Name, [u8, u16, u32, u64, uN, s8, s16, s32, s64, sN]) andalso
        lists:all(fun({integer, _, _}) -> true; (_) -> false end, Arguments) andalso total_expression(Value);
total_expression({call, _, {remote, _, {atom, _, hls_type}, {atom, _, zero}}, []}) -> true;
total_expression(_) -> false.

%% Whole-record aliases permit field patterns without permitting contribution mutation.
-spec data_variable(term()) -> atom().
data_variable({var, _, Name}) -> Name;
data_variable({match, _, {var, _, Name}, _}) -> Name;
data_variable({match, _, _, {var, _, Name}}) -> Name;
data_variable(Pattern) -> error({unbound_hls_statem_gather_data, Pattern}).

%% Completion identities are statically dispatched; key, mask and values remain patterns.
-spec completion_key(term()) -> {atom(), atom()}.
completion_key({clause, _, [{tuple, _, [{atom, _, gather_complete}, {atom, _, Name}, _, _, _]},
        {atom, _, Phase}, _], _, _}) -> {Name, Phase};
completion_key(Clause) -> error({unsupported_hls_statem_gather_completion, Clause}).

%% Element types and completion expressions belong to each individual gather site.
-spec close_site(map(), [map()], list(), [term()], atom(), [atom()], interface | closed, [atom()]) -> map().
close_site(O = #{id := Id, name := Name, phase := Phase, accumulator := Element}, Inputs,
        Completions, Forms, Data, Phases, Mode, Names) ->
    Cs = [C || C = #{name := N, phase := P} <- Inputs, N == Name, P == Phase],
    case Cs of [] -> error({gather_without_contributions, Name, Phase}); _ -> ok end,
    [{_, Clauses}] = [G || G = {K, _} <- Completions, K == {Name, Phase}],
    lists:foreach(fun(C) -> lists:foreach(fun(R) ->
        _ = xls_statem_reduction_lower:normalize_completion(R, Phase, Names)
    end, xls_callback_result:results(C)) end, Clauses),
    T = xls_statem_reduction_lower:collection_type(Forms, Element),
    Base = #{id => Id, name => Name, phase => Phase, element => T,
      population => maps:get(population, O), opens_conditionally => maps:get(opens_conditionally, O),
      representation => case {Element =:= Data, lists:member(Element, hls_records:wire_names(Forms))} of
          {true, _} -> data; {false, true} -> tagged; _ -> value
      end},
    Checked = xls_statem_reduction_lower:collection_contributions(Forms, Data, O, Cs, Phases, Mode),
    case Mode of
        interface -> Base#{contributions => lists:usort([maps:get(tag, C) || C <- Checked])};
        closed -> Base#{contributions => Checked, padding => padding(O, Data, T),
            completion => completion(Clauses, Phase, Data, Phases, Names)}
    end.

%% Padding is a constant typed source value, evaluated without actor context.
-spec padding(map(), atom(), map()) -> map().
padding(#{identity_expression := Zero, line := Line}, Data, #{dslx_type := Type}) ->
    Failure = ["zero!<", Type, ">()"],
    {Body, Result} = xls_callback_lower:lower([{clause, Line, [], [], [Zero]}], [], Data,
        fun(R) -> case Zero of {record, _, {value, _}, _} -> R; _ -> [R, ".1"] end end, Failure, fun(_) -> Failure end, #{}),
    #{body => xls_parse:print(Body), result => xls_parse:print(Result)}.

%% The ordered array is passed directly to source code; no application record receives it implicitly.
-spec completion([term()], atom(), atom(), [atom()], [atom()]) -> map().
completion(Clauses0, Phase, DataName, Phases, Names) ->
    Clauses = [begin
        {clause, L, [{tuple, _, [_, _, Key, Mask, Values]}, _, Data], Guards, Body} = C,
        Flat = {clause, L, [Key, Mask, Values, {var, L, '_'}, Data], Guards, Body},
        xls_callback_result:map(Flat, fun(R) -> xls_statem_reduction_lower:normalize_completion(R, Phase, Names) end)
    end || C <- Clauses0],
    Arguments = [xls_pattern_lower:value_argument(N) || N <- ["key", "members", "values", "phase"]] ++
        [xls_pattern_lower:record_argument(DataName, "data", ["(Tag::", xls_names:enum_member(DataName), ", data)"])],
    Tail = case Names of [] -> []; _ -> ", u8:0" end,
    Failure = fun(Code) -> ["(phase, data, Directive::FAIL, false, ", Code, Tail, ")"] end,
    [{clause, Line, _, _, _} | _] = Clauses,
    Enum = maps:merge(maps:from_list([{P, ["Phase::", xls_names:enum_member(P)]} || P <- Phases]),
        #{consume => "Directive::CONSUME", postpone => "Directive::POSTPONE", fail => "Directive::FAIL"}),
    {Body, Result} = xls_callback_lower:lower(Clauses, Arguments, DataName,
        fun(R) -> ["(", R, ".0, ", R, ".1.1, ", R, ".2, ", R, ".3, ", R, ".4",
            case Names of [] -> []; _ -> [", ", R, ".5"] end, ")"] end,
        Failure(xls_failure_sites:at(function_clause, Line)), Failure, Enum),
    #{body => xls_parse:print(Body), result => xls_parse:print(Result)}.

-doc "Strips lowered expressions from a public structural gather interface.".
-spec interface(none | map()) -> none | map().
interface(none) -> none;
interface(G = #{sites := Sites}) -> G#{sites := [(maps:without([completion, padding], S))#{contributions :=
    [maps:get(tag, C) || C <- maps:get(contributions, S)]} || S <- Sites]}.

-doc "Lists each distinct element record required by gather callbacks.".
-spec records(none | map()) -> [atom()].
records(none) -> [];
records(#{sites := Sites}) -> lists:usort([maps:get(name, maps:get(element, S)) || S <- Sites]).
