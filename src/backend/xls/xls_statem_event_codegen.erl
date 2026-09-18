-module(xls_statem_event_codegen).
-moduledoc "Renders finite state-machine internal steps without an event FIFO.".
-export([optional/2, functions/1, direct_step/1, shared_dispatch/1]).

-doc "Emits a fragment only for actors declaring finite internal events.".
-spec optional(map(), iodata()) -> iodata().
optional(Spec, Code) -> case maps:get(continuations, Spec, []) =/= [] orelse xls_statem_reply_codegen:enabled(Spec) of
    true -> Code; false -> []
end.

-doc "Emits phase-sensitive internal dispatch and its checked state transition.".
-spec functions(map()) -> iodata().
functions(Spec = #{data_name := DataName, internal_steps := Steps, reductions := Reduction}) ->
    optional(Spec, ["fn dispatch_internal(event: u8, phase: Phase, data: ", xls_names:record_type(DataName),
     ") -> (Phase, ", xls_names:record_type(DataName), ", Directive, u1, hls_failure::Code, u8", xls_statem_reply_codegen:optional(Spec, ", u64, axis::Frame, bool"), ") {\n",
     "  match (event, phase) {\n",
     [["    (u8:", integer_to_list(Event), ", Phase::", xls_names:enum_member(Phase), ") => {\n", Body, Value, "\n    },\n"]
         || #{event := Event, phase := Phase, body := Body, result := Value} <- Steps],
     "    _ => (phase, data, Directive::FAIL, u1:0, hls_failure::INVALID_MESSAGE, u8:0", xls_statem_reply_codegen:optional(Spec, ", u64:0, zero!<axis::Frame>(), true"), "),\n",
     "  }\n}\n\n",
     "fn shared_machine_next_event(machine: SharedMachine) -> SharedDispatch {\n",
     "  let (phase, data, directive, repeat_phase, callback_failure, next_event", xls_statem_reply_codegen:optional(Spec, ", reply_from, reply_frame, reply_allowed"), ") =\n",
     "    dispatch_internal(machine.next_event, machine.phase, machine.data);\n",
     "  let invalid = directive == Directive::POSTPONE ||\n",
     "    (repeat_phase && (directive != Directive::CONSUME || phase != machine.phase));\n",
     "  let boundary = phase != machine.phase || repeat_phase;\n",
     "  let incomplete = ", case Reduction of none -> "false"; _ ->
         "boundary && directive != Directive::FAIL && machine.reduction.status == ReductionStatus::OPEN" end, ";\n",
     "  let effective = !invalid && !incomplete;\n",
     "  let failure = hls_failure::dispatch(false, invalid, incomplete, effective, callback_failure);\n",
     xls_statem_reply_codegen:optional(Spec, ["  let (reply_book, response, response_valid) = hls_reply::complete(\n",
         "    machine.replies, reply_from, reply_frame, reply_allowed, hls_failure::kind(failure) as u32);\n",
         "  let contract_fault = failure == hls_failure::NONE && reply_book.failure == u32:15;\n",
         "  let failure = hls_failure::first(failure, if reply_book.failure != u32:0 { hls_failure::REPLY_CONTRACT } else { hls_failure::NONE });\n"]),
     "  let failed = hls_failure::failed(failure);\n",
     "  SharedDispatch {\n",
     "    machine: SharedMachine {\n",
     "      phase: if effective", xls_statem_reply_codegen:optional(Spec, " && !contract_fault"), " { phase } else { machine.phase },\n",
     "      entered_from: if effective && boundary { machine.phase } else { machine.entered_from },\n",
     "      data: if effective", xls_statem_reply_codegen:optional(Spec, " && !contract_fault"), " { data } else { machine.data },\n",
     xls_statem_reply_codegen:optional(Spec, "      replies: reply_book,\n"),
     "      next_event: if effective && !failed { next_event } else { u8:0 },\n",
     "      enter_pending: effective && boundary && !failed, failure, ..machine\n",
     "    },\n",
     "    phase_boundary: effective && boundary && !failed,\n",
     xls_statem_reply_codegen:optional(Spec, "    reply: response, reply_valid: response_valid,\n"),
     "    ..zero!<SharedDispatch>()\n",
     "  }\n}\n\n"]).

-doc "Runs one private step after phase entry, retaining every mailbox slot.".
-spec direct_step(map()) -> iodata().
direct_step(Spec) -> optional(Spec, ["""
      } else if machine.next_event != u8:0 {
    """, "    let step = ", "shared_machine_next_event(shared_machine(machine));\n",
        xls_statem_reply_codegen:optional(Spec, "    let step = if step.reply_valid && !egress_ready { SharedDispatch { machine: shared_machine(machine), ..zero!<SharedDispatch>() } } else { step };\n"), """
        let slots = unroll_for! (i, slots): (u32, MailboxSlot[MAILBOX_DEPTH]) in u32:0..MAILBOX_DEPTH {
          update(slots, i, MailboxSlot {
            postponed: if step.phase_boundary { false } else { slots[i].postponed }, ..slots[i]
          })
        }(machine.slots);
        MachineStep {
          machine: Machine {
            phase: step.machine.phase, entered_from: step.machine.entered_from,
            data: step.machine.data, next_event: step.machine.next_event,
            enter_pending: step.machine.enter_pending, failure: step.machine.failure,
    """, xls_statem_reply_codegen:optional(Spec, "        replies: step.machine.replies,\n"), """
            slots, ..machine
          },
    """, xls_statem_reply_codegen:optional(Spec, ["      egress: Egress { port: OutputPort::", reply_port(Spec), ", frame: step.reply }, egress_valid: step.reply_valid,\n"]), """
          ..zero!<MachineStep>()
        }
    """]).

-doc "Selects a named internal step before ordinary mailbox dispatch, after entry.".
-spec shared_dispatch(map()) -> iodata().
shared_dispatch(Spec = #{reductions := Reduction, shared_service := Mode}) ->
    Ordinary = xls_statem_reduction_service_codegen:shared_executor_dispatch(Reduction, Mode),
    case maps:get(continuations, Spec, []) =/= [] orelse xls_statem_reply_codegen:enabled(Spec) of
        false -> Ordinary;
        true -> ["  let dispatched = ",
              xls_statem_reply_codegen:optional(Spec, "if hls_failure::failed(machine.failure) { shared_machine_reply_failure(machine, request.frame, request.received) } else "),
              "if !hls_failure::failed(machine.failure) &&\n",
              "      !machine.enter_pending && machine.next_event != u8:0 {\n",
              "    shared_machine_next_event(machine)\n  } else {\n", Ordinary,
              "    dispatched\n  };\n"]
    end.

%% Port lookup stays harmless for actors with no reply facility.
-spec reply_port(map()) -> iodata().
reply_port(#{retained_calls := #{port := Port}}) -> xls_names:enum_member(Port);
reply_port(_) -> [].
