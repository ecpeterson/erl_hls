-module(xls_statem_plan).
-moduledoc "Retains checked callback structure alongside the ordinary spec produced by xls_statem_lower. xls_actor_program and ownership-planning consumers select complete callback families with source and dependency provenance. This source-side sidecar is distinct from deferred DSLX syntax and establishes neither field independence, protocol refinement nor physical benefit.".
%% Compile the rendering/planning pair from one source input.
-export([from_file/2, from_file/3]).
%% Internal lowerer handoff after successful ordinary preparation.
-export([build/5]).
%% Validate provenance and inspect complete callback families.
-export([validate/3, records/1, callbacks/1, select/2, provenance/1, manifest/1, identity/1]).
-export_type([plan/0, selection/0, provenance/0, identity/0]).

%% Planner-owned data is opaque so consumers select complete callback families
%% instead of constructing partial dispatch chains by dropping inconvenient arms.
-doc "Versioned planning sidecar bound to preprocessed source and ordinary lowering; validate against current source before using a saved value.".
-opaque plan() :: #{
    version := 1,
    source := file:filename(),
    source_sha256 := binary(),
    artifact_sha256 := binary(),
    planner_md5 := binary(),
    identity_inputs := identity_inputs(),
    phases := [atom(), ...],
    data := map(),
    records := [hls_source:record_declaration()],
    callbacks := [map()],
    entries := [map()],
    roots := [map()],
    helpers := [map()],
    protocol := map()
}.

%% These digests require the original source/artifact, which the sidecar does not retain.
-type identity_inputs() :: #{source_sha256 := binary(), artifact_sha256 := binary()}.

-doc "Path-independent compiler identity with lowercase hexadecimal digests. Source/preprocessing and closed-artifact digests bind construction inputs; the complete-plan digest is recomputed with payload-origin sharing preserved. This does not replace strict validation.".
-type identity() :: #{
    version := 1,
    source_sha256 := binary(),
    artifact_sha256 := binary(),
    plan_sha256 := binary(),
    planner_md5 := binary()
}.

-doc "Original source path and raw binary source, rendering-artifact and planner digests from construction. Unlike identity/1, these values are not path-normalized or hexadecimal encoded.".
-type provenance() :: #{
    source := file:filename(),
    source_sha256 := binary(),
    artifact_sha256 := binary(),
    planner_md5 := binary()
}.

-doc "A whole phase/event family. Selection retains every ordered clause, including failure and postponement alternatives; it cannot select a single successful clause.".
-type selection() :: {atom(), enter | cast | call | internal}.

-doc "Compiles an actor once and returns its unchanged rendering artifact with a planning sidecar. Source options have the ordinary compiler's preprocessing meaning; invalid actors fail in ordinary lowering.".
-spec from_file(file:filename(), [hls_source:option()] | hls_source:context()) ->
    {xls_actor_codegen:spec(), plan()}.
from_file(Filename, Options) -> from_file(Filename, Options, hls_frame_layout:default()).

-doc "Compiles rendering and planning together using an explicit checked ordinary-frame layout, retained in the plan protocol.".
-spec from_file(
    file:filename(),
    [hls_source:option()] | hls_source:context(),
    hls_frame_layout:layout()
) -> {xls_actor_codegen:spec(), plan()}.
from_file(Filename, Options, Layout) ->
    {ok, Source} = hls_source:parse_file(Filename, Options),
    Phases = hls_source:find_attribute(Source, hls_phases),
    xls_statem_lower:planned_artifact(Filename, Source, Phases, Layout).

