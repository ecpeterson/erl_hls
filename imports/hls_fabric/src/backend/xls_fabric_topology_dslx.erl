%%%% Select a compact family or explicit-instance representation.
-module(xls_fabric_topology_dslx).
-moduledoc """
The fabric build facade prepares this generation plan from a normalized topology and physical profile. RAM binding, inspection and DSLX rendering consume the retained plan without repeating source or placement analysis.

Exact and mixed graphs share one instance-based placement renderer. Each actor
may retain its direct service or join a homogeneous shared executor; the same
option and artifact-requirement contracts apply throughout. Regular-family
plans with wholly direct or wholly shared placement retain compact channel
arrays and generated loops instead of duplicating routing source per member.

Routes preserve per-source/recipient order across aliased output ports. The
supported fanout mode is `queued`: the source event completes at its common
egress, and its router subsequently waits for every recipient. Direct actors
retain mailbox admission credit while polling routed input. Their explicit
startup frames precede routed and external messages. Rectangle ingress selects
logical actor points or embedded families independently of placement. Wire selectors must match across routes;
selector remapping remains unsupported.

The `burst` egress policy reserves one entry-effect burst on an initially empty
path, counting the producer's required output register. Code generation must
retain `--flop_outputs=true`. A literal nonnegative depth specifies XLS FIFO
storage, so zero retains only that producer holding slot.
""".
%% Retained whole-network generation and inspection.
-export([plan/2, analysis/1, descriptor/1, artifact_requirements/1, emit/1]).

%% One-shot conveniences over the same plan boundary.
-export([artifact_requirements/2, emit/2, from_module/2]).
-export_type([profile/0, plan/0, analysis/0, descriptor/0]).
-doc "Physical generation options; logical actor identities and callback semantics remain separate.".
-type profile() :: xls_fabric_topology_profile:profile().

%% Materialized lanes bind physical units; logical recipients retain the source topology identities.
-type lane() :: #{index := non_neg_integer(), source := unit(), destination := unit(),
    recipient := {actor, term()} | {external, atom()}}.
%% Direct units and ingress endpoints are physical vertices, not scheduler-owner indices.
-type unit() :: {scheduler | direct | ingress, non_neg_integer()} | {external, atom()}.
-doc "The representation actually selected for generation. Shared compact plans expose prepared ownership and routing facts. Materialized plans expose explicit physical lanes and ownership domains. Dedicated compact families remain compiler-owned, with their checked topology and profile retained.".
-type descriptor() :: xls_topology_scheduler_plan:descriptor() |
    #{representation := materialized, topology := hls_topology:plan(), profile := profile(),
      lanes := [lane()], effect_window_domains := [[non_neg_integer()]]} |
    #{representation := compact_direct, topology := hls_topology:plan(), profile := profile()}.
-doc "The checked topology, physical profile, scheduler and source interfaces used by one generation plan. Consumers reuse this snapshot for RAM and observation metadata without rereading source or repeating placement.".
-type analysis() :: #{topology := hls_topology:plan(), profile := profile(),
    scheduler := hls_scheduler_plan:plan(),
    interfaces := #{module() => hls_actor_interface:summary()}}.
