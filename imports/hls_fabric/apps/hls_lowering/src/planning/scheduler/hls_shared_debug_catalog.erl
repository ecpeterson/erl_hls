-module(hls_shared_debug_catalog).
-moduledoc """
Build-side scheduler inspection preparation validates source and placement against the emitted projection. The retained binding is attached by hls_shared_observation without repeating compiler analysis.
""".

%% Source-checked inspection preparation.
-export([prepare/4]).
%% Build-side catalog conveniences.
-export([hardware/3, hardware/4]).

-doc "Describes logical actors with their shared or dedicated physical placements.".
-spec hardware(hls_topology:plan(), hls_scheduler_plan:spec(), list()) -> map().
hardware(Plan, Specs, Boundaries) ->
    Placements = hls_scheduler_plan:placements(hls_scheduler_plan:normalize(Plan, Specs)),
    hls_debug_catalog:hardware(Plan, Placements, Boundaries).

-doc "Checks source, schedule and failure metadata against an emitted projection and retains the catalog for runtime attachment.".
-spec prepare(hls_topology:plan(), hls_scheduler_plan:spec(), list(), map()) ->
    hls_shared_observation:binding().
prepare(Plan, Specs, Boundaries, Projection) ->
    ok = xls_scheduler_debug:validate(Plan, Specs, Projection),
    Layout = hls_frame_layout:new(maps:get(<<"frame_payload_words">>, Projection, 3)),
    Placements = hls_scheduler_plan:placements(hls_scheduler_plan:normalize(Plan, Specs, Layout)),
    #{
        catalog => hls_debug_catalog:hardware(Plan, Placements, Boundaries),
        projection => Projection
    }.

-doc "Prepares and attaches a catalog while compiler inputs are available; runtime-only callers retain prepare/4 and use hls_shared_observation:bind/2.".
-spec hardware(hls_topology:plan(), hls_scheduler_plan:spec(), list(), map()) -> map().
hardware(Plan, Specs, Boundaries, Session = #{manifest := Manifest}) ->
    Projection = maps:get(<<"actor_projection">>, Manifest, none),
    hls_shared_observation:bind(prepare(Plan, Specs, Boundaries, Projection), Session).
