-module(xls_phase_eval).
-moduledoc "Conservative successful-return interpreter for phase-field analysis. Unknown computations retain no value facts; unsupported syntax rejects the analysis.".
-export([context/1, unknown/0, record/2, call/3, clause/3, concrete/2]).
-export_type([value/0, state/0]).

-doc "Abstract immutable value; fresh unknown identities preserve aliases within one callback only.".
-type value() :: integer() | atom() | {nil} | {unknown, reference()} | {tuple, [value()]} |
    {record, atom(), #{atom() => value()}} | {cons, value(), value()}.
-doc "One successful path's variable bindings and equalities; absent equalities mean unconstrained values.".
-type state() :: #{vars := #{atom() => value()}, equal := map()}.
%% Read-only declarations and acyclic functions checked by ordinary lowering.
-type context() :: #{records := map(), functions := map()}.

-doc "Indexes resolved source after ordinary lowering has validated helpers and callback syntax.".
-spec context([hls_source:form()]) -> context().
context(Forms) ->
    #{records => maps:from_list([{N, [field(F) || F <- Fs]}
        || {attribute, _, record, {N, Fs}} <- Forms]),
      functions => maps:from_list([{{N, A}, Cs} || {function, _, N, A, Cs} <- Forms])}.

%% Retain initializers without evaluating arbitrary providers as compiler code.
-spec field(term()) -> {atom(), term()}.
field({typed_record_field, F = {record_field, _, {atom, _, N}, Default}, Type}) ->
    case {xls_parse:is_zero_default(Default), Type} of
        {true, {remote_type, _, [{atom, _, hls_nums}, {atom, _, Kind}, _]}} ->
            case lists:member(Kind, [u8, u16, u32, u64, uN, s8, s16, s32, s64, sN]) of
                true -> {N, {integer, 0, 0}};
                false -> field(F)
            end;
        {true, {remote_type, _, [{atom, _, hls_bool}, {atom, _, bool}, []]}} ->
            {N, {atom, 0, false}};
        _ -> field(F)
    end;
field({record_field, _, {atom, _, N}, V}) -> {N, V};
field({record_field, _, {atom, _, N}}) -> {N, {atom, 0, undefined}}.

-doc "Creates an unconstrained value distinct from every other evaluation.".
-spec unknown() -> value().
unknown() -> {unknown, make_ref()}.

