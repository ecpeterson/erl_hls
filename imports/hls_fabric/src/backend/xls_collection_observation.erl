-module(xls_collection_observation).
-moduledoc "Publishes authoritative shared collector progress independently of actor RAM writes.".
-export([width/1, layout/1, declarations/1, proc_field/1, config_parameter/1, config_value/1,
    sample/1, state_fields/1, retire/1, top_ports/1, spawn_argument/1, binding/1, wires/1, ports/1]).

-doc "Returns phase, validity and collection metadata width from a legacy reduction descriptor or actor specification; payloads are excluded.".
-spec width(map()) -> pos_integer().
width(#{sites := _} = Reduction) ->
    Layout = xls_statem_reduction_ir:packed_layout(Reduction),
    26 + lists:sum([maps:get(width, maps:get(N, Layout)) ||
        N <- xls_statem_reduction_ir:observation_fields(Reduction)]);
width(Spec) -> 26 + maps:get(width, layout(Spec)).

-doc "Describes live-only collection metadata in the unchanged query reply region; payload bits have no projection.".
-spec layout(map()) -> map().
layout(Spec) ->
    Collection = #{sites := Sites} = xls_actor_observation:collection(Spec),
    #{reduction := Layout = #{fields := Fields}} = xls_actor_observation:layout(Collection),
    Layout#{fields := maps:map(fun(_Name, Field = #{observation_offset := Offset}) ->
        (maps:remove(offset, Field))#{live_offset => Offset - 56 + 26}
    end, Fields), sites => [maps:with([id, phase, name, population, kind], Site) || Site <- Sites]}.

