-module(hls_actor_constants).
-moduledoc "Structural source-constant analysis under caller-supplied actor inputs. This is a conservative analysis, not an optimization pass or a protocol/progress proof.".
-export([analyze/4, from_source/3, constant/1, value/1, unknown_record/2]).
-export_type([value/0]).

-doc "An overapproximation of a value; unknown includes every Erlang term.".
-type value() :: unknown | unreachable | {scalar, term()} | {atoms, [atom()]} |
    {tuple, [value()]} | {list, [value()]} | {variants, [value()]}.
%% Analysis-local function and record definitions; no cache survives source changes.
-type context() :: #{functions := map(), records := map(), defaults := map(), stack := [tuple()]}.
%% Lexical bindings contain abstract values, never executed user code.
-type env() :: #{atom() => value()}.

-doc "Overapproximates callback data by phase. The caller must supply validated, record-resolved source, every phase, a hardware-normalized initializer and an exhaustive cast-message domain. Entry and internal callbacks are unrestricted; unsupported computations and iteration exhaustion lose facts. Missing phase keys are unreachable only under those assumptions.".
-spec analyze([hls_source:form()], [atom()], {atom(), term()}, [value()]) -> map().
analyze(Forms, Phases, {InitialPhase, InitialData}, Messages) ->
    fixed_point(#{InitialPhase => abstract(InitialData)}, Phases, Messages, context(Forms), 128).

-doc "Derives initialization from validated, record-resolved source, then analyzes the supplied exhaustive cast-message domain. Unknown initialization makes every phase unknown; no source identity or consumer eligibility certificate is issued.".
-spec from_source([hls_source:form()], [atom()], [value()]) -> map().
from_source(Forms, Phases, Messages) ->
    Context = context(Forms),
    case call_local({init, 1}, [{list, []}], Context) of
        {tuple, [{scalar, ok}, {scalar, Phase}, Data]} ->
            true = lists:member(Phase, Phases),
            fixed_point(#{Phase => Data}, Phases, Messages, Context, 128);
        _ -> maps:from_keys(Phases, unknown)
    end.

%% Type-directed defaults match the public lowerer's record construction.
-spec context([hls_source:form()]) -> context().
context(Forms) ->
    Functions = maps:from_list([{{N, A}, Cs} || {function, _, N, A, Cs} <- Forms]),
    Records = maps:from_list([{N, [field_name(F) || F <- Fs]} ||
        {attribute, _, record, {N, Fs}} <- Forms]),
    Defaults = maps:from_list([{N, Fs} || {attribute, _, record, {N, Fs}} <- Forms]),
    #{functions => Functions, records => Records, defaults => Defaults, stack => []}.

-doc "Returns an exact term only when the abstract value establishes every component.".
-spec constant(value()) -> {ok, term()} | unknown.
constant({scalar, V}) -> {ok, V};
constant({atoms, [V]}) -> {ok, V};
constant({tuple, Vs}) -> constant_sequence(Vs, fun list_to_tuple/1);
constant({list, Vs}) -> constant_sequence(Vs, fun(V) -> V end);
constant(_) -> unknown.

-doc "Describes an exact value already normalized to its hardware representation.".
-spec value(term()) -> value().
value(Term) -> abstract(Term).

-doc "Describes a message with a known record tag and unconstrained fields.".
-spec unknown_record(atom(), non_neg_integer()) -> value().
unknown_record(Name, Fields) -> {tuple, [{scalar, Name} | lists:duplicate(Fields, unknown)]}.

%% Structural constants permit fieldwise joins without treating varying tuples as opaque.
-spec abstract(term()) -> value().
abstract(T) when is_tuple(T) -> {tuple, [abstract(V) || V <- tuple_to_list(T)]};
abstract(T) when is_list(T) -> {list, [abstract(V) || V <- T]};
abstract(T) -> {scalar, T}.

%% Record field annotations do not alter tuple position.
-spec field_name(tuple()) -> atom().
field_name({typed_record_field, F, _}) -> field_name(F);
field_name({record_field, _, {atom, _, N}}) -> N;
field_name({record_field, _, {atom, _, N}, _}) -> N.

%% Exact reconstruction fails as soon as any component is uncertain.
-spec constant_sequence([value()], fun(([term()]) -> term())) -> {ok, term()} | unknown.
constant_sequence(Vs, Build) ->
    Values = [constant(V) || V <- Vs],
    case lists:member(unknown, Values) of
        true -> unknown;
        false -> {ok, Build([V || {ok, V} <- Values])}
    end.

%% Join loses distinctions but never discards a possible concrete value.
-spec join(value(), value()) -> value().
join(unreachable, B) -> B;
join(A, unreachable) -> A;
join(A, A) -> A;
join(unknown, _) -> unknown;
join(_, unknown) -> unknown;
join({variants, As}, {variants, Bs}) -> variants(As ++ Bs);
join({variants, As}, B) -> variants([B | As]);
join(A, {variants, Bs}) -> variants([A | Bs]);
join({scalar, A}, {scalar, B}) when is_atom(A), is_atom(B) -> {atoms, lists:usort([A, B])};
join({atoms, As}, {scalar, B}) when is_atom(B) -> {atoms, lists:usort([B | As])};
join({scalar, A}, {atoms, Bs}) when is_atom(A) -> {atoms, lists:usort([A | Bs])};
join({atoms, As}, {atoms, Bs}) -> {atoms, lists:usort(As ++ Bs)};
join({Kind, As}, {Kind, Bs}) when (Kind =:= tuple orelse Kind =:= list), length(As) =:= length(Bs) ->
    {Kind, [join(A, B) || {A, B} <- lists:zip(As, Bs)]};
join(A = {tuple, _}, B = {tuple, _}) -> variants([A, B]);
join(_, _) -> unknown.

%% Keep distinct callback result arities, while joining values of the same shape.
-spec variants([value()]) -> value().
variants(Vs) ->
    Groups = lists:foldl(fun(V, Acc) ->
        Key = case V of {tuple, Fs} -> {tuple, length(Fs)}; _ -> other end,
        Acc#{Key => case maps:find(Key, Acc) of error -> V; {ok, Old} -> join(Old, V) end}
    end, #{}, Vs),
    case maps:values(Groups) of [Only] -> Only; Values -> {variants, Values} end.

%% Widening is simply loss of constants; the finite field domain must stabilize.
-spec fixed_point(map(), [atom()], [value()], context(), non_neg_integer()) -> map().
fixed_point(_States, Phases, _Messages, _Context, 0) -> maps:from_keys(Phases, unknown);
fixed_point(States, Phases, Messages, Context, Fuel) ->
    Next = maps:fold(fun(Phase, Data, Acc0) ->
        %% Any predecessor and internal event is conservative, including unavailable events.
        Events = [{enter, unknown}] ++ [{cast, M} || M <- Messages] ++ [{internal, unknown}],
        lists:foldl(fun({Kind, Message}, Acc) ->
            Result = call_local({Phase, 3}, [{scalar, Kind}, Message, Data], Context),
            add_result(Kind, Phase, Result, Phases, Acc)
        end, Acc0, Events)
    end, States, States),
    case Next =:= States of
        true -> States;
        false -> fixed_point(Next, Phases, Messages, Context, Fuel - 1)
    end.

%% Directives govern mailbox disposal; explicit callback data remains significant.
-spec add_result(atom(), atom(), value(), [atom()], map()) -> map().
add_result(_, _, unreachable, _, States) -> States;
add_result(Kind, Phase, {variants, Values}, Phases, States) ->
    lists:foldl(fun(V, Acc) -> add_result(Kind, Phase, V, Phases, Acc) end, States, Values);
add_result(enter, Phase, {tuple, [Data, _Effects]}, _, States) -> add_state(Phase, Data, States);
add_result(Kind, Phase, {tuple, [Next, Data, _Directive | _]}, Phases, States) when Kind =/= enter ->
    lists:foldl(fun(P, Acc) -> add_state(P, Data, Acc) end,
        States, phase_values(Next, Phase, Phases));
add_result(enter, Phase, _, _, States) -> add_state(Phase, unknown, States);
add_result(_, _, _, Phases, States) ->
    lists:foldl(fun(P, Acc) -> add_state(P, unknown, Acc) end, States, Phases).

%% Reentry names the current phase, including within a joined helper result. Unknown targets permit every phase.
-spec phase_values(value(), atom(), [atom()]) -> [atom()].
phase_values({scalar, repeat_phase}, Phase, _) -> [Phase];
phase_values({scalar, P}, _, Phases) -> [P || lists:member(P, Phases)];
phase_values({atoms, Ps}, Phase, Phases) ->
    lists:usort(lists:append([phase_values({scalar, P}, Phase, Phases) || P <- Ps]));
phase_values(_, _, Phases) -> Phases.

%% Failed callbacks leave their existing state among the accumulated possibilities.
-spec add_state(atom(), value(), map()) -> map().
add_state(P, Data, States) -> States#{P => join(maps:get(P, States, unreachable), Data)}.

%% Local helper analysis is acyclic; unsupported calls cannot manufacture constants.
-spec call_local(tuple(), [value()], context()) -> value().
call_local(Key, Args, Context = #{functions := Functions, stack := Stack}) ->
    case {lists:member(Key, Stack), maps:find(Key, Functions)} of
        {false, {ok, Clauses}} -> element(1, branches(Clauses, Args, #{}, Context#{stack := [Key | Stack]}));
        _ -> unknown
    end.

%% Evaluate all feasible clauses. Ignoring first-match exclusion only adds possibilities.
-spec branches([tuple()], [value()], env(), context()) -> {value(), env()}.
branches(Clauses, Args, Env, Context) ->
    Results = lists:filtermap(fun({clause, _, Patterns, Guards, Body}) ->
        case bind_many(Patterns, Args, Env, Context) of
            impossible -> false;
            Bound -> case guards(Guards, Bound, Context) of
                false -> false;
                true -> {true, sequence(Body, Bound, Context)}
            end
        end
    end, Clauses),
    merge_branches(Results, Env).

%% Only bindings available on every branch may escape its lexical scope.
-spec merge_branches([{value(), env()}], env()) -> {value(), env()}.
merge_branches([], Env) -> {unreachable, Env};
merge_branches([{V, E} | Rest], _Env) ->
    lists:foldl(fun({W, F}, {A, B}) ->
        {join(A, W), maps:from_list([{K, join(X, maps:get(K, F))} ||
            {K, X} <- maps:to_list(B), maps:is_key(K, F)])}
    end, {V, E}, Rest).

%% A guard can exclude a path only when its failure is established.
-spec guards([[term()]], env(), context()) -> boolean().
guards([], _, _) -> true;
guards(Alternatives, Env, Context) ->
    lists:any(fun(And) -> lists:all(fun(G) ->
        case constant(element(1, expression(G, Env, Context))) of
            {ok, true} -> true;
            {ok, _} -> false;
            unknown -> true
        end
    end, And) end, Alternatives).

%% Refutable patterns may exclude exact contradictions but never unknown values.
-spec bind_many([term()], [value()], env(), context()) -> env() | impossible.
bind_many([], [], Env, _) -> Env;
bind_many([P | Ps], [V | Vs], Env, C) ->
    case bind(P, V, Env, C) of
        impossible -> impossible;
        E -> bind_many(Ps, Vs, E, C)
    end;
bind_many(_, _, _, _) -> impossible.

%% A repeated variable is an equality test; it never overwrites its first binding.
-spec bind(term(), value(), env(), context()) -> env() | impossible.
bind({var, _, '_'}, _, Env, _) -> Env;
bind({var, _, N}, V, Env, _) ->
    case maps:find(N, Env) of
        error -> Env#{N => V};
        {ok, Old} -> case {constant(Old), constant(V)} of
            {{ok, A}, {ok, B}} when is_atom(A), is_atom(B), A =/= B -> impossible;
            _ -> Env
        end
    end;
bind({match, _, A, B}, V, Env, C) ->
    case bind(A, V, Env, C) of impossible -> impossible; E -> bind(B, V, E, C) end;
bind({tuple, _, Ps}, {tuple, Vs}, Env, C) -> bind_many(Ps, Vs, Env, C);
bind({tuple, _, Ps}, unknown, Env, C) -> bind_many(Ps, lists:duplicate(length(Ps), unknown), Env, C);
bind({record, _, Name, Fs}, V, Env, C = #{records := Records}) ->
    Names = maps:get(Name, Records),
    Patterns = [{atom, 0, Name} | [case lists:keyfind(N, 1,
        [{F, P} || {record_field, _, {atom, _, F}, P} <- Fs]) of
        false -> {var, 0, '_'}; {_, P} -> P end || N <- Names]],
    bind({tuple, 0, Patterns}, V, Env, C);
bind(P, V, Env, C) ->
    case {constant(element(1, expression(P, Env, C))), constant(V)} of
        {{ok, A}, {ok, B}} when is_atom(A), is_atom(B), A =/= B -> impossible;
        _ -> Env
    end.

%% A failed match/body contributes no successful result to the abstract transition.
-spec sequence([term()], env(), context()) -> {value(), env()}.
sequence([], Env, _) -> {unreachable, Env};
sequence([E], Env, C) -> expression(E, Env, C);
sequence([E | Es], Env, C) ->
    case expression(E, Env, C) of
        {unreachable, Bound} -> {unreachable, Bound};
        {_, Bound} -> sequence(Es, Bound, C)
    end.

%% Evaluate the pure structural subset; all unsupported expressions yield no facts.
-spec expression(term(), env(), context()) -> {value(), env()}.
expression({var, _, N}, Env, _) -> {maps:get(N, Env, unknown), Env};
expression({Kind, _, V}, Env, _) when Kind =:= atom; Kind =:= integer; Kind =:= float; Kind =:= char -> {{scalar, V}, Env};
expression({nil, _}, Env, _) -> {{list, []}, Env};
expression({string, _, S}, Env, _) -> {abstract(S), Env};
expression({tuple, _, Es}, Env, C) -> {Values, Bound} = expressions(Es, Env, C), {{tuple, Values}, Bound};
expression({cons, _, H, T}, Env, C) ->
    {Head, E} = expression(H, Env, C), {Tail, F} = expression(T, E, C),
    {case Tail of {list, Vs} -> {list, [Head | Vs]}; _ -> unknown end, F};
expression({match, _, Pattern, Expr}, Env, C) ->
    {V, E} = expression(Expr, Env, C),
    case bind(Pattern, V, E, C) of impossible -> {unreachable, E}; F -> {V, F} end;
expression({block, _, Es}, Env, C) -> sequence(Es, Env, C);
expression({'case', _, E, Clauses}, Env, C) ->
    {V, Bound} = expression(E, Env, C), branches(Clauses, [V], Bound, C);
expression({'if', _, Clauses}, Env, C) -> branches(Clauses, [], Env, C);
expression({record, _, Name, Fs}, Env, C = #{defaults := Defaults}) ->
    Values = [default(F, C) || F <- maps:get(Name, Defaults)],
    record_update(Name, Fs, {tuple, [{scalar, Name} | Values]}, Env, C);
expression({record, _, Base, Name, Fs}, Env, C) ->
    {V, E} = expression(Base, Env, C), record_update(Name, Fs, V, E, C);
expression({record_field, _, Base, Name, {atom, _, Field}}, Env, C = #{records := Records}) ->
    {V, E} = expression(Base, Env, C),
    {component(V, index(Field, maps:get(Name, Records)) + 1), E};
expression({call, _, {atom, _, Name}, Args}, Env, C) ->
    {Vs, E} = expressions(Args, Env, C),
    {call_local({Name, length(Args)}, Vs, C), E};
expression({call, _, {remote, _, {atom, _, hls_type}, {atom, _, as}}, [_Type, _E]}, Env, _C) ->
    %% Numeric narrowing changes constants unless its type semantics are evaluated.
    {unknown, Env};
expression({op, _, Op, A, B}, Env, C) when Op =:= 'andalso'; Op =:= 'orelse' ->
    %% The second operand's bindings are not unconditional.
    {V, _} = operation(Op, [A, B], Env, C), {V, Env};
expression({op, _, Op, E}, Env, C) -> operation(Op, [E], Env, C);
expression({op, _, Op, A, B}, Env, C) -> operation(Op, [A, B], Env, C);
expression(_, Env, _) -> {unknown, Env}.

%% Only recognized typed zeros or supported literal/default expressions establish values.
-spec default(tuple(), context()) -> value().
default({typed_record_field, {record_field, _, _, Expr}, Type}, C) ->
    case hls_records:is_zero_default(Expr) of
        true -> abstract(hls_type:zero(hls_type:descriptor(Type)));
        false -> element(1, expression(Expr, #{}, C))
    end;
default({record_field, _, _, Expr}, C) -> element(1, expression(Expr, #{}, C));
default(_, _) -> unknown.

%% Process argument bindings in Erlang evaluation order.
-spec expressions([term()], env(), context()) -> {[value()], env()}.
expressions(Es, Env, C) -> lists:mapfoldl(fun(E, B) -> expression(E, B, C) end, Env, Es).

%% Resolve one declared field; unknown names are malformed compiler inputs.
-spec index(atom(), [atom()]) -> pos_integer().
index(Name, Names) -> hd([I || {I, N} <- lists:enumerate(Names), N =:= Name]).

%% Select only structurally known tuple components.
-spec component(value(), pos_integer()) -> value().
component({tuple, Vs}, I) when I =< length(Vs) -> lists:nth(I, Vs);
component(_, _) -> unknown.

%% Record updates preserve untouched fields even when the assigned expression is opaque.
-spec record_update(atom(), [tuple()], value(), env(), context()) -> {value(), env()}.
record_update(Name, Fs, Base, Env, C = #{records := Records}) ->
    Names = maps:get(Name, Records),
    Values = [component(Base, I) || I <- lists:seq(1, length(Names) + 1)],
    {Result, Bound} = lists:foldl(fun({record_field, _, {atom, _, F}, Expr}, {Vs, E}) ->
        {V, Next} = expression(Expr, E, C),
        I = index(F, Names) + 1,
        {[case J =:= I of true -> V; false -> Old end || {J, Old} <- lists:enumerate(Vs)], Next}
    end, {Values, Env}, Fs),
    {{tuple, Result}, Bound}.

%% Only exact scalar operations are evaluated; unknown operands remain unconstrained.
-spec operation(atom(), [term()], env(), context()) -> {value(), env()}.
operation(Op, Es, Env, C) ->
    {Vs, Bound} = expressions(Es, Env, C),
    %% Arithmetic constants need the lowerer's width/signedness context. Do not
    %% use unbounded ERTS arithmetic to infer a finite-width hardware constant.
    Safe = lists:member(Op, ['=:=', '=/=', '==', '/=',
        'not', 'and', 'or', 'xor', 'andalso', 'orelse']) andalso
        lists:all(fun(V) -> case constant(V) of
            {ok, A} when is_atom(A) -> true; _ -> false end end, Vs),
    Value = case {Safe, constant_sequence(Vs, fun(V) -> V end)} of
        {false, _} -> unknown;
        {true, unknown} -> unknown;
        {true, {ok, Args}} ->
            try atom_operation(Op, Args) of
                Result -> abstract(Result)
            catch _:_ -> unreachable end
    end,
    {Value, Bound}.

%% Boolean short-circuit syntax has no callable BIF; remaining supported atom operations do.
-spec atom_operation(atom(), [atom()]) -> boolean().
atom_operation('andalso', [A, B]) -> A andalso B;
atom_operation('orelse', [A, B]) -> A orelse B;
atom_operation(Op, Args) -> apply(erlang, Op, Args).
