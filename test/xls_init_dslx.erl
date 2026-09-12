-module(xls_init_dslx).
-export([write/1, statem_oracle/1]).

statem_oracle(Offset) ->
    {ok, Actor} = hls_statem:start_link(xls_init_statem_fixture, [],
        [{mailbox_capacity, 2}, {outputs, #{out => self()}}]),
    try
        hls_statem:cast(Actor, {configure, Offset}),
        receive {'$gen_cast', Report} -> Report
        after 1000 -> error(initialization_timeout)
        end
    after
        hls_statem:stop(Actor)
    end.

write(Stage) ->
    lists:foreach(fun({Kind, Module}) ->
        Path = "test/" ++ atom_to_list(Module) ++ ".erl",
        X = xls_parse:to_xls(Path),
        write(Stage, atom_to_list(Module) ++ ".x", X),
        write(Stage, "init_" ++ atom_to_list(Kind) ++ ".x",
            [X, semantics(Kind)]),
        {ok, Source} = file:read_file(Path),
        %% The BEAM oracle and XLS must both reject this refutable match,
        %% even though its bound result does not contribute to the state.
        BadSource = binary:replace(Source,
            <<"Expected = hls_nums:wrap(hls_nums:u32(), 41)">>,
            <<"Expected = hls_nums:wrap(hls_nums:u32(), 40)">>),
        BadPath = filename:join(Stage, "bad_" ++ atom_to_list(Kind) ++ ".erl"),
        ok = file:write_file(BadPath, BadSource),
        {ok, Module, Beam} = compile:file(BadPath, [binary]),
        {module, Module} = code:load_binary(Module, BadPath, Beam),
        try Module:init([]) of
            Value -> error({initializer_should_fail, Kind, Value})
        catch
            error:{badmatch, 41} -> ok
        after
            true = code:delete(Module),
            _ = code:purge(Module)
        end,
        write(Stage, "bad_" ++ atom_to_list(Kind) ++ ".x",
            [xls_parse:to_xls(BadPath), semantics(Kind)])
    end, [{gs, xls_init_gs_fixture}, {statem, xls_init_statem_fixture}]),
    %% Reload the compiled fixture after the failing-oracle variants.
    {module, xls_init_statem_fixture} = code:load_file(xls_init_statem_fixture),
    Reports = [statem_oracle(Offset) || Offset <- [8, 16]],
    write(Stage, "init_expected.svh", [
        io_lib:format("localparam [31:0] EXPECTED_~p = 32'd~p;\n", [I, Value])
        || {I, {report, Value, 0, 7}} <- lists:enumerate(Reports)]),
    Plan = topology(),
    Base = #{name => init_direct, channel_depth => 1, actor_egress_depth => burst},
    Groups = #{cells => #{members => [{family, cell}],
        state_storage => block_ram, mailbox_storage => block_ram}},
    write(Stage, "init_direct.x", xls_topology_dslx:emit(Plan, Base)),
    write(Stage, "init_shared.x", xls_topology_dslx:emit(Plan,
        Base#{name => init_shared, scheduler_groups => Groups})),
    Bindings = xls_scheduler_ram_v:bindings(hls_scheduler_plan:normalize(Plan, Groups)),
    {ok, Template} = file:read_file("test/rtl/xls_init_topology.template.v"),
    lists:foreach(fun({Name, Rams}) ->
        Wrapper = lists:foldl(fun({Pattern, Replacement}, Text) ->
            binary:replace(Text, Pattern, iolist_to_binary(Replacement), [global])
        end, Template, [
            {<<"@NAME@">>, Name},
            {<<"@WIRES@">>, xls_scheduler_ram_v:wires(Rams)},
            {<<"@PORTS@">>, xls_scheduler_ram_v:application_ports(Rams)},
            {<<"@RAMS@">>, xls_scheduler_ram_v:instances(Rams, "clk")}
        ]),
        write(Stage, Name ++ "_wrapper.v", Wrapper)
    end, [{"init_direct", []}, {"init_shared", Bindings}]).

topology() ->
    hls_topology:normalize(#{
        version => 1, actors => #{},
        ingresses => [{commands, {rectangle, [2, 1]}, [
            {configure, [configure], [{family, cell, {embed, [1, 1], [0, 0]}}]}
        ]}],
        families => #{cell => #{module => xls_init_statem_fixture, shape => [2, 1]}},
        externals => [{reports, out, [report]}],
        routes => [],
        route_relations => [{{cell, out}, [{external, reports}]}],
        startup => [{{cell, 0, 0}, [{configure, 8}]},
                    {{cell, 1, 0}, [{configure, 16}]}]
    }).

semantics(gs) ->
    "\n#[test]\nfn initialized_state() {\n"
    "  assert_eq(initial_state(), Ledger {value: u32:42, default: u32:0});\n"
    "}\n"
    "pub proc FrameTop {\n"
    "  config(request: chan<axis::Frame> in, report: chan<axis::Frame> out) {\n"
    "    spawn Service(request, report); ()\n"
    "  }\n  init { () }\n  next(state: ()) { state }\n}\n";
semantics(statem) ->
    "\n#[test]\nfn initialized_machine() {\n"
    "  let m = initial_machine();\n"
    "  assert_eq(m.phase, Phase::BOOT);\n"
    "  assert_eq(m.entered_from, Phase::BOOT);\n"
    "  assert_eq(m.data, Cell {value: u32:42, default: u32:0});\n"
    "  assert_eq(m.enter_pending, u1:1);\n"
    "  assert_eq(m.failure, hls_failure::NONE);\n"
    "  assert_eq(initial_shared_machine(), shared_machine(m));\n"
    "}\n".

write(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
