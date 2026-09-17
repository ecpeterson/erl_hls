%%%% Select a compact family or explicit-instance representation.
-module(xls_topology_dslx).
-moduledoc """
Generates a DSLX process graph from a normalized topology and physical profile.

Exact and mixed graphs share one instance-based placement renderer. Each actor
may retain its direct service or join a homogeneous shared executor; the same
option and artifact-requirement contracts apply throughout. Regular-family
plans with wholly direct or wholly shared placement retain compact channel
arrays and generated loops instead of duplicating routing source per member.

Routes preserve per-source/recipient order across aliased output ports. The
supported fanout mode is `queued`: the source event completes at its common
egress, and its router subsequently waits for every recipient. Direct actors
retain mailbox admission credit while polling routed input. Their explicit
startup frames precede routed messages. Wire selectors must match across routes;
selector remapping remains unsupported.

The `burst` egress policy reserves one entry-effect burst on an initially empty
path, counting the producer's required output register. Code generation must
retain `--flop_outputs=true`. A literal nonnegative depth specifies XLS FIFO
storage, so zero retains only that producer holding slot.
""".
-export([artifact_requirements/2, emit/2, from_module/2]).
-export_type([profile/0]).
-type profile() :: xls_topology_profile:profile().

-spec from_module(module(), profile()) -> iolist().
from_module(Module, Profile) -> emit(hls_topology:from_module(Module), Profile).

-spec emit(hls_topology:plan(), profile()) -> iolist().
emit(Plan, Profile) ->
    Backend = backend(Plan, Profile),
    Backend:emit(Plan, Profile).

-spec artifact_requirements(hls_topology:plan(), profile()) -> map().
artifact_requirements(Plan, Profile) ->
    Backend = backend(Plan, Profile),
    Backend:artifact_requirements(Plan, Profile).

%% Artifact signatures and graph generation choose the same representation.
backend(#{actors := [_ | _], families := _}, _Profile) -> xls_topology_instance_dslx;
backend(#{families := []}, _Profile) -> xls_topology_instance_dslx;
backend(Plan = #{actors := [], families := [_ | _]}, Profile) ->
    case xls_topology_instance_dslx:required(Plan, Profile) of
        true -> xls_topology_instance_dslx;
        false -> xls_topology_family_dslx
    end;
backend(Plan, _Profile) -> error({invalid_topology_plan, Plan}).
