-module(hls_mailbox_debug_tests).
-include_lib("eunit/include/eunit.hrl").

cpu_postponement_and_replay_test() ->
    Module = hls_mailbox_debug_fixture,
    #{outputs := Ports} = hls_actor_interface:from_module(Module),
    {ok, Pid} = hls_statem:start_link(Module, [],
        [{mailbox_capacity, 3}, {outputs, maps:from_keys(Ports, self())}]),
    try
        Actor = {hls_statem, Pid},
        ok = hls_statem:cast(Pid, {configure, 1}),
        ok = hls_statem:cast(Pid, {work, 1}),
        ok = hls_statem:cast(Pid, {work, 2}),
        ?assertEqual([{phase, waiting}, {message_queue_len, 2}, {postponed, 2},
            {reserved, 0}, {free_slots, 1}], hls_debug:info(Actor,
                [phase, message_queue_len, postponed, reserved, free_slots])),
        ok = hls_statem:cast(Pid, {advance, 0}),
        ?assertEqual([{phase, done}, {message_queue_len, 0}, {postponed, 0}, {free_slots, 3}],
            hls_debug:info(Actor, [phase, message_queue_len, postponed, free_slots]))
    after hls_statem:stop(Pid) end.

mailbox_wire_contract_test() ->
    Resource = #{<<"id">> => 0, <<"kind">> => <<"actor">>, <<"width">> => 56,
        <<"mailbox_capacity">> => 3, <<"phases">> => [<<"waiting">>], <<"failures">> => #{}},
    Decode = fun(Word, Actor) -> hls_topology_debug:decode_observation(
        <<0:32/little, 123:64/little, Actor:32/little, Word:32/little, 0:64>>, Resource) end,
    ?assertMatch({ok, #{initialized := false, mailbox_initialized := false,
        message_queue_len := undefined, free_slots := undefined}}, Decode(0, 0)),
    %% Same vector as the DSLX packing test: count=2, postponed=1, RUN,
    %% in-flight, mail candidate, egress waiter, and shared egress busy.
    ?assertMatch({ok, #{initialized := true, mailbox_initialized := true,
        phase := <<"waiting">>, scheduler_phase := run, message_queue_len := 2,
        postponed := 1, reserved := 0, free_slots := 1, in_flight := true,
        mail_candidate := true, entry_candidate := false, waiting_for_egress := true,
        egress_busy := true, cycle := 123}}, Decode(16#db0102, 1 bsl 25)),
    ?assertMatch({error, _}, Decode(16#db0104, 1 bsl 25)),
    ?assertMatch({error, _}, Decode(16#db0302, 1 bsl 25)),
    ?assertMatch({error, _}, Decode(16#fb0102, 1 bsl 25)),
    ?assertMatch({error, _}, Decode(16#5b0102, 1 bsl 25)),
    ?assertMatch({error, _}, Decode(16#db0102, 1 bsl 26)),
    ?assertMatch({error, _}, Decode(16#1db0102, 1 bsl 25)).

projection_binds_mailbox_geometry_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(mailbox),
    Artifacts = hls_actor_debug_dslx:artifacts(mailbox, #{mailbox_debug => true}),
    Projection = #{<<"banks">> := [First | Rest]} =
        xls_scheduler_debug:projection(Plan, Specs, Artifacts, #{mailbox_debug => true}),
    ?assertEqual(ok, xls_scheduler_debug:validate(Plan, Specs, Projection)),
    Mailbox = maps:get(<<"mailbox">>, First),
    ?assertException(error, actor_projection_mismatch, xls_scheduler_debug:validate(Plan, Specs,
        Projection#{<<"banks">> := [First#{<<"mailbox">> := Mailbox#{<<"capacity">> := 99}} | Rest]})),
    ?assertException(error, actor_projection_mismatch, xls_scheduler_debug:validate(Plan, Specs,
        Projection#{<<"banks">> := [maps:remove(<<"mailbox">>, First) | Rest]})).

diagnostic_profile_is_explicit_test() ->
    {Plan, Specs} = hls_actor_debug_dslx:fixture(mailbox),
    Profile = #{name => mailbox_fixture, channel_depth => 1, actor_egress_depth => burst, scheduler_groups => Specs},
    Plain = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)),
    ?assertEqual(Plain, iolist_to_binary(xls_topology_dslx:emit(Plan, Profile#{mailbox_debug => false}))),
    ?assertEqual(nomatch, binary:match(Plain, <<"mailbox_debug_out">>)),
    Debug = iolist_to_binary(xls_topology_dslx:emit(Plan, Profile#{mailbox_debug => true})),
    ?assertNotEqual(nomatch, binary:match(Debug, <<"mailbox_debug_out">>)),
    Requirements = xls_topology_dslx:artifact_requirements(Plan, Profile#{mailbox_debug => true}),
    ?assertMatch(#{hls_mailbox_debug_fixture := #{mailbox_debug := true}}, Requirements),
    ?assertError({mailbox_debug, yes}, xls_topology_dslx:emit(Plan, Profile#{mailbox_debug => yes})),
    ?assertError(mailbox_debug_requires_shared_schedulers,
        xls_topology_dslx:emit(Plan, Profile#{scheduler_groups => #{}, mailbox_debug => true})),
    ?assertError(mailbox_debug_requires_hls_statem,
        xls_parse:to_xls("src/examples/regsvc/regsvc.erl", #{mailbox_debug => true})).
