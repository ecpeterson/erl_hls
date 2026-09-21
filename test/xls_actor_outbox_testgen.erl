-module(xls_actor_outbox_testgen).
-moduledoc "Direct and shared references with two independently stalled actor outputs.".
-export([write/1]).

-doc "Writes both placements, production RAM wrappers and expected BEAM report values.".
-spec write(file:filename()) -> ok.
write(Stage) ->
    Actor = xls_parse:to_xls("test/xls_actor_outbox_fixture.erl", #{mailbox_debug => true}),
    save(Stage, "xls_actor_outbox_fixture.x", Actor),
    Plan = hls_topology:normalize(#{version => 1, actors => #{},
        families => #{cell => #{module => xls_actor_outbox_fixture, shape => [2, 1]}},
        ingresses => [], externals => [{reports, out, [report]}], routes => [], startup => [],
        route_relations => [{{cell, Port}, [{external, reports}]} || Port <- [first, second, third]]}),
    Groups = #{counters => #{members => [{family, cell}], state_storage => block_ram,
        mailbox_storage => block_ram}},
    Rams = xls_scheduler_ram_v:bindings(hls_scheduler_plan:normalize(Plan, Groups)),
    {ok, Template} = file:read_file("test/rtl/xls_actor_outbox.template.v"),
    lists:foreach(fun(Kind) ->
        Name = "outbox_" ++ atom_to_list(Kind),
        save(Stage, Name ++ ".x", topology(Kind)),
        Bindings = case Kind of direct -> []; shared -> Rams end,
        Wrapper = lists:foldl(fun({From, To}, Text) ->
            binary:replace(Text, From, iolist_to_binary(To), [global])
        end, Template, [{<<"@NAME@">>, Name},
            {<<"@WIRES@">>, xls_scheduler_ram_v:wires(Bindings)},
            {<<"@PORTS@">>, xls_scheduler_ram_v:application_ports(Bindings)},
            {<<"@RAMS@">>, xls_scheduler_ram_v:instances(Bindings, "clk")},
            {<<"@DEBUG_ASSIGN@">>, case Kind of direct -> "assign observation=0; assign observation_valid=0;"; shared -> [] end},
            {<<"@DEBUG@">>, case Kind of direct -> [];
                shared -> ", ._observation(observation), ._observation_vld(observation_valid), ._observation_rdy(1'b1)" end}]),
        save(Stage, Name ++ "_wrapper.v", Wrapper)
    end, [direct, shared]),
    {ok, Pid} = hls_statem:start_link(xls_actor_outbox_fixture, [], [{mailbox_capacity, 2}, {outputs, #{first => self(), second => self(), third => self()}}]),
    try
        Values = [begin
            hls_statem:cast(Pid, {add, 1}),
            [receive {'$gen_cast', {report, N, Part}} -> N
             after 1000 -> error({missing_report, N, Part}) end || Part <- [0, 1, 2]],
            N
        end || N <- lists:seq(1, 24)],
        save(Stage, "expected.hex", [io_lib:format("~8.16.0b~n", [V]) || V <- Values])
    after hls_statem:stop(Pid) end.

%% Identical public command/report ports isolate scheduling from the environment.
-spec topology(direct | shared) -> iolist().
topology(Kind) ->
    Header = "import axis;\nimport mailbox;\nimport xls_actor_outbox_fixture;\n",
    Basic = ["proc Input<SLOT: u32> {\n",
        " frames: chan<axis::Frame> in; requests: chan<xls_actor_outbox_fixture::ScheduledRequest> out;\n",
        " config(frames: chan<axis::Frame> in, requests: chan<xls_actor_outbox_fixture::ScheduledRequest> out) { (frames, requests) }\n",
        " init { () } next(state: ()) { let (tok, frame) = recv(join(), frames);\n",
        " let _sent = send(tok, requests, xls_actor_outbox_fixture::ScheduledRequest {slot: SLOT, frame, credit: false}); state }\n}\n",
        "proc Output {\n effects: chan<xls_actor_outbox_fixture::Egress> in; frames: chan<axis::Frame> out;\n",
        " config(effects: chan<xls_actor_outbox_fixture::Egress> in, frames: chan<axis::Frame> out) { (effects, frames) }\n",
        " init { () } next(state: ()) { let (tok, effect) = recv(join(), effects); let _sent = send(tok, frames, effect.frame); state }\n}\n",
        "proc Admission {\n credit: chan<u1> in; input: chan<axis::Frame> in; output: chan<axis::Frame> out;\n",
        " config(credit: chan<u1> in, input: chan<axis::Frame> in, output: chan<axis::Frame> out) {(credit,input,output)}\n",
        " init { () } next(state: ()) { let(tok,_) = recv(join(),credit); let(tok,frame)=recv(tok,input); let _sent=send(tok,output,frame); state }\n}\n"],
    Extra = case Kind of direct -> []; shared -> xls_actor_outbox_dslx:emit(xls_actor_outbox_fixture) end,
    Rams = case Kind of direct -> []; shared -> xls_scheduler_ram_dslx:parameters("scheduler_0_", "xls_actor_outbox_fixture::") end,
    Debug = case Kind of direct -> []; shared -> ["observation: chan<u24[2]> out"] end,
    Args = ["command0: chan<axis::Frame> in", "command1: chan<axis::Frame> in",
        "report0: chan<axis::Frame> out", "report1: chan<axis::Frame> out"] ++ Rams ++ Debug,
    [Header, Basic, Extra, "pub proc Top { config(", lists:join(", ", Args), ") {\n",
        " let(ep,ec)=chan<xls_actor_outbox_fixture::Egress,u32:0>[u32:2](\"effects\");\n",
        " spawn Output(ec[u32:0],report0); spawn Output(ec[u32:1],report1);\n",
        wiring(Kind), " () } init { () } next(state: ()) {state} }\n"].

%% Dedicated return producers keep credits independent of mailbox admission.
-spec wiring(direct | shared) -> iolist().
wiring(shared) ->
    [" let(rp,rc)=chan<xls_actor_outbox_fixture::ScheduledRequest,u32:1>[u32:4](\"requests\");\n",
     " let(sp,sc)=chan<xls_actor_outbox_fixture::ScheduledRequest,u32:1>(\"startup\");\n",
     " let(bp,bc)=chan<xls_actor_outbox_fixture::ScheduledEffects,u32:1>(\"batches\");\n",
     " spawn Input<u32:0>(command0,rp[u32:0]); spawn Input<u32:1>(command1,rp[u32:1]);\n",
     " spawn xls_actor_outbox_fixture::SharedService<u32:2,u32:4,u32:0,u32:0,true>(rc,sc,bp,",
     lists:join(",", xls_scheduler_ram_dslx:names("scheduler_0_")), ",observation);\n",
     " let(cp,cc)=chan<xls_actor_outbox_fixture::ScheduledRequest,u32:0>[u32:2](\"credits\");\n",
     " spawn mailbox::RequestRelay(cc[u32:0],rp[u32:2]); spawn mailbox::RequestRelay(cc[u32:1],rp[u32:3]);\n",
     " spawn ", xls_actor_outbox_dslx:name(xls_actor_outbox_fixture), "<u32:2>(bc,ep,cp);\n"];
wiring(direct) ->
    [" let(rp,rc)=chan<axis::Frame,u32:1>[u32:2](\"requests\");\n",
     " let(ap,ac)=chan<u1,u32:1>[u32:2](\"admissions\");\n",
     " spawn Admission(ac[u32:0],command0,rp[u32:0]); spawn Admission(ac[u32:1],command1,rp[u32:1]);\n",
     " spawn xls_actor_outbox_fixture::Service(rc[u32:0],ep[u32:0],ap[u32:0]);\n",
     " spawn xls_actor_outbox_fixture::Service(rc[u32:1],ep[u32:1],ap[u32:1]);\n"].

%% Stage every artifact with its fixture.
-spec save(file:filename(), file:filename(), iodata()) -> ok.
save(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
