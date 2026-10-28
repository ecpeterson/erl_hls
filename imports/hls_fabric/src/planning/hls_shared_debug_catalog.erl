-module(hls_shared_debug_catalog).
-moduledoc "Binds scheduler placement and dedicated actors to the common debug catalog used by partition inspection and hls_node_topology. Consumes checked topology and projection metadata; it does not add a second hardware observation protocol.".

%% Hardware observation binding.
-export([hardware/3, hardware/4]).
-doc "Describes logical actors with their shared or dedicated physical placements.".
-spec hardware(hls_topology:plan(), hls_scheduler_plan:spec(), list()) -> map().
hardware(Plan, Specs, Boundaries) ->
    Placements = hls_scheduler_plan:placements(hls_scheduler_plan:normalize(Plan, Specs)),
    hls_debug_catalog:hardware(Plan, Placements, Boundaries).
-doc "Validates the scheduler projection before binding manifest resources to logical actors.".
-spec hardware(hls_topology:plan(), hls_scheduler_plan:spec(), list(), map()) -> map().
hardware(Plan, Specs, Boundaries, Session = #{manifest := Manifest}) ->
    Projection = maps:get(<<"actor_projection">>, Manifest, none),
    ok = xls_scheduler_debug:validate(Plan, Specs, Projection),
    Layout = hls_frame_layout:new(maps:get(<<"frame_payload_words">>, Projection, 3)),
    Placements = hls_scheduler_plan:placements(hls_scheduler_plan:normalize(Plan, Specs, Layout)),
    hls_debug_catalog:bind(
        hls_debug_catalog:hardware(Plan, Placements, Boundaries), Projection, Session
    ).
