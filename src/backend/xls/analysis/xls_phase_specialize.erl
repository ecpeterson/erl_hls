-module(xls_phase_specialize).
-moduledoc "Opt-in source rewrite using xls_phase_values to specialize bounded constant-base shifts at committed phase fields. It obtains ordinary and rewritten specs through xls_statem_lower, retaining source failure checks and reporting the exact sites. This narrow consumer does not replace XLS algebraic optimization or alter default compilation.".
%% Compile ordinary and specialized specs with their source-bound facts.
-export([from_file/2, from_file/3]).

-doc "Infers fresh phase invariants and specializes direct committed-field shift counts to at most four constant alternatives. Valid only for normal initialized, nonfailed actor executions; no incoming-message assumption is added. Returns the ordinary and specialized artifacts, certificate and exact sites. Does not change storage, scheduling, guards or helper bodies.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context()) ->
    {xls_actor_codegen:spec(), xls_actor_codegen:spec(), xls_phase_values:facts(), [map()]}.
from_file(File, Options) -> from_file(File, Options, hls_frame_layout:default()).

-doc "Runs phase specialization with ordinary and rewritten artifacts bound to the same explicit frame layout.".
-spec from_file(
    file:filename(),
    [hls_source:option()] | hls_source:context(),
    hls_frame_layout:layout()
) ->
    {xls_actor_codegen:spec(), xls_actor_codegen:spec(), xls_phase_values:facts(), [map()]}.
from_file(File, Options, Layout) ->
    {ok, Source} = hls_source:parse_file(File, Options),
    Phases = hls_source:find_attribute(Source, hls_phases),
    Ordinary = xls_statem_lower:artifact(File, Source, Phases, Layout),
    Facts = xls_phase_values:analyze(Source, Ordinary),
    #{data_name := Data} = Ordinary,
    {Rewritten, Sites} = lists:mapfoldl(
        fun
            ({function, L, P, 3, Cs} = F, Acc) ->
                case lists:member(P, Phases) of
                    true ->
                        {New, More} = lists:mapfoldl(
                            fun(C, A) -> callback(C, P, Data, Facts, A) end, Acc, Cs
                        ),
                        {{function, L, P, 3, New}, More};
                    false ->
                        {F, Acc}
                end;
            (F, Acc) ->
                {F, Acc}
        end,
        [],
        Source
    ),
    Specialized = xls_statem_lower:artifact(File, Rewritten, Phases, Layout),
    {Ordinary, Specialized, Facts, lists:reverse(Sites)}.

%% Only the original committed-data binding qualifies. A similarly named field
%% in a new record or a helper's argument has no implicit phase invariant.
-spec callback(term(), atom(), atom(), xls_phase_values:facts(), [map()]) -> {term(), [map()]}.
callback({clause, L, [_, _, DataPattern] = Ps, Gs, Body}, Phase, Data, Facts, Sites) ->
    Vars = bindings(DataPattern),
    {New, More} = rewrite(
        Body, #{phase => Phase, data => Data, vars => Vars, facts => Facts}, Sites
    ),
    {{clause, L, Ps, Gs, New}, More};
callback(C, _, _, _, Sites) ->
    {C, Sites}.

%% A head alias names the whole committed record; inner pattern variables do not.
-spec bindings(term()) -> [atom()].
bindings({var, _, '_'}) -> [];
bindings({var, _, V}) -> [V];
bindings({match, _, A, B}) -> bindings(A) ++ bindings(B);
bindings(_) -> [].

%% Transform only a total constant base and an immutable direct record access.
%% All other evaluated expressions and failure locations remain as written.
-spec rewrite(term(), map(), [map()]) -> {term(), [map()]}.
rewrite(
    {op, L, 'bsl', Left, Right = {record_field, _, {var, _, V}, Data, {atom, _, Field}}} = E,
    C = #{phase := P, data := Data, vars := Vars, facts := Facts},
    Sites
) ->
    Values = xls_phase_values:field(Facts, P, Field),
    case lists:member(V, Vars) andalso constant(Left) andalso eligible(Values) of
        true ->
            Mask = discriminator(Values),
            Selected = {op, L, 'band', Right, {integer, L, Mask}},
            New = alternatives(Left, Selected, Values, Mask, L),
            {New, [
                #{
                    phase => P,
                    field => Field,
                    values => Values,
                    line => erl_anno:line(L),
                    discriminator_mask => Mask,
                    operation => constant_shift
                }
                | Sites
            ]};
        false ->
            descend(E, C, Sites)
    end;
rewrite(E, C, Sites) ->
    descend(E, C, Sites).

%% This first consumer deliberately avoids branch-local variable shadowing and
%% alias propagation: only ordinary expressions in a callback are traversed.
-spec descend(term(), map(), [map()]) -> {term(), [map()]}.
descend({'fun', _, _} = E, _, Sites) ->
    {E, Sites};
descend(T, C, Sites) when is_tuple(T) ->
    {New, More} = lists:mapfoldl(fun(E, A) -> rewrite(E, C, A) end, Sites, tuple_to_list(T)),
    {list_to_tuple(New), More};
descend(L, C, Sites) when is_list(L) -> lists:mapfoldl(fun(E, A) -> rewrite(E, C, A) end, Sites, L);
descend(E, _, Sites) ->
    {E, Sites}.

%% Restrict code growth and avoid negative or oversized shift alternatives.
-spec eligible(xls_phase_values:domain()) -> boolean().
eligible(Vs) when is_list(Vs), Vs =/= [], length(Vs) =< 4 ->
    lists:all(fun(V) -> is_integer(V) andalso V >= 0 andalso V < 64 end, Vs);
eligible(_) ->
    false.

%% Type ascription of a literal is total when ordinary lowering accepts it.
%% Arbitrary providers, arithmetic or discarded failure expressions do not qualify.
-spec constant(term()) -> boolean().
constant({integer, _, V}) ->
    V >= 0;
constant(
    {call, _, {remote, _, {atom, _, hls_type}, {atom, _, as}}, [
        {call, _, {remote, _, {atom, _, hls_nums}, {atom, _, Name}}, Args}, {integer, _, V}
    ]}
) ->
    lists:member(Name, [u8, u16, u32, u64, uN]) andalso V >= 0 andalso
        lists:all(
            fun
                ({integer, _, N}) -> N > 0;
                (_) -> false
            end,
            Args
        );
constant(_) ->
    false.

%% Final alternative is justified by the fresh invariant, not a default for
%% arbitrary corrupt machine state. No general-purpose callback API is changed.
-spec alternatives(term(), term(), [integer(), ...], non_neg_integer(), erl_anno:anno()) -> term().
alternatives(Left, _Right, [Last], _Mask, L) ->
    {op, L, 'bsl', Left, {integer, L, Last}};
alternatives(Left, Right, [First | Rest], Mask, L) ->
    {'case', 0, {op, L, '=:=', Right, {integer, L, First band Mask}}, [
        {clause, 0, [{atom, 0, true}], [], [{op, L, 'bsl', Left, {integer, L, First}}]},
        {clause, 0, [{atom, 0, false}], [], [alternatives(Left, Right, Rest, Mask, L)]}
    ]}.

%% One differing bit for each pair suffices to distinguish all admitted values.
%% This removes dependence on every field bit not present in the mask.
-spec discriminator([non_neg_integer()]) -> non_neg_integer().
discriminator(Vs) ->
    lists:foldl(
        fun({A, B}, Mask) ->
            Difference = A bxor B,
            Mask bor (Difference band -Difference)
        end,
        0,
        [{A, B} || A <- Vs, B <- Vs, A < B]
    ).
