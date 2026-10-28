-module(hls_partition_tile_debug).
-moduledoc """
Partition inspection setup binds an existing physical session through this catalog adapter. It validates the compiler-side scheduler projection, then exposes logical actors through the common debug API.

Logical actor catalogs for a shared physical tile layout.
""".
%% Physical-to-logical debug binding.
-export([catalog/3]).

-doc "Validates physical slot metadata and its logical relabeling before binding public debug targets. Untiled plans use the ordinary catalog.".
-spec catalog(map(), map(), map()) -> map().
catalog(
    Plan = #{actors := [#{logical_identity := _} | _]},
    Specs,
    Session = #{manifest := Manifest = #{<<"actor_projection">> := Projection}}
) ->
    Physical = maps:get(<<"tile_physical">>, Projection),
    %% Validate storage dimensions, codebooks and the exact physical schedule first.
    ok = xls_scheduler_debug:validate(Plan, Specs, Physical),
    Identities = maps:from_list([
        {Id, Logical}
     || #{id := Id, logical_identity := Logical} <- maps:get(actors, Plan)
    ]),
    #{groups := Groups} = hls_scheduler_plan:normalize(
        Plan,
        Specs,
        hls_frame_layout:new(maps:get(<<"frame_payload_words">>, Physical, 3))
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
    ByKey = maps:from_list([{maps:get(<<"key">>, L), {L, P}} || {L, P} <- Pairs]),
    Resources = [
        case R of
            #{<<"kind">> := <<"actor">>, <<"key">> := Key, <<"name">> := Name, <<"slot">> := Slot} ->
                {#{<<"name">> := Name, <<"slot">> := Slot}, P} = maps:get(Key, ByKey),
                maps:merge(R, maps:with([<<"key">>, <<"name">>], P));
            _ ->
                R
        end
     || R <- maps:get(<<"resources">>, Manifest)
    ],
    Checked = hls_shared_debug_catalog:hardware(Plan, Specs, [], Session#{
        manifest := Manifest#{
            <<"actor_projection">> := Physical, <<"resources">> := Resources
        }
    }),
    Checked#{
        actors := maps:from_list([
            begin
                Logical = {actor, maps:get(Id, Identities)},
                {Logical,
                    {actor, Metadata#{identity := Logical, scope := Scope#{id := Logical}},
                        {actor_snapshot, Session, Resource}}}
            end
         || {{actor, Id}, {actor, Metadata = #{scope := Scope}, {actor_snapshot, _, Resource}}} <-
                maps:to_list(maps:get(actors, Checked))
        ])
    };
catalog(Plan, Specs, Session) ->
    hls_shared_debug_catalog:hardware(Plan, Specs, [], Session).
