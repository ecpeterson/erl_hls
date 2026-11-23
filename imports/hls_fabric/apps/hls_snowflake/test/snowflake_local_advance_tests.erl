-module(snowflake_local_advance_tests).
-moduledoc "Reference and rejection checks for the optional local phase-advancement probe.".
-compile({parse_transform, hls_pack}).
-hls_data(barrier).
-include_lib("eunit/include/eunit.hrl").
-include("snowflake_actor_protocol.hrl").
-include("snowflake_barrier.hrl").

%% These cases apply only to the explicitly selected protocol variant.
-spec local_advance_test_() -> term().
local_advance_test_() ->
    ?SF_ADVANCE_SELECT([{timeout, 30, fun tree_fixtures/0},
            {timeout, 10, fun delayed_streams/0},
            {timeout, 30, fun sustained_burst/0},
            fun collector_command_race/0, fun collector_global_busy/0,
            fun collector_rejections/0, fun collector_rollover/0,
            fun future_snapshot_bound/0, fun growth_snapshot_skew/0,
            fun next_sheet_snapshot_race/0, fun future_snapshot_rejections/0], []).

-if(?SNOWFLAKE_LOCAL_ADVANCE).
%% The runner compares every round's complete state and correction against the independent reference.
-spec tree_fixtures() -> ok.
tree_fixtures() ->
    lists:foreach(fun(File) ->
        {ok, Bytes} = file:read_file(filename:join([code:priv_dir(hls_snowflake), "fixtures", File])),
        #{<<"cases">> := Cases} = json:decode(Bytes),
        lists:foreach(fun(Case) -> run_case(Case, #{barrier => tree6}) end, Cases)
    end, ["surface-named.json", "surface-enumerated.json"]).

%% Slow neighbors, root command recipients and completion branches exercise distinct races.
-spec delayed_streams() -> ok.
delayed_streams() ->
    {ok, Bytes} = file:read_file(filename:join([code:priv_dir(hls_snowflake), "fixtures", "surface-named.json"])),
    #{<<"cases">> := Cases} = json:decode(Bytes),
    [Case] = [C || C = #{<<"name">> := <<"surface_d3_burst">>} <- Cases],
    lists:foreach(fun(Delay) ->
        run_case(Case, Delay#{barrier => tree6, input_window => 8, delay_ms => 1})
    end, [#{delay_source => {vertex, 0}}, #{delay_source => {barrier, 2}},
          #{delay_phase_recipient => {barrier, 2}}, #{delay_phase_recipient => {vertex, 0}}]).

%% A longer physical-noise stream keeps all eight input credits occupied without adding drain sheets.
-spec sustained_burst() -> ok.
sustained_burst() ->
    {ok, Bytes} = file:read_file(filename:join([code:priv_dir(hls_snowflake), "fixtures", "d3-p005-seed0-first128.json"])),
    #{<<"case">> := Case} = json:decode(Bytes),
    run_case(Case, #{barrier => tree6, input_window => 8}).

%% Compare pinned phase counts and every retirement in addition to the runner's state checks.
-spec run_case(map(), map()) -> ok.
run_case(#{<<"distance">> := D, <<"window_height">> := H, <<"sheets">> := Sheets}, Options) ->
    Reports = snowflake_actor_run:run(D, H,
        [maps:get(<<"input_mask">>, Sheet) || Sheet <- Sheets], Options),
    ?assertEqual(length(Sheets), length(Reports)),
    lists:foreach(fun({Expected, Actual}) ->
        ?assertEqual(maps:get(<<"reference_runtime_all">>, Expected) + 1, maps:get(ticks, Actual)),
        lists:foreach(fun(Field) ->
            ?assertEqual(maps:get(atom_to_binary(Field), Expected), maps:get(Field, Actual))
        end, [retired_sheet, retired_spatial_mask, retired_temporal_mask])
    end, lists:zip(Sheets, Reports)).

%% Six early reports leave a mailbox slot for the command which determines their exact tags.
-spec collector_command_race() -> ok.
collector_command_race() ->
    with_barrier(fun(Pid) ->
        lists:foreach(fun(Source) -> cast(Pid, done(Source, 2, 2)) end, lists:seq(12, 17)),
        ?assertEqual(6, maps:get(postponed, hls_statem:info(Pid))),
        cast(Pid, #sf_phase{epoch = 0, kind = 0}),
        ?assertEqual(#sf_done{source = 2, epoch = 2, kind = 2, busy = false}, message()),
        ?assertEqual(0, maps:get(postponed, hls_statem:info(Pid)))
    end).

%% A locally quiet group must still repeat when some other group made the root busy.
-spec collector_global_busy() -> ok.
collector_global_busy() ->
    with_barrier(fun(Pid) ->
        complete(Pid, 0, 0, 2, 2),
        %% Quiet local completion permits either globally authorized successor.
        complete(Pid, 3, 2, 3, 2),
        complete(Pid, 4, 3, 5, 4),
        complete(Pid, 6, 4, 6, 4),
        complete(Pid, 7, 0, 9, 2)
    end).

%% Alternate future tags may wait, but become failures once an incompatible command arrives.
-spec collector_rejections() -> ok.
collector_rejections() ->
    lists:foreach(fun(Messages) ->
        with_barrier(fun(Pid) -> expect_failure(Pid, Messages) end)
    end, [
        [done(12, 3, 2)], [done(11, 2, 2)], [done(18, 2, 2)],
        [done(12, 2, 2), done(12, 2, 2), #sf_phase{epoch = 0, kind = 0}],
        [#sf_phase{epoch = 1, kind = 0}],
        [#sf_phase{epoch = 0, kind = 0}, done(12, 2, 4)] ++
            case ?SNOWFLAKE_ACK_REDUCTION of
                true -> [done(Source, 2, 2) || Source <- lists:seq(13, 17)];
                false -> []
            end
    ]),
    with_barrier(fun(Pid) ->
        complete(Pid, 0, 0, 2, 2),
        expect_failure(Pid, [done(12, 4, 4), #sf_phase{epoch = 3, kind = 2}])
    end).

%% Skipped intermediate epochs and publication both wrap on the serial counter.
-spec collector_rollover() -> ok.
collector_rollover() ->
    Cell = #barrier{source = 2, first = 12, count = 1, epoch = 16#ffffffff, kind = 4},
    {publishing, Cell, postpone} = snowflake_barrier:publishing(cast, done(12, 1, 2), Cell),
    {commanded, Armed, consume} = snowflake_barrier:publishing(cast,
        #sf_phase{epoch = 16#ffffffff, kind = 0}, Cell),
    ?assertEqual(1, Armed#barrier.epoch),
    Complete = case ?SNOWFLAKE_ACK_REDUCTION of
        true ->
            {commanded, Armed, {contribute, acknowledgments, 1, 12, Value}} =
                snowflake_barrier:commanded(cast, done(12, 1, 2), Armed),
            {publishing, Result, consume} = snowflake_barrier:commanded(internal,
                {reduction_complete, acknowledgments, 1, Value}, Armed),
            Result;
        false ->
            {publishing, Result, consume} = snowflake_barrier:commanded(cast, done(12, 1, 2), Armed),
            Result
    end,
    {Next, [{cast, status, #sf_done{epoch = 1, kind = 2}}]} =
        snowflake_barrier:publishing(enter, commanded, Complete),
    ?assertEqual(2, Next#barrier.epoch).

%% A slow vertex retains one future snapshot per neighbor, then replays it after exact local advance.
-spec future_snapshot_bound() -> ok.
future_snapshot_bound() ->
    with_vertex(fun(Pid) ->
        lists:foreach(fun(Direction) -> cast(Pid, snap(1, Direction)) end, lists:seq(1, 6)),
        ?assertEqual(6, maps:get(postponed, hls_statem:info(Pid))),
        cast(Pid, #sf_phase{epoch = 0, kind = 0}),
        ?assertEqual(6, maps:get(postponed, hls_statem:info(Pid))),
        cast(Pid, #sf_shift{epoch = 0, node = #node{cid = 80}}),
        #{phase := snapshotting, postponed := 0, data := Data} = hls_statem:info(Pid),
        ?assertEqual(2, maps:get(epoch, snowflake_vertex:snapshot(Data))),
        lists:foreach(fun(Direction) -> cast(Pid, snap(2, Direction)) end, lists:seq(1, 6)),
        lists:foreach(fun(Direction) -> cast(Pid, #sf_transfer{epoch = 2, direction = Direction}) end,
            lists:seq(1, 6)),
        receive {'$gen_cast', #sf_done{epoch = 2, kind = 2}} -> ok
        after 1000 -> error(missing_terminal_completion) end,
        ?assertEqual(0, maps:get(postponed, hls_statem:info(Pid)))
    end).

%% Current then successor frames from five peers may overtake the sixth peer's current frame.
-spec growth_snapshot_skew() -> ok.
growth_snapshot_skew() ->
    with_vertex(fun(Pid) ->
        cast(Pid, #sf_phase{epoch = 0, kind = 0}),
        cast(Pid, #sf_shift{epoch = 0, node = #node{cid = 80}}),
        lists:foreach(fun(Direction) ->
            cast(Pid, snap(1, Direction)), cast(Pid, snap(2, Direction))
        end, lists:seq(1, 5)),
        #{phase := snapshotting, postponed := 5, data := Before} = hls_statem:info(Pid),
        ?assertEqual(1, maps:get(epoch, snowflake_vertex:snapshot(Before))),
        cast(Pid, snap(1, 6)),
        #{phase := snapshotting, postponed := 0, data := After, gather := #{seen := 31}} = hls_statem:info(Pid),
        ?assertEqual(2, maps:get(epoch, snowflake_vertex:snapshot(After))),
        ?assertEqual(0, maps:get(seen, snowflake_vertex:snapshot(After))),
        cast(Pid, snap(2, 6)),
        #{phase := transferring} = hls_statem:info(Pid)
    end).

%% Next-sheet growth can race its command; a repeat-merge command instead rejects that future tag.
-spec next_sheet_snapshot_race() -> ok.
next_sheet_snapshot_race() ->
    lists:foreach(fun(NextKind) -> with_vertex(fun(Pid) ->
        cast(Pid, #sf_phase{epoch = 0, kind = 4}),
        lists:foreach(fun(Direction) -> cast(Pid, snap(0, Direction)) end, lists:seq(1, 6)),
        lists:foreach(fun(Direction) -> cast(Pid, #sf_transfer{epoch = 0, direction = Direction}) end,
            lists:seq(1, 6)),
        receive {'$gen_cast', #sf_done{epoch = 0, kind = 4}} -> ok
        after 1000 -> error(missing_half_merge) end,
        cast(Pid, snap(2, 1)),
        ?assertEqual(1, maps:get(postponed, hls_statem:info(Pid))),
        case NextKind of
            0 ->
                cast(Pid, #sf_phase{epoch = 1, kind = 0}),
                cast(Pid, #sf_shift{epoch = 1, node = #node{cid = 80}}),
                #{phase := snapshotting, postponed := 0, data := Data, gather := #{seen := 1}} = hls_statem:info(Pid),
                ?assertEqual(2, maps:get(epoch, snowflake_vertex:snapshot(Data))),
                ?assertEqual(0, maps:get(seen, snowflake_vertex:snapshot(Data)));
            4 -> expect_failure(Pid, [#sf_phase{epoch = 1, kind = 4}])
        end
    end) end, [0, 4]).

%% Only the exact successor and an existing endpoint may wait; duplicates fail on replay.
-spec future_snapshot_rejections() -> ok.
future_snapshot_rejections() ->
    lists:foreach(fun(Messages) ->
        with_vertex(fun(Pid) -> expect_failure(Pid, Messages) end)
    end, [[snap(2, 1)], [snap(1, 0)], [snap(1, 7)],
        [snap(1, 1), snap(1, 1), #sf_phase{epoch = 0, kind = 0},
            #sf_shift{epoch = 0, node = #node{cid = 80}}]]).

%% Send a root command and then a complete quiet group with its expected terminal tags.
-spec complete(pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> ok.
complete(Pid, CommandEpoch, CommandKind, Epoch, Kind) ->
    cast(Pid, #sf_phase{epoch = CommandEpoch, kind = CommandKind}),
    lists:foreach(fun(Source) -> cast(Pid, done(Source, Epoch, Kind)) end, lists:seq(12, 17)),
    ?assertEqual(#sf_done{source = 2, epoch = Epoch, kind = Kind, busy = false}, message()),
    ok.

%% A small collector group exercises its real bounded mailbox rather than direct callback scheduling.
-spec with_barrier(fun((pid()) -> term())) -> ok.
with_barrier(Fun) ->
    with_actor(snowflake_barrier, 8, #{status => self()}, fun(Pid) ->
        cast(Pid, #sf_barrier_config{source = 2, first = 12, count = 6}),
        lists:foreach(fun(Source) -> cast(Pid, #sf_ready{source = Source}) end, lists:seq(12, 17)),
        ?assertEqual(#sf_ready{source = 2}, message()),
        Fun(Pid)
    end).

%% All six neighbors exist, so the postponement bound exercises its maximum degree.
-spec with_vertex(fun((pid()) -> term())) -> ok.
with_vertex(Fun) ->
    Outputs = maps:from_list([{Port, self()} ||
        Port <- [west, east, down, up, north, south, below, status, correction]]),
    with_actor(snowflake_vertex, 24, Outputs, fun(Pid) ->
        cast(Pid, #sf_geometry{boundary_limit = 50, boundary_shift = 10, bulk_shift = 20}),
        cast(Pid, #sf_vertex_config{source = 0, id = 7, neighbors = 63, syndrome_bit = 255,
            height = 3, top = false}),
        ?assertEqual(#sf_ready{source = 0}, message()),
        Fun(Pid)
    end).

%% Teardown removes only this test's actor and output casts, including after intended rejection.
-spec with_actor(module(), pos_integer(), map(), fun((pid()) -> term())) -> ok.
with_actor(Module, Capacity, Outputs, Fun) ->
    {ok, Pid} = hls_statem:start_link(Module, [], [{outputs, Outputs}, {mailbox_capacity, Capacity}]),
    unlink(Pid),
    try Fun(Pid), ok
    after
        case is_process_alive(Pid) of true -> hls_statem:stop(Pid); false -> ok end,
        flush()
    end.

%% Protocol rejections must kill the actor rather than produce an extra completion.
-spec expect_failure(pid(), [tuple()]) -> ok.
expect_failure(Pid, Messages) ->
    Ref = monitor(process, Pid),
    lists:foreach(fun(Message) -> cast(Pid, Message) end, Messages),
    receive
        {'DOWN', Ref, process, Pid, {hls_statem_reduction_failure, {duplicate_member, _}, Message}} ->
            ?assert(is_tuple(Message));
        {'DOWN', Ref, process, Pid, {hls_statem_gather_failure, {duplicate_member, _}, Message}} ->
            ?assertMatch(#sf_snapshot{}, Message);
        {'DOWN', Ref, process, Pid, {hls_statem_failure, Message}} ->
            ?assert(is_tuple(Message));
        {'DOWN', Ref, process, Pid, {{badmatch, Value}, Stack}} ->
            ?assert(is_boolean(Value)), ?assert(is_list(Stack));
        {'DOWN', Ref, process, Pid, {function_clause, Stack}} ->
            ?assert(is_list(Stack));
        {'DOWN', Ref, process, Pid, Other} -> error({unrelated_actor_failure, Other})
    after 1000 -> error(malformed_message_accepted) end.

%% Keep the ordinary actor API visible at every injection site.
-spec cast(pid(), tuple()) -> ok.
cast(Pid, Message) -> hls_statem:cast(Pid, Message).

%% Minimal quiet records isolate phase and identity validation.
-spec done(non_neg_integer(), non_neg_integer(), non_neg_integer()) -> #sf_done{}.
done(Source, Epoch, Kind) -> #sf_done{source = Source, epoch = Epoch, kind = Kind}.

%% Snapshot contents do not change the bounded queue argument.
-spec snap(non_neg_integer(), non_neg_integer()) -> #sf_snapshot{}.
snap(Epoch, Direction) -> #sf_snapshot{epoch = Epoch, direction = Direction, node = #node{cid = 100}}.

%% A missing publication is a bounded test failure.
-spec message() -> tuple().
message() -> receive {'$gen_cast', Message} -> Message after 1000 -> error(missing_publication) end.

%% Discard only ordinary outputs owned by the just-stopped actor.
-spec flush() -> ok.
flush() -> receive {'$gen_cast', _} -> flush() after 0 -> ok end.

-endif.
