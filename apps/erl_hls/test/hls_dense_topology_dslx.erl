-module(hls_dense_topology_dslx).
-export([write/1]).

-doc "Writes generated DSLX and the matching oracle or wrapper files into the test stage.".
-spec write(atom() | binary() | [atom() | [any()] | char()]) -> 'ok'.
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
    %% Explicit actors and a family family exercise both startup packers.
    %% Loopback reports give exact actors a normal input alongside startup;
    %% the active handler consumes these reports without emitting again.
    Direct = hls_topology:normalize(#{version => 1,
        actors => #{first => hls_dense_statem_fixture, second => hls_dense_statem_fixture},
        families => #{}, ingresses => [], route_relations => [],
        externals => [{reports, out, [report]}],
        routes => [{{first, out}, queued, [{actor, first}, {external, reports}]},
                   {{second, out}, queued, [{actor, second}, {external, reports}]}],
        startup => [{first, [First]}, {second, [Second]}]}),
    Family = hls_topology:normalize(#{version => 1, actors => #{},
        ingresses => [{commands, {rectangle, [2, 1]}, [
            {configure, [configure], [{family, cell, {embed, [1, 1], [0, 0]}}]}
        ]}],
        families => #{cell => #{module => hls_dense_statem_fixture, shape => [2, 1]}},
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{cell, out}, [{external, reports}]}],
        startup => [{{cell, 0, 0}, [First]}, {{cell, 1, 0}, [Second]}]}),
    Base = #{channel_depth => 1, actor_egress_depth => burst},
    write(Stage, "dense_direct.x", xls_topology_dslx:emit(Direct, Base#{name => dense_direct})),
    write(Stage, "dense_family.x", xls_topology_dslx:emit(Family,
        Base#{name => dense_family})),
    {ok, Template} = file:read_file("test/rtl/xls_init_topology.template.v"),
    %% Startup drives both fixtures. Only the family family declares an ingress,
    %% which the wrapper holds idle.
    WithoutIngress0 = binary:replace(Template,
        <<"        ._commands_in('0), ._commands_in_vld(1'b0), ._commands_in_rdy(),\n">>, <<>>),
    WithoutIngress = binary:replace(WithoutIngress0, <<"    @NAME@ dut">>,
        <<"    __@NAME@__Top_0_next dut">>),
    [write(Stage, Name ++ "_wrapper.v", lists:foldl(fun({Pattern, Replacement}, Text) ->
        binary:replace(Text, Pattern, iolist_to_binary(Replacement), [global])
    end, case Name of
        "dense_direct" -> WithoutIngress;
        "dense_family" -> binary:replace(Template, <<"    @NAME@ dut">>,
            <<"    __@NAME@__Top_0_next dut">>)
    end, [{<<"@NAME@">>, Name},
        {<<"@WIRES@">>, ""},
        {<<"@PORTS@">>, ""},
        {<<"@RAMS@">>, ""}
    ])) || Name <- ["dense_direct", "dense_family"]],
    ok.

oracle(Message) ->
    {ok, Actor} = hls_statem:start_link(hls_dense_statem_fixture, [],
        [{mailbox_capacity, 2}, {outputs, #{out => self()}}]),
    try
        hls_statem:cast(Actor, Message),
        receive {'$gen_cast', Report} -> Report after 1000 -> error(no_report) end
    after hls_statem:stop(Actor) end.

write(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