%% Each representation retains the exact graph used by emit/1.
-record(plan, {implementation :: {compact_shared, xls_topology_scheduler_plan:plan()} |
    {materialized, map()} | {compact_direct, map()}, descriptor :: descriptor(),
    analysis :: analysis(), requirements :: #{module() => map()}}).
-doc "A checked in-process hardware generation plan. Interfaces and placement are resolved once, and each representation retains its lowered graph. No output files or external tools are created.".
-opaque plan() :: #plan{}.

-doc "Checks the selected placement, prepares its physical graph and retains actor requirements. Compact shared planning includes source-fragment capture and startup packing. This is the common authority used for both inspection and generation.".
-spec plan(hls_topology:plan(), profile()) -> plan().
plan(Topology, Profile0) ->
    Profile = #{scheduler_groups := Specs, frame_payload_words := Words} =
        xls_fabric_topology_profile:normalize(Profile0),
    Layout = hls_frame_layout:new(Words),
    Interfaces = hls_scheduler_plan:interfaces(Topology, Layout),
    Scheduler = hls_scheduler_plan:normalize(Topology, Specs, Layout, Interfaces),
    Analysis = #{topology => Topology, profile => Profile, scheduler => Scheduler,
        interfaces => Interfaces},
    case backend(Topology, Profile, Scheduler) of
        xls_fabric_topology_instance_dslx ->
            Graph = xls_fabric_topology_instance_dslx:lower(Topology, Profile, Scheduler, Interfaces),
            #plan{implementation = {materialized, Graph}, analysis = Analysis,
                requirements = maps:get(artifact_requirements, Graph),
                descriptor = #{representation => materialized, topology => Topology, profile => Profile,
                    lanes => [maps:with([index, source, destination, recipient], Lane)
                        || Lane <- maps:get(lanes, Graph)],
                    effect_window_domains => maps:get(effect_window_domains, Graph)}};
        xls_fabric_topology_family_dslx ->
            case xls_fabric_topology_family_dslx:lower(Topology, Profile, Scheduler, Interfaces) of
                Graph = #{schedulers := [], artifact_requirements := Requirements} ->
                    #plan{implementation = {compact_direct, Graph}, analysis = Analysis,
                        requirements = Requirements,
                        descriptor = #{representation => compact_direct, topology => Topology, profile => Profile}};
                Graph ->
                    Prepared = xls_topology_scheduler_plan:prepare(Graph),
                    #plan{implementation = {compact_shared, Prepared}, analysis = Analysis,
                        requirements = xls_topology_scheduler_plan:artifact_requirements(Prepared),
                        descriptor = xls_topology_scheduler_plan:descriptor(Prepared)}
            end
    end.

-doc "Returns the topology, profile, normalized scheduler and checked interfaces retained by this plan. It does not reload sources or repeat specialization.".
-spec analysis(plan()) -> analysis().
analysis(#plan{analysis = Analysis}) -> Analysis.

-doc "Returns the retained generation representation without reloading sources or rerunning placement and routing analysis.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{descriptor = Descriptor}) -> Descriptor.

-doc "Normalizes a topology module and renders its requested execution profile.".
-spec from_module(module(), profile()) -> iodata().
from_module(Module, Profile) -> emit(hls_topology:from_module(Module), Profile).

-doc "Renders a retained generation plan. The selected representation and ordered ownership decisions cannot change between inspection and rendering.".
-spec emit(plan()) -> iodata().
emit(#plan{implementation = {compact_shared, Prepared}}) -> xls_topology_scheduler_dslx:emit(Prepared);
emit(#plan{implementation = {materialized, Graph}}) -> xls_fabric_topology_instance_dslx:render(Graph);
emit(#plan{implementation = {compact_direct, Graph}}) -> xls_topology_family_dslx:render(Graph).

-doc "Checks and renders a topology in one call. Call plan/2 followed by descriptor/1 and emit/1 when inspecting the same retained graph.".
-spec emit(hls_topology:plan(), profile()) -> iodata().
emit(Topology, Profile) -> emit(plan(Topology, Profile)).

-doc "Returns the actor specializations retained by a generation plan without repeating lowering.".
-spec artifact_requirements(plan()) -> #{module() => map()}.
artifact_requirements(#plan{requirements = Requirements}) -> Requirements.

-doc "Checks the placement and returns its required actor specializations. Call plan/2 and artifact_requirements/1 when the graph will also be rendered or inspected.".
-spec artifact_requirements(hls_topology:plan(), profile()) -> #{module() => map()}.
artifact_requirements(Topology, Profile) -> artifact_requirements(plan(Topology, Profile)).

%% Artifact signatures and graph generation select a representation from the retained placement.
-spec backend(hls_topology:plan(), profile(), hls_scheduler_plan:plan()) ->
    xls_fabric_topology_family_dslx | xls_fabric_topology_instance_dslx.
backend(#{actors := [_ | _], families := _}, _Profile, _Scheduler) -> xls_fabric_topology_instance_dslx;
backend(#{families := []}, _Profile, _Scheduler) -> xls_fabric_topology_instance_dslx;
backend(#{actors := [], families := [_ | _]}, Profile, Scheduler) ->
    case xls_fabric_topology_instance_dslx:required(Profile, Scheduler) of
        true -> xls_fabric_topology_instance_dslx;
        false -> xls_fabric_topology_family_dslx
    end.
