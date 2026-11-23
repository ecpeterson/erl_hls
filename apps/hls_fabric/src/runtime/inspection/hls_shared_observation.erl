-module(hls_shared_observation).
-moduledoc """
Scheduler inspection clients attach retained build bindings to a matching topology session here. Attachment checks manifest projection and resource metadata without loading source, scheduler planners or generators. The same adapter decodes committed mailbox/actor observations into the common runtime inspection model.
""".
%% Scheduler inspection attachment.
-export([open/2, open/3, bind/2]).
-export_type([binding/0]).
%% Retained observation decoding.
-export([decode_observation/2, mailbox_observation/2, actor_fields/1]).

-doc "Source-checked catalog and projection retained by build-side inspection preparation; optional tile metadata maps logical identities to physical resources. This trusted build result is not an admission certificate for untrusted terms.".
-type binding() :: #{
    catalog := map(),
    projection := map(),
    tile => #{
        projection := map(),
        identities := #{term() => term()},
        resources := #{binary() => {map(), map()}}
    }
}.

-doc "Opens a verified topology session and attaches a retained binding. Transport errors are returned; mismatched projection or resource metadata raises an error.".
-spec open(binding(), pid(), map()) -> {ok, map()} | {error, term()}.
open(Binding, Client, Manifest) ->
    case open(Client, Manifest) of
        {ok, Session} -> {ok, bind(Binding, Session)};
        Error -> Error
    end.

-doc "Attaches a prepared catalog after checking exact projection and actor resources. Tile bindings retain logical identities while queries use the original physical session.".
-spec bind(binding(), map()) -> map().
bind(
    #{
        catalog := Catalog,
        projection := Physical,
        tile := #{projection := Projection, identities := Identities, resources := ByKey}
    },
    Session = #{manifest := Manifest}
) ->
    case maps:get(<<"actor_projection">>, Manifest, none) of
        Projection -> ok;
        _ -> error(actor_projection_mismatch)
    end,
    Resources = [physical_resource(R, ByKey) || R <- maps:get(<<"resources">>, Manifest)],
    Checked = hls_debug_catalog:bind(Catalog, Physical, Session#{
        manifest := Manifest#{<<"actor_projection">> := Physical, <<"resources">> := Resources}
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
bind(#{catalog := Catalog, projection := Projection}, Session) ->
    hls_debug_catalog:bind(Catalog, Projection, Session).

%% Preserve all resource checks while translating the retained logical key/name to its physical row.
-spec physical_resource(map(), #{binary() => {map(), map()}}) -> map().
physical_resource(
    R = #{<<"kind">> := <<"actor">>, <<"key">> := Key, <<"name">> := Name, <<"slot">> := Slot},
    ByKey
) ->
    {#{<<"name">> := Name, <<"slot">> := Slot}, Physical} = maps:get(Key, ByKey),
    maps:merge(R, maps:with([<<"key">>, <<"name">>], Physical));
physical_resource(Resource, _) ->
    Resource.

-doc "Opens a topology session with shared and dedicated actor decoding.".
-spec open(pid(), map()) -> {ok, map()} | {error, term()}.
open(Client, Manifest) ->
    case hls_topology_debug:open(Client, Manifest) of
        {ok, Session} -> {ok, hls_topology_debug:with_actor_observer(Session, ?MODULE)};
        Error -> Error
    end.

-doc "Decodes a reply using the shared mailbox format where requested by the projection.".
-spec decode_observation(binary(), map()) -> {ok, map()} | {error, term()}.
decode_observation(Bytes, Resource) ->
    hls_topology_debug:decode_observation(Bytes, Resource, ?MODULE).

-doc "Validates mailbox occupancy and decodes shared execution eligibility and phase.".
-spec mailbox_observation(map(), map()) -> {ok, map()} | {error, term()}.
mailbox_observation(
    Sample = #{value := Value},
    #{<<"mailbox_kind">> := <<"shared">>, <<"mailbox_capacity">> := Capacity}
) ->
    Word = (Value bsr 32) band 16#ffffff,
    Count = Word band 255,
    Postponed = (Word bsr 8) band 255,
    Phase = (Word bsr 21) band 3,
    case Word of
        0 ->
            {ok, (maps:merge(
                Sample,
                maps:from_keys(
                    [
                        message_queue_len,
                        postponed,
                        free_slots,
                        reserved,
                        in_flight,
                        mail_candidate,
                        entry_candidate,
                        waiting_for_egress,
                        egress_busy,
                        scheduler_phase
                    ],
                    undefined
                )
            ))#{
                mailbox_initialized => false
            }};
        _ when
            Word band (1 bsl 23) =/= 0,
            Phase < 3,
            Count =< Capacity,
            Postponed =< Count
        ->
            {ok, Sample#{
                mailbox_initialized => true,
                message_queue_len => Count,
                postponed => Postponed,
                free_slots => Capacity - Count,
                reserved => 0,
                in_flight => Word band (1 bsl 16) =/= 0,
                mail_candidate => Word band (1 bsl 17) =/= 0,
                entry_candidate => Word band (1 bsl 18) =/= 0,
                waiting_for_egress => Word band (1 bsl 19) =/= 0,
                egress_busy => Word band (1 bsl 20) =/= 0,
                scheduler_phase => element(Phase + 1, {boot, startup, run})
            }};
        _ ->
            {error, invalid_mailbox_observation}
    end;
mailbox_observation(Sample, Resource) ->
    hls_topology_debug:mailbox_observation(Sample, Resource).

-doc "Lists common actor items plus shared execution diagnostics.".
-spec actor_fields(map()) -> [atom()].
actor_fields(#{<<"mailbox_kind">> := <<"shared">>} = Resource) ->
    hls_topology_debug:actor_fields(Resource#{<<"mailbox_kind">> := <<"direct">>}) ++
        [
            in_flight,
            mail_candidate,
            entry_candidate,
            waiting_for_egress,
            egress_busy,
            scheduler_phase
        ];
actor_fields(Resource) ->
    hls_topology_debug:actor_fields(Resource).
