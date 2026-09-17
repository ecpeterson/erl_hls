%%%% A materialized topology graph with independent placement decisions.
-module(xls_topology_instance_dslx).
-moduledoc false.
-export([required/2, artifact_requirements/2, emit/2]).

%% The compact renderer preserves generated loops for wholly direct or wholly
%% shared families. An explicit graph is materialized: route size
%% follows deployed instances, while actor artifacts remain shared.
required(Plan, Profile) ->
    #{scheduler_groups := Specs} = xls_topology_profile:normalize(Profile),
    #{groups := Groups, direct_members := Direct} = hls_scheduler_plan:normalize(Plan, Specs),
    Groups =/= [] andalso Direct =/= [].

artifact_requirements(Plan, Profile) ->
    maps:get(artifact_requirements, lower(Plan, Profile)).

emit(Plan, Profile) ->
    render(lower(Plan, Profile)).

lower(Plan, Profile0) ->
    Profile = #{scheduler_groups := GroupSpecs,
        effect_window_partition := WindowPartition,
        reduction_placements := Reductions,
        direct_actor_debug := ActorDebug,
        mailbox_debug := MailboxDebug} =
        xls_topology_profile:normalize(Profile0),
    require_empty(ingresses, maps:get(ingresses, Plan)),
    require_empty(reduction_placements, maps:to_list(Reductions)),
    case WindowPartition of
        global -> ok;
        _ -> error({instance_effect_window_partition, WindowPartition})
    end,
    Schedule = #{groups := Groups0} = hls_scheduler_plan:normalize(Plan, GroupSpecs),
    Placements = hls_scheduler_plan:placements(Schedule),
    xls_topology_graph:check_lanes(lanes, maps:get(routes, Plan), Plan),
    xls_topology_graph:check_lanes(lane_relations, maps:get(route_relations, Plan), Plan),
    {Materialized, Origins} = materialize(Plan),
    Base = xls_topology_graph:lower(Materialized, Profile),
    Startup = maps:from_list([{Id, Frames} || #{target := Id, frames := Frames}
        <- maps:get(startup, Base)]),
    Actors = [place_actor(Actor, maps:get(maps:get(id, Actor), Origins),
        Placements, Startup) || Actor <- maps:get(actors, Base)],
    ActorIndex = maps:from_list([{maps:get(id, Actor), Actor} || Actor <- Actors]),
    Direct = [Actor || Actor = #{placement := direct} <- Actors],
    Schedulers = [scheduler(I, Group, Actors) || {I, Group} <- lists:enumerate(0, Groups0)],
    case {MailboxDebug, Schedulers} of
        {true, []} -> error(mailbox_debug_requires_shared_schedulers);
        _ -> ok
    end,
    Routes = maps:get(routes, Base),
    lists:foreach(fun validate_delivery/1, Routes),
    Units = Direct ++ Schedulers,
    Lanes0 = lists:usort([{maps:get(unit, maps:get(Id, ActorIndex)), Recipient}
        || #{source := {Id, _}, recipients := Recipients} <- Routes,
           Recipient <- Recipients]),
    Lanes = [lane(I, Source, Recipient, ActorIndex) ||
        {I, {Source, Recipient}} <- lists:enumerate(0, Lanes0)],
    Units1 = [unit_routes(Unit, Routes, ActorIndex, Lanes) || Unit <- Units],
    Schedulers1 = [Unit || Unit = #{kind := scheduler} <- Units1],
    Direct1 = [Unit || Unit = #{kind := direct} <- Units1],
    Requirements = maps:from_list([{Module, #{shared_service => ordinary}} ||
        #{module := Module} <- Actors]),
    WithDirect = flag_modules(Requirements, Direct1, direct_actor_debug, ActorDebug),
    WithMailbox = flag_modules(WithDirect, Schedulers1, mailbox_debug, MailboxDebug),
    Base#{actors := Actors, direct => Direct1, schedulers => Schedulers1,
        units => Units1, lanes := Lanes, actor_index => ActorIndex,
        semantic_plan => Plan, mailbox_debug => MailboxDebug,
        artifact_requirements => WithMailbox,
        effect_window_domains => [[I || #{index := I} <- Schedulers1]]}.

require_empty(_, []) -> ok;
require_empty(Section, _) -> error({unsupported_instance_section, Section}).

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
    {Plan#{actors := Expanded, families := [], routes := Routes,
        route_relations := [], lane_relations := [], lanes := xls_topology_graph:lanes(Routes)}, Origins}.

family_entries(I, Family = #{id := Id, shape := [W, H]}) ->
    [{maps:without([shape, instance_count], Family#{id := {Id, X, Y}}),
        #{logical => {family, Id, [X, Y]},
            debug => [xls_actor_observation:family_name(I), "[u32:", n(X),
                "][u32:", n(Y), "]"]}}
        || X <- lists:seq(0, W - 1), Y <- lists:seq(0, H - 1)];
family_entries(_, #{id := Id, shape := Shape}) ->
    error({unsupported_instance_family_shape, Id, Shape}).

place_actor(Actor = #{id := Id, index := Index}, Origin = #{logical := Logical},
        Placements, Startup) ->
    Frames = maps:get(Id, Startup, []),
    Base = maps:merge(Actor#{startup => Frames}, Origin),
    case maps:find(Logical, Placements) of
        error -> Base#{kind => direct, placement => direct, unit => {direct, Index}};
        {ok, Placement = #{index := Group, slot := Slot}} ->
            Capacity = maps:get(mailbox_capacity, Actor),
            case length(Frames) =< Capacity of
                true -> ok;
                false -> error({scheduler_startup_capacity, Id, length(Frames), Capacity})
            end,
            Base#{placement => Placement, unit => {scheduler, Group}, slot => Slot}
    end.

scheduler(I, Group = #{id := Id, state_storage := block_ram,
        mailbox_storage := block_ram}, Actors) ->
    Members = [Actor || Actor = #{unit := {scheduler, J}} <- Actors, J =:= I],
    Module = maps:get(module, Group),
    Group#{kind => scheduler, index => I, unit => {scheduler, I},
        stem => ["scheduler_", n(I)],
        module_name => xls_topology_profile:identifier(Module, {scheduler, Id}),
        actors => Members, startup => [{Slot, Frame} ||
            #{slot := Slot, startup := Frames} <- Members, Frame <- Frames]};
scheduler(_, #{id := Id, state_storage := State, mailbox_storage := Mailbox}, _) ->
    error({scheduler_storage, Id, State, Mailbox}).

flag_modules(Requirements, _, _, false) -> Requirements;
flag_modules(Requirements, Units, Flag, true) ->
    lists:foldl(fun(#{module := Module}, Acc) ->
        Acc#{Module := (maps:get(Module, Acc))#{Flag => true}}
    end, Requirements, Units).

validate_delivery(#{delivery := direct, recipients := [_]}) -> ok;
validate_delivery(#{delivery := queued, recipients := [_, _ | _]}) -> ok;
validate_delivery(#{source := Source, delivery := Delivery, recipients := Recipients}) ->
    error({unsupported_dslx_route_delivery, Source, Delivery, length(Recipients)}).

lane(I, Source, {external, Id} = Recipient, _) ->
    #{index => I, source => Source, recipient => Recipient,
        destination => {external, Id}, type => "axis::Frame"};
lane(I, Source, {actor, Id} = Recipient, ActorIndex) ->
    Actor = #{unit := Destination} = maps:get(Id, ActorIndex),
    Type = case Actor of
        #{placement := direct} -> "axis::Frame";
        #{module_name := Module} -> [Module, "::ScheduledRequest"]
    end,
    #{index => I, source => Source, recipient => Recipient,
        destination => Destination, type => Type, target => Actor}.

unit_routes(Unit = #{unit := Key}, Routes, Actors, Lanes) ->
    Unit#{routes => [Route || Route = #{source := {Id, _}} <- Routes,
        maps:get(unit, maps:get(Id, Actors)) =:= Key],
        outbound => [Lane || Lane = #{source := Source} <- Lanes, Source =:= Key],
        inbound => [Lane || Lane = #{destination := Destination} <- Lanes,
            Destination =:= Key]}.

render(Spec = #{units := Units, direct := Direct, schedulers := Schedulers}) ->
    [preamble(Spec), [direct_ingress(Actor) || Actor <- Direct],
        [startup_proc(Scheduler) || Scheduler <- Schedulers],
        [router(Spec, Unit) || Unit <- Units], top_proc(Spec)].

preamble(#{name := Name, actors := Actors, depth := Depth}) ->
    ["// ", Name, ".x\n// Materialized logical graph; placement does not change actor identity.\n",
        "import axis;\nimport frame_transport;\nimport effect_window;\n",
        [["import ", Module, ";\n"] || Module <- lists:usort([
            M || #{module_name := M} <- Actors])],
        "\nconst CHANNEL_DEPTH = u32:", n(Depth), ";\n\n"].

router(Spec, Unit = #{kind := scheduler, module_name := Module, outbound := Lanes}) ->
    Routing = #{arguments => [lane_argument(Lane) || Lane <- Lanes],
        names => [lane_name(Lane) || Lane <- Lanes],
        send => route_sends(Spec, Unit, Module, "effect", "scheduled.slot", "grant_tok", "emit")},
    xls_topology_scheduler_dslx:effect_router(Spec, Unit, Routing);
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

route_condition(_, #{source := {_, Port}}, Module, Effect, none) ->
    [Effect, ".port == ", Module, "::OutputPort::", xls_names:enum_member(Port)];
route_condition(#{actor_index := Actors}, #{source := {Id, Port}}, Module, Effect, Slot) ->
    #{slot := ActorSlot} = maps:get(Id, Actors),
    ["(", Slot, " == u32:", n(ActorSlot), " && ", Effect, ".port == ",
        Module, "::OutputPort::", xls_names:enum_member(Port), ")"].

lane_value(#{target := #{placement := #{}, slot := Slot, module_name := Module}}, Effect) ->
    [Module, "::ScheduledRequest { slot: u32:", n(Slot), ", frame: ", Effect,
        ".frame, ..zero!<", Module, "::ScheduledRequest>() }"];
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

startup_proc(#{startup := []}) -> [];
startup_proc(#{index := I, module_name := Module, startup := Frames}) ->
    [proc_header(["SchedulerStartup", n(I)],
        [["request_out: chan<", Module, "::ScheduledRequest> out"]], ["request_out"]),
        "  init { u32:0 }\n  next(index: u32) {\n",
        "    let request = match index {\n",
        [["      u32:", n(J), " => ", Module, "::ScheduledRequest { slot: u32:", n(Slot),
            ", frame: ", frame(Frame), ", ..zero!<", Module, "::ScheduledRequest>() },\n"]
            || {J, {Slot, Frame}} <- lists:enumerate(0, Frames)],
        "      _ => zero!<", Module, "::ScheduledRequest>(),\n    };\n",
        "    let active = index < u32:", n(length(Frames)), ";\n",
        "    let _done = send_if(join(), request_out, active, request);\n",
        "    if active { index + u32:1 } else { index }\n  }\n}\n\n"].

frame(#{tag := Tag, payload := Payload}) ->
    ["axis::pack(u8:", n(Tag), ", ", Payload, ")"].

proc_header(Name, Arguments, Names) ->
    ["proc ", Name, " {\n", [["  ", Argument, ";\n"] || Argument <- Arguments],
        "  config(\n    ", lists:join(",\n    ", Arguments), "\n  ) {\n    ",
        tuple(Names), "\n  }\n"].

top_proc(Spec = #{direct := Direct, schedulers := Schedulers, units := Units}) ->
    Ports = top_ports(Spec),
    Names = [Name || {Name, _} <- Ports],
    ok = xls_actor_observation:validate_channels(Names),
    ["pub proc Top {\n", [["  ", Argument, ";\n"] || {_, Argument} <- Ports],
        "  config(\n    ", lists:join(",\n    ", [A || {_, A} <- Ports]), "\n  ) {\n",
        [unit_channels(Unit) || Unit <- Units],
        external_channels(Spec), window_channels(Schedulers),
        [direct_spawn(Spec, Actor) || Actor <- Direct],
        [scheduler_spawn(Spec, Scheduler) || Scheduler <- Schedulers],
        [router_spawn(Spec, Unit) || Unit <- Units], external_spawns(Spec),
        "    ", tuple(Names), "\n  }\n  init { () }\n  next(state: ()) { state }\n}\n"].

top_ports(Spec = #{schedulers := Schedulers, externals := Externals}) ->
    Ram = lists:append([lists:zip(xls_scheduler_ram_dslx:names([Stem, "_"]),
        xls_scheduler_ram_dslx:parameters([Stem, "_"], [Module, "::"])) ||
        #{stem := Stem, module_name := Module} <- Schedulers]),
    Mailbox = lists:zip(xls_scheduler_observation:names(Spec),
        xls_scheduler_observation:arguments(Spec)),
    External = [{Name, [Name, ": chan<axis::Frame> out"]} ||
        #{output_name := Name} <- Externals],
    Ram ++ Mailbox ++ External ++ debug_ports(Spec).

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

unit_channels(#{kind := direct, stem := Stem, module_name := Module,
        egress_depth := EgressDepth, inbound := Inbound}) ->
    [channel([Stem, "_req"], "axis::Frame", none, "CHANNEL_DEPTH"),
        channel([Stem, "_admit"], "u1", none, "CHANNEL_DEPTH"),
        channel([Stem, "_egress"], [Module, "::Egress"], none, ["u32:", n(EgressDepth)]),
        case Inbound of [] -> []; _ -> channel([Stem, "_requests"], "axis::Frame",
            length(Inbound), "CHANNEL_DEPTH") end];
unit_channels(#{kind := scheduler, stem := Stem, module_name := Module, inbound := Inbound}) ->
    [channel([Stem, "_requests"], [Module, "::ScheduledRequest"],
        length(Inbound) + 1, "CHANNEL_DEPTH"),
        channel([Stem, "_startup"], [Module, "::ScheduledRequest"], none, "CHANNEL_DEPTH"),
        channel([Stem, "_egress"], [Module, "::ScheduledEffects"], none, "CHANNEL_DEPTH")].

channel(Stem, Type, Count, Depth) ->
    ["    let (", Stem, "_p, ", Stem, "_c) = chan<", Type, ", ", Depth, ">",
        case Count of none -> []; _ -> ["[u32:", n(Count), "]"] end,
        "(\"", Stem, "\");\n"].

window_channels([]) -> [];
window_channels(Schedulers) ->
    N = length(Schedulers),
    [[channel(["effect_window_", Name], "u1", N, "CHANNEL_DEPTH") ||
        Name <- ["request", "grant", "release"]],
        "    spawn effect_window::Arbiter<u32:", n(N), ">(",
        "effect_window_request_c, effect_window_grant_p, effect_window_release_c);\n"].

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

scheduler_spawn(Spec, #{stem := Stem, index := I, module_name := Module,
        slot_count := Slots, inbound := Inbound, startup := Startup}) ->
    [case Startup of
        [] -> [];
        _ -> ["    spawn SchedulerStartup", n(I), "(", Stem, "_startup_p);\n"]
    end,
        "    spawn ", Module, "::SharedService<u32:", n(Slots), ", u32:",
        n(length(Inbound) + 1), ", u32:", n(length(Startup)), ", u32:", n(I), ">(\n",
        "      ", Stem, "_requests_c, ", Stem, "_startup_c, ", Stem, "_egress_p,\n      ",
        lists:join(", ", xls_scheduler_ram_dslx:names([Stem, "_"])),
        xls_scheduler_observation:spawn_argument(Spec, Stem), ");\n"].

router_spawn(Spec, #{kind := direct, index := I, stem := Stem, outbound := Lanes}) ->
    ["    spawn ActorRouter", n(I), "(", Stem, "_egress_c",
        [[", ", lane_producer(Spec, Lane)] || Lane <- Lanes], ");\n"];
router_spawn(Spec, #{kind := scheduler, index := I, stem := Stem,
        outbound := Lanes, inbound := Inbound}) ->
    ["    spawn SchedulerRouter", n(I), "(", Stem, "_egress_c, ", Stem,
        "_requests_p[u32:", n(length(Inbound)), "]",
        [[", ", lane_producer(Spec, Lane)] || Lane <- Lanes],
        ", effect_window_request_p[u32:", n(I), "], effect_window_grant_c[u32:", n(I),
        "], effect_window_release_p[u32:", n(I), "]);\n"].

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
