%%%% A materialized topology graph with independent placement decisions.
-module(xls_shared_topology_instance_dslx).
-moduledoc false.
-export([required/2, lower/2, render/1, message_inputs/2]).

%% The compact renderer preserves generated loops for wholly direct or wholly
%% shared families. An explicit graph is materialized: route size
%% follows deployed instances, while actor artifacts remain shared.
-doc "Reports whether placement or dedicated collection requires an explicit instance graph.".
-spec required(map(),map()) -> boolean().
required(Plan, Profile) ->
    #{scheduler_groups := Specs, direct_collections := Collections, effect_delivery_width := Width,
        frame_payload_words := PayloadWords} =
        xls_shared_topology_profile:normalize(Profile),
    #{groups := Groups, direct_members := Direct} = hls_scheduler_plan:normalize(Plan, Specs, hls_frame_layout:new(PayloadWords)),
    Width > 1 orelse map_size(Collections) > 0 orelse (Groups =/= [] andalso Direct =/= []) orelse
        lists:any(fun(Group) -> maps:get(gathers, Group, none) =/= none end, Groups).

-doc "Returns physical receive lanes from the same validated lowering used by the common topology generation plan. Every lane includes all routed actor/port sources, including aliases merged by a scheduler. External ingress is explicit and supplies no actor value guarantee. Startup and credit are separate from these message lanes.".
-spec message_inputs(map(), map()) -> [map()].
message_inputs(Plan, Profile) ->
    case maps:get(families, Plan) of [] -> ok; _ -> error(message_inputs_requires_exact_graph) end,
    #{units := Units, actor_index := Actors} = lower(Plan, Profile),
    [#{unit => Key, module => maps:get(module, Unit),
        lanes => [begin
            Sources = [{Id, Port} || #{source := {Id, Port}, recipients := Recipients} <- maps:get(routes, Plan),
                maps:get(unit, maps:get(Id, Actors)) =:= Source, lists:member(Recipient, Recipients)],
            #{producer => Producer, lane => I, source_unit => Source, recipient => Recipient,
                slot => maps:get(slot, maps:get(element(2, Recipient), Actors), none),
                sources => Sources, external => element(1, Source) =:= ingress}
        end || {Producer, #{index := I, source := Source, recipient := Recipient}} <-
            lists:enumerate(0, maps:get(inbound, Unit))]}
        || Unit = #{unit := Key, kind := Kind} <- Units,
            Kind =:= scheduler orelse Kind =:= direct].

