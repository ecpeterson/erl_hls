-module(hls_build).
-moduledoc """
Public hardware-build selection used by hls_fabric_cli and Erlang clients. Dispatches checked requests to hls_source_build or hls_scheduler_build, retaining the selected plan for inspection and publication. Backend owners lower the source; the external executor consumes the emitted bundle.
""".
%% Checked backend planning and inspection.
-export([plan/1, inspect/2, descriptor/1]).

%% Retained source-bundle publication.
-export([write/2]).
%% Shared type contracts.
-export_type([
    request/0, plan/0, backend/0, descriptor/0, inspection_stage/0, inspection/0, manifest/0
]).

-doc "Two supported execution models; selecting one does not translate an incompatible placement or source protocol.".
-type backend() :: source_protocol | channel_scheduler.
-doc "Explicit backend request. A network source request may additionally carry one implementation_plan and selected target; that form derives target placement rather than accepting raw placement fields. Other source compositions retain their own boundary kind, while scheduler configuration owns channel placement and its allowed schedule.".
-type request() ::
    #{
        backend := source_protocol,
        kind := hls_source_build:kind(),
        configuration := hls_source_config:config() | file:filename()
    }
    | #{
        backend := source_protocol,
        kind := network,
        configuration := hls_source_config:network() | file:filename(),
        implementation_plan := hls_implementation_plan:plan(),
        target := hls_implementation_plan:target()
    }
    | #{
        backend := channel_scheduler,
        configuration := hls_scheduler_build:config() | file:filename()
    }.
%% Backend plans stay private to their owner and are never serialized as executable requests.
-record(plan, {
    backend :: backend(), value :: hls_source_build:plan() | hls_scheduler_build:plan()
}).
-doc "One checked backend plan. Retain unchanged in process; write consumes its prepared sources and reads support libraries at packaging time.".
-opaque plan() :: #plan{}.

-doc "The selected backend paired with its own static descriptor; callers retain the backend tag when inspecting placement and composition.".
-type descriptor() ::
    #{backend := source_protocol, build := hls_source_build:descriptor()}
    | #{backend := channel_scheduler, build := hls_scheduler_build:descriptor()}.
-doc "Inspection views supported by the selected backend; each view is diagnostic data rather than executable configuration.".
-type inspection_stage() ::
    hls_source_build:inspection_stage() | hls_scheduler_build:inspection_stage().
-doc "Backend-tagged inspection reports. Source compositions additionally retain their selected boundary kind; report data keeps ordinary Erlang values until formatted for display.".
-type inspection() ::
    #{
        version := 1,
        backend := source_protocol,
        kind := hls_source_build:kind(),
        stage := hls_source_build:inspection_stage(),
        data := term()
    }
    | hls_scheduler_build:inspection().
-doc "The common source-bundle schema with backend-owned metadata; both variants carry exact input hashes, unit schedules and role RTL lists.".
-type manifest() :: hls_source_build:manifest() | hls_scheduler_build:manifest().

-doc "Plans one explicit backend request, rejecting unknown fields before compiling source. Backend configuration can be a map or trusted terms filename; a request filename contains one such request map. No XLS tool or output directory is needed.".
-spec plan(request() | file:filename()) -> plan().
plan(
    Request = #{
        backend := source_protocol,
        kind := Kind,
        configuration := Config,
        implementation_plan := ImplementationPlan,
        target := Target
    }
) ->
    keys(Request, [backend, kind, configuration, implementation_plan, target]),
    #plan{
        backend = source_protocol,
        value = hls_source_build:plan(Kind, Config, ImplementationPlan, Target)
    };
plan(Request = #{backend := source_protocol, kind := Kind, configuration := Config}) ->
    keys(Request, [backend, kind, configuration]),
    #plan{backend = source_protocol, value = hls_source_build:plan(Kind, Config)};
plan(Request = #{backend := channel_scheduler, configuration := Config}) ->
    keys(Request, [backend, configuration]),
    #plan{backend = channel_scheduler, value = hls_scheduler_build:plan(Config)};
plan(Request) when is_map(Request) ->
    hls_diagnostic:raise(
        configuration,
        invalid_build_request,
        <<"Select source_protocol with kind/configuration and an optional implementation_plan/target pair, or channel_scheduler with configuration.">>,
        #{value => Request}
    );
plan(Filename) ->
    plan(hls_source_config:read(Filename)).

-doc "Returns the selected backend and its static descriptor. This is inspection data, not admission or an external-tool recipe.".
-spec descriptor(plan()) -> descriptor().
descriptor(#plan{backend = Backend, value = Plan}) ->
    Builder = builder(Backend),
    #{backend => Backend, build => Builder:descriptor(Plan)}.

-doc "Inspects configuration, source, topology, placement, composition, schedule or profile through the selected owner. The profile records declared hardware policy; actual external tools are identified only when compiling the emitted bundle.".
-spec inspect(plan(), inspection_stage()) -> inspection().
inspect(#plan{backend = Backend, value = Plan}, Stage) ->
    Builder = builder(Backend),
    (Builder:inspect(Plan, Stage))#{backend => Backend}.

-doc "Writes the retained backend plan to a fresh source bundle. Both backends use the same target-owned portable manifest and optional external driver; this call neither executes XLS nor runs simulation or qualification.".
-spec write(plan(), file:filename()) -> manifest().
write(#plan{backend = Backend, value = Plan}, Directory) ->
    Builder = builder(Backend),
    Builder:write(Plan, Directory).

%% Reject options that would otherwise look accepted but have no effect on a backend.
-spec keys(map(), [atom()]) -> ok.
keys(Request, Allowed) ->
    case maps:keys(Request) -- Allowed of
        [] ->
            ok;
        Unknown ->
            hls_diagnostic:raise(
                configuration,
                unknown_build_fields,
                <<"Build request contains unsupported fields.">>,
                #{field => lists:sort(Unknown)}
            )
    end.

%% Dispatch is closed: no module name is accepted from an untyped request.
-spec builder(backend()) -> module().
builder(source_protocol) -> hls_source_build;
builder(channel_scheduler) -> hls_scheduler_build.
