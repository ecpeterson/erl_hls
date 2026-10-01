-module(xls_collection_observation).
-moduledoc "Publishes authoritative shared collector progress independently of actor RAM writes.".
-export([width/1, declarations/1, proc_field/1, config_parameter/1, config_value/1,
    sample/1, top_ports/1, spawn_argument/1, binding/1, wires/1, ports/1]).

-doc "Returns packed phase, validity and selected reduction progress bits; accumulator values are excluded.".
-spec width(map()) -> pos_integer().
width(Reduction) ->
    Layout = xls_statem_reduction_ir:packed_layout(Reduction),
    26 + lists:sum([maps:get(width, maps:get(N, Layout)) ||
        N <- xls_statem_reduction_ir:observation_fields(Reduction)]).

-doc "Defines the collector observation codec only for opted-in shared actors.".
-spec declarations(map()) -> iodata().
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
sample(Spec) -> optional(Spec, [
    "\n    // Passive committed samples cannot backpressure the scheduler.\n",
    "    let samples = unroll_for! (slot, values): (u32, CollectionObservation[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {\n",
    "      update(values, slot, collection_observation(state.collection_context[slot], state.",
    initialized_field(Spec), "[slot]))\n",
    "    }(zero!<CollectionObservation[ACTOR_COUNT]>());\n",
    "    let _collection_observed = send(join(), collection_debug_out, samples);\n\n"]).

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
        #{reductions := R} = maps:get(Module, hls_actor_interface:from_modules([Module])),
        #{collection_observation_width => width(R) * Slots}
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
enabled(Spec) -> maps:get(admission_reductions, Spec, false) =/= false.
%% Emits nothing for ordinary shared actors.
-spec optional(map(), iodata()) -> iodata().
optional(Spec, Text) -> case enabled(Spec) of true -> Text; false -> [] end.
