-module(hls_actor_debug_dslx).
-export([write/1, write/2, write/3, fixture/1, artifacts/1, artifacts/2, projection/1]).

fixture(small) ->
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        ingresses => [{commands, {rectangle, [19, 1]}, [
            {configure, [configure], [{family, cell, {embed, [1, 1], [0, 0]}}]}]}],
        families => #{cell => #{module => hls_actor_debug_fixture, shape => [19, 1]}},
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{cell, out}, [{external, reports}]}],
        startup => [{{cell, I, 0}, [{configure, I}]} || I <- lists:seq(0, 18)]}),
    {Plan, #{cells => #{members => [{family, cell}],
        state_storage => block_ram, mailbox_storage => block_ram}}};
fixture(mailbox) ->
    Outputs = [work_a, work_b, advance] ++ [list_to_atom("blocked_" ++ integer_to_list(I)) || I <- lists:seq(0, 11)],
    Families = [producer, consumer],
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => maps:from_list([{F, #{module => hls_mailbox_debug_fixture, shape => [3, 1]}} || F <- Families]),
        ingresses => [{commands, {rectangle, [3, 1]}, [
            {configure, [configure], [{family, producer, {embed, [1, 1], [0, 0]}}]}]}],
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{F, Port}, case Port of
            work_a -> [{family, consumer, {translate, [0, 0], wrap}}];
            work_b -> [{family, consumer, {translate, [0, 0], wrap}}];
            advance -> [{family, consumer, {translate, [0, 0], wrap}}];
            _ -> [{external, reports}]
        end} || F <- Families, Port <- Outputs],
        startup => [{{F, I, 0}, [{configure, Role}]} || {F, Role} <- [{producer, 0}, {consumer, 1}], I <- lists:seq(0, 2)]}),
    {Plan, maps:from_list([{F, #{members => [{family, F}], state_storage => block_ram,
        mailbox_storage => block_ram}} || F <- Families])};
fixture(direct_reduction) ->
    {Plan, _Specs} = fixture(reduction),
    {Plan, #{}};
fixture(Kind) when Kind =:= reduction; Kind =:= aggregate ->
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cell => #{module => hls_reduction_failure_fixture, shape => [5, 1]}},
        ingresses => [{commands, {rectangle, [5, 1]}, [
            {configure, [configure], [{family, cell, {embed, [1, 1], [0, 0]}}]}]}],
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{cell, out}, [{external, reports}]} | [
            {{cell, Port}, [{family, cell, {translate, [Offset, 0], wrap}}]}
            || {Port, Offset} <- [{left, -1}, {middle, 0}, {right, 1}]]],
        startup => []}),
    {Plan, #{cells => #{members => [{family, cell}],
        state_storage => block_ram, mailbox_storage => block_ram}}};
fixture(phi) ->
    {hls_topology:from_module(phi_decoder_profile_topology),
        maps:get(scheduler_groups, phi_decoder_profile_topology_dslx:profile())}.

