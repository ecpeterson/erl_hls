-module(hls_fabric_runtime_package_tests).
-moduledoc "Checks retained deployment and inspection bindings plus a live virtual node in a child VM containing only deployed runtime applications.".
-include_lib("eunit/include/eunit.hrl").

%% Isolated child VM entry point.
-export([witness/0]).

%% Source preparation happens in the parent; the child has neither source actors nor build modules.
-spec isolated_runtime_test_() -> {timeout, pos_integer(), fun(() -> ok)}.
isolated_runtime_test_() ->
    {timeout, 45, fun isolated_runtime/0}.

%% Copy only the executable witness, device model and transformed service beside retained terms.
-spec isolated_runtime() -> ok.
isolated_runtime() ->
    Suffix = integer_to_list(erlang:unique_integer([positive])),
    Dir = filename:absname(filename:join(["_build", "fabric-runtime-package", Suffix])),
    ok = filelib:ensure_dir(filename:join(Dir, "fixture.etf")),
    try
        ok = file:write_file(filename:join(Dir, "fixture.etf"), term_to_binary(prepare())),
        lists:foreach(fun(Module) ->
            {Module, Beam, _} = code:get_object_code(Module),
            ok = file:write_file(filename:join(Dir, atom_to_list(Module) ++ ".beam"), Beam)
        end, [?MODULE, hls_device_fixture, regsvc]),
        Port = open_port({spawn_executable, os:find_executable("erl")},
            [binary, exit_status, stderr_to_stdout,
             {env, [{"ERL_LIBS", false}, {"ERL_AFLAGS", false}, {"ERL_FLAGS", false}]},
             {args, ["+S", "2:2", "+A", "2", "-noshell", "-sname", "fabric_runtime_" ++ Suffix,
                 "-pa", filename:join(code:lib_dir(hls_fabric), "ebin"), filename:join(code:lib_dir(hls_runtime), "ebin"), Dir,
                 "-runtime_fixture", Dir,
                 "-eval", "ok = hls_fabric_runtime_package_tests:witness(), halt(0)."]}]),
        await(Port, erlang:monotonic_time(millisecond) + 30000, <<>>)
    after
        ok = file:del_dir_r(Dir)
    end.

%% Use actual source lowering and slot normalization before removing those modules from the child path.
-spec prepare() -> map().
prepare() ->
    {Plan, Specs, Endpoints} = hls_actor_pid_dslx:fixture(),
    Deployment = hls_node_topology:normalize(Plan, Specs, Endpoints),
    Artifact = xls_scheduler_actor:to_artifact("apps/hls_fabric/test/hls_actor_pid_fixture.erl", #{}),
    Projection = xls_scheduler_debug:projection(Plan, Specs, #{hls_actor_pid_fixture => Artifact}),
    Binding = hls_shared_debug_catalog:prepare(Plan, Specs, [], Projection),
    Raw = [A#{<<"kind">> => <<"actor">>, <<"bank">> => Index,
        <<"module">> => Module, <<"phases">> => Phases, <<"failures">> => Failures,
        <<"width">> => 26}
        || #{<<"index">> := Index, <<"module">> := Module, <<"phases">> := Phases,
            <<"failures">> := Failures, <<"actors">> := Actors} <- maps:get(<<"banks">>, Projection),
            A <- Actors],
    Resources = [R#{<<"id">> => Id} || {Id, R} <- lists:enumerate(0, Raw)],
    Manifest = #{<<"actor_projection">> => Projection, <<"resources">> => Resources,
        <<"fingerprint">> => <<"isolated-runtime-fixture">>},
    #{deployment => Deployment, binding => Binding, manifest => Manifest,
        selector => hls_actor_pid_fixture:pack_tag(work)}.

%% Bound wall time and retained failure output even if the child repeatedly emits diagnostics.
-spec await(port(), integer(), binary()) -> ok.
await(Port, Deadline, Output) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Bytes}} ->
            Combined = <<Output/binary, Bytes/binary>>,
            Start = max(0, byte_size(Combined) - 65536),
            await(Port, Deadline, binary:part(Combined, Start, byte_size(Combined) - Start));
        {Port, {exit_status, 0}} -> ok;
        {Port, {exit_status, Status}} -> error({fabric_runtime_witness_failed, Status, Output})
    after Remaining ->
        port_close(Port),
        error({fabric_runtime_witness_timeout, Output})
    end.

-doc "Exercises retained cast packing, inspection attachment and a real virtual-node request without compiler or lowering code. This is a finite wire-model witness, not hardware execution.".
-spec witness() -> ok.
witness() ->
    ok = absent_build_modules(),
    {ok, [[Dir]]} = init:get_argument(runtime_fixture),
    {ok, Bytes} = file:read_file(filename:join(Dir, "fixture.etf")),
    #{deployment := Deployment = #{actors := Actors}, binding := Binding,
        manifest := Manifest, selector := Selector} = binary_to_term(Bytes),
    {ok, _} = application:ensure_all_started(hls_fabric),
    ok = hls_node_binding:validate(Deployment),
    lists:foreach(fun(Actor = #{slot := Slot}) ->
        {{Selector, 255, 1}, <<Slot:32/little, 16#12345678:32/little>>} =
            hls_node_binding:encode_cast(Actor, {work, 16#12345678})
    end, Actors),
    Session = #{manifest => Manifest, resources => list_to_tuple(maps:get(<<"resources">>, Manifest))},
    Catalog = hls_shared_observation:bind(Binding, Session),
    4 = length(hls_debug_catalog:actors(Catalog)),
    {ok, Target} = hls_debug_catalog:actor(Catalog, {family, cells, [0, 0]}),
    {identity, {family, cells, [0, 0]}} = hls_debug:info(Target, identity),
    {observation, #{fingerprint := <<"isolated-runtime-fixture">>}} =
        hls_debug:info(Target, observation),
    ok = live_node(),
    absent_build_modules().

%% Missing actor source is deliberate: retained codecs must not reacquire its generated packers.
-spec absent_build_modules() -> ok.
absent_build_modules() ->
    [non_existing = code:which(Module) || Module <-
        [hls_source, hls_pack, hls_actor_interface, hls_service_contract, xls_parse,
         hls_build, hls_source_build, hls_scheduler_plan, hls_node_topology,
         hls_host_codec_plan, hls_shared_debug_catalog, xls_scheduler_debug,
         hls_actor_pid_fixture]],
    ok.

%% A production broker and virtual node serve one precompiled service through the existing wire model.
-spec live_node() -> ok.
live_node() ->
    [_Own, Host] = string:split(atom_to_list(node()), "@"),
    Name = list_to_atom("fabric_runtime_device@" ++ Host),
    {ok, Model} = hls_device_fixture:start(#{}),
    try
        #{brokers := Brokers} = hls_device_fixture:stats(Model),
        {ok, Node} = hls_fabric_sup:start_node(Name, Brokers,
            [#{name => registers, module => regsvc, endpoint => 1}], #{}),
        try
            #{registers := #{application := Actor, debug := Debug}} = hls_node:services(Node),
            Name = node(Actor),
            42 = regsvc:ping(Actor, 42),
            {ok, #{app_rx_frames := 1}} = hls_debug:get_counters(Debug),
            ok
        after
            ok = hls_fabric_sup:stop_node(Name)
        end
    after
        ok = hls_device_fixture:stop(Model)
    end.
