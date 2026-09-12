-module(hls_debug_target_tests).
-include_lib("eunit/include/eunit.hrl").
-export([init/1, waiting/3]).

beam_queue_is_distinct_from_actor_mailbox_test() ->
    {ok, Pid} = hls_statem:start_link(?MODULE, self(),
        [{mailbox_capacity, 4}, {outputs, #{}}]),
    try
        hls_statem:cast(Pid, postponed),
        ?assertEqual([{message_queue_len, 1}, {postponed, 1}, {free_slots, 3},
            {mailbox_capacity, 4}, {reserved, 0}, {beam_message_queue_len, 0}],
            hls_debug:info({hls_statem, Pid}, [message_queue_len, postponed,
                free_slots, mailbox_capacity, reserved, beam_message_queue_len])),
        ?assertEqual(erlang:process_info(Pid, message_queue_len),
            hls_debug:info(Pid, message_queue_len)),
        {scope, Scope} = hls_debug:info({hls_statem, Pid}, scope),
        ?assertEqual({error, {unsupported_items, Scope, [occupancy]}},
            hls_debug:info({hls_statem, Pid}, occupancy)),
        %% Native mailbox inspection still works during a blocked callback.
        hls_statem:cast(Pid, block),
        receive blocked -> ok after 1000 -> error(not_blocked) end,
        hls_statem:cast(Pid, postponed),
        ?assertEqual({beam_message_queue_len, 1},
            hls_debug:info({hls_statem, Pid}, beam_message_queue_len)),
        ?assertEqual({error, timeout}, hls_debug:info({hls_statem, Pid}, phase, 1)),
        Pid ! release,
        ?assertEqual({message_queue_len, 2}, hls_debug:info({hls_statem, Pid}, message_queue_len))
    after
        unlink(Pid),
        Monitor = monitor(process, Pid),
        exit(Pid, kill),
        receive {'DOWN', Monitor, process, Pid, _} -> ok end
    end,
    ?assertEqual(undefined, hls_debug:info(Pid, message_queue_len)),
    ?assertEqual(undefined, hls_debug:info({hls_statem, Pid}, message_queue_len)).

init(Owner) -> {ok, waiting, Owner}.
waiting(enter, _, Owner) -> {Owner, []};
waiting(cast, postponed, Owner) -> {waiting, Owner, postpone};
waiting(cast, block, Owner) ->
    Owner ! blocked,
    receive release -> {waiting, Owner, consume} end.

shared_boundary_requires_explicit_selection_test() ->
    {ok, Fabric} = phi_memory_fabric_fixture:start_link(),
    {ok, Client} = hls_debug:start_link(undefined, {fabric, Fabric, 1}),
    try
        Boundary = {boundary, Client, host_stream},
        Plan = hls_topology:from_module(phi_decoder_profile_topology),
        Catalog = hls_debug_catalog:hardware(Plan,
            maps:get(scheduler_groups, phi_decoder_profile_topology_dslx:profile()), [Boundary]),
        {ok, Actor} = hls_debug_catalog:actor(Catalog, {family, phi_x, [0, 0]}),
        {scope, Scope} = hls_debug:info(Actor, scope),
        ?assertEqual({error, {unsupported_operation, Scope, get_trace}}, hls_debug:get_trace(Actor)),
        ?assertEqual({error, {unsupported_operation, Scope, get_counters}}, hls_debug:get_counters(Actor)),
        ?assertEqual({error, {unsupported_items, Scope, [message_queue_len]}},
            hls_debug:info(Actor, message_queue_len)),
        ?assertEqual([], phi_memory_fabric_fixture:sends(Fabric)),
        ?assertEqual({boundaries, [Boundary]}, hls_debug:info(Actor, boundaries)),
        %% Rejecting an actor-level trace must not drain the shared bank.
        Parent = self(),
        spawn_link(fun() -> Parent ! {trace, hls_debug:get_trace(Boundary)} end),
        [{{0, 1}, {3, Tx, 0}, <<>>}] = phi_memory_fabric_fixture:await_sends(Fabric, 1, 1000),
        ok = phi_memory_fabric_fixture:deliver(Fabric, {1, 0}, {16#83, Tx, 0},
            <<1:32/little, 2:32/little, 1:32/little, 0:32/little, 0:32/little,
                123:32/little, 7:8, 42:8, 1:8, 1:8>>),
        receive {trace, {ok, Trace}} ->
            ?assertEqual(#{kind => boundary, id => host_stream}, maps:get(scope, Trace)),
            ?assertMatch([#{cycle := 123, kind := application_rx, tx_id := 42}], maps:get(events, Trace))
        after 1000 -> error(no_trace) end
    after hls_debug:stop(Client), phi_memory_fabric_fixture:stop(Fabric) end.

resource_items_use_one_hardware_sample_test() ->
    {ok, Fabric} = phi_memory_fabric_fixture:start_link(),
    {ok, Client} = hls_debug:start_link(undefined, {fabric, Fabric, 2}),
    try
        Resource = #{<<"kind">> => <<"fifo">>, <<"id">> => 0, <<"name">> => <<"queue">>,
            <<"capacity">> => 4, <<"width">> => 3},
        Session = #{client => Client, resources => {Resource}, manifest => #{<<"fingerprint">> => <<"fixture">>}},
        {ok, Target} = hls_topology_debug:resource(Session, 0),
        {scope, Scope} = hls_debug:info(Target, scope),
        ?assertEqual({error, {unsupported_items, Scope, [message_queue_len]}},
            hls_debug:info(Target, message_queue_len)),
        ?assertEqual([], phi_memory_fabric_fixture:sends(Fabric)),
        Parent = self(),
        spawn_link(fun() -> Parent ! {sample, hls_debug:info(Target, [cycle, occupancy, free_slots, capacity, occupancy])} end),
        [{{0, 2}, {16#11, Tx, 0}, <<0:32/little>>}] = phi_memory_fabric_fixture:await_sends(Fabric, 1, 1000),
        ok = phi_memory_fabric_fixture:deliver(Fabric, {2, 0}, {16#91, Tx, 0},
            <<0:32/little, 33:64/little, 3:32/little>>),
        receive {sample, Values} ->
            ?assertEqual([{cycle, 33}, {occupancy, 3}, {free_slots, 1}, {capacity, 4}, {occupancy, 3}], Values)
        after 1000 -> error(no_sample) end,
        ?assertEqual(1, length(phi_memory_fabric_fixture:sends(Fabric)))
    after hls_debug:stop(Client), phi_memory_fabric_fixture:stop(Fabric) end.