artifacts(Kind) -> artifacts(Kind, #{}).

artifacts(Kind, Options) ->
    {Directory, Requirements} = case Kind of
        small -> {"test", #{hls_actor_debug_fixture => #{}}};
        mailbox -> {"test", #{hls_mailbox_debug_fixture => #{}}};
        reduction -> {"test", #{hls_reduction_failure_fixture => #{}}};
        direct_reduction -> {"test", #{hls_reduction_failure_fixture => #{}}};
        aggregate -> {"test", #{hls_reduction_failure_fixture => #{shared_service => aggregate_only}}};
        phi ->
            {Plan, _} = fixture(phi),
            {"src/examples/phi_decoder", xls_topology_dslx:artifact_requirements(Plan,
                phi_decoder_profile_topology_dslx:profile())}
    end,
    maps:map(fun(Module, Requirement) ->
        xls_parse:to_xls(filename:join(Directory, atom_to_list(Module) ++ ".erl"),
            maps:merge(Requirement, Options))
    end, Requirements).

projection(Kind) ->
    {Plan, Specs} = fixture(Kind),
    xls_scheduler_debug:projection(Plan, Specs, artifacts(Kind)).

write(Stage) -> write(Stage, #{}).

write(Stage, Options) -> write(small, Stage, Options).

write(phi, Stage, Options) ->
    {Plan, Specs} = fixture(phi),
    ok = write_file(Stage, "phi_decoder_profile.json", json:encode(phi_decoder_profile:manifest(#{}))),
    Artifacts = artifacts(phi, Options),
    maps:foreach(fun(Module, Actor) -> ok = write_file(Stage, atom_to_list(Module) ++ ".x", Actor) end, Artifacts),
    ok = write_file(Stage, "phi_decoder_profile_topology.x", xls_topology_dslx:emit(Plan,
        maps:merge(phi_decoder_profile_topology_dslx:profile(), Options))),
    ok = write_file(Stage, "phi_decoder_profile_top.v", phi_decoder_profile_top_v:to_verilog(3, Options)),
    write_file(Stage, "phi-actors.json", json:encode(xls_scheduler_debug:projection(Plan, Specs, Artifacts, Options)));
write(Kind, Stage, Options0) ->
    Options = case Kind of
        aggregate -> Options0#{reduction_placements => #{cell => source_fragments}};
        _ -> Options0
    end,
    {Plan, Specs} = fixture(Kind),
    Small = artifacts(Kind, Options0),
    maps:foreach(fun(Module, Actor) -> ok = write_file(Stage, atom_to_list(Module) ++ ".x", Actor) end, Small),
    ok = write_file(Stage, "actor_debug.x", xls_topology_dslx:emit(Plan,
        maps:merge(#{name => actor_debug, channel_depth => 1, actor_egress_depth => burst,
            scheduler_groups => Specs}, Options))),
    Scheduler = hls_scheduler_plan:normalize(Plan, Specs),
    Bindings = xls_scheduler_ram_v:bindings(Scheduler),
    {DebugWires, DebugPorts} = case xls_scheduler_observation:enabled(Options) of
        false -> {[], []};
        true -> {xls_scheduler_observation:wires(Scheduler), xls_scheduler_observation:ports(Scheduler)}
    end,
    {ActorWires, ActorPorts} = case maps:get(direct_actor_debug, Options, false) of
        false -> {[], []};
        true ->
            Observations = xls_actor_observation:bindings(Plan, Specs),
            {xls_actor_observation:wires(Observations), xls_actor_observation:ports(Observations)}
    end,
    TemplateFile = case Kind of
        K when K =:= reduction; K =:= aggregate; K =:= direct_reduction ->
            "test/rtl/hls_reduction_debug.template.v";
        _ -> "test/rtl/xls_init_topology.template.v"
    end,
    {ok, Template} = file:read_file(TemplateFile),
    Configure = case Kind of
        C when C =:= reduction; C =:= aggregate; C =:= direct_reduction ->
            #{selector := Selector} = hls_actor_interface:schema(
                hls_actor_interface:from_module(hls_reduction_failure_fixture), configure),
            integer_to_list(Selector);
        _ -> []
    end,
    Wrapper = lists:foldl(fun({Pattern, Replacement}, Text) ->
        binary:replace(Text, Pattern, iolist_to_binary(Replacement), [global])
    end, Template, [{<<"@NAME@">>, "actor_debug"}, {<<"@CONFIGURE@">>, Configure},
        {<<"@WIRES@">>, [xls_scheduler_ram_v:wires(Bindings), DebugWires, ActorWires]},
        {<<"@PORTS@">>, [xls_scheduler_ram_v:application_ports(Bindings), DebugPorts, ActorPorts]},
        {<<"@RAMS@">>, xls_scheduler_ram_v:instances(Bindings, "clk")}]),
    ok = write_file(Stage, "actor_debug_wrapper.v", Wrapper),
    ok = write_file(Stage, "small-actors.json",
        json:encode(xls_scheduler_debug:projection(Plan, Specs, Small, Options))),
    write_file(Stage, "phi-actors.json", json:encode(projection(phi))).

write_file(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
