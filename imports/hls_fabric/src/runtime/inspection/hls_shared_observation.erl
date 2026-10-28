-module(hls_shared_observation).
-moduledoc """
Scheduler inspection clients use this adapter with an existing debug client to open a matching topology session. It decodes committed mailbox/actor observations into the common runtime inspection model.
""".
%% Scheduler inspection attachment.
-export([open/2]).
%% Retained observation decoding.
-export([decode_observation/2, mailbox_observation/2, actor_fields/1]).

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