-doc "Creates a typed record with independent unknown fields, never default field values.".
-spec record(atom(), context()) -> value().
record(Name, #{records := Rs}) ->
    {record, Name, maps:from_list([{F, unknown()} || {F, _} <- maps:get(Name, Rs)])}.

-doc "Overapproximates all successful returns of a checked nonrecursive function. More than 512 paths or unsupported syntax aborts; failures yield no committed result.".
-spec call({atom(), arity()}, [value()], context()) -> [{value(), state()}].
call(Key, Args, C = #{functions := Fs}) ->
    clauses(maps:get(Key, Fs), Args, fresh(), C).

-doc "Analyzes one complete callback clause under supplied arguments; unmatched patterns and failing assertions have no successful return.".
-spec clause(erl_parse:abstract_clause(), [value()], context()) -> [{value(), state()}].
clause(Clause, Args, C) -> clauses([Clause], Args, fresh(), C).

%% Each top-level callback has independent unknown input values.
-spec fresh() -> state().
fresh() -> #{vars => #{}, equal => #{}}.

-doc "Resolves successful-path equalities recursively, keeping unresolved values explicitly unknown.".
-spec concrete(value(), state()) -> value().
concrete({unknown, Id} = U, S = #{equal := E}) ->
    case maps:find(Id, E) of {ok, V} -> concrete(V, S); error -> U end;
concrete({record, N, Fs}, S) -> {record, N, maps:map(fun(_, V) -> concrete(V, S) end, Fs)};
concrete({tuple, Vs}, S) -> {tuple, [concrete(V, S) || V <- Vs]};
concrete({cons, H, T}, S) -> {cons, concrete(H, S), concrete(T, S)};
concrete(V, _) -> V.

%% Including shadowed arms is conservative. Stop only at an unguarded arm
%% whose patterns cannot further restrict the incoming abstract arguments.
-spec clauses([term()], [value()], state(), context()) -> [{value(), state()}].
clauses([], _, _, _) -> [];
clauses([{clause, _, Ps, Gs, Body} | Rest], Args, S, C) ->
    Matched = patterns(Ps, Args, S, C),
    Results = lists:append([sequence(Body, T, C) || M <- Matched, T <- guards(Gs, M, C)]),
    Covered = Gs =:= [] andalso lists:any(fun(M) ->
        maps:get(equal, M) =:= maps:get(equal, S)
    end, Matched),
    bounded(Results ++ case Covered of true -> []; false -> clauses(Rest, Args, S, C) end).

%% Keep resource exhaustion distinct from an empty (unreachable) result.
-spec bounded([T]) -> [T].
bounded(Results) when length(Results) =< 512 -> Results;
bounded(_) -> throw({phase_analysis, path_limit}).

%% Arguments and statements preserve source order and selected-path failures.
-spec sequence([term()], state(), context()) -> [{value(), state()}].
sequence([Last], S, C) -> eval(Last, S, C);
sequence([First | Rest], S, C) ->
    bounded(lists:append([sequence(Rest, T, C) || {_, T} <- eval(First, S, C)])).

%% Return product values while threading constraints from evaluated operands.
-spec arguments([term()], state(), context()) -> [{[value()], state()}].
arguments([], S, _) -> [{[], S}];
arguments([H | T], S, C) ->
    bounded([{[V | Vs], End} || {V, Next} <- eval(H, S, C),
        {Vs, End} <- arguments(T, Next, C)]).

%% Unknown providers may fail or return any value. Including every return is
%% safe for containment; none is granted purity, totality or elimination rights.
-spec eval(term(), state(), context()) -> [{value(), state()}].
eval({var, _, N}, S = #{vars := Vs}, _) -> [{maps:get(N, Vs), S}];
eval({Tag, _, V}, S, _) when Tag =:= integer; Tag =:= char; Tag =:= atom -> [{V, S}];
eval({nil, _}, S, _) -> [{{nil}, S}];
eval({tuple, _, Es}, S, C) -> [{{tuple, Vs}, T} || {Vs, T} <- arguments(Es, S, C)];
eval({cons, _, H, T}, S, C) ->
    [{{cons, A, B}, U} || {[A, B], U} <- arguments([H, T], S, C)];
eval({record, _, Name, Fs}, S, C = #{records := Rs}) ->
    Defaults = [{record_field, 0, {atom, 0, F}, V} || {F, V} <- maps:get(Name, Rs),
        not lists:member(F, [N || {record_field, _, {atom, _, N}, _} <- Fs])],
    fields(Defaults ++ Fs, record(Name, C), S, C);
eval({record, _, Base, Name, Fs}, S, C) ->
    bounded(lists:append([case concrete(V, T) of
        {record, Name, _} = R -> fields(Fs, R, T, C);
        {unknown, _} -> fields(Fs, record(Name, C), T, C);
        _ -> [] end || {V, T} <- eval(Base, S, C)]));
eval({record_field, _, Base, Name, {atom, _, F}}, S, C) ->
    [{maps:get(F, Fs), U} || {V, T} <- eval(Base, S, C),
        U <- equal(V, record(Name, C), T), {record, _Name, Fs} <- [concrete(V, U)]];
eval({match, _, P, E}, S, C) ->
    bounded([{V, T} || {V, Next} <- eval(E, S, C), T <- pattern(P, V, Next, C)]);
eval({block, _, Es}, S, C) -> sequence(Es, S, C);
eval({'case', _, E, Cs}, S, C) ->
    bounded(lists:append([clauses(Cs, [V], T, C) || {V, T} <- eval(E, S, C)]));
eval({'if', _, Cs}, S, C) -> clauses(Cs, [], S, C);
eval({op, _, Op, A, B}, S, C) when Op =:= 'andalso'; Op =:= 'orelse' ->
    bounded(lists:append([short_circuit(Op, V, B, T, C) || {V, T} <- eval(A, S, C)]));
eval({op, _, 'not', E}, S, C) ->
    [{not V, T} || {A, Next} <- eval(E, S, C), V <- [true, false], T <- equal(A, V, Next)];
eval({op, _, Op, A, B}, S, C) when Op =:= '=:='; Op =:= '=/=' ->
    bounded(lists:append([comparison(Op, X, Y, T) || {[X, Y], T} <- arguments([A, B], S, C)]));
eval({op, _, Op, A, B}, S, C) when Op =:= '<'; Op =:= '>'; Op =:= '=<'; Op =:= '>=' ->
    [{V, T} || {[X, Y], T} <- arguments([A, B], S, C),
        V <- ordered(Op, concrete(X, T), concrete(Y, T))];
eval({op, _, _, E}, S, C) -> [{unknown(), T} || {_, T} <- eval(E, S, C)];
eval({op, _, _, A, B}, S, C) -> [{unknown(), T} || {_, T} <- arguments([A, B], S, C)];
eval({call, _, {atom, _, Name}, Es}, S, C = #{functions := Fs}) ->
    bounded(lists:append([begin
        CallerVars = maps:get(vars, T),
        [{V, End#{vars := CallerVars}} || {V, End} <-
            clauses(maps:get({Name, length(Es)}, Fs), Vs, T#{vars := #{}}, C)]
    end || {Vs, T} <- arguments(Es, S, C)]));
eval({call, _, {remote, _, _, _}, Es}, S, C) ->
    [{unknown(), T} || {_, T} <- arguments(Es, S, C)];
eval(Other, _, _) -> throw({phase_analysis, {unsupported_expression, element(1, Other)}}).

%% Arithmetic deliberately forgets its result: Erlang integers and scheduled
%% fixed-width operations need a separate overflow-aware transfer function.
-spec ordered(atom(), value(), value()) -> [boolean()].
ordered(Op, X, Y) when is_integer(X), is_integer(Y) -> [erlang:apply(erlang, Op, [X, Y])];
ordered(_, _, _) -> [true, false].

%% Positive equalities refine aliased fields; negative unknown comparisons do
%% not refine. This loses precision, never successful executions.
-spec comparison(atom(), value(), value(), state()) -> [{boolean(), state()}].
comparison(Op, X, Y, S) ->
    True = [{Op =:= '=:=', T} || T <- equal(X, Y, S)],
    False = case concrete(X, S) =:= concrete(Y, S) of
        true -> [];
        false -> [{Op =:= '=/=', S}]
    end,
    True ++ False.

%% Short-circuit alternatives retain constraints established by their operand.
-spec short_circuit(atom(), value(), term(), state(), context()) -> [{value(), state()}].
short_circuit(Op, A, B, S, C) ->
    Continue = Op =:= 'andalso',
    [{not Continue, T} || T <- equal(A, not Continue, S)] ++
        lists:append([eval(B, T, C) || T <- equal(A, Continue, S)]).

%% Record updates preserve every field not explicitly replaced.
-spec fields([term()], value(), state(), context()) -> [{value(), state()}].
fields([], R, S, _) -> [{R, S}];
fields([{record_field, _, {atom, _, F}, E} | Rest], {record, N, Fs}, S, C) ->
    bounded(lists:append([fields(Rest, {record, N, Fs#{F := V}}, T, C)
        || {V, T} <- eval(E, S, C)])).

%% Guard alternatives are a union; failed guard evaluations have no return.
-spec guards([list()], state(), context()) -> [state()].
guards([], S, _) -> [S];
guards(Gs, S, C) -> bounded(lists:append([guard_sequence(G, S, C) || G <- Gs])).

%% Every guard in one alternative must evaluate to true.
-spec guard_sequence([term()], state(), context()) -> [state()].
guard_sequence([], S, _) -> [S];
guard_sequence([G | Rest], S, C) ->
    bounded(lists:append([guard_sequence(Rest, T, C) || {V, Next} <- eval(G, S, C),
        T <- equal(V, true, Next)])).

%% Head matching binds variables left-to-right, including repeated variables.
-spec patterns([term()], [value()], state(), context()) -> [state()].
patterns([], [], S, _) -> [S];
patterns([P | Ps], [V | Vs], S, C) ->
    bounded(lists:append([patterns(Ps, Vs, T, C) || T <- pattern(P, V, S, C)])).

%% Structural patterns materialize unknown values only on successful matches.
-spec pattern(term(), value(), state(), context()) -> [state()].
pattern({var, _, '_'}, _, S, _) -> [S];
pattern({var, _, N}, V, S = #{vars := Vars}, _) ->
    case maps:find(N, Vars) of
        {ok, Old} -> equal(V, Old, S);
        error -> [S#{vars := Vars#{N => V}}]
    end;
pattern({match, _, A, B}, V, S, C) ->
    bounded(lists:append([pattern(B, V, T, C) || T <- pattern(A, V, S, C)]));
pattern({Tag, _, V}, Other, S, _) when Tag =:= integer; Tag =:= char; Tag =:= atom -> equal(V, Other, S);
pattern({nil, _}, V, S, _) -> equal({nil}, V, S);
pattern({tuple, _, Ps}, V, S, C) ->
    Shape = {tuple, [unknown() || _ <- Ps]},
    bounded(lists:append([begin {tuple, Vs} = concrete(V, T), patterns(Ps, Vs, T, C) end
        || T <- equal(V, Shape, S)]));
pattern({record, _, Name, Fs}, V, S, C) ->
    bounded(lists:append([begin
        {record, Name, Fields} = concrete(V, T),
        patterns([P || {record_field, _, _, P} <- Fs],
            [maps:get(F, Fields) || {record_field, _, {atom, _, F}, _} <- Fs], T, C)
    end || T <- equal(V, record(Name, C), S)]));
pattern(Other, _, _, _) -> throw({phase_analysis, {unsupported_pattern, element(1, Other)}}).

%% Unification only adds positive facts; no equation may rewrite an established
%% value or create cyclic unknown aliases.
-spec equal(value(), value(), state()) -> [state()].
equal(A, B, S) -> unify(concrete(A, S), concrete(B, S), S).

%% All structured children must agree on the same successful path.
-spec unify(value(), value(), state()) -> [state()].
unify(V, V, S) -> [S];
unify({unknown, Id}, V, S = #{equal := E}) -> bind(Id, V, S, E);
unify(V, {unknown, Id}, S = #{equal := E}) -> bind(Id, V, S, E);
unify({tuple, As}, {tuple, Bs}, S) when length(As) =:= length(Bs) -> equal_list(As, Bs, S);
unify({record, N, As}, {record, N, Bs}, S) -> equal_list(maps:values(As), maps:values(Bs), S);
unify({cons, A, B}, {cons, X, Y}, S) -> equal_list([A, B], [X, Y], S);
unify(_, _, _) -> [].

%% Thread field equalities rather than independently accepting each one.
-spec equal_list([value()], [value()], state()) -> [state()].
equal_list([], [], S) -> [S];
equal_list([A | As], [B | Bs], S) ->
    bounded(lists:append([equal_list(As, Bs, T) || T <- equal(A, B, S)])).

%% Cyclic record equations have no finite Erlang value. Reject those paths.
-spec bind(reference(), value(), state(), map()) -> [state()].
bind(Id, V, S, E) ->
    case occurs(Id, V) of true -> []; false -> [S#{equal := E#{Id => V}}] end.

%% Resolved abstract values are finite trees before inserting an equality.
-spec occurs(reference(), term()) -> boolean().
occurs(Id, {unknown, Id}) -> true;
occurs(Id, M) when is_map(M) -> occurs(Id, maps:values(M));
occurs(Id, T) when is_tuple(T) -> occurs(Id, tuple_to_list(T));
occurs(Id, L) when is_list(L) -> lists:any(fun(V) -> occurs(Id, V) end, L);
occurs(_, _) -> false.
