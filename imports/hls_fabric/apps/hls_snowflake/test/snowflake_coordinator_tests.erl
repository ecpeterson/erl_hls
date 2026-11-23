-module(snowflake_coordinator_tests).
-moduledoc "Barrier identity, startup ordering and stale-epoch rejection checks.".
-include_lib("eunit/include/eunit.hrl").
-include("snowflake_actor_protocol.hrl").

%% Configuration can trail vertex readiness and input without starting a partial population.
-spec early_startup_test() -> ok.
early_startup_test() ->
    with_actor(fun(Pid) ->
        hls_statem:cast(Pid, #sf_ready{source = 1}),
        hls_statem:cast(Pid, #sf_input{sheet = 0, mask = 7}),
        hls_statem:cast(Pid, #sf_coordinator_config{count = 2, height = 3}),
        ?assertEqual(configuring, maps:get(phase, hls_statem:info(Pid))),
        hls_statem:cast(Pid, #sf_ready{source = 0}),
        ?assertEqual(#sf_phase{epoch = 0, kind = 0, mask = 7}, command())
    end).

%% A whole large population can report before configuration without filling the mailbox.
-spec large_early_startup_test() -> ok.
large_early_startup_test() ->
    with_actor(fun(Pid) ->
        Count = min(150, maps:get(sources, snowflake_coordinator:bounds())),
        lists:foreach(fun(Source) -> hls_statem:cast(Pid, #sf_ready{source = Source}) end,
            lists:seq(0, Count - 1)),
        hls_statem:cast(Pid, #sf_input{sheet = 0, mask = 0}),
        hls_statem:cast(Pid, #sf_coordinator_config{count = Count, height = 5}),
        ?assertEqual(#sf_phase{epoch = 0, kind = 0, mask = 0}, command())
    end).

%% Early acknowledgments are checked against the eventual configured population.
-spec unknown_early_source_test() -> ok.
unknown_early_source_test() ->
    with_actor(fun(Pid) ->
        hls_statem:cast(Pid, #sf_ready{source = 2}),
        Monitor = monitor(process, Pid),
        hls_statem:cast(Pid, #sf_coordinator_config{count = 2, height = 3}),
        rejected(Pid, Monitor, {badmatch, false})
    end).

%% Population specialization rejects excess identities instead of truncating their bits.
-spec compiled_source_bound_test() -> ok.
compiled_source_bound_test() ->
    #{sources := Bound} = snowflake_coordinator:bounds(),
    lists:foreach(fun(Message) -> with_actor(fun(Pid) ->
        Monitor = monitor(process, Pid),
        hls_statem:cast(Pid, Message),
        rejected(Pid, Monitor, {badmatch, false})
    end) end, [#sf_ready{source = Bound},
        #sf_coordinator_config{count = Bound + 1, height = 3}]).

%% All eight input credits may arrive before startup; completion traffic must still advance every sheet.
-spec full_input_window_test() -> ok.
full_input_window_test() ->
    with_actor(fun(Pid) ->
        Count = min(6, maps:get(sources, snowflake_coordinator:bounds())),
        lists:foreach(fun(Sheet) -> hls_statem:cast(Pid, #sf_input{sheet = Sheet, mask = 0}) end,
            lists:seq(0, 7)),
        lists:foreach(fun(Source) -> hls_statem:cast(Pid, #sf_ready{source = Source}) end,
            lists:seq(0, Count - 1)),
        hls_statem:cast(Pid, #sf_coordinator_config{count = Count, height = 3}),
        lists:foreach(fun(Sheet) ->
            lists:foreach(fun(Kind) ->
                Epoch = Sheet * 5 + Kind,
                ?assertEqual(#sf_phase{epoch = Epoch, kind = Kind, mask = 0}, command()),
                lists:foreach(fun(Source) -> acknowledge(Pid, Source, Epoch, Kind, false) end,
                    lists:reverse(lists:seq(0, Count - 1)))
            end, lists:seq(0, 4)),
            %% Distinct output ports may deliver the next command before this report.
            Report = receive {'$gen_cast', Round = #sf_round{}} -> Round
                after 1000 -> error(missing_round_report) end,
            ?assertEqual(#sf_round{sheet = Sheet, epoch = Sheet * 5 + 4}, Report)
        end, lists:seq(0, 7))
    end).

%% A single busy vertex keeps a merge alive; quiet peers cannot erase its contribution.
-spec busy_barrier_test() -> ok.
busy_barrier_test() ->
    with_actor(fun(Pid) ->
        start_sheet(Pid),
        lists:foreach(fun({Epoch, Kind}) ->
            acknowledge(Pid, 1, Epoch, Kind, false),
            %% The info call ensures that the first acknowledgment was consumed.
            ?assertEqual(executing, maps:get(phase, hls_statem:info(Pid))),
            receive {'$gen_cast', Unexpected} -> error({early_barrier, Unexpected}) after 0 -> ok end,
            acknowledge(Pid, 0, Epoch, Kind, false),
            ?assertEqual(#sf_phase{epoch = Epoch + 1, kind = Kind + 1, mask = 0}, command())
        end, [{0, 0}, {1, 1}]),
        acknowledge(Pid, 0, 2, 2, true),
        acknowledge(Pid, 1, 2, 2, false),
        ?assertEqual(#sf_phase{epoch = 3, kind = 2, mask = 0}, command()),
        acknowledge(Pid, 1, 3, 2, false),
        acknowledge(Pid, 0, 3, 2, false),
        ?assertEqual(#sf_phase{epoch = 4, kind = 3, mask = 0}, command())
    end).

%% A repeated source must fail before it could stand in for an absent vertex.
-spec duplicate_done_test() -> ok.
duplicate_done_test() ->
    with_actor(fun(Pid) ->
        start_sheet(Pid),
        Monitor = monitor(process, Pid),
        acknowledge(Pid, 0, 0, 0, false),
        acknowledge(Pid, 0, 0, 0, false),
        rejected(Pid, Monitor, {badmatch, true})
    end).

%% Neither a future phase nor a nonmember source may satisfy the current barrier.
-spec stale_or_unknown_done_test_() -> [fun(() -> ok)].
stale_or_unknown_done_test_() ->
    [fun() -> with_actor(fun(Pid) ->
        start_sheet(Pid),
        Monitor = monitor(process, Pid),
        hls_statem:cast(Pid, Message),
        rejected(Pid, Monitor, Reason)
    end) end || {Message, Reason} <- [
        {#sf_done{source = 0, epoch = 1, kind = 0, busy = false}, function_clause},
        {#sf_done{source = 2, epoch = 0, kind = 0, busy = false}, {badmatch, false}}]].

%% Use the real behavior, with ordinary output casts observed by the test process.
-spec with_actor(fun((pid()) -> ok)) -> ok.
with_actor(Fun) ->
    #{mailbox := Capacity} = snowflake_coordinator:bounds(),
    {ok, Pid} = hls_statem:start_link(snowflake_coordinator, [],
        [{mailbox_capacity, Capacity}, {outputs, #{command => self(), report => self()}}]),
    unlink(Pid),
    try Fun(Pid)
    after
        case is_process_alive(Pid) of true -> hls_statem:stop(Pid); false -> ok end
    end.

%% A complete startup produces exactly one drop command for the first sheet.
-spec start_sheet(pid()) -> ok.
start_sheet(Pid) ->
    hls_statem:cast(Pid, #sf_coordinator_config{count = 2, height = 3}),
    hls_statem:cast(Pid, #sf_ready{source = 0}),
    hls_statem:cast(Pid, #sf_ready{source = 1}),
    hls_statem:cast(Pid, #sf_input{sheet = 0, mask = 0}),
    ?assertEqual(#sf_phase{epoch = 0, kind = 0, mask = 0}, command()).

%% Send one commit using the public application protocol.
-spec acknowledge(pid(), non_neg_integer(), non_neg_integer(), non_neg_integer(), boolean()) -> ok.
acknowledge(Pid, Source, Epoch, Kind, Busy) ->
    hls_statem:cast(Pid, #sf_done{source = Source, epoch = Epoch, kind = Kind, busy = Busy}).

%% A missing command is a failed liveness check, never a successful quiet result.
-spec command() -> #sf_phase{}.
command() ->
    receive {'$gen_cast', Phase = #sf_phase{}} -> Phase
    after 1000 -> error(missing_phase_command)
    end.

%% Preserve the callback failure reason so an unrelated crash cannot satisfy rejection.
-spec rejected(pid(), reference(), term()) -> ok.
rejected(Pid, Monitor, Reason) ->
    receive {'DOWN', Monitor, process, Pid, {Actual, _Stack}} -> ?assertEqual(Reason, Actual)
    after 1000 -> error(invalid_acknowledgment_was_accepted)
    end.
