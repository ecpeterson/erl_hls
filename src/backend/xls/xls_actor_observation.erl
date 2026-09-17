-module(xls_actor_observation).
-moduledoc "Optional observations of committed register-backed actor state.".
-export([enabled/1, layout/1, bindings/2, wires/1, ports/1,
    scalar_name/1, family_name/1, declarations/1, proc_field/1,
    config_parameter/1, config_value/1, sample/1, spawn_argument/2]).

enabled(Options) ->
    case maps:get(direct_actor_debug, Options, false) of
        Flag when is_boolean(Flag) -> Flag;
        Other -> error({direct_actor_debug, Other})
    end.

%% The observation contains no payload or accumulator bits. Its reduction
%% metadata is contiguous on the compiler output; the query shell inserts the
%% common protocol's initialization and reserved mailbox fields.
layout(none) ->
    #{width => 25, fields => #{phase => #{offset => 0, width => 8},
        enter_pending => #{offset => 8, width => 1},
        failure => #{offset => 9, width => 16}}};
layout(Reduction) ->
    Sizes = xls_statem_reduction_ir:layout(Reduction),
    {Width, Fields} = lists:foldl(fun({Name, Size}, {Offset, Acc}) ->
        Bits = maps:get(Size, Sizes),
        {Offset + Bits, Acc#{Name => #{offset => 25 + Offset,
            width => Bits, observation_offset => 56 + Offset}}}
    end, {0, #{}}, [{status, status_bits}, {site, site_bits}, {key, key_bits},
        {remaining, remaining_bits}, {failure, failure_bits}]),
    (layout(none))#{width := 25 + Width,
        reduction => #{width => Width, fields => Fields}}.

%% Names come from the same normalized actor/family ordering as topology
%% emission. XLS lowers a channel array [height][width] to __x_y port suffixes.
bindings(Plan = #{actors := Actors, families := Families}, Specs) ->
    Placements = hls_scheduler_plan:placements(hls_scheduler_plan:normalize(Plan, Specs)),
    Logical = [{{actor, Id}, Module, ["_", scalar_name(I)]} ||
        {I, #{id := Id, module := Module}} <- lists:enumerate(0, Actors)] ++
        [{{family, Id, [X, Y]}, Module, ["_", family_name(I), "__",
            integer_to_list(X), "_", integer_to_list(Y)]} ||
            {I, #{id := Id, module := Module, shape := [Width, Height]}} <-
                lists:enumerate(0, Families),
            X <- lists:seq(0, Width - 1), Y <- lists:seq(0, Height - 1)],
    Direct = [Entry || Entry = {Id, _, _} <- Logical, not maps:is_key(Id, Placements)],
    Interfaces = hls_actor_interface:from_modules([Module || {_, Module, _} <- Direct]),
    [begin
        Interface = maps:get(Module, Interfaces),
        #{width := Width} = layout(maps:get(reductions, Interface, none)),
        #{id => Id, module => Module, index => I, port => iolist_to_binary(Port), width => Width}
    end || {I, {Id, Module, Port}} <- lists:enumerate(0, Direct)].

wires(Bindings) ->
    [["    wire [", integer_to_list(Width - 1), ":0] ", wire_name(I), ";\n",
        "    wire ", wire_name(I), "_vld;\n"] ||
        #{index := I, width := Width} <- Bindings].

ports(Bindings) ->
    [[",\n        .", Port, "(", wire_name(I), "),\n",
        "        .", Port, "_vld(", wire_name(I), "_vld),\n",
        "        .", Port, "_rdy(1'b1)"] || #{index := I, port := Port} <- Bindings].

wire_name(Index) -> ["direct_actor_", integer_to_list(Index), "_debug"].
scalar_name(Index) -> ["actor_", integer_to_list(Index), "_debug_out"].
family_name(Index) -> ["family_", integer_to_list(Index), "_debug_out"].

declarations(Spec) ->
    Reduction = maps:get(reductions, Spec, none),
    #{width := Width} = Layout = layout(Reduction),
    Prefix = case Layout of
        #{reduction := #{fields := Fields}} ->
            [["    (machine.reduction.", atom_to_list(Name), " as bits[",
                integer_to_list(maps:get(width, maps:get(Name, Fields))), "]) ++\n"] ||
                Name <- [failure, remaining, key, site, status]];
        _ -> []
    end,
    optional(Spec, ["pub type ActorObservation = bits[", integer_to_list(Width), "];\n\n",
        "fn actor_observation(machine: Machine) -> ActorObservation {\n", Prefix,
        "    machine.failure ++ machine.enter_pending ++ (machine.phase as u8)\n",
        "}\n\n"]).

proc_field(Options) -> optional(Options,
    "  actor_debug_out: chan<ActorObservation> out;\n").
config_parameter(Options) -> optional(Options,
    ",\n         actor_debug_out: chan<ActorObservation> out").
config_value(Options) -> optional(Options, ", actor_debug_out").
spawn_argument(Options, Channel) -> optional(Options, [", ", Channel]).

sample(Options) -> optional(Options, """

    // Publish the committed state entering this step, before any current
    // receive or egress can stall. The shell always accepts and retains this
    // diagnostic output independently of host query backpressure.
    let _observation = send(join(), actor_debug_out, actor_observation(machine));

""").

optional(Options, Value) -> case enabled(Options) of true -> Value; false -> [] end.