-doc "Builds a sidecar from one successful ordinary lowering's source, prepared helpers/callbacks and closed artifact. Internal lowerer entry point: callers must not combine inputs from different compilations.".
-spec build(
    [hls_source:form()],
    [hls_source:form()],
    [map()],
    map(),
    xls_actor_codegen:spec()
) -> plan().
build(
    Source,
    Forms,
    Helpers,
    Prepared,
    Spec = #{
        source := Filename,
        phases := Phases,
        data_name := DataName,
        data_width := DataWidth
    }
) ->
    Families = xls_statem_callbacks:prepare(Forms, Phases),
    Callbacks = lists:append([
        callbacks(Kind, maps:get(Kind, Families))
     || Kind <- [enter, cast, call, internal]
    ]),
    Roots = [
        #{function => {Name, Arity}, clauses => Clauses}
     || {function, _, Name, Arity, Clauses} <- Forms,
        {Name, Arity} =:= {init, 1} orelse {Name, Arity} =:= {reduce, 3}
    ],
    %% Verify dependency closure before exposing a plan, including helper bodies
    %% not directly called by any selected callback. Ordering is XLS's callee order.
    _ = closure([maps:get(name, H) || H <- Helpers], Helpers),
    _ = closure(
        lists:append([maps:get(helpers, C) || C <- Callbacks]) ++
            helper_calls(Roots),
        Helpers
    ),
    #{
        version => 1,
        source => Filename,
        source_sha256 => digest(Source),
        artifact_sha256 => digest(Spec),
        planner_md5 => ?MODULE:module_info(md5),
        identity_inputs => identity_inputs(Source, Spec),
        phases => Phases,
        data => #{name => DataName, width => DataWidth},
        records => [F || F = {attribute, _, record, _} <- Forms],
        callbacks => Callbacks,
        entries => maps:get(entries, Prepared),
        roots => Roots,
        helpers => Helpers,
        protocol => maps:with(
            [
                frame_layout,
                capacity,
                output_names,
                message_names,
                message_words,
                retained_calls,
                continuations,
                reductions,
                gathers,
                failure_locations
            ],
            Spec
        )
    }.

-doc "Recompiles current source and compares the complete sidecar, renaming only compilation-local payload-origin identities. Rejects stale or modified plans; this freshness check is not an equivalence proof.".
-spec validate(file:filename(), [hls_source:option()] | hls_source:context(), plan()) -> ok.
validate(Filename, Options, Plan = #{protocol := #{frame_layout := Layout}}) ->
    {_, Current} = from_file(Filename, Options, Layout),
    case canonical(Current) =:= canonical(Plan) of
        true -> ok;
        false -> error(stale_statem_plan)
    end.

-doc "Returns every complete resolved record declaration retained by the plan, preserving field order, types, defaults and source annotations. This read-only snapshot view does not revalidate current files.".
-spec records(plan()) -> [hls_source:record_declaration()].
records(#{records := Records}) -> Records.

-doc "Returns all complete prepared callback clauses across every phase, grouped as enter, cast, call and internal with source order preserved within each family. Includes guards, failure/postponement arms and helper/provider dependencies without selection or reachability filtering. This view does not revalidate current files.".
-spec callbacks(plan()) -> [map()].
callbacks(#{callbacks := Callbacks}) -> Callbacks.

-doc "Returns exactly the original source path and raw source/artifact/planner digests captured at construction. This provenance view is distinct from canonical build identity and does not establish current-file freshness; use validate/3 for saved plans.".
-spec provenance(plan()) -> provenance().
provenance(#{
    source := Source,
    source_sha256 := SourceHash,
    artifact_sha256 := ArtifactHash,
    planner_md5 := PlannerHash
}) ->
    #{
        source => Source,
        source_sha256 => SourceHash,
        artifact_sha256 => ArtifactHash,
        planner_md5 => PlannerHash
    }.

-doc "Selects nonempty complete phase/event families and their transitive helpers in dependency order. Keeps exact clauses, entry programs, all record declarations and actor-wide protocol obligations. Provider calls are inventoried, not certified for projection; the result remains planning-only.".
-spec select(plan(), [selection(), ...]) -> map().
select(
    Plan = #{
        callbacks := Callbacks,
        entries := Entries,
        roots := Roots,
        helpers := Helpers
    },
    Choices
) ->
    ok = choices(Choices, Callbacks),
    Selected = [
        C
     || C = #{phase := P, kind := K} <- Callbacks,
        lists:member({P, K}, Choices)
    ],
    SelectedEntries = [E || E = #{phase := P} <- Entries, lists:member({P, enter}, Choices)],
    Needed = closure(
        lists:append([maps:get(helpers, C) || C <- Selected]) ++
            helper_calls([Roots, SelectedEntries]),
        Helpers
    ),
    SelectedHelpers = [H || H = #{name := Name} <- Helpers, lists:member(Name, Needed)],
    Providers = lists:usort(
        lists:append([maps:get(providers, C) || C <- Selected]) ++
            provider_calls([Roots, SelectedEntries]) ++
            lists:append([provider_calls(maps:get(clauses, H)) || H <- SelectedHelpers])
    ),
    #{
        role => planning_only,
        source => maps:get(source, Plan),
        source_sha256 => maps:get(source_sha256, Plan),
        artifact_sha256 => maps:get(artifact_sha256, Plan),
        planner_md5 => maps:get(planner_md5, Plan),
        choices => Choices,
        callbacks => Selected,
        helpers => SelectedHelpers,
        providers => Providers,
        entries => SelectedEntries,
        roots => Roots,
        data => maps:get(data, Plan),
        records => maps:get(records, Plan),
        protocol => maps:get(protocol, Plan)
    }.

-doc "Produces a compact, serializable inventory without source bodies. Counts describe retained structure, not inferred independence, totality, removed hardware or timing.".
-spec manifest(plan()) -> map().
manifest(#{
    version := Version,
    source := Source,
    source_sha256 := SourceHash,
    artifact_sha256 := ArtifactHash,
    planner_md5 := PlannerHash,
    phases := Phases,
    data := Data,
    callbacks := Callbacks,
    entries := Entries,
    roots := Roots,
    helpers := Helpers
}) ->
    #{
        version => Version,
        role => planning_only,
        source => Source,
        source_sha256 => binary:encode_hex(SourceHash, lowercase),
        artifact_sha256 => binary:encode_hex(ArtifactHash, lowercase),
        planner_md5 => binary:encode_hex(PlannerHash, lowercase),
        phases => Phases,
        data => Data,
        callbacks => [maps:without([clause], C) || C <- Callbacks],
        entries => [
            #{phase => maps:get(phase, E), alternatives => length(maps:get(variants, E))}
         || E <- Entries
        ],
        roots => [
            #{
                function => maps:get(function, R),
                helpers => helper_calls(R),
                providers => provider_calls(R)
            }
         || R <- Roots
        ],
        helpers => [
            #{
                name => maps:get(name, H),
                helpers => helper_calls(maps:get(clauses, H)),
                providers => provider_calls(maps:get(clauses, H))
            }
         || H <- Helpers
        ]
    }.

