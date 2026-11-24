-module(hls_spacetime_plan).
-moduledoc """
System-level proposal and revision over shared implementation contracts.

Proposal uses process-free topology values and deterministic partition/scheduler policy. Revision
accepts characterization by value and a caller-supplied pure policy. Target tools, shared caches and
parallel execution stay outside the optimizer; callers drive the implementation and measured
characterization steps between proposal and revision.
""".

-export([propose/3, revise/4]).

-doc "Builds a proposed implementation from one normalized logical topology and target set, deriving the logical-system identity from the topology. `sharing` is `none` (the default) or `{by_module, MaxActors}`; other options are `constraints`, `capabilities`, `planner` and opaque `inputs`.".
-spec propose(
    hls_logical_topology:compact_plan(), [hls_implementation_plan:target(), ...], map()
) ->
    hls_implementation_plan:plan().
propose(Topology, Targets, Options) when is_map(Options) ->
    keys(Options),
    Placement = hls_spacetime_partition:balanced(Topology, Targets),
    Schedules = schedules(Topology, Placement, maps:get(sharing, Options, none)),
    hls_implementation_plan:new(
        hls_logical_topology:identity(Topology),
        Placement,
        Schedules,
        maps:get(constraints, Options, #{}),
        maps:get(capabilities, Options, #{}),
        #{
            planner => maps:get(planner, Options, <<"hls_spacetime">>),
            inputs => maps:get(inputs, Options, [])
        }
    );
propose(_Topology, _Targets, Options) ->
    error({invalid_spacetime_plan_options, Options}).

-doc "Validates exact plan, realized-implementation and characterization correlation, asks a pure policy for replacement placement and schedules, then records the characterization identity as revision provenance. The logical system and owner-defined constraints/capabilities cannot change.".
-spec revise(
    hls_implementation_plan:plan(),
    binary(),
    hls_characterization:characterization(),
    fun(
        (hls_implementation_plan:plan(), hls_characterization:characterization()) ->
            {hls_implementation_plan:placement(), [hls_implementation_plan:schedule()]}
    )
) -> hls_implementation_plan:plan().
revise(Plan, ImplementationIdentity, Characterization, Policy) when is_function(Policy, 2) ->
    case hls_characterization:matches(Plan, ImplementationIdentity, Characterization) of
        ok ->
            {Placement, Schedules} = Policy(Plan, Characterization),
            hls_implementation_plan:revise(
                Plan,
                Placement,
                Schedules,
                hls_characterization:identity(Characterization)
            );
        {error, Reason} ->
            error({spacetime_revision, Reason})
    end.

%% Preserve independent implementations unless the caller explicitly requests grouping.
-spec schedules(
    hls_logical_topology:compact_plan(),
    hls_implementation_plan:placement(),
    none | {by_module, pos_integer()}
) -> [hls_implementation_plan:schedule()].
schedules(_Topology, _Placement, none) ->
    [];
schedules(Topology, Placement, {by_module, MaxActors}) ->
    hls_spacetime_schedule:shared_by_module(Topology, Placement, MaxActors);
schedules(_Topology, _Placement, Sharing) ->
    error({invalid_spacetime_sharing, Sharing}).

%% Reject ignored optimizer options before applying policy.
-spec keys(map()) -> ok.
keys(Options) ->
    case maps:keys(Options) -- [sharing, constraints, capabilities, planner, inputs] of
        [] -> ok;
        Unknown -> error({unknown_spacetime_plan_options, lists:sort(Unknown)})
    end.
