-module(xls_statem_plan).
-moduledoc "Retains checked callback structure for a bounded ownership-planning consumer. This sidecar establishes provenance and dependency closure, not field independence, protocol refinement or physical benefit.".
-export([from_file/2, build/5, validate/3, select/2, manifest/1]).
-export_type([plan/0, selection/0]).

%% Planner-owned data is opaque so consumers select complete callback families
%% instead of constructing partial dispatch chains by dropping inconvenient arms.
-doc "Versioned planning sidecar bound to preprocessed source and ordinary lowering; validate against current source before using a saved value.".
-opaque plan() :: #{version := 1, source := file:filename(), source_sha256 := binary(),
    artifact_sha256 := binary(), planner_md5 := binary(), phases := [atom(), ...],
    data := map(), records := [hls_source:form()], callbacks := [map()],
    entries := [map()], roots := [map()], helpers := [map()], protocol := map()}.

-doc "A whole phase/event family. Selection retains every ordered clause, including failure and postponement alternatives; it cannot select a single successful clause.".
-type selection() :: {atom(), enter | cast | call | internal}.

-doc "Compiles an actor once and returns its unchanged rendering artifact with a planning sidecar. Source options have the ordinary compiler's preprocessing meaning; invalid actors fail in ordinary lowering.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context()) ->
    {xls_actor_codegen:spec(), plan()}.
from_file(Filename, Options) ->
    {ok, Source} = xls_parse:parse_file(Filename, Options),
    Phases = xls_parse:find_attribute(Source, hls_phases),
    xls_statem_lower:planned_artifact(Filename, Source, Phases).

-doc "Builds a sidecar from one successful ordinary lowering's source, prepared helpers/callbacks and closed artifact. Internal lowerer entry point: callers must not combine inputs from different compilations.".
-spec build([hls_source:form()], [hls_source:form()], [map()], map(),
    xls_actor_codegen:spec()) -> plan().
build(Source, Forms, Helpers, Prepared, Spec = #{source := Filename, phases := Phases,
        data_name := DataName, data_width := DataWidth}) ->
    Families = xls_statem_callbacks:prepare(Forms, Phases),
    Callbacks = lists:append([callbacks(Kind, maps:get(Kind, Families))
        || Kind <- [enter, cast, call, internal]]),
    Roots = [#{function => {Name, Arity}, clauses => Clauses}
        || {function, _, Name, Arity, Clauses} <- Forms,
            {Name, Arity} =:= {init, 1} orelse {Name, Arity} =:= {reduce, 3}],
    %% Verify dependency closure before exposing a plan, including helper bodies
    %% not directly called by any selected callback. Ordering is XLS's callee order.
    _ = closure([maps:get(name, H) || H <- Helpers], Helpers),
    _ = closure(lists:append([maps:get(helpers, C) || C <- Callbacks]) ++
        helper_calls(Roots), Helpers),
    #{version => 1, source => Filename, source_sha256 => digest(Source),
        artifact_sha256 => digest(Spec), planner_md5 => ?MODULE:module_info(md5),
        phases => Phases, data => #{name => DataName, width => DataWidth},
        records => [F || F = {attribute, _, record, _} <- Forms],
        callbacks => Callbacks, entries => maps:get(entries, Prepared), roots => Roots,
        helpers => Helpers,
        protocol => maps:with([capacity, output_names, message_names, message_words,
            retained_calls, continuations, reductions, gathers, failure_sites], Spec)}.

-doc "Recompiles current source and compares the complete sidecar, renaming only compilation-local payload-origin identities. Rejects stale or modified plans; this freshness check is not an equivalence proof.".
-spec validate(file:filename(), [hls_source:option()] | hls_source:context(), plan()) -> ok.
validate(Filename, Options, Plan) ->
    {_, Current} = from_file(Filename, Options),
    case canonical(Current) =:= canonical(Plan) of
        true -> ok;
        false -> error(stale_statem_plan)
    end.