-doc "Returns canonical source/preprocessing, closed-artifact, current complete-plan and planner identities. Source locations are relative to the actor directory, ordered include roots to the captured build directory; semantic literals and failure locations remain exact. Renaming fresh origins preserves alias sharing. Call validate/3 separately to reject stale or modified plans.".
-spec identity(plan()) -> identity().
identity(
    Plan = #{
        identity_inputs := #{
            source_sha256 := SourceHash,
            artifact_sha256 := ArtifactHash
        },
        planner_md5 := PlannerHash
    }
) ->
    Structure = maps:without([source, source_sha256, artifact_sha256, planner_md5], Plan),
    #{
        version => 1,
        source_sha256 => binary:encode_hex(SourceHash, lowercase),
        artifact_sha256 => binary:encode_hex(ArtifactHash, lowercase),
        plan_sha256 => binary:encode_hex(digest(canonical(Structure)), lowercase),
        planner_md5 => binary:encode_hex(PlannerHash, lowercase)
    }.

%% Canonicalize only compiler-owned provenance fields. In particular, a source
%% ?FILE expansion is an ordinary literal and must retain its semantic value.
-spec identity_inputs([hls_source:form()], xls_actor_codegen:spec()) -> identity_inputs().
identity_inputs(Source, Spec = #{source := Filename}) ->
    Context =
        #{
            directory := Directory,
            source_name := SourceName,
            includes := Includes
        } = hls_source:from_forms(Source, []),
    ActorRoot = filename:dirname(filename:absname(SourceName, Directory)),
    Forms = [
        identity_form(Form, Directory, ActorRoot)
     || Form <- Source,
        not source_context(Form)
    ],
    Preprocessing = (maps:remove(directory, Context))#{
        source_name := relative_path(SourceName, Directory, ActorRoot),
        includes := [relative_path(Path, Directory, Directory) || Path <- Includes],
        origins := lists:usort([
            relative_path(Path, Directory, ActorRoot)
         || Path <- maps:get(origins, Context)
        ])
    },
    #{
        source_sha256 => digest(#{forms => Forms, preprocessing => Preprocessing}),
        artifact_sha256 => digest(Spec#{source := relative_path(Filename, Directory, ActorRoot)})
    }.

%% The context is represented once, independently of its synthetic form location.
-spec source_context(hls_source:form()) -> boolean().
source_context({attribute, _, hls_source_context, _}) -> true;
source_context(_) -> false.

%% epp file attributes are diagnostic metadata; all other forms remain literal.
-spec identity_form(hls_source:form(), file:filename(), file:filename()) -> hls_source:form().
identity_form({attribute, Anno, file, {File, Line}}, Directory, ActorRoot) ->
    {attribute, Anno, file, {relative_path(File, Directory, ActorRoot), Line}};
identity_form(Form, _Directory, _ActorRoot) ->
    Form.

%% Keep relative topology, including parent-directory traversal, without exposing
%% the build host's absolute root. Source spelling alone is not semantic content.
-spec relative_path(file:filename(), file:filename(), file:filename()) -> string().
relative_path(Path, Directory, Root) ->
    Absolute = filename:split(filename:absname(Path, Directory)),
    Base = filename:split(filename:absname(Root)),
    case relative_parts(Base, Absolute) of
        [] -> ".";
        Parts -> filename:join(Parts)
    end.

%% Strip a common prefix before retaining each unmatched directory component.
-spec relative_parts([string()], [string()]) -> [string()].
relative_parts([Part | Base], [Part | Path]) -> relative_parts(Base, Path);
relative_parts(Base, Path) -> lists:duplicate(length(Base), "..") ++ Path.

%% Callback preparation preserves order within a family. Ordinals are per
%% phase/event, not source line numbers (which can collide after includes/macros).
-spec callbacks(atom(), [erl_parse:abstract_clause()]) -> [map()].
callbacks(Kind, Clauses) ->
    {Result, _} = lists:mapfoldl(
        fun(Clause = {clause, _, [_, {atom, _, Phase} | _], _, _}, Seen) ->
            Ordinal = maps:get(Phase, Seen, 0) + 1,
            {
                #{
                    phase => Phase,
                    kind => Kind,
                    ordinal => Ordinal,
                    clause => Clause,
                    helpers => helper_calls(Clause),
                    providers => provider_calls(Clause)
                },
                Seen#{Phase => Ordinal}
            }
        end,
        #{},
        Clauses
    ),
    Result.

