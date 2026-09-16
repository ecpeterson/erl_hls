-module(hls_dense_topology_dslx).
-export([write/1]).

write(Stage) ->
    write(Stage, "hls_dense_statem_fixture.x", xls_parse:to_xls("test/hls_dense_statem_fixture.erl")),
    Messages = [{configure, false, 7, -256}, {configure, true, 3, 255}],
    Reports = [oracle(Message) || Message <- Messages],
    write(Stage, "dense_expected.svh", [begin
        Width = hls_dense_statem_fixture:pack_width(report),
        Header = (((Width + 31) div 32) bsl 24) bor hls_dense_statem_fixture:pack_tag(report),
        Frame = (Header bsl 96) bor hls_codec:unsigned(hls_codec:align(hls_dense_statem_fixture:pack(Report), 32)),
        io_lib:format("localparam [127:0] EXPECTED_~B = 128'h~32.16.0b;~n", [Index, Frame])
    end || {Index, Report} <- lists:enumerate(Reports)]),
    [First, Second] = Messages,
    %% Explicit actors and a shared family exercise both startup packers.
    %% Loopback reports give exact actors a normal input alongside startup;
    %% the active handler consumes these reports without emitting again.
    Direct = hls_topology:normalize(#{version => 1,
        actors => #{first => hls_dense_statem_fixture, second => hls_dense_statem_fixture},
        families => #{}, ingresses => [], route_relations => [],
        externals => [{reports, out, [report]}],
        routes => [{{first, out}, queued, [{actor, first}, {external, reports}]},
                   {{second, out}, queued, [{actor, second}, {external, reports}]}],
        startup => [{first, [First]}, {second, [Second]}]}),
    Shared = hls_topology:normalize(#{version => 1, actors => #{},
        ingresses => [{commands, {rectangle, [2, 1]}, [
            {configure, [configure], [{family, cell, {embed, [1, 1], [0, 0]}}]}
        ]}],
        families => #{cell => #{module => hls_dense_statem_fixture, shape => [2, 1]}},
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{cell, out}, [{external, reports}]}],
        startup => [{{cell, 0, 0}, [First]}, {{cell, 1, 0}, [Second]}]}),
    Groups = #{cells => #{members => [{family, cell}],
        state_storage => block_ram, mailbox_storage => block_ram}},
    Base = #{channel_depth => 1, actor_egress_depth => burst},
    write(Stage, "dense_direct.x", xls_topology_dslx:emit(Direct, Base#{name => dense_direct})),
    write(Stage, "dense_shared.x", xls_topology_dslx:emit(Shared,
        Base#{name => dense_shared, scheduler_groups => Groups})),
    Bindings = xls_scheduler_ram_v:bindings(hls_scheduler_plan:normalize(Shared, Groups)),
    {ok, Template} = file:read_file("test/rtl/xls_init_topology.template.v"),
    %% Startup drives both fixtures. Only the shared family declares an ingress,
    %% which the wrapper holds idle.
    WithoutIngress0 = binary:replace(Template,
        <<"        ._commands_in('0), ._commands_in_vld(1'b0), ._commands_in_rdy(),\n">>, <<>>),
    WithoutIngress = binary:replace(WithoutIngress0, <<"    @NAME@ dut">>,
        <<"    __@NAME@__Top_0_next dut">>),
    [write(Stage, Name ++ "_wrapper.v", lists:foldl(fun({Pattern, Replacement}, Text) ->
        binary:replace(Text, Pattern, iolist_to_binary(Replacement), [global])
    end, case Name of
        "dense_direct" -> WithoutIngress;
        "dense_shared" -> binary:replace(Template, <<"    @NAME@ dut">>,
            <<"    __@NAME@__Top_0_next dut">>)
    end, [{<<"@NAME@">>, Name},
        {<<"@WIRES@">>, xls_scheduler_ram_v:wires(Rams)},
        {<<"@PORTS@">>, xls_scheduler_ram_v:application_ports(Rams)},
        {<<"@RAMS@">>, xls_scheduler_ram_v:instances(Rams, "clk")}
    ])) || {Name, Rams} <- [{"dense_direct", []}, {"dense_shared", Bindings}]],
    ok.

oracle(Message) ->
    {ok, Actor} = hls_statem:start_link(hls_dense_statem_fixture, [],
        [{mailbox_capacity, 2}, {outputs, #{out => self()}}]),
    try
        hls_statem:cast(Actor, Message),
        receive {'$gen_cast', Report} -> Report after 1000 -> error(no_report) end
    after hls_statem:stop(Actor) end.

write(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
