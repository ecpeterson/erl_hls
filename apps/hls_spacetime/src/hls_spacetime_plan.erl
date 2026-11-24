-module(hls_spacetime_plan).
-moduledoc """
System-level proposal and revision over shared implementation contracts.

Proposal uses process-free topology values and deterministic partition/scheduler policy. Revision
accepts characterization by value and a caller-supplied pure policy, so target tools, caches and
parallel execution stay outside the optimizer. Shared cache ownership and iterative physical
optimization remain later campaign work.
""".

-export([propose/4, revise/3]).

-doc "Builds a proposed implementation from one logical topology and target set. Options are `max_group_size`, `constraints`, `capabilities`, `planner` and opaque `inputs`.".
-spec propose(
    binary(), hls_logical_topology:plan(), [hls_implementation_plan:target(), ...], map()
) ->
    hls_implementation_plan:plan().
propose(LogicalSystem, Topology, Targets, Options) when is_map(Options) ->
    keys(Options),
    Placement = hls_spacetime_partition:balanced(Topology, Targets),
    Schedules = hls_spacetime_schedule:shared_by_module(
        Topology, Placement, maps:get(max_group_size, Options, 1)
    ),
    hls_implementation_plan:new(
        LogicalSystem,
        Placement,
        Schedules,
        maps:get(constraints, Options, #{}),
        maps:get(capabilities, Options, #{}),
        #{
            planner => maps:get(planner, Options, <<"hls_spacetime">>),
            inputs => maps:get(inputs, Options, [])
        }
    );
propose(_LogicalSystem, _Topology, _Targets, Options) ->
    error({invalid_spacetime_plan_options, Options}).

-doc "Validates exact plan/characterization correlation, asks a pure policy for replacement placement and schedules, then records the characterization identity as revision provenance. The logical system and owner-defined constraints/capabilities cannot change.".
-spec revise(
    hls_implementation_plan:plan(),
    hls_characterization:characterization(),
    fun(
        (hls_implementation_plan:plan(), hls_characterization:characterization()) ->
            {hls_implementation_plan:placement(), [hls_implementation_plan:schedule()]}
    )
) -> hls_implementation_plan:plan().
revise(Plan, Characterization, Policy) when is_function(Policy, 2) ->
    case hls_characterization:matches(Plan, Characterization) of
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

%% Reject ignored optimizer options before applying policy.
-spec keys(map()) -> ok.
keys(Options) ->
    case maps:keys(Options) -- [max_group_size, constraints, capabilities, planner, inputs] of
        [] -> ok;
        Unknown -> error({unknown_spacetime_plan_options, lists:sort(Unknown)})
    end.
