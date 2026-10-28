-module(hls_indexed_debug_dslx).
-moduledoc "Builds the production shared indexed backend for live debug-query witnesses.".
-export([fixture/0, write/1]).

-doc "Places one gather actor behind ordinary addressed ingress and a shared scheduler.".
-spec fixture() -> {hls_topology:plan(), hls_scheduler_plan:spec()}.
fixture() ->
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cell => #{module => hls_indexed_debug_fixture, shape => [1, 1]}},
        ingresses => [{commands, {rectangle, [1, 1]}, [
            {piece, [piece], [{family, cell, {embed, [1, 1], [0, 0]}}]}]}],
        externals => [{reports, out, [report]}], routes => [],
        route_relations => [{{cell, Port}, [{external, reports}]} || Port <- [out_a, out_b, out_c, out_d]], startup => []}),
    {Plan, #{cells => #{members => [{family, cell}], state_storage => block_ram,
        mailbox_storage => block_ram, gather_collection => true}}}.

-doc "Writes the exact topology, metadata-only projection and test-driven physical wrapper.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    {Plan, Groups} = fixture(),
    Options = #{name => actor_debug, channel_depth => 1, actor_egress_depth => burst,
        scheduler_groups => Groups, mailbox_debug => true},
    Requirements = xls_fabric_topology_dslx:artifact_requirements(Plan, Options),
    Artifacts = maps:map(fun(Module, Requirement) ->
        xls_scheduler_actor:to_artifact(filename:join("test", atom_to_list(Module) ++ ".erl"),
            maps:merge(Requirement, #{mailbox_debug => true}))
    end, Requirements),
    maps:foreach(fun(Module, Actor) ->
        ok = file:write_file(filename:join(Stage, atom_to_list(Module) ++ ".x"), xls_emitted:bytes(Actor))
    end, Artifacts),
    ok = file:write_file(filename:join(Stage, "actor_debug.x"), xls_fabric_topology_dslx:emit(Plan, Options)),
    Scheduler = #{groups := [Group]} = hls_scheduler_plan:normalize(Plan, Groups),
    [Binding] = Bindings = xls_scheduler_ram_v:bindings(Scheduler),
    %% The complete payload belongs only to the two masked physical rows and the transient loader request.
    Interface = hls_actor_interface:from_module(hls_indexed_debug_fixture),
    ProgressWidth = xls_statem_gather_codegen:progress_width(maps:get(gathers, Interface)),
    ProgressWidth = maps:get(gather_storage_width, Group),
    #{gather_members := 3, gather_element_bits := 8} = Binding,
    ActorText = xls_emitted:bytes(maps:get(hls_indexed_debug_fixture, Artifacts)),
    lists:foreach(fun(Name) ->
        {match, [Body]} = re:run(ActorText, ["struct ", Name, " \\{([^}]+)\\}"], [{capture, [1], binary}]),
        nomatch = binary:match(Body, <<"GatherValues">>),
        nomatch = binary:match(Body, <<"ActorState">>)
    end, ["SharedDispatchTicket", "SharedExecutorResult"]),
    Projection = xls_scheduler_debug:projection(Plan, Groups, Artifacts, Options),
    [#{<<"reduction">> := #{<<"fields">> := Fields}}] = maps:get(<<"banks">>, Projection),
    true = lists:all(fun(F) -> is_map_key(<<"live_offset">>, F) andalso not is_map_key(<<"offset">>, F) end,
        maps:values(Fields)),
    false = is_map_key(<<"values">>, Fields),
    ok = file:write_file(filename:join(Stage, "small-actors.json"), json:encode(Projection)),
    #{selector := Selector} = hls_actor_interface:schema(Interface, piece),
    {ok, Template} = file:read_file("test/rtl/hls_indexed_debug.template.v"),
    Wrapper = lists:foldl(fun({Pattern, Value}, Acc) ->
        binary:replace(Acc, Pattern, iolist_to_binary(Value), [global])
    end, Template, [{<<"@PIECE@">>, integer_to_list(Selector)},
        {<<"@WIRES@">>, [xls_scheduler_ram_v:wires(Bindings), xls_scheduler_observation:wires(Scheduler)]},
        {<<"@PORTS@">>, [xls_scheduler_ram_v:application_ports(Bindings), xls_scheduler_observation:ports(Scheduler)]},
        {<<"@RAMS@">>, xls_scheduler_ram_v:instances(Bindings, "clk")}]),
    file:write_file(filename:join(Stage, "actor_debug_wrapper.v"), Wrapper).
