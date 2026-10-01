-module(xls_statem_codegen).
-moduledoc false.
-export([emit/1, body/1]).
-define(REDUCTION_SERVICE, xls_statem_reduction_service_codegen).
%% Validated callback artifact; execution options do not alter its semantics.
-type spec() :: xls_actor_codegen:spec().

-doc "Renders a dedicated actor with register-backed state, mailbox and ordered effects.".
-spec emit(spec()) -> iolist().
emit(Spec) ->
    xls_actor_codegen:emit(Spec, [direct_mailbox_observation],
        body(Spec)).

-doc "Renders dedicated mailbox and service storage around the common callback declarations.".
-spec body(spec()) -> iodata().
body(Spec) ->
        [machine_declarations(Spec), xls_actor_observation:declarations(Spec),
         initial_machine(Spec), machine_step_function(Spec), service(Spec),
         egress_demux(Spec), top(Spec)].
%% Stores one actor's mailbox and currently visible execution state in registers.
-spec machine_declarations(spec()) -> iodata().
machine_declarations(#{capacity := Capacity, data_name := DataName} = Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    DataStruct = xls_names:record_type(DataName),
    [
        "type MailboxSlot = direct_mailbox_observation::Slot;\n\n",
        "struct Machine {\n",
        "  phase: Phase,\n",
        "  entered_from: Phase,\n",
        "  data: ", DataStruct, ",\n",
        ?REDUCTION_SERVICE:machine_state_field(Reductions),
        "  slots: MailboxSlot[", integer_to_list(Capacity), "],\n",
        "  occupied: u8,\n",
        xls_statem_reply_codegen:optional(Spec, "  replies: ReplyBook,\n"),
        xls_statem_event_codegen:optional(Spec, "  next_event: u8,\n"),
        "  enter_pending: u1,\n",
        "  entry_effect_index: u8,\n",
        "  // Reserves one queue slot for the frame being assembled.\n",
        "  admission_pending: u1,\n",
        "  // A failed service ignores input until reset.\n",
        "  failure: hls_failure::Code,\n",
        "}\n\n",
        "struct MachineStep {\n",
        "  machine: Machine,\n",
        "  egress: Egress,\n",
        "  egress_valid: u1,\n",
        "  admission_valid: u1,\n",
        "}\n\n"
    ].
%% Initializes mailbox storage around the common compile-time actor initializer.
-spec initial_machine(spec()) -> iodata().
initial_machine(Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    ["fn initial_machine() -> Machine {\n  let machine = initial_actor_state();\n",
     "  Machine { phase: machine.phase, entered_from: machine.entered_from, data: machine.data,\n",
     ?REDUCTION_SERVICE:machine_state_copy_field(Reductions),
     xls_statem_reply_codegen:optional(Spec, "    replies: machine.replies,\n"),
     xls_statem_event_codegen:optional(Spec, "    next_event: machine.next_event,\n"),
     "    enter_pending: machine.enter_pending, failure: machine.failure, ..zero!<Machine>() }\n}\n\n",
        "fn actor_state(machine: Machine) -> ActorState {\n",
        "  ActorState {\n",
        "    phase: machine.phase,\n",
        "    entered_from: machine.entered_from,\n",
        "    data: machine.data,\n",
        ?REDUCTION_SERVICE:machine_state_copy_field(Reductions),
        xls_statem_reply_codegen:optional(Spec, "    replies: machine.replies,\n"),
        xls_statem_event_codegen:optional(Spec, "    next_event: machine.next_event,\n"),
        "    enter_pending: machine.enter_pending,\n",
        "    failure: machine.failure,\n",
        "  }\n",
        "}\n\n"
    ].

%%%
%%% Dedicated actor service
%%%

%% Advances one singleton activation without committing a blocked reply.
-spec machine_step_function(spec()) -> iodata().
machine_step_function(#{
    capacity := Capacity,
    message_names := MessageNames,
    message_words := MessageWords
} = Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    #{
        eligible_bindings := EligibleBindings,
        found_expression := FoundExpression,
        selected_expression := SelectedExpression,
        compaction_bindings := CompactionBindings,
        compacted_array := CompactedArray,
        unblocked_array := UnblockedArray
    } = queue_expansion(Capacity),
    [
        "fn machine_step(\n",
        "    machine: Machine, frame: axis::Frame, received: u1,\n",
        "    egress_ready: u1) -> MachineStep {\n",
        "  if hls_failure::failed(machine.failure) {\n",
        direct_failure_step(Spec),
        ?REDUCTION_SERVICE:direct_after_failed(Reductions, Capacity),
        machine_entry_step(Reductions),
        xls_statem_event_codegen:direct_step(Spec),
        "  } else {\n",
        "      let tag_ok = ",
        xls_actor_codegen:input_tag_ok(Spec, MessageNames, MessageWords), ";\n",
        "      let accepted = received && tag_ok;\n",
        "      let invalid_input = received && !tag_ok;\n",
        "      let incoming_slot = MailboxSlot {\n",
        "        frame,\n",
        "        ..zero!<MailboxSlot>()\n",
        "      };\n",
        "      let admitted_slots = if accepted {\n",
        "        update(machine.slots, machine.occupied as u32, incoming_slot)\n",
        "      } else { machine.slots };\n",
        "      let admitted_occupied = machine.occupied + (accepted as u8);\n",
        EligibleBindings,
        "      let found = ", FoundExpression, ";\n",
        "      let selected = ", SelectedExpression, ";\n",
        "      let selected_frame = admitted_slots[selected as u32].frame;\n",
        "      let dispatchable = found && !invalid_input;\n",
        xls_statem_reply_codegen:admit(Spec, "selected_frame", "dispatchable"),
        ?REDUCTION_SERVICE:direct_dispatch_bindings(Reductions, Spec),
        "      let invalid_repeat = ", xls_statem_reply_codegen:optional(Spec, "(dispatchable && is_call(selected_frame.header.op) && directive == Directive::POSTPONE) || "), "dispatchable && repeat_phase &&\n",
        "        (directive != Directive::CONSUME ||\n",
        "         next_phase != machine.phase);\n",
        ?REDUCTION_SERVICE:direct_effective_binding(Reductions),
        "      let selected_slot = admitted_slots[selected as u32];\n",
        "      let postponed_slot = MailboxSlot {\n",
        "        postponed: u1:1,\n",
        "        ..selected_slot\n",
        "      };\n",
        "      let postponed_slots = update(\n",
        "        admitted_slots, selected as u32, postponed_slot);\n",
        CompactionBindings,
        "      let compacted_slots = ", CompactedArray, ";\n",
        "      let transition_slots = match directive {\n",
        "        Directive::CONSUME => compacted_slots,\n",
        "        Directive::POSTPONE => postponed_slots,\n",
        "        Directive::FAIL => admitted_slots,\n",
        "      };\n",
        "      let candidate_slots = if effective {\n",
        "        transition_slots\n",
        "      } else { admitted_slots };\n",
        "      let candidate_occupied = if effective &&\n",
        "          directive == Directive::CONSUME {\n",
        "        admitted_occupied - u8:1\n",
        "      } else { admitted_occupied };\n",
        "      let candidate_phase = if effective {\n",
        "        next_phase\n",
        "      } else { machine.phase };\n",
        "      let candidate_data = if effective {\n",
        "        next_data\n",
        "      } else { machine.data };\n",
        "      let phase_changed = candidate_phase != machine.phase;\n",
        "      let phase_boundary = phase_changed ||\n",
        "        (effective && repeat_phase);\n",
        "      let unblocked_slots = ", UnblockedArray, ";\n",
        "      let final_slots = if phase_boundary {\n",
        "        unblocked_slots\n",
        "      } else { candidate_slots };\n",
        ?REDUCTION_SERVICE:direct_failed_binding(Reductions),
        xls_statem_reply_codegen:finish(Spec, "selected_frame"),
        xls_actor_codegen:reply_failure_binding(Spec),
        "      let admission_pending =\n",
        "        machine.admission_pending && !received;\n",
        "      // Preserve occupied + admission_pending <= capacity.\n",
        "      let reserve = !failed && !received && !admission_pending &&\n",
        "        candidate_occupied < MAILBOX_CAPACITY;\n",
        "      let next_machine = Machine {\n",
        "        phase: ", xls_statem_reply_codegen:optional(Spec, "if contract_fault { machine.phase } else { "), "candidate_phase", xls_statem_reply_codegen:optional(Spec, " }"), ",\n",
        "        entered_from: if phase_boundary {\n",
        "          machine.phase\n",
        "        } else { machine.entered_from },\n",
        "        data: ", xls_statem_reply_codegen:optional(Spec, "if contract_fault { machine.data } else { "), "candidate_data", xls_statem_reply_codegen:optional(Spec, " }"), ",\n",
        xls_statem_reply_codegen:optional(Spec, "        replies: reply_book,\n"),
        xls_statem_event_codegen:optional(Spec, "        next_event: if effective && !failed { next_event } else { u8:0 },\n"),
        ?REDUCTION_SERVICE:direct_reduction_field(Reductions),
        "        slots: ", xls_statem_reply_codegen:optional(Spec, "if failed && dispatchable { compacted_slots } else { "), "final_slots", xls_statem_reply_codegen:optional(Spec, " }"), ",\n",
        "        occupied: ", xls_statem_reply_codegen:optional(Spec, "if failed && dispatchable { admitted_occupied - u8:1 } else { "), "candidate_occupied", xls_statem_reply_codegen:optional(Spec, " }"), ",\n",
        "        enter_pending: effective && phase_boundary && !failed,\n",
        "        admission_pending: admission_pending || reserve,\n",
        "        failure,\n",
        "        ..machine\n",
        "      };\n",
        xls_statem_reply_codegen:optional(Spec, ["      if response_valid && !egress_ready {\n",
            "        MachineStep { machine: Machine { slots: admitted_slots, occupied: admitted_occupied,\n",
            "          admission_pending: machine.admission_pending && !received, ..machine }, ..zero!<MachineStep>() }\n",
            "      } else {\n"]),
        "      MachineStep {\n",
        "        machine: next_machine,\n",
        "        admission_valid: reserve,\n",
        direct_reply_effect(Spec),
        "        ..zero!<MachineStep>()\n",
        "      }\n",
        xls_statem_reply_codegen:optional(Spec, "      }\n"),
        "  }\n",
        "}\n\n"
    ].

machine_entry_step(Reductions) ->
    [
        "    let outcome = enter(\n",
        "      machine.entered_from, machine.phase, machine.data);\n",
        "    let effects = outcome.effects;\n",
        "    let effect_count = entry_effect_count(effects);\n",
        "    let has_effect = machine.entry_effect_index < effect_count;\n",
        "    let effect = entry_effect(\n",
        "      effects, machine.entry_effect_index);\n",
        ?REDUCTION_SERVICE:direct_entry_bindings(Reductions),
        "    let can_advance = !entry_failed && (!has_effect || egress_ready);\n",
        "    let next_effect_index = machine.entry_effect_index +\n",
        "      ((has_effect && can_advance) as u8);\n",
        "    let entry_complete = can_advance &&\n",
        "      next_effect_index >= effect_count;\n",
        "    let reserve = entry_complete &&\n",
        "      !machine.admission_pending &&\n",
        "      machine.occupied < MAILBOX_CAPACITY;\n",
        "    let advanced_machine = Machine {\n",
        "      data: if entry_complete { outcome.data } else { machine.data },\n",
        ?REDUCTION_SERVICE:direct_entry_reduction_field(Reductions),
        "      enter_pending: !entry_complete && !entry_failed,\n",
        "      entry_effect_index: if entry_complete {\n",
        "        u8:0\n",
        "      } else { next_effect_index },\n",
        "      admission_pending: machine.admission_pending || reserve,\n",
        "      failure: entry_failure,\n",
        "      ..machine\n",
        "    };\n",
        "    MachineStep {\n",
        "      machine: if can_advance || entry_failed { advanced_machine }\n",
        "        else { machine },\n",
        "      egress: effect,\n",
        "      egress_valid: has_effect && can_advance,\n",
        "      admission_valid: reserve,\n",
        "    }\n"
    ].

%% Connects singleton admissions and output readiness to the actor step.
-spec service(spec()) -> iodata().
service(Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    [
        "pub proc Service {\n",
        "  req_in: chan<axis::Frame> in;\n",
        "  egress_out: chan<Egress> out;\n",
        "  admission_out: chan<u1> out;\n",
        xls_actor_observation:proc_field(Spec),
        "\n",
        "  config(req_in: chan<axis::Frame> in,\n",
        "         egress_out: chan<Egress> out,\n",
        "         admission_out: chan<u1> out",
        xls_actor_observation:config_parameter(Spec), ") {\n",
        "    (req_in, egress_out, admission_out",
        xls_actor_observation:config_value(Spec), ")\n",
        "  }\n\n",
        "  init { (initial_machine(), u1:0) }\n\n",
        "  next(state: (Machine, u1)) {\n",
        "    let (machine, admission_valid) = state;\n",
        xls_actor_observation:sample(Spec),
        "    // Reserve capacity in machine_step, then publish its credit\n",
        "    // from registered state to break receive/admission feedback.\n",
        "    // Its token is independent of the current receive and egress.\n",
        "    let _admission_tok = send_if(\n",
        "      join(), admission_out, admission_valid, u1:1);\n",
        case xls_statem_reply_codegen:enabled(Spec) of
            true -> ["    let receive_enabled = machine.admission_pending && (hls_failure::failed(machine.failure) || (!machine.enter_pending && machine.next_event == u8:0", ?REDUCTION_SERVICE:direct_receive_gate(Reductions), "));\n"];
            false -> [
        "    let receive_enabled = !hls_failure::failed(machine.failure) &&\n",
        "      !machine.enter_pending && machine.admission_pending",
        xls_statem_event_codegen:optional(Spec, " && machine.next_event == u8:0"),
        ?REDUCTION_SERVICE:direct_receive_gate(Reductions), ";\n"
            ]
        end,
        "    let (tok, frame, received) = recv_if_non_blocking(\n",
        "      join(), req_in, receive_enabled, zero!<axis::Frame>());\n",
        "    let stepped = machine_step(machine, frame, received, u1:1);\n",
        "    let _egress_tok = send_if(\n",
        "      tok, egress_out, stepped.egress_valid, stepped.egress);\n",
        "    (stepped.machine, stepped.admission_valid)\n",
        "  }\n",
        "}\n\n"
    ].

%% Each selection step is named so large mailboxes do not exhaust XLS parser nesting.
-spec queue_expansion(1..255) -> map().
queue_expansion(Capacity) ->
    Indexes = lists:seq(0, Capacity - 1),
    EligibleBindings = [eligible_binding(Index) || Index <- Indexes],
    FoundExpression = join_with(" || ", [
        ["eligible_", integer_to_list(Index)] || Index <- Indexes
    ]),
    SelectedExpression = ["{\n",
        "        let selected_", integer_to_list(Capacity), " = u8:0;\n",
        [["        let selected_", integer_to_list(Index), " = if eligible_",
            integer_to_list(Index), " { u8:", integer_to_list(Index),
            " } else { selected_", integer_to_list(Index + 1), " };\n"]
            || Index <- lists:reverse(Indexes)],
        "        selected_0\n      }"],
    CompactionBindings = [
        compaction_binding(Index, Capacity) || Index <- Indexes
    ],
    CompactedArray = [
        "[",
        join_with(", ", [
            ["compacted_", integer_to_list(Index)] || Index <- Indexes
        ]),
        "]"
    ],
    UnblockedArray = [
        "[",
        join_with(",\n        ", [
            [
                "MailboxSlot { postponed: u1:0, ..candidate_slots[",
                integer_to_list(Index), "] }"
            ]
            || Index <- Indexes
        ]),
        "]"
    ],
    #{
        eligible_bindings => EligibleBindings,
        found_expression => FoundExpression,
        selected_expression => SelectedExpression,
        compaction_bindings => CompactionBindings,
        compacted_array => CompactedArray,
        unblocked_array => UnblockedArray
    }.

eligible_binding(Index) ->
    [
        "      let eligible_", integer_to_list(Index), " = u8:",
        integer_to_list(Index), " < admitted_occupied &&\n",
        "        !admitted_slots[", integer_to_list(Index),
        "].postponed;\n"
    ].

compaction_binding(Index, Capacity) when Index + 1 < Capacity ->
    [
        "      let compacted_", integer_to_list(Index), " = if u8:",
        integer_to_list(Index), " < selected {\n",
        "        admitted_slots[", integer_to_list(Index), "]\n",
        "      } else if u8:", integer_to_list(Index + 1),
        " < admitted_occupied {\n",
        "        admitted_slots[", integer_to_list(Index + 1), "]\n",
        "      } else { zero!<MailboxSlot>() };\n"
    ];
compaction_binding(Index, _Capacity) ->
    [
        "      let compacted_", integer_to_list(Index),
        " = zero!<MailboxSlot>();\n"
    ].

%%%
%%% Top-level streams
%%%

egress_demux(#{output_names := OutputNames}) ->
    [
        "proc EgressDemux {\n",
        "  egress_in: chan<Egress> in;\n",
        [
            ["  ", name(Port), "_out: chan<axis::Frame> out;\n"]
            || Port <- OutputNames
        ],
        "\n  config(egress_in: chan<Egress> in,\n",
        [
            ["         ", name(Port), "_out: chan<axis::Frame> out",
                separator(Index, length(OutputNames)), "\n"]
            || {Index, Port} <- lists:enumerate(0, OutputNames)
        ],
        "  ) {\n",
        "    (egress_in, ",
        join_with(", ", [[name(Port), "_out"] || Port <- OutputNames]),
        ")\n",
        "  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, egress) = recv(join(), egress_in);\n",
        "    let _send_tok = match egress.port {\n",
        [
            [
                "      OutputPort::", xls_names:enum_member(Port), " =>\n",
                "        send(tok, ", name(Port),
                "_out, egress.frame),\n"
            ]
            || Port <- OutputNames
        ],
        "    };\n",
        "    state\n",
        "  }\n",
        "}\n\n"
    ].

top(Spec = #{output_names := OutputNames}) ->
    [
        "pub proc Top {\n",
        "  ext_recv: chan<axis::Beat> in;\n",
        [
            ["  ", name(Port), "_send: chan<axis::Beat> out;\n"]
            || Port <- OutputNames
        ],
        xls_actor_observation:proc_field(Spec),
        "\n  config(ext_recv: chan<axis::Beat> in,\n",
        [
            ["         ", name(Port), "_send: chan<axis::Beat> out,\n"]
            || Port <- lists:droplast(OutputNames)
        ],
        "         ", name(lists:last(OutputNames)),
        "_send: chan<axis::Beat> out",
        xls_actor_observation:config_parameter(Spec), ") {\n",
        "    let (req_p, req_c) = chan<axis::Frame, u32:1>(\"req\");\n",
        "    let (admit_p, admit_c) = chan<u1, u32:1>(\"admit\");\n",
        "    let (egress_p, egress_c) =\n",
        "      chan<Egress, EGRESS_DEPTH>(\"egress\");\n",
        [
            [
                "    let (", name(Port), "_p, ", name(Port),
                "_c) = chan<axis::Frame, u32:1>(\"", name(Port), "\");\n"
            ]
            || Port <- OutputNames
        ],
        "    spawn axis::ReservedRx(ext_recv, req_p, admit_c);\n",
        "    spawn Service(req_c, egress_p, admit_p",
        xls_actor_observation:spawn_argument(Spec, "actor_debug_out"), ");\n",
        "    spawn EgressDemux(egress_c, ",
        join_with(", ", [[name(Port), "_p"] || Port <- OutputNames]),
        ");\n",
        [
            [
                "    spawn axis::Tx(", name(Port), "_c, ", name(Port),
                "_send);\n"
            ]
            || Port <- OutputNames
        ],
        "    (ext_recv, ",
        join_with(", ", [[name(Port), "_send"] || Port <- OutputNames]),
        xls_actor_observation:config_value(Spec),
        ")\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n"
    ].

%%%
%%% Naming and iodata helpers
%%%

name(Atom) ->
    atom_to_list(Atom).

separator(Index, Count) when Index + 1 < Count -> ",";
separator(_Index, _Count) -> "".

join_with(_Separator, []) ->
    [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].

%% Singleton outputs commit together with their checked callback state.
-spec direct_reply_effect(map()) -> iodata().
direct_reply_effect(Spec = #{retained_calls := #{port := Port}}) ->
    xls_statem_reply_codegen:optional(Spec, ["      egress: Egress { port: OutputPort::", xls_names:enum_member(Port),
        ", frame: response }, egress_valid: response_valid,\n"]);
direct_reply_effect(_) -> [].

%% Failed actors retire outstanding callers serially without executing application code.
-spec direct_failure_step(map()) -> iodata().
direct_failure_step(#{retained_calls := #{port := Port}}) ->
    ["    let admitted_slots = if received { update(machine.slots, machine.occupied as u32, MailboxSlot { frame, ..zero!<MailboxSlot>() }) } else { machine.slots };\n",
     "    let occupied = machine.occupied + received as u8;\n",
     "    let step = actor_reply_failure(actor_state(machine), admitted_slots[u32:0].frame, occupied != u8:0);\n",
     "    let commit = !step.reply_valid || egress_ready;\n",
     "    let consume = step.dispatched && commit;\n",
     "    let remaining = occupied - consume as u8;\n",
     "    let slots = unroll_for! (i, slots): (u32, MailboxSlot[MAILBOX_DEPTH]) in u32:0..MAILBOX_DEPTH {\n",
     "      update(slots, i, if consume && i + u32:1 < occupied as u32 { admitted_slots[i + u32:1] } else { admitted_slots[i] })\n",
     "    }(admitted_slots);\n",
     "    let pending = machine.admission_pending && !received;\n",
     "    let reserve = !pending && !received && remaining < MAILBOX_CAPACITY;\n",
     "    MachineStep { machine: Machine { replies: if commit { step.machine.replies } else { machine.replies },\n",
     "        occupied: remaining, slots, next_event: u8:0, enter_pending: false, admission_pending: pending || reserve, ..machine },\n",
     "      egress: Egress { port: OutputPort::", xls_names:enum_member(Port), ", frame: step.reply },\n",
     "      egress_valid: step.reply_valid && commit, admission_valid: reserve, ..zero!<MachineStep>() }\n"];
direct_failure_step(_) -> "    MachineStep { machine, ..zero!<MachineStep>() }\n".
