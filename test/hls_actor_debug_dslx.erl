-module(hls_actor_debug_dslx).
-export([write/1, fixture/1, artifacts/1, projection/1]).

fixture(small) ->
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        ingresses => [{commands, {rectangle, [8, 1]}, [
            {configure, [configure], [{family, cell, {embed, [1, 1], [0, 0]}}]}]}],
        families => #{cell => #{module => hls_actor_debug_fixture, shape => [8, 1]}},
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{cell, out}, [{external, reports}]}],
        startup => [{{cell, I, 0}, [{configure, I}]} || I <- lists:seq(0, 7)]}),
    {Plan, #{cells => #{members => [{family, cell}],
        state_storage => block_ram, mailbox_storage => block_ram}}};
fixture(phi) ->
    {hls_topology:from_module(phi_decoder_profile_topology),
        maps:get(scheduler_groups, phi_decoder_profile_topology_dslx:profile())}.

artifacts(small) ->
    #{hls_actor_debug_fixture => xls_parse:to_xls("test/hls_actor_debug_fixture.erl")};
artifacts(phi) ->
    {Plan, _Specs} = fixture(phi),
    Requirements = xls_topology_dslx:artifact_requirements(Plan,
        phi_decoder_profile_topology_dslx:profile()),
    maps:from_list([{Module, xls_parse:to_xls(
        "src/examples/phi_decoder/" ++ atom_to_list(Module) ++ ".erl",
        maps:get(Module, Requirements, #{shared_service => ordinary}))}
        || Module <- maps:keys(Requirements)]).

projection(Kind) ->
    {Plan, Specs} = fixture(Kind),
    xls_scheduler_debug:projection(Plan, Specs, artifacts(Kind)).

write(Stage) ->
    {Plan, Specs} = fixture(small),
    Small = #{hls_actor_debug_fixture := Actor} = artifacts(small),
    ok = write(Stage, "hls_actor_debug_fixture.x", Actor),
    ok = write(Stage, "actor_debug.x", xls_topology_dslx:emit(Plan,
        #{name => actor_debug, channel_depth => 1, actor_egress_depth => burst,
            scheduler_groups => Specs})),
    Bindings = xls_scheduler_ram_v:bindings(hls_scheduler_plan:normalize(Plan, Specs)),
    {ok, Template} = file:read_file("test/rtl/xls_init_topology.template.v"),
    Wrapper = lists:foldl(fun({Pattern, Replacement}, Text) ->
        binary:replace(Text, Pattern, iolist_to_binary(Replacement), [global])
    end, Template, [{<<"@NAME@">>, "actor_debug"},
        {<<"@WIRES@">>, xls_scheduler_ram_v:wires(Bindings)},
        {<<"@PORTS@">>, xls_scheduler_ram_v:application_ports(Bindings)},
        {<<"@RAMS@">>, xls_scheduler_ram_v:instances(Bindings, "clk")}]),
    ok = write(Stage, "actor_debug_wrapper.v", Wrapper),
    ok = write(Stage, "small-actors.json",
        json:encode(xls_scheduler_debug:projection(Plan, Specs, Small))),
    write(Stage, "phi-actors.json", json:encode(projection(phi))).

write(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
