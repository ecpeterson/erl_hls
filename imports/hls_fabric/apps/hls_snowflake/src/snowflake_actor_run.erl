-module(snowflake_actor_run).
-moduledoc "BEAM realization of the ordinary actor topology, with passive round-boundary reference checks.".
-export([run/3, run/4, write_vectors/4]).
-include("snowflake_actor_protocol.hrl").

-doc "Runs one input at a time and checks every committed vertex, edge replica and retirement.".
-spec run(pos_integer(), pos_integer(), [non_neg_integer()]) -> [map()].
run(Distance, Height, Masks) -> run(Distance, Height, Masks, #{}).

-doc """
Runs with a flat or tree6 barrier and input_window up to eight. The default
window of one checks full state after every round; larger windows check
each retirement and the final full state. delay_source/delay_ms perturb
relay arrival order, including vertex and barrier outputs, in BEAM time.
delay_phase_recipient delays commands to one actor after earlier recipients;
peer traffic remains independent, exercising command/completion races.
""".
-spec run(pos_integer(), pos_integer(), [non_neg_integer()], map()) -> [map()].
run(Distance, Height, Masks, Options) ->
    Host = self(),
    Ref = make_ref(),
    {Owner, Monitor} = spawn_monitor(fun() ->
        Host ! {Ref, deploy(Distance, Height, Masks, Options)}
    end),
    receive
        {Ref, Reports} ->
            receive
                {'DOWN', Monitor, process, Owner, normal} -> Reports
            end;
        {'DOWN', Monitor, process, Owner, Reason} ->
            error({actor_run_failed, Reason})
    after 60000 ->
        exit(Owner, kill),
        receive
            {'DOWN', Monitor, process, Owner, _} -> ok
        end,
        error(actor_run_timeout)
    end.

%% The deployment interprets only topology routes and startup, never decoder phases.
-spec deploy(pos_integer(), pos_integer(), [non_neg_integer()], map()) -> [map()].
deploy(Distance, Height, Masks, Options) ->
    Geometry = snowflake_actor_topology:geometry(Distance, Height),
    #{actors := Actors, routes := Routes, startup := Startup} =
        hls_topology:normalize(
            snowflake_actor_topology:topology(
                Distance,
                Height,
                #{barrier => maps:get(barrier, Options, flat)}
            )
        ),
    Pids = maps:from_list([
        begin
            {ok, Pid} = hls_statem:start_link(Module, [], [{mailbox_capacity, Capacity}]),
            {Id, Pid}
        end
     || #{id := Id, module := Module, mailbox_capacity := Capacity} <- Actors
    ]),
    Host = self(),
    Keys = lists:usort([
        {Source, Recipients}
     || #{source := {Source, _}, recipients := Recipients} <- Routes
    ]),
    Relays = maps:from_list([
        {Key, spawn_link(fun() -> relay(Source, Recipients, Pids, Host, Options) end)}
     || Key = {Source, Recipients} <- Keys
    ]),
    try
        maps:foreach(
            fun(Id, Pid) ->
                Outputs = maps:from_list([
                    {Port, maps:get({Id, Recipients}, Relays)}
                 || #{source := {Source, Port}, recipients := Recipients} <- Routes, Source =:= Id
                ]),
                ok = hls_statem:connect(Pid, Outputs)
            end,
            Pids
        ),
        lists:foreach(
            fun(#{target := Id, messages := Messages}) ->
                lists:foreach(
                    fun(Message) -> hls_statem:cast(maps:get(Id, Pids), Message) end, Messages
                )
            end,
            lists:reverse(Startup)
        ),
        Reports =
            case maps:get(input_window, Options, 1) of
                1 -> sequential(Masks, Height, Geometry, Pids);
                Window when Window > 1, Window =< 8 -> burst(Masks, Height, Geometry, Pids, Window)
            end,
        assert_healthy(Pids),
        Reports
    after
        maps:foreach(
            fun(_, Pid) ->
                unlink(Pid),
                exit(Pid, kill)
            end,
            Relays
        ),
        maps:foreach(fun(_, Pid) -> hls_statem:stop(Pid) end, Pids)
    end.

%% One outstanding request permits a stable full-state comparison at each round.
-spec sequential([non_neg_integer()], pos_integer(), snowflake_geometry:geometry(), map()) ->
    [map()].
sequential(Masks, Height, Geometry = #{distance := Distance}, Pids) ->
    {Reports, _} = lists:mapfoldl(
        fun({Sheet, Mask}, {Reference, Epoch}) ->
            {Next, Expected} = snowflake_window:decode(Mask, Reference),
            Started = erlang:monotonic_time(nanosecond),
            hls_statem:cast(maps:get(coordinator, Pids), #sf_input{sheet = Sheet, mask = Mask}),
            {Round, Corrections} = collect(Sheet, Height, Geometry, Pids, undefined, []),
            Finished = erlang:monotonic_time(nanosecond),
            NextEpoch = Epoch + maps:get(ticks, Expected),
            same({Sheet, epoch}, NextEpoch - 1, Round#sf_round.epoch),
            Actual = snapshot(Geometry, Pids),
            same({Sheet, window}, maps:get(state, Expected), Actual),
            check_corrections(Sheet, Height, Geometry, Expected, Corrections),
            {
                Expected#{
                    state := Actual,
                    actor_round => Round#sf_round.epoch,
                    beam_service_ns => Finished - Started,
                    correction_messages => length(Corrections)
                },
                {Next, NextEpoch}
            }
        end,
        {snowflake_window:new(surface, Distance, Height), 0},
        lists:enumerate(0, Masks)
    ),
    Reports.

%% Saturated valid senders hold at most eight requests; only round reports release credit.
-spec burst([non_neg_integer()], pos_integer(), snowflake_geometry:geometry(), map(), 2..8) ->
    [map()].
burst([], _Height, _Geometry, _Pids, _Window) ->
    [];
burst(Masks, Height, Geometry = #{distance := Distance}, Pids, Window) ->
    Inputs = lists:enumerate(0, Masks),
    {Initial, Pending} = lists:split(min(Window, length(Inputs)), Inputs),
    Coordinator = maps:get(coordinator, Pids),
    lists:foreach(
        fun({Sheet, Mask}) ->
            hls_statem:cast(Coordinator, #sf_input{sheet = Sheet, mask = Mask})
        end,
        Initial
    ),
    OwnerCount = length(
        lists:usort([maps:get(source, O) || O <- snowflake_actor_topology:ownership(Geometry)])
    ),
    CorrectionCount = OwnerCount * max(0, length(Masks) - Height),
    {Rounds, Corrections} = burst_collect(
        length(Masks), Pending, Coordinator, [], [], CorrectionCount
    ),
    check_owner_order(lists:reverse(Corrections)),
    Reports = snowflake_window:stream(surface, Distance, Height, Masks),
    {Checked, _} = lists:mapfoldl(
        fun({Sheet, Report}, Epoch) ->
            NextEpoch = Epoch + maps:get(ticks, Report),
            [Round] = [R || R = #sf_round{sheet = S} <- Rounds, S =:= Sheet],
            same({Sheet, burst_epoch}, NextEpoch - 1, Round#sf_round.epoch),
            SiteCorrections = [
                C
             || C = #sf_correction{sheet = S} <- Corrections, S =:= Sheet - Height
            ],
            check_corrections(Sheet, Height, Geometry, Report, SiteCorrections),
            {
                Report#{
                    actor_round => Round#sf_round.epoch,
                    correction_messages => length(SiteCorrections)
                },
                NextEpoch
            }
        end,
        0,
        lists:enumerate(0, Reports)
    ),
    same(burst_final_state, maps:get(state, lists:last(Reports)), snapshot(Geometry, Pids)),
    Checked.

%% Independent owners may interleave, but each site's retirement sequence starts at zero.
-spec check_owner_order([#sf_correction{}]) -> ok.
check_owner_order(Corrections) ->
    _ = lists:foldl(
        fun(#sf_correction{source = Source, sheet = Sheet}, Next) ->
            same({owner_order, Source}, maps:get(Source, Next, 0), Sheet),
            Next#{Source => Sheet + 1}
        end,
        #{},
        Corrections
    ),
    ok.

%% Separate output relays may lag the last round; then await remaining owner reports.
-spec burst_collect(
    non_neg_integer(),
    [{non_neg_integer(), non_neg_integer()}],
    pid(),
    [#sf_round{}],
    [#sf_correction{}],
    non_neg_integer()
) -> {[#sf_round{}], [#sf_correction{}]}.
burst_collect(0, [], _Coordinator, Rounds, Corrections, CorrectionCount) ->
    {lists:reverse(Rounds), drain_corrections(Corrections, CorrectionCount)};
burst_collect(Remaining, Pending, Coordinator, Rounds, Corrections, CorrectionCount) ->
    receive
        {actor_output, rounds, Round = #sf_round{sheet = Sheet}} ->
            same(burst_round_order, length(Rounds), Sheet),
            Next =
                case Pending of
                    [] ->
                        [];
                    [{NextSheet, Mask} | Rest] ->
                        hls_statem:cast(Coordinator, #sf_input{sheet = NextSheet, mask = Mask}),
                        Rest
                end,
            burst_collect(
                Remaining - 1, Next, Coordinator, [Round | Rounds], Corrections, CorrectionCount
            );
        {actor_output, corrections, Correction = #sf_correction{}} ->
            burst_collect(
                Remaining, Pending, Coordinator, Rounds, [Correction | Corrections], CorrectionCount
            );
        {actor_output, Port, Value} ->
            error({unexpected_burst_output, Port, Value})
    after 10000 -> error({actor_burst_timeout, Remaining})
    end.

%% Await an exact finite output population; no quiet-time heuristic can hide missing reports.
-spec drain_corrections([#sf_correction{}], non_neg_integer()) -> [#sf_correction{}].
drain_corrections(Collected, Count) when length(Collected) =:= Count -> Collected;
drain_corrections(Collected, Count) when length(Collected) < Count ->
    receive
        {actor_output, corrections, Correction = #sf_correction{}} ->
            drain_corrections([Correction | Collected], Count);
        {actor_output, Port, Value} ->
            error({unexpected_burst_tail, Port, Value})
    after 10000 -> error({missing_corrections, Count - length(Collected)})
    end.

%% Identical recipient sets share one source relay, preserving aliased-port order.
-spec relay(term(), [term()], map(), pid(), map()) -> no_return().
relay(Source, Recipients, Pids, Host, Options) ->
    receive
        {'$gen_cast', Message} ->
            case maps:get(delay_source, Options, none) =:= Source of
                true -> timer:sleep(maps:get(delay_ms, Options, 1));
                false -> ok
            end,
            lists:foreach(
                fun
                    ({actor, Id}) ->
                        case
                            is_record(Message, sf_phase) andalso
                                maps:get(delay_phase_recipient, Options, none) =:= Id
                        of
                            true -> timer:sleep(maps:get(delay_ms, Options, 1));
                            false -> ok
                        end,
                        hls_statem:cast(maps:get(Id, Pids), Message);
                    ({external, Port}) ->
                        Host ! {actor_output, Port, Message}
                end,
                Recipients
            ),
            relay(Source, Recipients, Pids, Host, Options)
    end.

%% Report and correction paths are independent; await the complete uncensored output set.
-spec collect(
    non_neg_integer(),
    pos_integer(),
    snowflake_geometry:geometry(),
    map(),
    undefined | #sf_round{},
    [#sf_correction{}]
) -> {#sf_round{}, [#sf_correction{}]}.
collect(Sheet, Height, Geometry, Pids, Round, Corrections) ->
    Owners = lists:usort([
        maps:get(source, Entry)
     || Entry <- snowflake_actor_topology:ownership(Geometry)
    ]),
    Count =
        case Sheet >= Height of
            true -> length(Owners);
            false -> 0
        end,
    case Round =/= undefined andalso length(Corrections) =:= Count of
        true ->
            {Round, Corrections};
        false ->
            receive
                {actor_output, rounds, Next = #sf_round{sheet = Sheet}} when Round =:= undefined ->
                    collect(Sheet, Height, Geometry, Pids, Next, Corrections);
                {actor_output, corrections, Correction = #sf_correction{sheet = Retired}} when
                    Retired =:= Sheet - Height, Sheet >= Height
                ->
                    collect(Sheet, Height, Geometry, Pids, Round, [Correction | Corrections]);
                {actor_output, Port, Value} ->
                    error({unexpected_actor_output, Sheet, Port, Value})
            after 10000 ->
                error(
                    {actor_round_timeout, Sheet, length(Corrections),
                        maps:map(fun(_, Pid) -> hls_statem:info(Pid) end, Pids)}
                )
            end
    end.

%% The standard state-machine API exposes callback state; debug queries check health separately.
-spec snapshot(snowflake_geometry:geometry(), map()) -> map().
snapshot(
    #{
        coordinates := Coordinates,
        ids := Ids,
        neighbors := Neighbors,
        endpoints := Endpoints
    },
    Pids
) ->
    Cells = list_to_tuple([
        begin
            #{data := Data} = hls_statem:info(maps:get({vertex, Source}, Pids)),
            snowflake_vertex:snapshot(Data)
        end
     || Source <- lists:seq(0, tuple_size(Coordinates) - 1)
    ]),
    Nodes = [
        begin
            #{node := Node} = element(I, Cells),
            maps:merge(
                #{coordinate => tuple_to_list(element(I, Coordinates)), id => element(I, Ids)},
                maps:from_list(lists:zip(record_info(fields, node), tl(tuple_to_list(Node))))
            )
        end
     || I <- lists:seq(1, tuple_size(Coordinates))
    ],
    Edges = [
        begin
            Replicas = [
                edge_copy(Direction, element(I, Cells))
             || I <- lists:seq(1, tuple_size(Neighbors)),
                {Direction, _, Edge} <- element(I, Neighbors),
                Edge =:= E
            ],
            [First, Second] = Replicas,
            same({edge_replica, E - 1}, First, Second),
            {A, B} = element(E, Endpoints),
            {Growth, Correction} = First,
            #{
                endpoints => [tuple_to_list(A), tuple_to_list(B)],
                growth => Growth,
                correction => Correction
            }
        end
     || E <- lists:seq(1, tuple_size(Endpoints))
    ],
    #{nodes => Nodes, edges => Edges}.

%% Packed incident values use two growth bits and one correction bit per direction.
-spec edge_copy(1..6, map()) -> {non_neg_integer(), boolean()}.
edge_copy(Direction, #{growth := Growth, correction := Correction}) ->
    {(Growth bsr (2 * (Direction - 1))) band 3, Correction band (1 bsl (Direction - 1)) =/= 0}.

%% Explicit zero-valued site reports distinguish quiet corrections from dropped output.
-spec check_corrections(non_neg_integer(), pos_integer(), snowflake_geometry:geometry(), map(), [
    #sf_correction{}
]) -> ok.
check_corrections(Sheet, Height, _Geometry, _Expected, []) when Sheet < Height -> ok;
check_corrections(Sheet, Height, Geometry, Expected, Corrections) ->
    Values = correction_values(Sheet, Height, Geometry, Expected),
    same({Sheet, corrections}, lists:sort(Values), lists:sort(Corrections)).

%% Derive expected output records from the independent complete-window reference.
-spec correction_values(non_neg_integer(), pos_integer(), snowflake_geometry:geometry(), map()) ->
    [#sf_correction{}].
correction_values(Sheet, Height, _Geometry, _Expected) when Sheet < Height -> [];
correction_values(Sheet, Height, Geometry, Expected) ->
    Ownership = snowflake_actor_topology:ownership(Geometry),
    Owners = lists:usort([maps:get(source, O) || O <- Ownership]),
    [
        begin
            Mask = lists:foldl(
                fun
                    (#{source := Owner, direction := Direction, kind := Kind, bit := Bit}, Acc) when
                        Owner =:= Source
                    ->
                        Field =
                            case Kind of
                                spatial -> retired_spatial_mask;
                                temporal -> retired_temporal_mask
                            end,
                        case maps:get(Field, Expected) band (1 bsl Bit) of
                            0 -> Acc;
                            _ -> Acc bor (1 bsl (Direction - 1))
                        end;
                    (_, Acc) ->
                        Acc
                end,
                0,
                Ownership
            ),
            #sf_correction{sheet = Sheet - Height, source = Source, edges = Mask}
        end
     || Source <- Owners
    ].

-doc "Writes input and expected output frames; the RTL driver receives no phase decisions or mutable decoder state.".
-spec write_vectors(pos_integer(), pos_integer(), [non_neg_integer()], file:filename()) -> ok.
write_vectors(Distance, Height, Masks, Path) ->
    Geometry = snowflake_actor_topology:geometry(Distance, Height),
    Reports = snowflake_window:stream(surface, Distance, Height, Masks),
    {Rows, _} = lists:mapfoldl(
        fun({Sheet, Report}, Epoch) ->
            NextEpoch = Epoch + maps:get(ticks, Report),
            Input = #sf_input{sheet = Sheet, mask = maps:get(input_mask, Report)},
            Round = #sf_round{sheet = Sheet, epoch = NextEpoch - 1},
            Corrections = correction_values(Sheet, Height, Geometry, Report),
            {
                #{
                    sheet => Sheet,
                    input_mask => Input#sf_input.mask,
                    reference_observation => maps:with(
                        [
                            ticks,
                            phase_counts,
                            retired_sheet,
                            retired_spatial_mask,
                            retired_temporal_mask
                        ],
                        Report
                    ),
                    input_frame => frame_hex(snowflake_coordinator, Input),
                    round_frame => frame_hex(snowflake_coordinator, Round),
                    corrections => [
                        #{
                            source => C#sf_correction.source,
                            sheet => C#sf_correction.sheet,
                            edges => C#sf_correction.edges,
                            frame => frame_hex(snowflake_vertex, C)
                        }
                     || C <- Corrections
                    ]
                },
                NextEpoch
            }
        end,
        0,
        lists:enumerate(0, Reports)
    ),
    file:write_file(
        Path,
        json:encode(#{
            schema => <<"snowflake-actor-vectors-v1">>,
            distance => Distance,
            height => Height,
            source_sheets => length(Masks),
            vertices => tuple_size(maps:get(coordinates, Geometry)),
            input_credit_limit => 8,
            sheets => Rows
        })
    ).

%% XLS Frame layout places the header over the dense, word-aligned payload.
-spec frame_hex(module(), tuple()) -> binary().
frame_hex(Module, Record) ->
    Payload = hls_codec:align(Module:pack(Record), 32),
    Header = ((bit_size(Payload) div 32) bsl 24) bor Module:pack_tag(element(1, Record)),
    iolist_to_binary(io_lib:format("~32.16.0b", [(Header bsl 96) bor hls_codec:unsigned(Payload)])).

%% A completed finite stream must leave no failing or postponed work behind.
-spec assert_healthy(map()) -> ok.
assert_healthy(Pids) ->
    maps:foreach(
        fun(Id, Pid) ->
            Info = hls_debug:info({hls_statem, Pid}, [
                lifecycle, phase, message_queue_len, postponed, reserved
            ]),
            %% A barrier remains in its publication phase after the entry has completed.
            Phase =
                case Id of
                    {barrier, _} -> publishing;
                    _ -> ready
                end,
            same(
                {Id, health},
                [
                    {lifecycle, connected},
                    {phase, Phase},
                    {message_queue_len, 0},
                    {postponed, 0},
                    {reserved, 0}
                ],
                Info
            )
        end,
        Pids
    ).

%% Retain the first differing value and its logical site in a diagnostic failure.
-spec same(term(), term(), term()) -> ok.
same(_Where, Expected, Expected) -> ok;
same(Where, Expected, Actual) -> error({actor_reference_mismatch, Where, Expected, Actual}).
