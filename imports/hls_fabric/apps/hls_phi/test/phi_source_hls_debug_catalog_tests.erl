-module(phi_source_hls_debug_catalog_tests).
-include_lib("eunit/include/eunit.hrl").

%% Checks phi cpu targets retain logical identity for the retained Phi application.
-spec phi_cpu_targets_retain_logical_identity_test() -> ok.
phi_cpu_targets_retain_logical_identity_test() ->
    {ok, Fabric} = phi_memory_cpu_fabric:start_link(3, 0),
    try
        Catalog = phi_memory_cpu_fabric:debug_targets(Fabric),
        ?assertEqual(54, length(hls_debug_catalog:actors(Catalog))),
        {ok, Target} = hls_debug_catalog:actor(Catalog, {family, phi_x, [0, 0]}),
        ?assertEqual([{identity, {family, phi_x, [0, 0]}}, {lifecycle, disconnected}],
            hls_debug:info(Target, [identity, lifecycle])),
        {placement, #{kind := process, pid := Pid}} = hls_debug:info(Target, placement),
        #{mailbox := #{committed := Count}} = hls_statem:info(Pid),
        ?assertEqual({message_queue_len, Count}, hls_debug:info(Target, message_queue_len)),
        ?assertMatch({error, {unknown_actor, _}}, hls_debug_catalog:actor(Catalog, {family, phi_x, [9, 9]}))
    after phi_memory_cpu_fabric:stop(Fabric) end.