-doc "Selects nonempty complete phase/event families and their transitive helpers in dependency order. Keeps exact clauses, entry programs, all record declarations and actor-wide protocol obligations. Provider calls are inventoried, not certified for projection; the result remains planning-only.".
-spec select(plan(), [selection(), ...]) -> map().
select(Plan = #{callbacks := Callbacks, entries := Entries, roots := Roots,
        helpers := Helpers}, Choices) ->
    ok = choices(Choices, Callbacks),
    Selected = [C || C = #{phase := P, kind := K} <- Callbacks,
        lists:member({P, K}, Choices)],
    SelectedEntries = [E || E = #{phase := P} <- Entries, lists:member({P, enter}, Choices)],
    Needed = closure(lists:append([maps:get(helpers, C) || C <- Selected]) ++
        helper_calls([Roots, SelectedEntries]), Helpers),
    SelectedHelpers = [H || H = #{name := Name} <- Helpers, lists:member(Name, Needed)],
    Providers = lists:usort(lists:append([maps:get(providers, C) || C <- Selected]) ++
        provider_calls([Roots, SelectedEntries]) ++
        lists:append([provider_calls(maps:get(clauses, H)) || H <- SelectedHelpers])),
    #{role => planning_only, source => maps:get(source, Plan),
        source_sha256 => maps:get(source_sha256, Plan),
        artifact_sha256 => maps:get(artifact_sha256, Plan),
        planner_md5 => maps:get(planner_md5, Plan), choices => Choices,
        callbacks => Selected, helpers => SelectedHelpers, providers => Providers,
        entries => SelectedEntries, roots => Roots,
        data => maps:get(data, Plan), records => maps:get(records, Plan),
        protocol => maps:get(protocol, Plan)}.

-doc "Produces a compact, serializable inventory without source bodies. Counts describe retained structure, not inferred independence, totality, removed hardware or timing.".
-spec manifest(plan()) -> map().
manifest(#{version := Version, source := Source, source_sha256 := SourceHash,
        artifact_sha256 := ArtifactHash, planner_md5 := PlannerHash, phases := Phases,
        data := Data, callbacks := Callbacks, entries := Entries, roots := Roots, helpers := Helpers}) ->
    #{version => Version, role => planning_only, source => Source,
        source_sha256 => binary:encode_hex(SourceHash, lowercase),
        artifact_sha256 => binary:encode_hex(ArtifactHash, lowercase),
        planner_md5 => binary:encode_hex(PlannerHash, lowercase), phases => Phases, data => Data,
        callbacks => [maps:without([clause], C) || C <- Callbacks],
        entries => [#{phase => maps:get(phase, E), alternatives => length(maps:get(variants, E))}
            || E <- Entries],
        roots => [#{function => maps:get(function, R), helpers => helper_calls(R),
            providers => provider_calls(R)} || R <- Roots],
        helpers => [#{name => maps:get(name, H),
            helpers => helper_calls(maps:get(clauses, H)),
            providers => provider_calls(maps:get(clauses, H))} || H <- Helpers]}.