%% Empty/duplicate/missing families must not become vacuous success at a later
%% dependency boundary. Selection does not prune by schema, guard or outcome.
-spec choices([selection()], [map()]) -> ok.
choices([], _Callbacks) ->
    error(empty_statem_plan_selection);
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
closure([], _Definitions, Seen) ->
    lists:sort(Seen);
closure([Name | Rest], Definitions, Seen) ->
    case lists:member(Name, Seen) of
        true ->
            closure(Rest, Definitions, Seen);
        false ->
            case maps:find(Name, Definitions) of
                {ok, #{clauses := Clauses}} ->
                    closure(helper_calls(Clauses) ++ Rest, Definitions, [Name | Seen]);
                error ->
                    error({missing_statem_plan_helper, Name})
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
calls({xls_helper_call, _, Name, Args}, helper) ->
    [Name | calls(Args, helper)];
calls({call, _, {remote, _, {atom, _, Module}, {atom, _, Function}}, Args}, provider) ->
    [{Module, Function, length(Args)} | calls(Args, provider)];
calls(Tuple, Kind) when is_tuple(Tuple) -> calls(tuple_to_list(Tuple), Kind);
calls(Map, Kind) when is_map(Map) -> calls(maps:values(Map), Kind);
calls(List, Kind) when is_list(List) -> lists:append([calls(X, Kind) || X <- List]);
calls(_, _Kind) ->
    [].

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
canonical(Value, Seen) ->
    {Value, Seen}.
