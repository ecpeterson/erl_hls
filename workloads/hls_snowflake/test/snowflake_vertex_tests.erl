-module(snowflake_vertex_tests).
-moduledoc "Adversarial mailbox and edge-replica checks for the ordinary Snowflake vertex actor.".
-compile({parse_transform, hls_pack}).
-hls_data(test_state).
%% A separate codec root leaves the shared node record available as a nested value.
-record(test_state, {value = hls_type:zero() :: hls_nums:u8()}).
-include_lib("eunit/include/eunit.hrl").
-include("snowflake_actor_protocol.hrl").

%% A future phase cannot silently replace the configured epoch.
-spec wrong_epoch_test() -> ok.
wrong_epoch_test() ->
    with_vertex(config(0), fun(Pid, Monitor) ->
        hls_statem:cast(Pid, #sf_phase{epoch = 1, kind = 0}),
        failed(Pid, Monitor)
    end).

%% A completed drop advances the epoch, making a duplicate old shift a failure.
-spec stale_shift_test() -> ok.
stale_shift_test() ->
    with_vertex(config(0), fun(Pid, Monitor) ->
        hls_statem:cast(Pid, #sf_phase{epoch = 0, kind = 0}),
        done(0, 0),
        hls_statem:cast(Pid, #sf_shift{epoch = 0}),
        failed(Pid, Monitor)
    end).

%% The last snapshot commits growth before completion, independently of arrival order.
-spec complete_growth_snapshot_test() -> ok.
complete_growth_snapshot_test() ->
    with_vertex((config(3))#sf_vertex_config{top = false}, fun(Pid, _Monitor) ->
        shift(Pid, 0, #node{cid = 80, active = true, whole = true}, 5, 0),
        done(0, 0),
        #{node := Before} = observed(Pid),
        hls_statem:cast(Pid, #sf_phase{epoch = 1, kind = 1}),
        hls_statem:cast(Pid, #sf_snapshot{epoch = 1, direction = 2,
            node = #node{active = true, whole = false}}),
        #{phase := snapshotting, gather := #{seen := 2}} = hls_statem:info(Pid),
        #{node := Before, seen := 0, growth := 5} = observed(Pid),
        hls_statem:cast(Pid, #sf_snapshot{epoch = 1, direction = 1,
            node = #node{active = true, whole = true}}),
        done(0, 1),
        {Expected, true} = snowflake_node:grow(Before, true, false),
        #{phase := ready} = hls_statem:info(Pid),
        #{node := Actual, growth := 10, epoch := 2} = observed(Pid),
        ?assertEqual(Expected, Actual),
        hls_statem:cast(Pid, #sf_snapshot{epoch = 2, direction = 1,
            node = #node{active = true, whole = false}}),
        #{phase := ready, postponed := 1} = hls_statem:info(Pid),
        hls_statem:cast(Pid, #sf_phase{epoch = 2, kind = 3}),
        hls_statem:cast(Pid, #sf_snapshot{epoch = 2, direction = 2}),
        done(0, 2),
        {HalfExpected, false} = snowflake_node:grow(Expected, false, false),
        #{node := HalfActual, growth := 10, epoch := 3} = observed(Pid),
        ?assertEqual(HalfExpected, HalfActual)
    end).

%% An isolated vertex performs both growth kinds without waiting for nonexistent peers.
-spec isolated_growth_test() -> ok.
isolated_growth_test() ->
    with_vertex((config(0))#sf_vertex_config{top = false, bottom = true}, fun(Pid, _Monitor) ->
        shift(Pid, 0, #node{cid = 80, active = true, whole = true, pointer = 3}, 0, 0),
        done(0, 0),
        #{node := Before} = observed(Pid),
        hls_statem:cast(Pid, #sf_phase{epoch = 1, kind = 1}),
        done(0, 1),
        {Expected, true} = snowflake_node:grow(Before, true, true),
        #{node := Actual, growth := 0, epoch := 2} = observed(Pid),
        ?assertEqual(Expected, Actual),
        ?assertEqual({-1, 0}, {Actual#node.cid, Actual#node.pointer}),
        hls_statem:cast(Pid, #sf_phase{epoch = 2, kind = 3}),
        done(0, 2),
        {HalfExpected, false} = snowflake_node:grow(Expected, false, true),
        #{node := HalfActual, growth := 0, epoch := 3} = observed(Pid),
        ?assertEqual(HalfExpected, HalfActual)
    end).

%% Duplicate arrivals do not count toward a complete snapshot set.
-spec duplicate_snapshot_test() -> ok.
duplicate_snapshot_test() ->
    with_vertex(config(3), fun(Pid, Monitor) ->
        hls_statem:cast(Pid, #sf_phase{epoch = 0, kind = 1}),
        Message = #sf_snapshot{epoch = 0, direction = 1},
        hls_statem:cast(Pid, Message),
        hls_statem:cast(Pid, Message),
        failed(Pid, Monitor)
    end).

%% A snapshot for another phase is rejected while the current collection is incomplete.
-spec wrong_snapshot_epoch_test() -> ok.
wrong_snapshot_epoch_test() ->
    with_vertex(config(3), fun(Pid, Monitor) ->
        hls_statem:cast(Pid, #sf_phase{epoch = 0, kind = 1}),
        hls_statem:cast(Pid, #sf_snapshot{epoch = 1, direction = 1}),
        failed(Pid, Monitor)
    end).

%% Boundary shifts use the separate above/below link and discard absent temporal slots.
-spec early_boundary_shift_and_retirement_test() -> ok.
early_boundary_shift_and_retirement_test() ->
    Config = (config(2))#sf_vertex_config{top = false, bottom = true,
        boundary = true, height = 1, retire_mask = 2},
    with_vertex(Config, fun(Pid, _Monitor) ->
        Source = #node{cid = 10, whole = false, defect = true, grown = true, unrooted = true},
        hls_statem:cast(Pid, #sf_shift{epoch = 0, node = Source, growth = 16#aaa, correction = 63}),
        #{phase := configured, postponed := 1} = hls_statem:info(Pid),
        hls_statem:cast(Pid, #sf_phase{epoch = 0, kind = 0}),
        done(0, 0),
        #{node := Node, growth := Growth, correction := Correction, epoch := 1} = observed(Pid),
        ?assertEqual(Source#node{cid = 20, grown = false, unrooted = false}, Node),
        ?assertEqual({8, 2}, {Growth, Correction}),
        shift(Pid, 1, Source, 0, 0),
        correction(0, 0, 2), done(0, 1),
        shift(Pid, 2, Source, 0, 0),
        correction(0, 1, 0), done(0, 2)
    end).

%% The top sends its old state downward before injecting the newly offered syndrome.
-spec immutable_top_shift_test() -> ok.
immutable_top_shift_test() ->
    Config = (config(0))#sf_vertex_config{below = true, syndrome_bit = 0},
    with_vertex(Config, fun(Pid, _Monitor) ->
        hls_statem:cast(Pid, #sf_phase{epoch = 0, kind = 0, mask = 1}),
        receive
            {'$gen_cast', #sf_shift{epoch = 0, node = Old, growth = 0, correction = 0}} ->
                ?assertEqual(snowflake_node:reset(7), Old)
        after 1000 -> error(missing_immutable_shift)
        end,
        done(0, 0),
        #{node := Node} = observed(Pid),
        ?assertEqual(true, Node#node.defect),
        ?assertEqual(7, Node#node.cid)
    end).

%% The same undirected shifted edge appears in opposite endpoint slots.
-spec shifted_endpoint_agreement_test() -> ok.
shifted_endpoint_agreement_test() ->
    Left = (config(2))#sf_vertex_config{source = 1, top = false, boundary = true},
    Right = (config(1))#sf_vertex_config{source = 2, top = false},
    with_vertex(Left, fun(A, _AMonitor) ->
        with_vertex(Right, fun(B, _BMonitor) ->
            shift(A, 0, #node{cid = 10, whole = true}, 8, 2),
            shift(B, 0, #node{cid = 70, whole = true}, 2, 1),
            done(1, 0), done(2, 0),
            #{node := AN, growth := AG, correction := AC} = observed(A),
            #{node := BN, growth := BG, correction := BC} = observed(B),
            ?assertEqual({20, 90}, {AN#node.cid, BN#node.cid}),
            ?assertEqual({2, 2, 1, 1}, {(AG bsr 2) band 3, BG band 3, (AC bsr 1) band 1, BC band 1})
        end)
    end).

%% Two incoming defects cancel at the vertex but toggle both correction edges.
-spec incoming_transfer_parity_test() -> ok.
incoming_transfer_parity_test() ->
    with_vertex((config(3))#sf_vertex_config{top = false}, fun(Pid, _Monitor) ->
        merging(Pid),
        hls_statem:cast(Pid, #sf_transfer{epoch = 1, direction = 2, outgoing = 1}),
        hls_statem:cast(Pid, #sf_transfer{epoch = 1, direction = 1, outgoing = 2}),
        done(0, 1),
        #{node := Node, correction := 3} = observed(Pid),
        ?assertEqual(false, Node#node.defect),
        ?assertEqual(false, Node#node.busy)
    end).

%% Duplicate transfer acknowledgments cannot hide a missing neighbor contribution.
-spec duplicate_transfer_test() -> ok.
duplicate_transfer_test() ->
    with_vertex((config(3))#sf_vertex_config{top = false}, fun(Pid, Monitor) ->
        merging(Pid),
        Message = #sf_transfer{epoch = 1, direction = 1, outgoing = 2},
        hls_statem:cast(Pid, Message),
        hls_statem:cast(Pid, Message),
        failed(Pid, Monitor)
    end).

%% Invalid epochs, foreign neighbors and invalid outgoing directions still fail through the actor.
-spec malformed_transfer_test_() -> [fun(() -> ok)].
malformed_transfer_test_() ->
    [fun() -> with_vertex((config(3))#sf_vertex_config{top = false}, fun(Pid, Monitor) ->
        merging(Pid), hls_statem:cast(Pid, Message), failed(Pid, Monitor)
    end) end || Message <- [#sf_transfer{epoch = 0, direction = 1},
        #sf_transfer{epoch = 2, direction = 1}, #sf_transfer{epoch = 1, direction = 3},
        #sf_transfer{epoch = 1, direction = 0}, #sf_transfer{epoch = 1, direction = 7},
        #sf_transfer{epoch = 1, direction = 1, outgoing = 7}]].

%% Early traffic is replayed into the same collection; partial parity is private until completion.
-spec early_transfer_progress_test() -> ok.
early_transfer_progress_test() ->
    with_vertex((config(3))#sf_vertex_config{top = false}, fun(Pid, _Monitor) ->
        shift(Pid, 0, #node{cid = 80, whole = true}, 10, 0), done(0, 0),
        hls_statem:cast(Pid, #sf_phase{epoch = 1, kind = 2}),
        hls_statem:cast(Pid, #sf_transfer{epoch = 1, direction = 2, outgoing = 1}),
        ?assertMatch(#{phase := snapshotting, postponed := 1}, hls_statem:info(Pid)),
        lists:foreach(fun(Direction) -> hls_statem:cast(Pid,
            #sf_snapshot{epoch = 1, direction = Direction, node = #node{cid = 100, whole = true}})
        end, [1, 2]),
        ?assertMatch(#{phase := transferring, reduction := #{population := {members, [0, 1]},
            remaining := 1, received := 1}}, hls_statem:info(Pid)),
        ?assertMatch(#{correction := 0}, observed(Pid)),
        hls_statem:cast(Pid, #sf_transfer{epoch = 1, direction = 1, outgoing = 2}),
        done(0, 1),
        ?assertMatch(#{correction := 3}, observed(Pid)),
        ?assertMatch(#{reduction := idle}, hls_statem:info(Pid))
    end).

%% An isolated vertex follows its explicit empty-collection path without opening an invalid mask.
-spec isolated_vertex_transfer_test() -> ok.
isolated_vertex_transfer_test() ->
    with_vertex((config(0))#sf_vertex_config{top = false}, fun(Pid, _Monitor) ->
        shift(Pid, 0, #node{cid = 80, whole = true}, 0, 0), done(0, 0),
        hls_statem:cast(Pid, #sf_phase{epoch = 1, kind = 2}), done(0, 1),
        ?assertMatch(#{phase := ready, reduction := idle}, hls_statem:info(Pid)),
        ?assertMatch(#{correction := 0}, observed(Pid))
    end).

%% A minimal valid startup leaves geometry choices explicit in each test.
-spec config(hls_nums:u8()) -> #sf_vertex_config{}.
config(Neighbors) -> #sf_vertex_config{source = 0, id = 7, neighbors = Neighbors,
    syndrome_bit = 255, height = 3, top = true}.

%% All outputs are ordinary casts; tests keep the actor unlinked before deliberately failing it.
-spec with_vertex(#sf_vertex_config{}, fun((pid(), reference()) -> term())) -> ok.
with_vertex(Config, Fun) ->
    Ports = [west, east, down, up, north, south, below, status, correction],
    Outputs = maps:from_list([{Port, self()} || Port <- Ports]),
    {ok, Pid} = hls_statem:start_link(snowflake_vertex, [], [{outputs, Outputs}, {mailbox_capacity, 24}]),
    unlink(Pid), Monitor = monitor(process, Pid),
    try
        hls_statem:cast(Pid, #sf_geometry{boundary_limit = 50, boundary_shift = 10, bulk_shift = 20}),
        hls_statem:cast(Pid, Config),
        Source = Config#sf_vertex_config.source,
        receive {'$gen_cast', #sf_ready{source = Source}} -> ok after 1000 -> error(vertex_not_ready) end,
        Fun(Pid, Monitor), ok
    after
        demonitor(Monitor, [flush]),
        catch hls_statem:stop(Pid),
        flush_casts()
    end.

%% Enter a merge with two full edges and no local defect or busy work.
-spec merging(pid()) -> ok.
merging(Pid) ->
    shift(Pid, 0, #node{cid = 80, whole = true}, 10, 0),
    done(0, 0),
    hls_statem:cast(Pid, #sf_phase{epoch = 1, kind = 2}),
    hls_statem:cast(Pid, #sf_snapshot{epoch = 1, direction = 2, node = #node{cid = 100, whole = true}}),
    hls_statem:cast(Pid, #sf_snapshot{epoch = 1, direction = 1, node = #node{cid = 100, whole = true}}),
    #{phase := transferring} = hls_statem:info(Pid),
    ok.

%% Delivering shift data first also checks postponement before the phase command.
-spec shift(pid(), non_neg_integer(), #node{}, non_neg_integer(), non_neg_integer()) -> ok.
shift(Pid, Epoch, Node, Growth, Correction) ->
    hls_statem:cast(Pid, #sf_shift{epoch = Epoch, node = Node, growth = Growth, correction = Correction}),
    hls_statem:cast(Pid, #sf_phase{epoch = Epoch, kind = 0}).

%% Observe callback data through the supported runtime query.
-spec observed(pid()) -> map().
observed(Pid) ->
    #{data := Data} = hls_statem:info(Pid),
    snowflake_vertex:snapshot(Data).

%% Explicit record matching keeps unrelated neighbor traffic in the test mailbox.
-spec done(non_neg_integer(), non_neg_integer()) -> ok.
done(Source, Epoch) ->
    receive {'$gen_cast', #sf_done{source = Source, epoch = Epoch}} -> ok
    after 1000 -> error({missing_vertex_done, Source, Epoch}) end.

%% Even zero retired parity is an observable correction record after warmup.
-spec correction(non_neg_integer(), non_neg_integer(), non_neg_integer()) -> ok.
correction(Source, Sheet, Edges) ->
    receive {'$gen_cast', #sf_correction{source = Source, sheet = Sheet, edges = Edges}} -> ok
    after 1000 -> error({missing_vertex_correction, Source, Sheet, Edges}) end.

%% Both an explicit fail conclusion and a rejected invariant must stop the malformed actor.
-spec failed(pid(), reference()) -> ok.
failed(Pid, Monitor) ->
    receive {'DOWN', Monitor, process, Pid, Reason} -> ?assertNotEqual(normal, Reason)
    after 1000 -> error(vertex_accepted_malformed_message) end.

%% Each test owns its relay mailbox and removes only its leftover ordinary casts.
-spec flush_casts() -> ok.
flush_casts() -> receive {'$gen_cast', _} -> flush_casts() after 0 -> ok end.