%% Callback preparation preserves order within a family. Ordinals are per
%% phase/event, not source line numbers (which can collide after includes/macros).
-spec callbacks(atom(), [erl_parse:abstract_clause()]) -> [map()].
callbacks(Kind, Clauses) ->
    {Result, _} = lists:mapfoldl(fun(Clause = {clause, _, [_, {atom, _, Phase} | _], _, _}, Seen) ->
        Ordinal = maps:get(Phase, Seen, 0) + 1,
        {#{phase => Phase, kind => Kind, ordinal => Ordinal, clause => Clause,
            helpers => helper_calls(Clause), providers => provider_calls(Clause)},
            Seen#{Phase => Ordinal}}
    end, #{}, Clauses),
    Result.

%% Empty/duplicate/missing families must not become vacuous success at a later
%% dependency boundary. Selection does not prune by schema, guard or outcome.
-spec choices([selection()], [map()]) -> ok.
choices([], _Callbacks) -> error(empty_statem_plan_selection);
choices(Choices, Callbacks) ->
    case length(Choices) =:= length(lists:usort(Choices)) of
        true -> ok;
        false -> error(duplicate_statem_plan_selection)
    end,
    Available = lists:usort([{P, K} || #{phase := P, kind := K} <- Callbacks]),
    case Choices -- Available of
        [] -> ok;
        Missing -> error({missing_statem_plan_families, Missing})
    end.

%% Follow only prepared helper-call nodes; a miss indicates a broken sidecar,
%% never permission to treat an opaque computation as independent or pure.
-spec closure([string()], [map()]) -> [string()].
closure(Roots, Helpers) ->
    Definitions = maps:from_list([{Name, H} || H = #{name := Name} <- Helpers]),
    case map_size(Definitions) =:= length(Helpers) of
        true -> closure(lists:usort(Roots), Definitions, []);
        false -> error(duplicate_statem_plan_helper)
    end.

%% The upstream helper preparation rejects recursion; the visited set also
%% bounds traversal when checking a damaged externally retained sidecar.
-spec closure([string()], #{string() => map()}, [string()]) -> [string()].
closure([], _Definitions, Seen) -> lists:sort(Seen);
closure([Name | Rest], Definitions, Seen) ->
    case lists:member(Name, Seen) of
        true -> closure(Rest, Definitions, Seen);
        false ->
            case maps:find(Name, Definitions) of
                {ok, #{clauses := Clauses}} ->
                    closure(helper_calls(Clauses) ++ Rest, Definitions, [Name | Seen]);
                error -> error({missing_statem_plan_helper, Name})
            end
    end.

%% Retain nested argument calls as well as the direct callee.
-spec helper_calls(term()) -> [string()].
helper_calls(Term) -> lists:usort(calls(Term, helper)).

%% A provider can inspect lowering state. Listing it grants no operand-only
%% semantics, purity, totality or authority to elide its evaluation.
-spec provider_calls(term()) -> [{atom(), atom(), arity()}].
provider_calls(Term) -> lists:usort(calls(Term, provider)).

%% Traverse all evaluated and conditional AST subtrees, including discarded
%% matches and guards, without folding branches or treating dead values as dead work.
-spec calls(term(), helper | provider) -> [term()].
calls({xls_helper_call, _, Name, Args}, helper) -> [Name | calls(Args, helper)];
calls({call, _, {remote, _, {atom, _, Module}, {atom, _, Function}}, Args}, provider) ->
    [{Module, Function, length(Args)} | calls(Args, provider)];
calls(Tuple, Kind) when is_tuple(Tuple) -> calls(tuple_to_list(Tuple), Kind);
calls(Map, Kind) when is_map(Map) -> calls(maps:values(Map), Kind);
calls(List, Kind) when is_list(List) -> lists:append([calls(X, Kind) || X <- List]);
calls(_, _Kind) -> [].

%% Bind full terms, not the narrow actor-interface summary; bodies, includes,
%% failure annotations and resolved layouts participate in these fingerprints.
-spec digest(term()) -> binary().
digest(Value) -> crypto:hash(sha256, term_to_binary(Value, [deterministic])).

%% Entry payload origins use fresh references to distinguish established values.
%% Alpha-renaming retains sharing and nonsharing while making fresh compilations
%% comparable; dropping origin metadata would lose an observable planning fact.
-spec canonical(term()) -> term().
canonical(Value) ->
    {Result, _} = canonical(Value, #{}),
    Result.

%% Traverse map keys in a deterministic order; references occur in origin values.
-spec canonical(term(), #{reference() => non_neg_integer()}) ->
    {term(), #{reference() => non_neg_integer()}}.
canonical(Ref, Seen) when is_reference(Ref) ->
    Id = maps:get(Ref, Seen, map_size(Seen)),
    {{statem_plan_origin, Id}, Seen#{Ref => Id}};
canonical(Map, Seen) when is_map(Map) ->
    {Pairs, Next} = canonical(lists:sort(maps:to_list(Map)), Seen),
    {maps:from_list(Pairs), Next};
canonical(Tuple, Seen) when is_tuple(Tuple) ->
    {Fields, Next} = canonical(tuple_to_list(Tuple), Seen),
    {list_to_tuple(Fields), Next};
canonical(List, Seen) when is_list(List) -> lists:mapfoldl(fun canonical/2, Seen, List);
canonical(Value, Seen) -> {Value, Seen}.
