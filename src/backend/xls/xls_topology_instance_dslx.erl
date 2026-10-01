%%%% A materialized topology graph with independent placement decisions.
-module(xls_topology_instance_dslx).
-moduledoc false.
-export([artifact_requirements/2, emit/2]).

artifact_requirements(Plan, Profile) ->
    maps:get(artifact_requirements, lower(Plan, Profile)).

emit(Plan, Profile) ->
    render(lower(Plan, Profile)).

%% Resolves validated logical actors and routes into a renderable physical graph.
-spec lower(map(),map()) -> map().
lower(Plan, Profile0) ->
    Profile = #{direct_actor_debug := ActorDebug} = xls_topology_profile:normalize(Profile0),
    xls_topology_graph:check_lanes(lanes, maps:get(routes, Plan), Plan),
    xls_topology_graph:check_lanes(lane_relations, maps:get(route_relations, Plan), Plan),
    {Materialized, Origins} = materialize(Plan),
    Base = xls_topology_graph:lower(Materialized, Profile),
    Startup = maps:from_list([{Id, Frames} || #{target := Id, frames := Frames}
        <- maps:get(startup, Base)]),
    Actors = [place_actor(Actor, maps:get(maps:get(id, Actor), Origins),
        Startup) || Actor <- maps:get(actors, Base)],
    ActorIndex = maps:from_list([{maps:get(id, Actor), Actor} || Actor <- Actors]),
    Direct = [Actor || Actor = #{placement := direct} <- Actors],
    Routes = maps:get(routes, Base),
    lists:foreach(fun validate_delivery/1, Routes),
    Ingresses = ingress_units(Plan, ActorIndex),
    Routed = [{maps:get(unit, maps:get(Id, ActorIndex)), Recipient}
        || #{source := {Id, _}, recipients := Recipients} <- Routes,
           Recipient <- Recipients],
    Incoming = [{Key, {actor, Id}} || #{unit := Key, bindings := Bindings} <- Ingresses,
        Id <- maps:keys(Bindings)],
    Lanes0 = lists:usort(Routed ++ Incoming),
    Lanes = [lane(I, Source, Recipient, ActorIndex) ||
        {I, {Source, Recipient}} <- lists:enumerate(0, Lanes0)],
    Direct1 = [unit_routes(Unit, Routes, ActorIndex, Lanes) || Unit <- Direct],
    Units = Direct1 ++ [unit_routes(Unit, Routes, ActorIndex, Lanes) || Unit <- Ingresses],
    Requirements = maps:from_list([{Module, #{direct_actor_debug => ActorDebug}} || #{module := Module} <- Actors]),
    Base#{actors := Actors, direct => Direct1, units => Units, lanes := Lanes,
        actor_index => ActorIndex, semantic_plan => Plan, ingresses => Ingresses,
        artifact_requirements => flag_modules(Requirements, Direct1, direct_actor_debug, ActorDebug)}.

materialize(Plan = #{actors := Exact, families := Families,
        routes := ExactRoutes}) ->
    ExactOrigins = [{Id, #{logical => {actor, Id},
        debug => xls_actor_observation:scalar_name(I)}} ||
        {I, #{id := Id}} <- lists:enumerate(0, Exact)],
    FamilyEntries = lists:append([family_entries(I, Family) ||
        {I, Family} <- lists:enumerate(0, Families)]),
    Expanded = Exact ++ [Actor || {Actor, _} <- FamilyEntries],
    Origins = maps:from_list(ExactOrigins ++ [{maps:get(id, Actor), Origin}
        || {Actor, Origin} <- FamilyEntries]),
    Relations = lists:append([hls_topology:routes_for_instance(Plan, Id, [X, Y]) ||
        #{id := Id, shape := [W, H]} <- Families,
        X <- lists:seq(0, W - 1), Y <- lists:seq(0, H - 1)]),
    Routes = ExactRoutes ++ Relations,
    {Plan#{actors := Expanded, families := [], ingresses := [], routes := Routes,
        route_relations := [], lane_relations := [], lanes := xls_topology_graph:lanes(Routes)}, Origins}.

ingress_units(#{families := Families, ingresses := Ingresses}, Actors) ->
    Interfaces = maps:from_list([{Module, Interface} ||
        #{module := Module, interface := Interface} <- maps:values(Actors)]),
    FamilyIndex = maps:from_list([{Id, Family#{interface => maps:get(Module, Interfaces)}}
        || Family = #{id := Id, module := Module} <- Families]),
    [Ingress#{kind => ingress, unit => {ingress, I}, bindings => maps:from_list(
        lists:append([ingress_bindings(Recipient, FamilyIndex)
            || Recipient <- Recipients]))} ||
        Ingress = #{index := I, recipients := Recipients} <-
            xls_topology_ingress:lower(Ingresses, #{actors => Actors, families => FamilyIndex})].

ingress_bindings(#{actor := Id, at := Point, targets := Targets}, _) ->
    [{Id, #{point => Point, targets => Targets}}];
ingress_bindings(#{family := Id, scale := [SX, SY], offset := [OX, OY],
        targets := Targets}, Families) ->
    #{shape := [W, H]} = maps:get(Id, Families),
    [{{Id, X, Y}, #{point => [OX + SX * X, OY + SY * Y], targets => Targets}}
        || X <- lists:seq(0, W - 1), Y <- lists:seq(0, H - 1)].

family_entries(I, Family = #{id := Id, shape := [W, H]}) ->
    [{maps:without([shape, instance_count], Family#{id := {Id, X, Y}}),
        #{logical => {family, Id, [X, Y]},
            debug => [xls_actor_observation:family_name(I), "[u32:", n(X),
                "][u32:", n(Y), "]"]}}
        || X <- lists:seq(0, W - 1), Y <- lists:seq(0, H - 1)];
family_entries(_, #{id := Id, shape := Shape}) ->
    error({unsupported_instance_family_shape, Id, Shape}).
%% Attaches generated channel names and storage placement to one logical actor.
-spec place_actor(map(),map(),map()) -> map().
place_actor(Actor = #{id := Id, index := Index}, Origin, Startup) ->
    maps:merge(Actor#{startup => maps:get(Id, Startup, []), kind => direct,
        placement => direct, unit => {direct, Index}}, Origin).


flag_modules(Requirements, _, _, false) -> Requirements;
flag_modules(Requirements, Units, Flag, true) ->
    lists:foldl(fun(#{module := Module}, Acc) ->
        Acc#{Module := (maps:get(Module, Acc))#{Flag => true}}
    end, Requirements, Units).

validate_delivery(#{delivery := direct, recipients := [_]}) -> ok;
validate_delivery(#{delivery := queued, recipients := [_, _ | _]}) -> ok;
validate_delivery(#{source := Source, delivery := Delivery, recipients := Recipients}) ->
    error({unsupported_dslx_route_delivery, Source, Delivery, length(Recipients)}).

%% Describes a source-to-recipient channel and its message representation.
-spec lane(integer(),term(),{'actor',term()} | {'external',term()},map()) -> map().
lane(I, Source, {external, Id} = Recipient, _) ->
    #{index => I, source => Source, recipient => Recipient,
        destination => {external, Id}, type => "axis::Frame"};
lane(I, Source, {actor, Id} = Recipient, ActorIndex) ->
    Actor = #{unit := Destination} = maps:get(Id, ActorIndex),
    Type = "axis::Frame",
    #{index => I, source => Source, recipient => Recipient,
        destination => Destination, type => Type, target => Actor}.

unit_routes(Unit = #{unit := Key}, Routes, Actors, Lanes) ->
    Unit#{routes => [Route || Route = #{source := {Id, _}} <- Routes,
        maps:get(unit, maps:get(Id, Actors)) =:= Key],
        outbound => [Lane || Lane = #{source := Source} <- Lanes, Source =:= Key],
        inbound => [Lane || Lane = #{destination := Destination} <- Lanes,
            Destination =:= Key]}.

%% Assembles declarations, routing procs and the top-level composition.
-spec render(map()) -> [[any()],...].
render(Spec = #{units := Units, direct := Direct}) ->
    [preamble(Spec), [direct_ingress(Actor) || Actor <- Direct],
        [router(Spec, Unit) || Unit <- Units], top_proc(Spec)].

%% Emits module identity, imports and constants required by generated declarations.
-spec preamble(map()) -> [any(),...].
preamble(#{name := Name, actors := Actors, depth := Depth, ingresses := Ingresses}) ->
    ["// ", Name, ".x\n// Materialized logical graph; placement does not change actor identity.\n",
        "import axis;\nimport frame_transport;\n",
        case Ingresses of [] -> []; _ -> "import hls_spatial_router;\n" end,
        [["import ", Module, ";\n"] || Module <- lists:usort([
            M || #{module_name := M} <- Actors])],
        "\nconst CHANNEL_DEPTH = u32:", n(Depth), ";\n\n",
        [xls_topology_ingress:target_enum(Ingress) || Ingress <- Ingresses]].

%% Renders ordered source effects into the recipient lanes selected by the topology.
-spec router(map(),map()) -> iodata().
router(_Spec, Ingress = #{kind := ingress, index := I, bindings := Bindings,
        outbound := Lanes}) ->
    Arguments = ["spatial_in: chan<hls_spatial_router::SpatialFrame> in" |
        [lane_argument(Lane) || Lane <- Lanes]],
    Names = ["spatial_in" | [lane_name(Lane) || Lane <- Lanes]],
    [proc_header(["IngressRouter", n(I)], Arguments, Names),
        "  init { () }\n  next(state: ()) {\n",
        "    let (tok, packet) = recv(join(), spatial_in);\n",
        [begin
            #{point := [X, Y], targets := Targets} = maps:get(Id, Bindings),
            ["    let lane_", n(Index), "_tok = send_if(tok, ", lane_name(Lane), ", (",
                xls_topology_ingress:condition(Targets, Ingress, "packet"),
                ") && hls_spatial_router::contains(packet.rectangle, u16:", n(X),
                ", u16:", n(Y), "), ", lane_value(Lane, "packet"), ");\n"]
        end || Lane = #{index := Index, recipient := {actor, Id}} <- Lanes],
        "    let _done = ", join_tokens(["tok" | [["lane_", n(Index), "_tok"]
            || #{index := Index} <- Lanes]]), ";\n",
        "    state\n  }\n}\n\n"];
router(Spec, Unit = #{kind := direct, module_name := Module, outbound := Lanes,
        index := I}) ->
    Arguments = [["egress_in: chan<", Module, "::Egress> in"] |
        [lane_argument(Lane) || Lane <- Lanes]],
    Names = ["egress_in" | [lane_name(Lane) || Lane <- Lanes]],
    [proc_header(["ActorRouter", n(I)], Arguments, Names),
        "  init { () }\n  next(state: ()) {\n",
        "    let (tok, effect) = recv(join(), egress_in);\n",
        route_sends(Spec, Unit, Module, "effect", none, "tok", "true"),
        "    state\n  }\n}\n\n"].

route_sends(Spec, #{routes := Routes, outbound := Lanes}, Module,
        Effect, Slot, Token, Valid) ->
    [[begin
        Conditions = [route_condition(Spec, Route, Module, Effect, Slot) ||
            Route = #{recipients := Recipients} <- Routes,
            lists:member(maps:get(recipient, Lane), Recipients)],
        ["    let lane_", n(maps:get(index, Lane)), "_tok = send_if(\n",
            "      ", Token, ", ", lane_name(Lane), ", ", Valid, " && (",
            lists:join(" || ", Conditions), "), ", lane_value(Lane, Effect), ");\n"]
    end || Lane <- Lanes],
        "    let routed_tok = ", join_tokens([Token | [
            ["lane_", n(maps:get(index, Lane)), "_tok"] || Lane <- Lanes]]), ";\n"].

%% Tests whether a routed rectangle includes the selected recipient.
-spec route_condition(map(),map(),term(),[99 | 101 | 102 | 116,...],'none') -> [any(),...].
route_condition(_, #{source := {_, Port}}, Module, Effect, none) ->
    [Effect, ".port == ", Module, "::OutputPort::", xls_names:enum_member(Port)].
%% Wraps a frame in the representation expected by its destination lane.
-spec lane_value(map(),[97 | 99 | 101 | 102 | 107 | 112 | 116,...]) -> [[46 | 97 | 99 | 101 | 102 | 107 | 109 | 112 | 114 | 116,...],...].
lane_value(_, Effect) -> [Effect, ".frame"].

lane_argument(Lane = #{type := Type}) -> [lane_name(Lane), ": chan<", Type, "> out"].
lane_name(#{index := I}) -> ["lane_", n(I), "_out"].

%% One credit is retained across empty polls; startup frames precede the first
%% routed receive. A startup-only actor does not need a dummy connected input.
direct_ingress(#{index := I, inbound := Inbound, startup := Frames}) ->
    Count = length(Inbound),
    Inputs = case Count of
        0 -> [];
        _ -> [["frame_in: chan<axis::Frame>[u32:", n(Count), "] in"]]
    end,
    Arguments = Inputs ++ ["frame_out: chan<axis::Frame> out", "admission_in: chan<u1> in"],
    Names = case Count of 0 -> []; _ -> ["frame_in"] end ++ ["frame_out", "admission_in"],
    [proc_header(["ActorIngress", n(I)], Arguments, Names),
        "  init { (u32:0, false, u32:0) }\n",
        "  next(state: (u32, u1, u32)) {\n",
        "    if !state.1 {\n",
        "      let (_tok, _credit) = recv(join(), admission_in);\n",
        "      (state.0, true, state.2)\n",
        "    } else if state.2 < u32:", n(length(Frames)), " {\n",
        "      let frame = match state.2 {\n",
        [["        u32:", n(J), " => ", frame(Frame), ",\n"] ||
            {J, Frame} <- lists:enumerate(0, Frames)],
        "        _ => zero!<axis::Frame>(),\n      };\n",
        "      let _tok = send(join(), frame_out, frame);\n",
        "      (state.0, false, state.2 + u32:1)\n",
        "    } else {\n", ingress_poll(Count),
        "    }\n  }\n}\n\n"].

ingress_poll(0) -> "      state\n";
ingress_poll(Count) ->
    ["      let (tok, valid, frame) = unroll_for! (candidate, acc):\n",
        "          (u32, (token, u1, axis::Frame)) in u32:0..u32:", n(Count), " {\n",
        "        let (tok, frame, valid) = recv_if_non_blocking(\n",
        "          acc.0, frame_in[candidate], state.0 == candidate, zero!<axis::Frame>());\n",
        "        (tok, acc.1 || valid, if valid { frame } else { acc.2 })\n",
        "      }((join(), false, zero!<axis::Frame>()));\n",
        "      let _done = send_if(tok, frame_out, valid, frame);\n",
        "      (if state.0 + u32:1 == u32:", n(Count), " { u32:0 } else { state.0 + u32:1 },\n",
        "        !valid, state.2)\n"].

frame(#{tag := Tag, payload := Payload}) ->
    ["axis::pack(u8:", n(Tag), ", ", Payload, ")"].

proc_header(Name, Arguments, Names) ->
    ["proc ", Name, " {\n", [["  ", Argument, ";\n"] || Argument <- Arguments],
        "  config(\n    ", lists:join(",\n    ", Arguments), "\n  ) {\n    ",
        tuple(Names), "\n  }\n"].

%% Connects actor services, routers, external ports and startup producers.
-spec top_proc(map()) -> [[any()],...].
top_proc(Spec = #{direct := Direct, units := Units}) ->
    Ports = top_ports(Spec),
    Names = [Name || {Name, _} <- Ports],
    ok = xls_actor_observation:validate_channels(Names),
    ["pub proc Top {\n", [["  ", Argument, ";\n"] || {_, Argument} <- Ports],
        "  config(\n    ", lists:join(",\n    ", [A || {_, A} <- Ports]), "\n  ) {\n",
        [unit_channels(Unit) || Unit <- Units],
        external_channels(Spec),
        [direct_spawn(Spec, Actor) || Actor <- Direct],
        [router_spawn(Spec, Unit) || Unit <- Units], external_spawns(Spec),
        "    ", tuple(Names), "\n  }\n  init { () }\n  next(state: ()) { state }\n}\n"].

%% Lists the externally visible channels of the generated composition.
-spec top_ports(map()) -> [{term(),[any(),...]}].
top_ports(Spec = #{externals := Externals, ingresses := Ingresses}) ->
    External = [{Name, [Name, ": chan<axis::Frame> out"]} ||
        #{output_name := Name} <- Externals],
    Inputs = [{Name, [Name, ": chan<hls_spatial_router::SpatialFrame> in"]}
        || #{input_name := Name} <- Ingresses],
    Inputs ++ External ++ debug_ports(Spec).

debug_ports(#{direct_actor_debug := false}) -> [];
debug_ports(#{semantic_plan := #{actors := Actors, families := Families},
        direct := Direct}) ->
    Logical = maps:from_keys([L || #{logical := L} <- Direct], true),
    [{Name, [Name, ": chan<", atom_to_list(Module), "::ActorObservation> out"]} ||
        {I, #{id := Id, module := Module}} <- lists:enumerate(0, Actors),
        maps:is_key({actor, Id}, Logical),
        Name <- [xls_actor_observation:scalar_name(I)]] ++
    [{Name, [Name, ": chan<", atom_to_list(Module), "::ActorObservation>[u32:",
        n(H), "][u32:", n(W), "] out"]} ||
        {I, #{id := Id, module := Module, shape := [W, H]}} <- lists:enumerate(0, Families),
        maps:is_key({family, Id, [0, 0]}, Logical),
        Name <- [xls_actor_observation:family_name(I)]].

%% Declares the internal channels owned by one execution unit.
-spec unit_channels(map()) -> [[[any()]]].
unit_channels(#{kind := ingress}) -> [];
unit_channels(#{kind := direct, stem := Stem, module_name := Module,
        egress_depth := EgressDepth, inbound := Inbound}) ->
    [channel([Stem, "_req"], "axis::Frame", none, "CHANNEL_DEPTH"),
        channel([Stem, "_admit"], "u1", none, "CHANNEL_DEPTH"),
        channel([Stem, "_egress"], [Module, "::Egress"], none, ["u32:", n(EgressDepth)]),
        case Inbound of [] -> []; _ -> channel([Stem, "_requests"], "axis::Frame",
            length(Inbound), "CHANNEL_DEPTH") end].

channel(Stem, Type, Count, Depth) ->
    ["    let (", Stem, "_p, ", Stem, "_c) = chan<", Type, ", ", Depth, ">",
        case Count of none -> []; _ -> ["[u32:", n(Count), "]"] end,
        "(\"", Stem, "\");\n"].

direct_spawn(Spec, Actor = #{id := Id, index := I, stem := Stem, module_name := Module,
        inbound := Inbound, debug := Debug}) ->
    ["    // Actor ", io_lib:format("~p", [Id]), " uses ", Module, ".\n",
        "    spawn ", Module, "::Service(", Stem, "_req_c, ", Stem, "_egress_p, ",
        Stem, "_admit_p", xls_actor_observation:spawn_argument(Spec, Debug), ");\n",
        "    spawn ActorIngress", n(I), "(",
        case Inbound of [] -> []; _ -> [Stem, "_requests_c, "] end,
        Stem, "_req_p, ", Stem, "_admit_c);\n",
        case {Inbound, maps:get(startup, Actor)} of
            {[], []} -> "    // Actor has no routed or startup input.\n";
            _ -> []
        end].

%% Connects a unit's ordered output to its topology router.
-spec router_spawn(map(),map()) -> [any(),...].
router_spawn(Spec, #{kind := ingress, index := I, input_name := Name, outbound := Lanes}) ->
    ["    spawn IngressRouter", n(I), "(", Name,
        [[", ", lane_producer(Spec, Lane)] || Lane <- Lanes], ");\n"];
router_spawn(Spec, #{kind := direct, index := I, stem := Stem, outbound := Lanes}) ->
    ["    spawn ActorRouter", n(I), "(", Stem, "_egress_c",
        [[", ", lane_producer(Spec, Lane)] || Lane <- Lanes], ");\n"].

lane_producer(#{units := Units}, Lane = #{destination := {external, _}}) ->
    external_lane_producer(Lane, Units);
lane_producer(#{units := Units}, #{index := I, destination := Destination}) ->
    Unit = hd([U || U = #{unit := Key} <- Units, Key =:= Destination]),
    #{stem := Stem, inbound := Inbound} = Unit,
    Position = index_of(I, [J || #{index := J} <- Inbound]),
    [Stem, "_requests_p[u32:", n(Position), "]"].

%% External channel positions are assigned from the same globally sorted lanes
%% as both producer wiring and merge generation.
external_lane_producer(#{source := Source, recipient := Recipient}, Units) ->
    ExternalLanes = lists:sort([{maps:get(index, L), L} || #{outbound := Lanes} <- Units,
        L = #{recipient := R} <- Lanes, R =:= Recipient]),
    I = index_of(Source, [S || {_, #{source := S}} <- ExternalLanes]),
    {external, Id} = Recipient,
    [external_stem(Id), "_p[u32:", n(I), "]"].

external_channels(#{externals := Externals, lanes := Lanes}) ->
    [begin
        Count = length([ok || #{recipient := R} <- Lanes, R =:= {external, Id}]),
        case Count of 0 -> error({unconnected_dslx_destination, Id}); _ -> ok end,
        channel(external_stem(Id), "axis::Frame", Count, "CHANNEL_DEPTH")
    end || #{id := Id} <- Externals].

external_spawns(#{externals := Externals, lanes := Lanes}) ->
    [["    spawn frame_transport::FrameArrayMux<u32:",
        n(length([ok || #{recipient := R} <- Lanes, R =:= {external, Id}])), ">(",
        external_stem(Id), "_c, ", Output, ");\n"] ||
        #{id := Id, output_name := Output} <- Externals].

external_stem(Id) -> [xls_topology_profile:identifier(Id, external_id), "_lanes"].
index_of(Value, List) -> length(lists:takewhile(fun(V) -> V =/= Value end, List)).
n(I) -> integer_to_list(I).
tuple([]) -> "()";
tuple([Name]) -> ["(", Name, ",)"];
tuple(Names) -> ["(", lists:join(", ", Names), ")"].
join_tokens([Token]) -> Token;
join_tokens(Tokens) -> ["join(", lists:join(", ", Tokens), ")"].