-doc "Defines the collector observation codec only for opted-in shared actors.".
-spec declarations(map()) -> iodata().
declarations(Spec = #{gather_collection := true}) -> indexed_declarations(Spec);
declarations(Spec = #{gathers := Gathers}) when Gathers =/= none ->
    [collection_declarations(Spec), scalar_declarations(Spec)];
declarations(Spec) -> case enabled(Spec) of
    false -> [];
    true ->
        R = maps:get(reductions, Spec), Layout = xls_statem_reduction_ir:packed_layout(R),
        ["pub type CollectionObservation = bits[", integer_to_list(width(R)), "];\n\n",
         "// A coherent committed sample; no callback data or accumulator is exposed.\n",
         "fn collection_observation(machine: ", context_type(Spec), ", initialized: bool) -> CollectionObservation {\n",
         [["  (machine.reduction.", atom_to_list(N), " as bits[",
           integer_to_list(maps:get(width, maps:get(N, Layout))), "]) ++\n"] ||
            N <- lists:reverse(xls_statem_reduction_ir:observation_fields(R))],
         "  initialized ++ machine.failure ++ machine.enter_pending ++ (machine.phase as u8)\n}\n\n"]
end.

%% Indexed banks own progress; the actor copy only identifies its captured active key.
-spec indexed_declarations(map()) -> iodata().
indexed_declarations(Spec) ->
    [collection_declarations(Spec),
     "// Observe only the source-opened bank; provisional successors have no public collection yet.\n",
     "fn indexed_observation_progress(context: IndexedContext) -> GatherProgress {\n",
     "  let found = indexed_find(context.banks, context.machine.gather.progress.key);\n",
     "  let bank = context.banks.banks[found.1 as u32];\n",
     "  let complete = bank.status == indexed_collection_core::Status::SEALED ||\n",
     "    bank.status == indexed_collection_core::Status::BORROWED;\n",
     "  let active = context.actor_opened && found.0 &&\n",
     "    (bank.status == indexed_collection_core::Status::OPEN || complete);\n",
     "  let remaining = unroll_for! (member, count): (u32, u8) in u32:0..INDEXED_CAPACITY {\n",
     "    count + (((bank.members & !bank.seen) >> member) as u1 as u8)\n",
     "  }(u8:0);\n",
     "  if !active {\n",
     "    if context.actor_opened { GatherProgress { failure: indexed_failure(context),\n",
     "      ..context.machine.gather.progress } } else { zero!<GatherProgress>() }\n",
     "  } else {\n",
     "    GatherProgress { status: if complete { GatherStatus::COMPLETE } else { GatherStatus::OPEN },\n",
     "      site: INDEXED_SITE, key: bank.key, expected: bank.members, seen: bank.seen,\n",
     "      remaining, failure: indexed_failure(context) }\n",
     "  }\n}\n\n"].

%% Both storage policies publish the same packed progress union and omit every payload field.
-spec collection_declarations(map()) -> iodata().
collection_declarations(Spec) ->
    #{fields := Fields} = layout(Spec),
    Ordered = lists:sort([{maps:get(live_offset, F), N, maps:get(width, F)} || {N, F} <- maps:to_list(Fields)]),
    ["pub type CollectionObservation = bits[", integer_to_list(width(Spec)), "];\n\n",
     "// Phase and collection fields belong to one committed authority; no element value is read.\n",
     "fn collection_observation(machine: ActorState, gather: GatherProgress, initialized: bool) -> CollectionObservation {\n",
     [["  ", progress_value(N, Bits, Spec), " ++\n"] || {_, N, Bits} <- lists:reverse(Ordered)],
     "  initialized ++ machine.failure ++ machine.enter_pending ++ (machine.phase as u8)\n}\n\n"].

%% A live scalar collector supersedes its last retired RAM copy when no gather is active.
-spec scalar_declarations(map()) -> iodata().
scalar_declarations(Spec) ->
    case maps:get(admission_reductions, Spec, false) of
        false -> [];
        _ ->
            #{fields := Fields} = layout(Spec),
            Ordered = lists:sort([{maps:get(live_offset, F), N, maps:get(width, F)} || {N, F} <- maps:to_list(Fields)]),
            ["// Preserve the scalar collector's coherent phase and live progress.\n",
             "fn scalar_collection_observation(machine: ", context_type(Spec), ", initialized: bool) -> CollectionObservation {\n",
             [["  ", scalar_value(N, ["bits[", integer_to_list(Bits), "]"], maps:get(reductions, Spec)), " ++\n"] ||
                {_, N, Bits} <- lists:reverse(Ordered)],
             "  initialized ++ machine.failure ++ machine.enter_pending ++ (machine.phase as u8)\n}\n\n"]
    end.

%% Match the public one-active-collection vocabulary, placing gather sites after scalar sites.
-spec progress_value(atom(), pos_integer(), map()) -> iodata().
progress_value(Name, Width, Spec) ->
    Type = ["bits[", integer_to_list(Width), "]"],
    Reduction = maps:get(reductions, Spec, none),
    Count = case Reduction of none -> 0; #{sites := Sites} -> length(Sites) end,
    GatherValue = ["(gather.", atom_to_list(Name), " as ", Type, ")"],
    Gather = case {Name, Count} of
        {site, N} when N > 0 -> ["(", GatherValue, " + ", Type, ":", integer_to_list(N), ")"];
        _ -> GatherValue
    end,
    case Reduction of
        none -> Gather;
        _ ->
            Scalar = scalar_value(Name, Type, Reduction),
            ["(if gather.status != GatherStatus::IDLE { ", Gather, " } else { ", Scalar, " })"]
    end.

%% Static scalar populations have no stored runtime expected mask.
-spec scalar_value(atom(), iodata(), map()) -> iodata().
scalar_value(Name, Type, Reduction) ->
    case Name =:= expected andalso not xls_statem_reduction_ir:has_runtime_members(Reduction) of
        true -> ["zero!<", Type, ">()"];
        false -> ["(machine.reduction.", atom_to_list(Name), " as ", Type, ")"]
    end.

-doc "Declares one passive observation array per scheduler.".
-spec proc_field(map()) -> iodata().
proc_field(Spec) -> optional(Spec, "\n  collection_debug_out: chan<CollectionObservation[ACTOR_COUNT]> out;\n").
-doc "Adds the always-accepted observation endpoint to shared configuration.".
-spec config_parameter(map()) -> iodata().
config_parameter(Spec) -> optional(Spec, ",\n      collection_debug_out: chan<CollectionObservation[ACTOR_COUNT]> out").
-doc "Retains the collection observation endpoint in proc configuration.".
-spec config_value(map()) -> iodata().
config_value(Spec) -> optional(Spec, "\n      collection_debug_out,\n").
-doc "Samples prior committed context, independently of this activation's handshakes.".
-spec sample(map()) -> iodata().
sample(Spec = #{gather_collection := true}) -> indexed_sample(Spec);
sample(Spec = #{gathers := Gathers}) when Gathers =/= none -> ordinary_sample(Spec);
sample(Spec) -> optional(Spec, [
    "\n    // Passive committed samples cannot backpressure the scheduler.\n",
    "    let samples = unroll_for! (slot, values): (u32, CollectionObservation[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {\n",
    "      update(values, slot, collection_observation(state.collection_context[slot], state.",
    initialized_field(Spec), "[slot]))\n",
    "    }(zero!<CollectionObservation[ACTOR_COUNT]>());\n",
    "    let _collection_observed = send(join(), collection_debug_out, samples);\n\n"]).

-doc "Retains only committed observation bits for ordinary gathers; unused passive outputs and their shadows are removable by synthesis.".
-spec state_fields(map()) -> iodata().
state_fields(Spec) -> ["  gather_observations: bits[", integer_to_list(width(Spec)), "][ACTOR_COUNT],\n"].

-doc "Captures one retiring ordinary actor's progress without retaining payload or callback state.".
-spec retire(map()) -> iodata().
retire(_Spec) ->
    "        let gather_observations = if retire_valid {\n"
    "          update(retired.gather_observations, result.slot,\n"
    "            collection_observation(resolved.machine, resolved.machine.gather.progress, true))\n"
    "        } else { retired.gather_observations };\n"
    "        let retired = SharedState<ACTOR_COUNT, PRODUCER_COUNT> { gather_observations, ..retired };\n".

%% The passive sample is coherent with actor retirement and cannot stall application work.
-spec ordinary_sample(map()) -> iodata().
ordinary_sample(Spec) ->
    ["\n    // Uninstrumented shells may eliminate this metadata-only passive observation.\n",
     "    let samples = unroll_for! (slot, values): (u32, CollectionObservation[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {\n",
     "      let observed = state.gather_observations[slot];\n",
     "      update(values, slot, ", ordinary_sample_value(Spec), ")\n",
     "    }(zero!<CollectionObservation[ACTOR_COUNT]>());\n",
     "    let _collection_observed = send(join(), collection_debug_out, samples);\n\n"].

%% A remapped nonidle gather site owns the ordinary shadow; scalar sites use their live collector.
-spec ordinary_sample_value(map()) -> iodata().
ordinary_sample_value(Spec) ->
    case maps:get(admission_reductions, Spec, false) of
        false -> "observed";
        _ ->
            #{reductions := #{sites := Sites}} = Spec,
            #{fields := #{status := #{live_offset := Status}, site := #{live_offset := Site, width := Bits}}} = layout(Spec),
            ["if observed[", integer_to_list(Status), "+:u2] != u2:0 && observed[", integer_to_list(Site),
             "+:bits[", integer_to_list(Bits), "]] >= bits[", integer_to_list(Bits), "]:", integer_to_list(length(Sites)),
             " { observed } else { scalar_collection_observation(state.collection_context[slot], state.",
             initialized_field(Spec), "[slot]) }"]
    end.

%% Prefer indexed progress during its active source collection and preserve scalar collector timing otherwise.
-spec indexed_sample(map()) -> iodata().
indexed_sample(Spec) ->
    ["\n    // Passive committed samples cannot backpressure the scheduler.\n",
     "    let samples = unroll_for! (slot, values): (u32, CollectionObservation[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {\n",
     "      let indexed = state.indexed_context[slot];\n",
     indexed_sample_context(Spec),
     "      let machine = ActorState { failure: hls_failure::first(machine.failure, indexed_failure(indexed)), ..machine };\n",
     "      update(values, slot, collection_observation(machine, indexed_observation_progress(indexed), initialized))\n",
     "    }(zero!<CollectionObservation[ACTOR_COUNT]>());\n",
     "    let _collection_observed = send(join(), collection_debug_out, samples);\n\n"].

%% Exclusive scalar commands publish one activation later; never combine their phase with newer scalar progress.
-spec indexed_sample_context(map()) -> iodata().
indexed_sample_context(#{admission_reductions := exclusive_epoch} = Spec) ->
    ["      let scalar = state.collection_context[slot];\n",
     "      let machine = if indexed.actor_opened { indexed.machine } else {\n",
     "        ActorState { phase: scalar.phase, enter_pending: scalar.enter_pending, failure: scalar.failure,\n",
     "          reduction: scalar.reduction, ..indexed.machine }\n      };\n",
     "      let initialized = if indexed.actor_opened { indexed.initialized } else { state.", initialized_field(Spec), "[slot] };\n"];
indexed_sample_context(#{admission_reductions := true} = Spec) ->
    ["      let machine = if indexed.actor_opened { indexed.machine } else { state.collection_context[slot] };\n",
     "      let initialized = if indexed.actor_opened { indexed.initialized } else { state.", initialized_field(Spec), "[slot] };\n"];
indexed_sample_context(_) ->
    "      let machine = indexed.machine;\n      let initialized = indexed.initialized;\n".

%% Exclusive collectors retain only observation metadata beside the bank.
-spec context_type(map()) -> string().
context_type(#{admission_reductions := exclusive_epoch}) -> "CollectionContext";
context_type(_) -> "ActorState".

%% Both policies retain the same validity bit in the observation wire contract.
-spec initialized_field(map()) -> string().
initialized_field(#{admission_reductions := exclusive_epoch}) -> "collection_owners.initialized";
initialized_field(_) -> "collection_initialized".

-doc "Lists the materialized topology's collector observation endpoints.".
-spec top_ports([map()]) -> [{iodata(), iodata()}].
top_ports(Groups) -> [{[Stem, "_collection_debug_out"],
    [Stem, "_collection_debug_out: chan<", Module, "::CollectionObservation[u32:", integer_to_list(Slots), "]> out"]} ||
    #{stem := Stem, module_name := Module, slot_count := Slots} = G <- Groups, enabled(G)].
-doc "Connects the matching collector observation endpoint to its owning service.".
-spec spawn_argument(map()) -> iodata().
spawn_argument(G = #{stem := Stem}) -> optional(G, [",\n      ", Stem, "_collection_debug_out"]).

-doc "Adds optional observation dimensions to a RAM wrapper binding.".
-spec binding(map()) -> map().
binding(Group) -> case enabled(Group) of
    false -> #{};
    true ->
        #{module := Module, slot_count := Slots} = Group,
        Interface = maps:get(Module, hls_actor_interface:from_modules([Module])),
        Width = case maps:get(gathers, Interface, none) of
            none -> width(maps:get(reductions, Interface));
            _ -> width(Interface)
        end,
        #{collection_observation_width => Width * Slots}
end.
-doc "Declares passive observation wires for the opted-in scheduler bindings.".
-spec wires([map()]) -> iodata().
wires(Bindings) -> [["    wire [", integer_to_list(W - 1), ":0] scheduler_", integer_to_list(I),
    "_collection_debug;\n    wire scheduler_", integer_to_list(I), "_collection_debug_vld;\n"] ||
    #{index := I, collection_observation_width := W} <- Bindings].
-doc "Ties observation readiness high; sampling cannot introduce application backpressure.".
-spec ports([map()]) -> iodata().
ports(Bindings) -> [[",\n        ._scheduler_", integer_to_list(I), "_collection_debug_out(scheduler_", integer_to_list(I), "_collection_debug),\n",
    "        ._scheduler_", integer_to_list(I), "_collection_debug_out_vld(scheduler_", integer_to_list(I), "_collection_debug_vld),\n",
    "        ._scheduler_", integer_to_list(I), "_collection_debug_out_rdy(1'b1)"] ||
    #{index := I, collection_observation_width := _} <- Bindings].

%% Artifact and group validation establish this boolean policy.
-spec enabled(map()) -> boolean().
enabled(Spec) -> maps:get(admission_reductions, Spec, false) =/= false orelse
    maps:get(gather_collection, Spec, false) orelse maps:get(gathers, Spec, none) =/= none.
%% Emits nothing for ordinary shared actors.
-spec optional(map(), iodata()) -> iodata().
optional(Spec, Text) -> case enabled(Spec) of true -> Text; false -> [] end.