-doc "Resolves logical actors, physical units, receive lanes and backpressure domains into a retained materialized graph. Checks startup, collection placement and actor requirements before rendering.".
-spec lower(hls_topology:plan(), xls_shared_topology_profile:profile()) -> map().
lower(Plan, Profile0) ->
    Profile = #{scheduler_groups := GroupSpecs,
        effect_window_partition := WindowPartition,
        reduction_placements := Reductions,
        direct_actor_debug := ActorDebug,
        mailbox_debug := MailboxDebug, frame_payload_words := PayloadWords} =
        xls_shared_topology_profile:normalize(Profile0),
    require_empty(reduction_placements, maps:to_list(Reductions)),
    Schedule = #{groups := Groups0} = hls_scheduler_plan:normalize(Plan, GroupSpecs, hls_frame_layout:new(PayloadWords)),
    Placements = hls_scheduler_plan:placements(Schedule),
    xls_topology_graph:check_lanes(lanes, maps:get(routes, Plan), Plan),
    xls_topology_graph:check_lanes(lane_relations, maps:get(route_relations, Plan), Plan),
    {Materialized, Origins} = materialize(Plan),
    %% Compiler graph lowering owns buffering and frame layout; placement stays here.
    GraphProfile = maps:with([name, channel_depth, actor_egress_depth,
        direct_actor_debug, frame_payload_words], Profile),
    Base = xls_topology_graph:lower(Materialized, GraphProfile),
    Startup = maps:from_list([{Id, Frames} || #{target := Id, frames := Frames}
        <- maps:get(startup, Base)]),
    Actors = [place_actor(Actor, maps:get(maps:get(id, Actor), Origins),
        Placements, Startup) || Actor <- maps:get(actors, Base)],
    ActorIndex = maps:from_list([{maps:get(id, Actor), Actor} || Actor <- Actors]),
    Direct = [Actor || Actor = #{placement := direct} <- Actors],
    Schedulers = [scheduler(I, Group, Actors) || {I, Group} <- lists:enumerate(0, Groups0)],
    lists:foreach(fun validate_indexed_startup/1, Schedulers),
    case {MailboxDebug, Schedulers} of
        {true, []} -> error(mailbox_debug_requires_shared_schedulers);
        _ -> ok
    end,
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
    %% Ownership analysis follows actor-to-actor backpressure dependencies.
    %% External input/output endpoints terminate here; direct actors remain
    %% vertices, including fan-in, fan-out, and arbitrarily long relay paths.
    Dependencies = [[window_vertex(Source), window_vertex(Destination)] ||
        #{source := Source, destination := Destination} <- Lanes,
        element(1, Source) =/= ingress, element(1, Destination) =/= external],
    Domains = xls_topology_effect_windows:partition(
        [I || #{index := I} <- Schedulers], WindowPartition, Dependencies),
    Schedulers1 = xls_topology_effect_windows:annotate(
        [unit_routes(Unit, Routes, ActorIndex, Lanes) || Unit <- Schedulers], Domains),
    Policies = maps:get(direct_collections, Profile),
    Direct1 = [Unit#{direct_collection => maps:get(maps:get(module, Unit), Policies, false)} ||
        Actor <- Direct, Unit <- [unit_routes(Actor, Routes, ActorIndex, Lanes)]],
    ok = validate_direct_collections(Policies, Direct1, Schedulers1),
    Units = Direct1 ++ Schedulers1 ++
        [unit_routes(Unit, Routes, ActorIndex, Lanes) || Unit <- Ingresses],
    Requirements = hls_topology_constants:requirements(Groups0,
        maps:from_list([{Module, #{shared_service => ordinary}} || #{module := Module} <- Actors])),
    Collected = xls_shared_collection_codegen:requirements(Groups0, Direct1, Requirements),
    Specialized = lists:foldl(fun(#{module := M, direct_collection := Mode}, Acc) ->
        case Mode of false -> Acc; _ -> Acc#{M := (maps:get(M, Acc))#{direct_collection => Mode}} end
    end, Collected, Direct1),
    WithDirect = flag_modules(Specialized, Direct1, direct_actor_debug, ActorDebug),
    WithMailbox = flag_modules(WithDirect, Schedulers1, mailbox_debug, MailboxDebug),
    Base#{actors := Actors, direct => Direct1, schedulers => Schedulers1,
        units => Units, lanes := Lanes, actor_index => ActorIndex,
        semantic_plan => Plan, mailbox_debug => MailboxDebug, ingresses => Ingresses,
        artifact_requirements => maps:map(fun(_, Requirement) ->
            Requirement#{frame_payload_words => maps:get(frame_payload_words, Profile)}
        end, WithMailbox),
        effect_window_domains => Domains,
        effect_delivery_width => maps:get(effect_delivery_width, Profile)}.

%% Selected modules must use one singleton backend throughout this deployment.
-spec validate_direct_collections(map(), [map()], [map()]) -> ok.
validate_direct_collections(Policies, Direct, Schedulers) ->
    maps:foreach(fun(Module, Mode) ->
        Units = [A || A = #{module := M} <- Direct, M =:= Module],
        case Mode =:= exclusive_epoch andalso Units =/= [] andalso
                not lists:any(fun(#{module := M}) -> M =:= Module end, Schedulers) andalso
                lists:all(fun(#{inbound := Inputs}) -> Inputs =/= [] end, Units) of
            true -> lists:foreach(fun validate_collection_startup/1, Units);
            false -> error({direct_collection_placement, Module, Mode})
        end
    end, Policies).

%% Startup initializes ordinary actor state; reserved contributions enter the
%% routed receiver. Reject them here rather than losing a mailbox-side fold.
-spec validate_collection_startup(map()) -> ok.
validate_collection_startup(#{id := Id, module := Module, startup := Frames, interface := Interface}) ->
    case maps:get(reductions, Interface, none) of
        #{sites := Sites} ->
            Tags = [Module:pack_tag(Tag) || S <- Sites,
                Tag <- maps:get(contributions, S)],
            case lists:any(fun(#{tag := Tag}) -> lists:member(Tag, Tags) end, Frames) of
                true -> error({reserved_collection_startup, Id});
                false -> ok
            end;
        _ -> error(direct_collection_requires_reduced_statem)
    end.

%% Indexed contributions must enter the reserved receiver, not startup mailbox storage.
-spec validate_indexed_startup(map()) -> ok.
validate_indexed_startup(#{gather_collection := true, actors := Actors}) ->
    lists:foreach(fun(#{id := Id, module := Module, startup := Frames,
            interface := #{gathers := #{sites := Sites}}}) ->
        Tags = [Module:pack_tag(Tag) || Site <- Sites,
            Tag <- maps:get(contributions, Site)],
        case lists:any(fun(#{tag := Tag}) -> lists:member(Tag, Tags) end, Frames) of
            true -> error({reserved_gather_startup, Id});
            false -> ok
        end
    end, Actors);
validate_indexed_startup(_) -> ok.

%% Maps a physical execution unit to its effect-window graph vertex.
-spec window_vertex({direct, term()} | {scheduler, non_neg_integer()}) -> {direct, term()} | non_neg_integer().
window_vertex({scheduler, Index}) -> Index;
window_vertex({direct, _} = Actor) -> Actor.

%% Rejects an unsupported nonempty placement request.
-spec require_empty('reduction_placements',[]) -> 'ok'.
require_empty(_, []) -> ok;
require_empty(Section, _) -> error({unsupported_instance_section, Section}).

%% Expands exact actors and bounded family members into one routing graph.
-spec materialize(map()) -> {map(),map()}.
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

%% Assigns router identities to external rectangle-addressed inputs.
-spec ingress_units(map(),map()) -> [map()].
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

%% Lists the target lanes of an external ingress without duplicating aliases.
-spec ingress_bindings(map(),map()) -> [{term(),map()}].
ingress_bindings(#{actor := Id, at := Point, targets := Targets}, _) ->
    [{Id, #{point => Point, targets => Targets}}];
ingress_bindings(#{family := Id, scale := [SX, SY], offset := [OX, OY],
        targets := Targets}, Families) ->
    #{shape := [W, H]} = maps:get(Id, Families),
    [{{Id, X, Y}, #{point => [OX + SX * X, OY + SY * Y], targets => Targets}}
        || X <- lists:seq(0, W - 1), Y <- lists:seq(0, H - 1)].

%% Enumerates family instances with coordinates and startup frames.
-spec family_entries(integer(),map()) -> [{map(),map()}].
family_entries(I, Family = #{id := Id, shape := [W, H]}) ->
    [{maps:without([shape, instance_count], Family#{id := {Id, X, Y}}),
        #{logical => {family, Id, [X, Y]},
            debug => [xls_actor_observation:family_name(I), "[u32:", n(X),
                "][u32:", n(Y), "]"]}}
        || X <- lists:seq(0, W - 1), Y <- lists:seq(0, H - 1)];
family_entries(_, #{id := Id, shape := Shape}) ->
    error({unsupported_instance_family_shape, Id, Shape}).

%% Attaches generated channel names and storage placement to one logical actor.
-spec place_actor(map(),map(),map(),map()) -> map().
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

%% Combines grouped actor identities, RAM layout and observation settings.
-spec scheduler(integer(),map(),[map()]) -> map().
scheduler(I, Group = #{id := Id, state_storage := block_ram,
        mailbox_storage := block_ram}, Actors) ->
    Members = [Actor || Actor = #{unit := {scheduler, J}} <- Actors, J =:= I],
    Module = maps:get(module, Group),
    Group#{kind => scheduler, index => I, unit => {scheduler, I},
        stem => ["scheduler_", n(I)],
        module_name => xls_shared_topology_profile:identifier(Module, {scheduler, Id}),
        actors => Members, startup => [{Slot, Frame} ||
            #{slot := Slot, startup := Frames} <- Members, Frame <- Frames]};
scheduler(_, #{id := Id, state_storage := State, mailbox_storage := Mailbox}, _) ->
    error({scheduler_storage, Id, State, Mailbox}).

%% Requires all uses of an actor module to agree on artifact options.
-spec flag_modules(map(),[map()],'direct_actor_debug' | 'mailbox_debug',boolean()) -> map().
flag_modules(Requirements, _, _, false) -> Requirements;
flag_modules(Requirements, Units, Flag, true) ->
    lists:foldl(fun(#{module := Module}, Acc) ->
        Acc#{Module := (maps:get(Module, Acc))#{Flag => true}}
    end, Requirements, Units).

%% Checks recipient schemas before constructing physical channels.
-spec validate_delivery(map()) -> 'ok'.
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
    Type = case Actor of
        #{placement := direct} -> "axis::Frame";
        #{module_name := Module} -> [Module, "::ScheduledRequest"]
    end,
    #{index => I, source => Source, recipient => Recipient,
        destination => Destination, type => Type, target => Actor}.

%% Collects the logical routes emitted by one physical execution unit.
-spec unit_routes(map(),[any()],map(),[map()]) -> map().
unit_routes(Unit = #{unit := Key}, Routes, Actors, Lanes) ->
    Unit#{routes => [Route || Route = #{source := {Id, _}} <- Routes,
        maps:get(unit, maps:get(Id, Actors)) =:= Key],
        outbound => [Lane || Lane = #{source := Source} <- Lanes, Source =:= Key],
        inbound => [Lane || Lane = #{destination := Destination} <- Lanes,
            Destination =:= Key]}.

-doc "Renders a retained materialized graph from lower/2 without repeating placement, lane allocation or source interface analysis.".
-spec render(map()) -> iodata().
render(Spec = #{units := Units, direct := Direct, schedulers := Schedulers}) ->
    [preamble(Spec), [direct_ingress(Actor) || Actor <- Direct],
        [startup_proc(Scheduler) || Scheduler <- Schedulers],
        [router(Spec, Unit) || Unit <- Units], top_proc(Spec)].

%% Emits module identity, imports and constants required by generated declarations.
-spec preamble(map()) -> iodata().
preamble(#{name := Name, actors := Actors, depth := Depth, ingresses := Ingresses}) ->
    ["// ", Name, ".x\n// Materialized logical graph; placement does not change actor identity.\n",
        "import axis;\nimport frame_transport;\nimport effect_window;\n",
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
router(Spec, Unit = #{kind := scheduler, module_name := Module, outbound := Lanes}) ->
    Routing = #{arguments => [lane_argument(Lane) || Lane <- Lanes],
        names => [lane_name(Lane) || Lane <- Lanes],
        send => route_sends(Spec, Unit, Module, "effect", "scheduled.slot", "grant_tok", "emit")},
    case maps:get(effect_delivery_width, Spec, 1) of
        W when W =:= 1; Lanes =:= [] -> xls_topology_scheduler_dslx:effect_router(Spec, Unit, Routing);
        Width -> parallel_router(Spec, Unit, Width)
    end;
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

%% Resolve actual recipient sets before choosing a disjoint publication prefix.
-spec parallel_router(map(), map(), pos_integer()) -> binary().
parallel_router(Spec, Unit = #{module_name := Module, routes := Routes, outbound := Lanes}, Width) ->
    Count = length(Lanes),
    case Count of 0 -> error(parallel_router_requires_destinations); _ -> ok end,
    Masks = [["    ((", lists:join(" || ", [
        route_condition(Spec, Route, Module, "effect", "slot") ||
        Route = #{recipients := Recipients} <- Routes,
        lists:member(maps:get(recipient, Lane), Recipients)]),
        ") as bits[LANES]) << u32:", n(I)] || {I, Lane} <- lists:enumerate(0, Lanes)],
    Targets = ["// Static route membership; aliases occupy the same bit.\n",
        "fn router_targets(slot: u32, effect: ACTOR::Egress) -> bits[LANES] {\n",
        lists:join(" |\n", Masks), "\n}\n\n"],
    Sends = [[begin
        Id = n(maps:get(index, Lane)),
        ["    let lane_", Id, " = router_frame(head, u32:", n(I), ");\n",
         "    let lane_", Id, "_tok = send_if(grant_tok, ", lane_name(Lane),
         ", batch_valid && lane_", Id, ".0, ",
         lane_frame_value(Lane, ["lane_", Id, ".1"]), ");\n"]
    end || {I, Lane} <- lists:enumerate(0, Lanes)],
        "    let routed_tok = ", join_tokens(["grant_tok" | [
            ["lane_", n(maps:get(index, Lane)), "_tok"] || Lane <- Lanes]]), ";\n"],
    xls_parallel_effect_router_dslx:emit(Unit, Width, Count,
        [lane_argument(Lane) || Lane <- Lanes], Targets, Sends).

%% Wraps a selected frame without retaining a redundant port tag in the head.
-spec lane_frame_value(map(), iodata()) -> iodata().
lane_frame_value(#{target := #{placement := #{}, slot := Slot, module_name := Module}}, Frame) ->
    [Module, "::ScheduledRequest { slot: u32:", n(Slot), ", frame: ", Frame,
        ", ..zero!<", Module, "::ScheduledRequest>() }"];
lane_frame_value(_, Frame) -> Frame.

%% Renders all selected recipients while preserving effect acceptance order.
-spec route_sends(map(),map(),term(),string(),'none' | string(),string(),string()) -> iodata().
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
-spec route_condition(map(),map(),term(),string(),'none' | string()) -> iodata().
route_condition(_, #{source := {_, Port}}, Module, Effect, none) ->
    [Effect, ".port == ", Module, "::OutputPort::", xls_names:enum_member(Port)];
route_condition(#{actor_index := Actors}, #{source := {Id, Port}}, Module, Effect, Slot) ->
    #{slot := ActorSlot} = maps:get(Id, Actors),
    ["(", Slot, " == u32:", n(ActorSlot), " && ", Effect, ".port == ",
        Module, "::OutputPort::", xls_names:enum_member(Port), ")"].

%% Wraps a frame in the representation expected by its destination lane.
-spec lane_value(map(),string()) -> iodata().
lane_value(Lane, Effect) -> lane_frame_value(Lane, [Effect, ".frame"]).

%% Declares the destination-specific representation of a routing channel.
-spec lane_argument(map()) -> iodata().
lane_argument(Lane = #{type := Type}) -> [lane_name(Lane), ": chan<", Type, "> out"].
%% Builds a unique generated name for a source-to-recipient lane.
-spec lane_name(map()) -> [string(),...].
lane_name(#{index := I}) -> ["lane_", n(I), "_out"].

%% One credit is retained across empty polls; startup frames precede the first
%% routed receive. A startup-only actor does not need a dummy connected input.
-spec direct_ingress(map()) -> iodata().
direct_ingress(#{direct_collection := exclusive_epoch, index := I, startup := Frames}) ->
    [proc_header(["DirectStartup", n(I)], ["frame_out: chan<axis::Frame> out"], ["frame_out"]),
        "  init { u32:0 }\n  next(index: u32) {\n",
        "    let frame = match index {\n",
        [["      u32:", n(J), " => ", frame(Frame), ",\n"] || {J, Frame} <- lists:enumerate(0, Frames)],
        "      _ => zero!<axis::Frame>(),\n    };\n",
        "    let active = index < u32:", n(length(Frames)), ";\n",
        "    let _sent = send_if(join(), frame_out, active, frame);\n",
        "    index + (active as u32)\n  }\n}\n\n"];
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

%% Selects among external ingress frames without duplicating acceptance.
-spec ingress_poll(non_neg_integer()) -> iodata().
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

%% Emits the finite per-instance startup sequence under backpressure.
-spec startup_proc(map()) -> iodata().
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

%% Encodes a typed startup message as a DSLX frame literal.
-spec frame(map()) -> iodata().
frame(#{tag := Tag, payload := Payload}) ->
    ["axis::pack(u8:", n(Tag), ", ", Payload, ")"].

%% Declares proc channels and retains them in configuration order.
-spec proc_header([string(),...],[[any(),...],...],[[[any()] | 1 .. ((1 bsl 8) - 1),...],...]) -> iodata().
proc_header(Name, Arguments, Names) ->
    ["proc ", Name, " {\n", [["  ", Argument, ";\n"] || Argument <- Arguments],
        "  config(\n    ", lists:join(",\n    ", Arguments), "\n  ) {\n    ",
        tuple(Names), "\n  }\n"].

%% Connects actor services, routers, external ports and startup producers.
-spec top_proc(map()) -> iodata().
top_proc(Spec = #{direct := Direct, schedulers := Schedulers, units := Units,
        effect_window_domains := Domains}) ->
    Ports = top_ports(Spec),
    Names = [Name || {Name, _} <- Ports],
    ok = xls_actor_observation:validate_channels(Names),
    ["pub proc Top {\n", [["  ", Argument, ";\n"] || {_, Argument} <- Ports],
        "  config(\n    ", lists:join(",\n    ", [A || {_, A} <- Ports]), "\n  ) {\n",
        [unit_channels(Unit) || Unit <- Units],
        external_channels(Spec),
        xls_effect_window_dslx:channels(Domains),
        xls_effect_window_dslx:spawn(Domains),
        [direct_spawn(Spec, Actor) || Actor <- Direct],
        [scheduler_spawn(Spec, Scheduler) || Scheduler <- Schedulers],
        [router_spawn(Spec, Unit) || Unit <- Units], external_spawns(Spec),
        "    ", tuple(Names), "\n  }\n  init { () }\n  next(state: ()) { state }\n}\n"].

%% Lists the externally visible channels of the generated composition.
-spec top_ports(map()) -> [any()].
top_ports(Spec = #{schedulers := Schedulers, externals := Externals, ingresses := Ingresses}) ->
    Ram = lists:append([lists:zip(xls_scheduler_ram_dslx:names(all, [Stem, "_"], Group),
        xls_scheduler_ram_dslx:parameters(all, [Stem, "_"], [Module, "::"], Group)) ||
        Group = #{stem := Stem, module_name := Module} <- Schedulers]),
    Mailbox = lists:zip(xls_scheduler_observation:names(Spec),
        xls_scheduler_observation:arguments(Spec)),
    External = [{Name, [Name, ": chan<axis::Frame> out"]} ||
        #{output_name := Name} <- Externals],
    Inputs = [{Name, [Name, ": chan<hls_spatial_router::SpatialFrame> in"]}
        || #{input_name := Name} <- Ingresses],
    Ram ++ Mailbox ++ xls_collection_observation:top_ports(Schedulers) ++ Inputs ++ External ++ debug_ports(Spec).

%% Lists optional actor and mailbox observation outputs.
-spec debug_ports(map()) -> [{[any(),...],[any(),...]}].
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
-spec unit_channels(map()) -> iodata().
unit_channels(#{kind := ingress}) -> [];
unit_channels(#{kind := direct, direct_collection := exclusive_epoch, stem := Stem,
        module_name := Module, egress_depth := EgressDepth, inbound := Inbound}) ->
    [channel([Stem, "_startup"], "axis::Frame", none, "CHANNEL_DEPTH"),
     channel([Stem, "_egress"], [Module, "::Egress"], none, ["u32:", n(EgressDepth)]),
     channel([Stem, "_requests"], "axis::Frame", length(Inbound), "CHANNEL_DEPTH")];
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
        channel([Stem, "_egress"], [Module, "::ScheduledEffects"], none,
            ["u32:", n(xls_shared_codegen:publication_depth())])].

%% Declares a channel with its representation and bounded queue depth.
-spec channel([any(),...],[any(),...],'none' | non_neg_integer(),[string() | 65 | 67 | 68 | 69 | 72 | 76 | 78 | 80 | 84 | 95,...]) -> iodata().
channel(Stem, Type, Count, Depth) ->
    ["    let (", Stem, "_p, ", Stem, "_c) = chan<", Type, ", ", Depth, ">",
        case Count of none -> []; _ -> ["[u32:", n(Count), "]"] end,
        "(\"", Stem, "\");\n"].

%% Connects one dedicated actor to its input and output lanes.
-spec direct_spawn(map(),map()) -> iodata().
direct_spawn(Spec, #{direct_collection := exclusive_epoch, index := I, stem := Stem,
        module_name := Module, inbound := Inbound, startup := Frames, debug := Debug}) ->
    ["    spawn ", Module, "::CollectionService<u32:", n(length(Inbound)), ", u32:", n(length(Frames)), ">(",
        Stem, "_requests_c, ", Stem, "_startup_c, ", Stem, "_egress_p",
        xls_actor_observation:spawn_argument(Spec, Debug), ");\n",
        "    spawn DirectStartup", n(I), "(", Stem, "_startup_p);\n"];
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

%% Connects a shared service, executor and RAM interfaces.
-spec scheduler_spawn(map(),map()) -> iodata().
scheduler_spawn(Spec, Group = #{stem := Stem, index := I, module_name := Module,
        slot_count := Slots, inbound := Inbound, startup := Startup}) ->
    [case Startup of
        [] -> [];
        _ -> ["    spawn SchedulerStartup", n(I), "(", Stem, "_startup_p);\n"]
    end,
        "    spawn ", Module, "::SharedService<u32:", n(Slots), ", u32:",
        n(length(Inbound) + 1), ", u32:", n(length(Startup)), ", u32:", n(I), ">(\n",
        "      ", Stem, "_requests_c, ", Stem, "_startup_c, ", Stem, "_egress_p,\n      ",
        lists:join(", ", xls_scheduler_ram_dslx:names(all, [Stem, "_"], Group)),
        xls_scheduler_observation:spawn_argument(Spec, Stem),
        xls_collection_observation:spawn_argument(Group), ");\n"].

%% Connects a unit's ordered output to its topology router.
-spec router_spawn(map(),map()) -> iodata().
router_spawn(Spec, #{kind := ingress, index := I, input_name := Name, outbound := Lanes}) ->
    ["    spawn IngressRouter", n(I), "(", Name,
        [[", ", lane_producer(Spec, Lane)] || Lane <- Lanes], ");\n"];
router_spawn(Spec, #{kind := direct, index := I, stem := Stem, outbound := Lanes}) ->
    ["    spawn ActorRouter", n(I), "(", Stem, "_egress_c",
        [[", ", lane_producer(Spec, Lane)] || Lane <- Lanes], ");\n"];
router_spawn(Spec, Scheduler = #{kind := scheduler, index := I, stem := Stem,
        outbound := Lanes, inbound := Inbound}) ->
    ["    spawn SchedulerRouter", n(I), "(", Stem, "_egress_c, ", Stem,
        "_requests_p[u32:", n(length(Inbound)), "]",
        [[", ", lane_producer(Spec, Lane)] || Lane <- Lanes],
        ", ", lists:join(", ", xls_effect_window_dslx:arguments(
            maps:get(effect_window_domains, Spec), Scheduler)), ");\n"].

%% Selects the producer endpoint for a physical routing lane.
-spec lane_producer(map(),map()) -> iodata().
lane_producer(#{units := Units}, Lane = #{destination := {external, _}}) ->
    external_lane_producer(Lane, Units);
lane_producer(#{units := Units}, #{index := I, destination := Destination}) ->
    Unit = hd([U || U = #{unit := Key} <- Units, Key =:= Destination]),
    #{stem := Stem, inbound := Inbound} = Unit,
    Position = index_of(I, [J || #{index := J} <- Inbound]),
    [Stem, "_requests_p[u32:", n(Position), "]"].

%% External channel positions are assigned from the same globally sorted lanes
%% as both producer wiring and merge generation.
-spec external_lane_producer(map(),[map()]) -> iodata().
external_lane_producer(#{source := Source, recipient := Recipient}, Units) ->
    ExternalLanes = lists:sort([{maps:get(index, L), L} || #{outbound := Lanes} <- Units,
        L = #{recipient := R} <- Lanes, R =:= Recipient]),
    I = index_of(Source, [S || {_, #{source := S}} <- ExternalLanes]),
    {external, Id} = Recipient,
    [external_stem(Id), "_p[u32:", n(I), "]"].

%% Declares source buffers for externally visible outputs.
-spec external_channels(map()) -> iodata().
external_channels(#{externals := Externals, lanes := Lanes}) ->
    [begin
        Count = length([ok || #{recipient := R} <- Lanes, R =:= {external, Id}]),
        case Count of 0 -> error({unconnected_dslx_destination, Id}); _ -> ok end,
        channel(external_stem(Id), "axis::Frame", Count, "CHANNEL_DEPTH")
    end || #{id := Id} <- Externals].

%% Connects buffered sources to each external output arbiter.
-spec external_spawns(map()) -> iodata().
external_spawns(#{externals := Externals, lanes := Lanes}) ->
    [["    spawn frame_transport::FrameArrayMux<u32:",
        n(length([ok || #{recipient := R} <- Lanes, R =:= {external, Id}])), ">(",
        external_stem(Id), "_c, ", Output, ");\n"] ||
        #{id := Id, output_name := Output} <- Externals].

%% Creates a stable generated prefix for an external output.
-spec external_stem(atom() | string()) -> iodata().
external_stem(Id) -> [xls_shared_topology_profile:identifier(Id, external_id), "_lanes"].
%% Returns a zero-based position and fails when the expected item is absent.
-spec index_of(term(),[any()]) -> non_neg_integer().
index_of(Value, List) -> length(lists:takewhile(fun(V) -> V =/= Value end, List)).
%% Formats an integer as a DSLX decimal literal fragment.
-spec n(integer()) -> string().
n(I) -> integer_to_list(I).
%% Joins generated values into a DSLX tuple expression.
-spec tuple([any()]) -> iodata().
tuple([]) -> "()";
tuple([Name]) -> ["(", Name, ",)"];
tuple(Names) -> ["(", lists:join(", ", Names), ")"].
%% Orders a generated operation after every listed token dependency.
-spec join_tokens([[[any()] | 95 | 97 | 103 | 107 | 110 | 111 | 114 | 116,...],...]) -> iodata().
join_tokens([Token]) -> Token;
join_tokens(Tokens) -> ["join(", lists:join(", ", Tokens), ")"].
