-module(hls_partition_tile_debug).
-moduledoc """
Tile builds validate the physical scheduler projection and its logical identity relabeling here. Runtime inspection attaches the retained mapping through hls_shared_observation without loading scheduler or tile generators.
""".

%% Source-checked physical-to-logical inspection preparation.
-export([prepare/3]).
%% Build-side attachment convenience.
-export([catalog/3]).

-doc "Validates physical slot metadata and its exact logical relabeling, retaining both for runtime attachment. Untiled plans use the ordinary binding.".
-spec prepare(map(), map(), map()) -> hls_shared_observation:binding().
prepare(Plan = #{actors := [#{logical_identity := _} | _]}, Specs, Projection) ->
    Physical = maps:get(<<"tile_physical">>, Projection),
    Binding = hls_shared_debug_catalog:prepare(Plan, Specs, [], Physical),
    Identities = maps:from_list([
        {Id, Logical}
     || #{id := Id, logical_identity := Logical} <- maps:get(actors, Plan)
    ]),
    #{groups := Groups} = hls_scheduler_plan:normalize(
        Plan, Specs, hls_frame_layout:new(maps:get(<<"frame_payload_words">>, Physical, 3))
    ),
    Local = #{
        tile => true,
        schedulers => [
            G#{
                index => I,
                actors => [
                    #{identity => maps:get(Id, Identities), slot => Slot}
                 || #{id := Id, base_slot := Slot} <- maps:get(members, G)
                ]
            }
         || {I, G} <- lists:enumerate(0, Groups)
        ]
    },
    Projection = hls_partition_tile:projection(Local, Physical),
    Pairs = lists:append([
        lists:zip(maps:get(<<"actors">>, L), maps:get(<<"actors">>, P))
     || {L, P} <- lists:zip(maps:get(<<"banks">>, Projection), maps:get(<<"banks">>, Physical))
    ]),
    Binding#{
        tile => #{
            projection => Projection,
            identities => Identities,
            resources => maps:from_list([{maps:get(<<"key">>, L), {L, P}} || {L, P} <- Pairs])
        }
    };
prepare(Plan, Specs, Projection) ->
    hls_shared_debug_catalog:prepare(Plan, Specs, [], Projection).

-doc "Prepares and attaches a tile catalog while compiler inputs are available; retained bindings can instead be attached by hls_shared_observation:bind/2.".
-spec catalog(map(), map(), map()) -> map().
catalog(Plan, Specs, Session = #{manifest := Manifest}) ->
    hls_shared_observation:bind(
        prepare(Plan, Specs, maps:get(<<"actor_projection">>, Manifest, none)), Session
    ).
