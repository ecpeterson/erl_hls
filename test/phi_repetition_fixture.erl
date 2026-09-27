-module(phi_repetition_fixture).
-moduledoc "Prepares a complete line workload and its independent BEAM event witness.".
-export([write/2, oracle/2]).

-doc "Writes the generated topology, three actor modules and RAM shell into an existing stage.".
-spec write(file:filename(), pos_integer()) -> ok.
write(Stage, N) ->
    Plan = hls_topology:normalize(phi_repetition_topology:topology(N)),
    Profile = #{scheduler_groups := Groups} = phi_repetition_topology:profile(N),
    maps:foreach(fun(Module, Options) ->
        Source = xls_parse:to_xls("src/examples/phi_decoder/" ++ atom_to_list(Module) ++ ".erl", Options),
        save(Stage, atom_to_list(Module) ++ ".x", Source)
    end, xls_topology_dslx:artifact_requirements(Plan, Profile)),
    save(Stage, "phi_repetition_topology.x", xls_topology_dslx:emit(Plan, Profile)),
    Bindings = xls_scheduler_ram_v:bindings(hls_scheduler_plan:normalize(Plan, Groups)),
    save(Stage, "phi_repetition_top.v", [
        "module phi_repetition_top(input wire aclk, input wire aresetn,\n",
        "output wire [127:0] decoder_event, output wire decoder_event_valid,\n",
        "input wire decoder_event_ready,\n",
        %% Router request: two-bit target selector, four u16 bounds, Frame.
        "input wire [193:0] control, input wire control_valid, output wire control_ready,\n",
        "output wire [127:0] measurement, output wire measurement_valid,\n",
        "input wire measurement_ready);\n",
        xls_scheduler_ram_v:wires(Bindings),
        "__phi_repetition_topology__Top_0_next application(\n",
        ".clk(aclk), .reset(!aresetn),\n",
        "._control_router_in(control), ._control_router_in_vld(control_valid),\n",
        "._control_router_in_rdy(control_ready),\n",
        "._decoder_events_out(decoder_event),\n",
        "._decoder_events_out_vld(decoder_event_valid),\n",
        "._decoder_events_out_rdy(decoder_event_ready),\n",
        "._data_measurements_out(measurement), ._data_measurements_out_vld(measurement_valid),\n",
        "._data_measurements_out_rdy(measurement_ready)",
        xls_scheduler_ram_v:application_ports(Bindings), ");\n",
        xls_scheduler_ram_v:instances(Bindings, "aclk"), "endmodule\n"
    ]).

-doc "Runs the actual noise and phi actors through step 32 and saves per-source events.".
-spec oracle(file:filename(), pos_integer()) -> ok.
oracle(Stage, N) ->
    Plan = #{families := Families, startup := Startup} =
        hls_topology:normalize(phi_repetition_topology:topology(N)),
    Owner = self(),
    Sink = spawn_link(fun() -> forward(Owner) end),
    Actors = maps:from_list([begin
        {ok, Pid} = Module:start_link(),
        {{Family, X, 0}, {Module, Pid}}
    end || #{id := Family, module := Module} <- Families, X <- lists:seq(0,N-1)]),
    try
        lists:foreach(fun(#{target := Id, messages := Messages}) ->
            {_, Pid} = maps:get(Id, Actors),
            [hls_statem:cast(Pid, Message) || Message <- Messages]
        end, Startup),
        %% Data must be configured before checks issue queries; phi goes last.
        lists:foreach(fun(Family) ->
            lists:foreach(fun(X) ->
                {Module, Pid} = maps:get({Family, X, 0}, Actors),
                Outputs = maps:from_list([{Port, case Target of
                    {actor, Id} -> element(2,maps:get(Id,Actors));
                    {external, _} -> Sink
                end} || #{source := {_, Port}, recipients := [Target]} <-
                    hls_topology:routes_for_instance(Plan,Family,[X,0])]),
                ok = Module:connect(Pid,Outputs)
            end,lists:seq(0,N-1))
        end,[data,syndrome,phi]),
        Events = collect(33*N,[],erlang:monotonic_time(millisecond)+30000),
        save(Stage,"oracle.json",json:encode(lists:reverse(Events)))
    after
        maps:foreach(fun(_,{_,Pid}) -> unlink(Pid),exit(Pid,kill) end,Actors),
        unlink(Sink), exit(Sink,kill)
    end.

%% Forward public output terms, retaining their causal per-sender order.
-spec forward(pid()) -> no_return().
forward(Owner) ->
    receive {'$gen_cast', Event} -> Owner ! {event,Event}, forward(Owner) end.

%% Finish only after every actor has emitted its step-32 status.
-spec collect(non_neg_integer(), [list()], integer()) -> [list()].
collect(0, Events, _) -> Events;
collect(Remaining, Events, Deadline) ->
    Timeout = max(0,Deadline-erlang:monotonic_time(millisecond)),
    receive
        {event,{Kind,Step,X,Y,Value}} when Step =< 32,
            (Kind =:= phi_status orelse Kind =:= phi_correction) ->
            Next = case Kind of phi_status -> Remaining-1; phi_correction -> Remaining end,
            collect(Next,[[0,X,Y,Step,Kind,Value]|Events],Deadline);
        {event,_} -> collect(Remaining,Events,Deadline)
    after Timeout -> error({repetition_oracle_timeout,Remaining})
    end.

%% Fail before compilation if the artifact cannot be written completely.
-spec save(file:filename(), string(), iodata()) -> ok.
save(Stage,Name,Contents) -> ok = file:write_file(filename:join(Stage,Name),Contents).
