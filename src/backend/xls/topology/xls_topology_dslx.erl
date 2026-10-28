-module(xls_topology_dslx).
-moduledoc "Facade for dedicated-actor DSLX wiring from normalized hls_topology plans. It selects compact family rendering or materialized instance rendering and exposes their actor compilation requirements. Each actor owns register-backed state and a bounded mailbox; RAM sharing and placement belong to hls_fabric.".
%% Determine required actor specializations before compiling modules.
-export([artifact_requirements/2]).
%% Render a normalized graph or normalize a topology module first.
-export([emit/2, from_module/2]).
-export_type([profile/0]).
-doc "Dedicated topology name, channel capacity, egress capacity and optional observations.".
-type profile() :: xls_topology_profile:profile().
-doc "Normalizes an Erlang topology module and emits its dedicated actor graph.".
-spec from_module(module(), profile()) -> iolist().
from_module(Module, Profile) -> emit(hls_topology:from_module(Module), Profile).
-doc "Emits dedicated actors, startup traffic, ingress, routers and external destinations.".
-spec emit(hls_topology:plan(), profile()) -> iolist().
emit(Plan, Profile) -> (backend(Plan)):emit(Plan, Profile).
-doc "Returns per-module actor compilation options required by this graph.".
-spec artifact_requirements(hls_topology:plan(), profile()) -> map().
artifact_requirements(Plan, Profile) -> (backend(Plan)):artifact_requirements(Plan, Profile).

%% Keep regular-family wiring compact; mixed graphs use explicit instance lanes.
-spec backend(hls_topology:plan()) -> module().
backend(#{actors := [], families := [_ | _]}) -> xls_topology_family_dslx;
backend(_) -> xls_topology_instance_dslx.
