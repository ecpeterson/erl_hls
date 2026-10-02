-module(xls_shared_codegen).
-moduledoc false.
-export([emit/1, shared_machine_width/1, shared_machine_width/2, shared_machine_width/3, shared_machine_layout/2, shared_machine_layout/3]).
-define(REDUCTION_SERVICE, xls_shared_reduction_service_codegen).
%% Checked actor artifact augmented with private physical options.
-type spec() :: map().

-doc "Renders RAM-backed shared execution of a validated actor artifact.".
-spec emit(spec()) -> iolist().
emit(Spec) ->
    ok = xls_shared_names:validate(Spec),
    Reductions = maps:get(reductions, Spec, none),
    Mode = maps:get(shared_service, Spec, ordinary),
    xls_actor_codegen:emit(xls_exclusive_collection_codegen:actor_spec(Spec), [bram, mailbox, scheduler, arbitration, std, direct_mailbox_observation] ++ xls_scheduler_observation:imports(Spec) ++ xls_indexed_collection_codegen:imports(Spec),
        [xls_shared_reduction_codegen:declarations(Reductions, Mode),
         xls_exclusive_collection_codegen:declarations(Spec),
         xls_indexed_collection_codegen:declarations(Spec),
         machine_declarations(Spec), xls_state_projection:functions(Spec), machine_codec(Spec),
         xls_shared_collection_codegen:helpers(Spec), xls_indexed_collection_codegen:helpers(Spec), xls_collection_observation:declarations(Spec),
         "fn initial_shared_machine() -> ActorState { initial_actor_state() }\n\n",
         xls_shared_reduction_codegen:functions(Reductions, Mode),
         xls_shared_gather_codegen:helpers(Spec),
         xls_shared_gather_codegen:selection_helpers(Spec),
         scheduled_effect_function(Spec), shared_machine_step_function(Spec),
         shared_executor(Spec), shared_loader(Spec), shared_service(Spec), xls_statem_codegen:body(Spec), xls_direct_collection_codegen:body(Spec)]).
%% Defines accepted-work tickets, RAM row types and scheduler-owned metadata.
-spec machine_declarations(spec()) -> iodata().
machine_declarations(#{capacity := Capacity} = Spec) ->
    DataWidth = xls_state_projection:width(Spec),
    Reductions = maps:get(reductions, Spec, none),
    SharedService = maps:get(shared_service, Spec, ordinary),
    ReductionWidth = xls_statem_reduction_codegen:private_width(Reductions),
    GatherWidth = xls_shared_gather_codegen:storage_width(Spec),
    MachineBits = shared_machine_width(DataWidth, ReductionWidth, GatherWidth) + event_width(Spec) + xls_statem_reply_codegen:width(Spec),
    [
        "pub type MachineBits = bits[", integer_to_list(MachineBits), "];\n\n",
        "pub type MachineRamReadReq = bram::ReadReq;\n",
        "pub type MachineRamReadResp = bram::ReadResp<u32:",
        integer_to_list(MachineBits), ">;\n",
        "pub type MachineRamWriteReq = bram::WriteReq<u32:",
        integer_to_list(MachineBits), ">;\n",
        "pub type MachineRamWriteResp = bram::WriteResp;\n\n",
        "pub type MailboxRamReadReq = mailbox::RamReadReq;\n",
        "pub type MailboxRamReadResp = mailbox::RamReadResp;\n",
        "pub type MailboxRamWriteReq = mailbox::RamWriteReq;\n",
        "pub type MailboxRamWriteResp = mailbox::RamWriteResp;\n\n",
        "pub type ScheduledRequest = mailbox::ScheduledRequest;\n\n",
        "pub struct ScheduledEffects {\n",
        "  slot: u32,\n",
        "  effects: EntryEffects,\n",
        "}\n\n",
        "struct SharedStep {\n",
        "  machine: ActorState,\n",
        "  effects: EntryEffects,\n",
        "  effects_valid: u1,\n",
        "  dispatched: u1,\n",
        "  directive: Directive,\n",
        "  phase_boundary: u1,\n",
        "  egress_blocked: u1,\n",
        "}\n\n",
        "// Immutable selection; actor ownership and result storage are already reserved.\n",
        "struct SharedDispatchTicket {\n",
        "  slot: u32,\n  received: u1,\n  mailbox_index: u8,\n  order_index: u8,\n",
        ?REDUCTION_SERVICE:shared_executor_request_field(Reductions, SharedService),
        xls_shared_collection_codegen:ticket_field(Spec),
        xls_indexed_collection_codegen:ticket_field(Spec),
        "}\n\n",
        "pub struct SharedExecutorRequest {\n",
        xls_indexed_memory_codegen:request_fields(Spec),
        "  slot: u32,\n",
        "  machine: MachineBits,\n",
        "  frame: axis::Frame,\n",
        ?REDUCTION_SERVICE:shared_executor_request_field(
            Reductions, SharedService
        ),
        "  received: u1,\n",
        "  mailbox_index: u8,\n",
        "  order_index: u8,\n",
        "  egress_ready: u1,\n",
        "}\n\n",
        "pub struct SharedExecutorResult {\n",
        "  slot: u32,\n",
        "  machine: MachineBits,\n",
        "  effects: EntryEffects,\n",
        "  effects_valid: u1,\n",
        "  dispatched: u1,\n",
        "  directive: Directive,\n",
        "  phase_boundary: u1,\n",
        "  egress_blocked: u1,\n",
        "  received: u1,\n",
        "  mailbox_index: u8,\n",
        "  order_index: u8,\n",
        "}\n\n",
        "enum SharedPhase : u3 {\n",
        "  BOOT = u3:0,\n",
        "  STARTUP = u3:1,\n",
        "  RUN = u3:2,\n",
        "}\n\n",
        "// XLS channel legalization currently confuses multiple otherwise-\n",
        "// identical SharedService instances connected to different external\n",
        "// RAM ports. INSTANCE_ID distinguishes those specializations; it is\n",
        "// neither actor state nor part of scheduling policy.\n",
        "struct SharedState<ACTOR_COUNT: u32, PRODUCER_COUNT: u32> {\n",
        "  instance_id: u32,\n",
        "  phase: SharedPhase,\n",
        "  in_flight: u1[ACTOR_COUNT],\n",
        ?REDUCTION_SERVICE:shared_state_fields(Reductions, SharedService),
        xls_shared_collection_codegen:state_fields(Spec),
        xls_shared_gather_codegen:state_fields(Spec),
        xls_indexed_collection_codegen:state_fields(Spec),
        xls_indexed_memory_codegen:optional(Spec, "  gather_write_pending: bool,\n"),
        "  completed_valid: u1,\n",
        "  completed: SharedExecutorResult,\n",
        "  admission_cursor: u32,\n",
        "  // Only BOOT and accepted actor selection advance this bounded cursor.\n",
        "  cursor: uN[std::max(u32:1, std::clog2(ACTOR_COUNT))],\n",
        "  startup_seen: u32,\n",
        "  pending: ScheduledRequest[PRODUCER_COUNT],\n",
        "  pending_valid: u1[PRODUCER_COUNT],\n",
        "  occupied: u8[ACTOR_COUNT],\n",
        "  order: u8[", integer_to_list(Capacity), "][ACTOR_COUNT],\n",
        "  used: bool[", integer_to_list(Capacity), "][ACTOR_COUNT],\n",
        "  postponed: u1[", integer_to_list(Capacity), "][ACTOR_COUNT],\n",
        "  // Mailbox work that has not yet been postponed in this phase.\n",
        "  mail_candidates: u1[ACTOR_COUNT],\n",
        "  // Entry work whose effect batch has not yet been classified.\n",
        "  entry_probes: u1[ACTOR_COUNT],\n",
        "  // Entry work known to need the scheduler's batch sequencer.\n",
        "  egress_waiters: u1[ACTOR_COUNT],\n",
        "  egress_busy: u1,\n",
        "  outbox_busy: u1[ACTOR_COUNT],\n",
        "  state_write_pending: u1,\n",
        "  mailbox_write_pending: u1,\n",
        "}\n\n"
    ].

-doc "Returns the packed actor-state width including private runtime metadata.".
-spec shared_machine_width(non_neg_integer()) -> pos_integer().
shared_machine_width(DataWidth) ->
    shared_machine_width(DataWidth, 0).

-doc "Returns the packed actor-state width including private runtime metadata.".
-spec shared_machine_width(non_neg_integer(), non_neg_integer()) ->
    pos_integer().
shared_machine_width(DataWidth, ReductionWidth) ->
    shared_machine_width(DataWidth, ReductionWidth, 0).

-doc "Returns the physical row width including independently sized gather storage.".
-spec shared_machine_width(non_neg_integer(), non_neg_integer(), non_neg_integer()) -> pos_integer().
shared_machine_width(DataWidth, ReductionWidth, GatherWidth) ->
    maps:get(width, shared_machine_layout(DataWidth, ReductionWidth, GatherWidth)).

%% Low-to-high packed RAM layout, shared by the codec and passive debug taps.
-doc "Returns bit offsets used consistently by codecs and observation extraction.".
-spec shared_machine_layout(non_neg_integer(), non_neg_integer()) -> map().
shared_machine_layout(DataWidth, ReductionWidth) ->
    maps:remove(gather, shared_machine_layout(DataWidth, ReductionWidth, 0)).

-doc "Places gather storage after reduction storage, preserving ordinary observation offsets.".
-spec shared_machine_layout(non_neg_integer(), non_neg_integer(), non_neg_integer()) -> map().
shared_machine_layout(DataWidth, ReductionWidth, GatherWidth) ->
    {Width, Fields} = lists:foldl(fun({Name, Bits}, {Offset, Acc}) ->
        {Offset + Bits, Acc#{Name => #{offset => Offset, width => Bits}}}
    end, {0, #{}}, [{phase, 8}, {entered_from, 8}, {data, DataWidth},
        {enter_pending, 1}, {failure, 16}, {reduction, ReductionWidth}, {gather, GatherWidth}]),
    Fields#{width => Width}.

%% Packs shared RAM rows; optional private fields follow the stable observation offsets.
-spec machine_codec(spec()) -> iodata().
machine_codec(Spec) ->
    DataWidth = xls_state_projection:width(Spec),
    Reductions = maps:get(reductions, Spec, none),
    ReductionWidth = xls_statem_reduction_codegen:private_width(Reductions),
    #{data := #{offset := DataStart}, enter_pending := #{offset := EnterStart},
        failure := #{offset := FailureStart}, reduction := #{offset := ReductionStart},
        gather := #{offset := GatherStart}, width := PrivateEnd} =
        shared_machine_layout(DataWidth, ReductionWidth, xls_shared_gather_codegen:storage_width(Spec)),
    ReductionEnd = ReductionStart + ReductionWidth,
    [
        "fn machine_from_bits", xls_state_projection:parameter(Spec), "(raw: MachineBits",
        case maps:is_key(state_projection, Spec) of true -> ", slot: u32"; false -> "" end,
        ") -> ActorState {\n",
        "  ActorState {\n",
        "    phase: raw[0:8] as Phase,\n",
        "    entered_from: raw[8:16] as Phase,\n",
        "    data: ", xls_state_projection:decode(Spec,
            ["raw[", integer_to_list(DataStart), ":", integer_to_list(EnterStart), "]"], "slot"), ",\n",
        xls_statem_reply_codegen:optional(Spec, ["    replies: hls_reply::from_bits<REPLY_CAPACITY>(raw[",
            integer_to_list(PrivateEnd + event_width(Spec)), ":",
            integer_to_list(PrivateEnd + event_width(Spec) + xls_statem_reply_codegen:width(Spec)), "]),\n"]),
        xls_statem_event_codegen:optional(Spec, ["    next_event: raw[", integer_to_list(PrivateEnd), ":", integer_to_list(PrivateEnd + 8), "],\n"]),
        "    enter_pending: raw[", integer_to_list(EnterStart), ":",
        integer_to_list(FailureStart), "],\n",
        "    failure: raw[", integer_to_list(FailureStart), ":",
        integer_to_list(FailureStart + 16), "],\n",
        ?REDUCTION_SERVICE:machine_decode_field(
            Reductions,
            ReductionStart,
            ReductionEnd
        ),
        xls_shared_gather_codegen:machine_decode_field(Spec, GatherStart, PrivateEnd),
        "  }\n",
        "}\n\n",
        "fn bits_from_machine(machine: ActorState) -> MachineBits {\n",
        xls_statem_reply_codegen:optional(Spec, "  hls_reply::to_bits(machine.replies) ++\n"),
        xls_statem_event_codegen:optional(Spec, "  machine.next_event ++\n"),
        xls_shared_gather_codegen:machine_encode_prefix(Spec),
        ?REDUCTION_SERVICE:machine_encode_prefix(Reductions),
        "  machine.failure ++\n",
        "    machine.enter_pending ++\n",
        "    ", xls_state_projection:encode(Spec, "machine.data"), " ++\n",
        "    (machine.entered_from as bits[8]) ++\n",
        "    (machine.phase as bits[8])\n",
        "}\n\n",
        "fn machine_read(slot: u32) -> MachineRamReadReq {\n",
        "  bram::read(slot)\n",
        "}\n\n",
        "fn machine_write(\n",
        "    slot: u32, machine: ActorState) -> MachineRamWriteReq {\n",
        "  bram::write(slot, bits_from_machine(machine))\n",
        "}\n\n"
    ].

%% Tags an ordered effect batch with its owning actor slot.
-spec scheduled_effect_function(map()) -> iodata().
scheduled_effect_function(Spec) ->
    ["""
    pub fn scheduled_effect(
        scheduled: ScheduledEffects, index: u8) -> (Egress, u1, u1) {
      let count = entry_effect_count(scheduled.effects);
      let emit = index < count;
      let last = index + u8:1 >= count;
      (entry_effect(scheduled.effects, index), emit, last)
    }

    """, scheduled_reduction_prefix_function(Spec)].

%% Counts effects captured by the source-fragment reduction plane.
-spec scheduled_reduction_prefix_function(map()) -> iodata().
scheduled_reduction_prefix_function(#{shared_service := aggregate_only,
        reductions := #{sites := Sites}, entries := Entries}) ->
    [
        "pub fn scheduled_reduction_prefix(\n",
        "    scheduled: ScheduledEffects) -> (u1, u8, u1) {\n",
        "  let count = entry_effect_count(scheduled.effects);\n",
        "  match scheduled.effects.layout {\n",
        [scheduled_reduction_prefix_arm(Site, Layout)
            || Site = #{phase := Phase} <- Sites,
                Layout = #{phase := LayoutPhase} <- lists:append([maps:get(layouts, Entry) || Entry <- Entries]),
                LayoutPhase =:= Phase],
        "    _ => (u1:0, u8:0, u1:0),\n",
        "  }\n",
        "}\n\n"
    ];
scheduled_reduction_prefix_function(_Spec) -> [].

%% Selects the captured contribution prefix for one entry layout.
-spec scheduled_reduction_prefix_arm(map(),map()) -> [string(),...].
scheduled_reduction_prefix_arm(#{population := #{size := Size}},
        #{layout := Layout, actions := Effects}) ->
    Valid = case length(Effects) >= Size of
        true -> "u1:1";
        false -> "u1:0"
    end,
    ["    u8:", integer_to_list(Layout), " => (", Valid, ", u8:",
        integer_to_list(Size), ", count == u8:", integer_to_list(Size), "),\n"].

%% Evaluates mailbox and entry callbacks for scheduler-owned state.
-spec shared_machine_step_function(spec()) -> iodata().
shared_machine_step_function(#{
    message_names := MessageNames,
    message_words := MessageWords
} = Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    SharedService = maps:get(shared_service, Spec, ordinary),
    [
        ?REDUCTION_SERVICE:shared_machine_support(
            Reductions, SharedService, Spec
        ),
        "fn shared_machine_dispatch(\n",
        "    machine: ActorState, frame: axis::Frame, received: u1)\n",
        "    -> ActorDispatch {\n",
        "  if hls_failure::failed(machine.failure) {\n",
        "    ActorDispatch { machine, ..zero!<ActorDispatch>() }\n",
        "  } else if machine.enter_pending || !received {\n",
        "    ActorDispatch { machine, ..zero!<ActorDispatch>() }\n",
        "  } else {\n",
        "    let tag_ok = ",
        xls_actor_codegen:input_tag_ok(Spec, MessageNames, MessageWords), ";\n",
        xls_statem_reply_codegen:admit(Spec, "frame", "tag_ok"),
        ?REDUCTION_SERVICE:shared_dispatch_bindings(
            Reductions, SharedService, Spec
        ),
        "    let invalid_repeat = ", xls_statem_reply_codegen:optional(Spec, "(tag_ok && is_call(frame.header.op) && directive == Directive::POSTPONE) || "), "tag_ok && repeat_phase &&\n",
        "      (directive != Directive::CONSUME ||\n",
        "       next_phase != machine.phase);\n",
        ?REDUCTION_SERVICE:shared_dispatch_effective_binding(
            Reductions, SharedService, Spec
        ),
        "    let phase_changed = effective && next_phase != machine.phase;\n",
        "    let phase_boundary = phase_changed ||\n",
        "      (effective && repeat_phase);\n",
        ?REDUCTION_SERVICE:shared_dispatch_failed_binding(
            Reductions, SharedService, Spec
        ),
        xls_statem_reply_codegen:finish(Spec, "frame"),
        xls_actor_codegen:reply_failure_binding(Spec),
        "    let next_machine = ActorState {\n",
        "      phase: if effective", xls_statem_reply_codegen:optional(Spec, " && !contract_fault"), " { next_phase } else { machine.phase },\n",
        "      entered_from: if phase_boundary {\n",
        "        machine.phase\n",
        "      } else { machine.entered_from },\n",
        "      data: if effective", xls_statem_reply_codegen:optional(Spec, " && !contract_fault"), " { next_data } else { machine.data },\n",
        xls_statem_reply_codegen:optional(Spec, "      replies: reply_book,\n"),
        xls_statem_event_codegen:optional(Spec, "      next_event: if effective && !failed { next_event } else { u8:0 },\n"),
        ?REDUCTION_SERVICE:shared_dispatch_reduction_field(
            Reductions, SharedService
        ),
        "      enter_pending: effective && phase_boundary && !failed,\n",
        "      failure,\n",
        "      ..machine\n",
        "    };\n",
        "    ActorDispatch {\n",
        "      machine: next_machine,\n",
        xls_statem_reply_codegen:optional(Spec, "      reply: response, reply_valid: response_valid,\n"),
        case xls_statem_reply_codegen:enabled(Spec) of
            true -> "      dispatched: failed || effective,\n      directive: if failed { Directive::CONSUME } else { directive },\n";
            false -> [?REDUCTION_SERVICE:shared_dispatch_dispatched_field(Reductions, SharedService, Spec), "      directive,\n"]
        end,
        "      phase_boundary,\n",
        "      ..zero!<ActorDispatch>()\n",
        "    }\n",
        "  }\n",
        "}\n\n",
        "fn shared_machine_enter(machine: ActorState, egress_ready: u1)\n",
        "    -> SharedStep {\n",
        "  if hls_failure::failed(machine.failure) || !machine.enter_pending {\n",
        "    SharedStep { machine, ..zero!<SharedStep>() }\n",
        "  } else {\n",
        ?REDUCTION_SERVICE:shared_entry_step(Reductions, Spec),
        "  }\n",
        "}\n\n"
    ].

%% A shared scheduler owns mailbox ordering and actor state. This stateless
%% boundary contains only the actor-specific work, allowing XLS to pipeline
%% several distinct actor activations without putting either RAM in the
%% recurrence.
%% Returns one atomic activation outcome to the shared scheduler.
-spec shared_executor(spec()) -> iodata().
shared_executor(Spec) ->
    ["pub fn shared_execute", xls_state_projection:parameter(Spec), """
    (request: SharedExecutorRequest) ->
        SharedExecutorResult {
    """,
      "  let machine = ", decode_machine(Spec, "request.machine", "request.slot"), ";\n",
      "\n",
      xls_shared_event_codegen:shared_dispatch(Spec),
      xls_statem_reply_codegen:optional(Spec, ["  let dispatched = if dispatched.reply_valid && !request.egress_ready {\n",
          "    ActorDispatch { machine, ..zero!<ActorDispatch>() }\n  } else { dispatched };\n"]),
    """
    """, "  let entered = ", shared_reply_effect(Spec), "shared_machine_enter(\n",
        "    dispatched.machine, request.egress_ready)", xls_statem_reply_codegen:optional(Spec, " }"), ";\n", """
      SharedExecutorResult {
        slot: request.slot,
        machine: bits_from_machine(entered.machine),
        effects: entered.effects,
        effects_valid: entered.effects_valid,
        dispatched: dispatched.dispatched,
        directive: dispatched.directive,
        phase_boundary: dispatched.phase_boundary,
        egress_blocked: entered.egress_blocked,
        received: request.received,
        mailbox_index: request.mailbox_index,
        order_index: request.order_index,
      }
    }

    """, "pub proc SharedExecutor", xls_state_projection:parameter(Spec), """
     {
      request_in: chan<SharedExecutorRequest> in;
      result_out: chan<SharedExecutorResult> out;

      config(
          request_in: chan<SharedExecutorRequest> in,
          result_out: chan<SharedExecutorResult> out
      ) {
        (request_in, result_out)
      }

      init { () }

      next(state: ()) {
        let (tok, request) = recv(join(), request_in);
        // The loader issues only requests with reserved completion storage.
        // Publication waits at retirement, not while evaluating this callback.
        // Specialize the invariant here; shared_execute remains a pure reference
        // for callers which explicitly exercise unavailable effect capacity.
        let issued = SharedExecutorRequest { egress_ready: true, ..request };
    """, "    let _done = send(tok, result_out, shared_execute", xls_state_projection:argument(Spec), "(issued));\n", """
        state
      }
    }

    """].

%% Both executor and retirement decode from the same physical layout and actor identity.
-spec decode_machine(spec(), iodata(), iodata()) -> iodata().
decode_machine(Spec, Raw, Slot) ->
    ["machine_from_bits", xls_state_projection:argument(Spec), "(", Raw,
        case maps:is_key(state_projection, Spec) of true -> [", ", Slot]; false -> "" end, ")"].

%% The loader has its own advance condition and owns no writable actor state.
-spec shared_loader(spec()) -> binary().
shared_loader(Spec) ->
    Path = filename:join([code:priv_dir(hls_fabric), "xls", "templates", "shared_loader.x.in"]),
    {ok, Template} = file:read_file(Path),
    Fields = case {maps:get(reductions, Spec, none), maps:get(shared_service, Spec, ordinary)} of
        {none, _} -> [];
        {_, ordinary} -> [internal];
        {_, aggregate_only} -> [internal, aggregate_request, aggregate_valid]
    end,
    Copy = iolist_to_binary([[atom_to_list(Field), ": ticket.", atom_to_list(Field), ",\n      "]
        || Field <- Fields]),
    xls_template:render(Template, [
        {<<"@@REDUCTION_FIELDS@@">>, Copy},
        {<<"@@MACHINE_BITS@@">>, xls_shared_collection_codegen:loader_value(Spec)} |
        xls_indexed_memory_codegen:loader_bindings(Spec)]).

%% Emits RAM-backed scheduling, retaining one pending request per producer.
-spec shared_service(spec()) -> iodata().
shared_service(Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    SharedService = maps:get(shared_service, Spec, ordinary),
    RamParameters = xls_scheduler_ram_dslx:parameters(write, [], [], Spec),
    RamConfigParameters = xls_scheduler_ram_dslx:parameters(all, [], [], Spec),
    RamNames = xls_scheduler_ram_dslx:names(write, [], Spec),
    [
    ?REDUCTION_SERVICE:shared_service_helpers(Reductions, SharedService),
    """
    fn ready_selection<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        cursor: u32,
        in_flight: u1[ACTOR_COUNT]) -> (u1, u32) {
      scheduler::select(
        scheduler::Candidates<ACTOR_COUNT> {
          entry: state.entry_probes,
          mail: state.mail_candidates,
          egress: state.egress_waiters,
          ..zero!<scheduler::Candidates<ACTOR_COUNT>>()
        }, state.egress_busy, scheduler::exclude_reserved(in_flight, state.outbox_busy), cursor)
    }

    // Translate actor-specific results into the shared metadata transition.
    fn retire_actor<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>,
        valid: u1,
        slot: u32,
        stepped: SharedStep,
        received: u1,
        mailbox_index: u8,
        order_index: u8) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      let metadata = mailbox::retire(
        mailbox::Metadata<ACTOR_COUNT, MAILBOX_DEPTH> {
          occupied: state.occupied,
          order: state.order,
          used: state.used,
          postponed: state.postponed,
          mail_candidates: state.mail_candidates,
          entry_probes: state.entry_probes,
          egress_waiters: state.egress_waiters,
        }, slot, order_index, mailbox_index,
        mailbox::Retirement {
          valid,
          consume: received && stepped.dispatched &&
            stepped.directive == Directive::CONSUME,
          postpone: received && stepped.dispatched &&
            stepped.directive == Directive::POSTPONE,
    """, "\n      phase_boundary: stepped.phase_boundary",
        xls_statem_reply_codegen:optional(Spec, " || hls_failure::failed(stepped.machine.failure)"), ",\n",
        "      failed: ", case xls_statem_reply_codegen:enabled(Spec) of
            true -> "false"; false -> "hls_failure::failed(stepped.machine.failure)" end, ",\n",
        "      enter_pending: stepped.machine.enter_pending",
        xls_statem_event_codegen:optional(Spec, " || stepped.machine.next_event != u8:0"),
        xls_statem_reply_codegen:optional(Spec, " || (hls_failure::failed(stepped.machine.failure) && hls_reply::first(stepped.machine.replies.slots, true).0)"), ",\n", """
          egress_blocked: stepped.egress_blocked,
        });
      SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
        occupied: metadata.occupied,
        order: metadata.order,
        used: metadata.used,
        postponed: metadata.postponed,
        mail_candidates: metadata.mail_candidates,
        entry_probes: metadata.entry_probes,
        egress_waiters: metadata.egress_waiters,
        ..state
      }
    }

    // One metadata owner reserves actors and completion storage before handing
    // a registered ticket to the independent RAM loader. One outstanding ticket
    // per actor bounds completion demand by ACTOR_COUNT. Retirement returns that
    // reservation; prior writes must complete before another read ticket leaves.
    // Producer and credit capture do not depend on the loader's RAM responses.
    // PER_ACTOR_EGRESS requires one independently drained batch slot per actor.
    // A credit names the drained actor; no second activation issues while its
    // slot is occupied. The demultiplexer must accept every reserved batch.
    pub proc SharedService<
        ACTOR_COUNT: u32,
        PRODUCER_COUNT: u32,
        STARTUP_COUNT: u32,
        INSTANCE_ID: u32,
        PER_ACTOR_EGRESS: u1 = {u1:0}
    > {
      request_in: chan<ScheduledRequest>[PRODUCER_COUNT] in;
      startup_in: chan<ScheduledRequest> in;
      egress_out: chan<ScheduledEffects> out;
    """,
        "\n", lists:join("\n", [["  ", Parameter, ";"]
            || Parameter <- RamParameters]),
        ?REDUCTION_SERVICE:shared_proc_field(Reductions, SharedService),
        xls_scheduler_observation:proc_field(Spec), xls_collection_observation:proc_field(Spec),
    """
      dispatch_out: chan<SharedDispatchTicket> out;
      executor_result_in: chan<SharedExecutorResult> in;

      config(
          request_in: chan<ScheduledRequest>[PRODUCER_COUNT] in,
          startup_in: chan<ScheduledRequest> in,
          egress_out: chan<ScheduledEffects> out,
    """,
        "\n", lists:join(",\n", [["      ", Parameter]
            || Parameter <- RamConfigParameters]),
        ?REDUCTION_SERVICE:shared_config_parameter(
            Reductions, SharedService
        ),
        xls_scheduler_observation:config_parameter(Spec), xls_collection_observation:config_parameter(Spec),
    """
      ) {
        let (executor_request_p, executor_request_c) =
          chan<SharedExecutorRequest, u32:1>("executor_request");
        let (loaded_request_p, loaded_request_c) =
          chan<SharedExecutorRequest, u32:0>("loaded_request");
        // One reserved result per actor: the FIFO plus the existing skid slot
        // can park every outstanding activation even while shared egress stops.
        let (executor_result_p, executor_result_c) =
          chan<SharedExecutorResult, {if ACTOR_COUNT > u32:1 {
            ACTOR_COUNT - u32:1
          } else { u32:1 }}>("executor_result");
        let (dispatch_p, dispatch_c) = chan<SharedDispatchTicket, u32:1>("dispatch_ticket");
    """, "    spawn SharedExecutor", xls_state_projection:argument(Spec), "(executor_request_c, executor_result_p);\n", """
        spawn SharedRequestStage(loaded_request_c, executor_request_p);
        spawn SharedLoader<INSTANCE_ID, {mailbox::physical_stride(ACTOR_COUNT, MAILBOX_DEPTH)}>(
          dispatch_c, loaded_request_p,
          ram_read_req_out, ram_read_resp_in, mailbox_read_req_out, mailbox_read_resp_in
    """, xls_indexed_memory_codegen:optional(Spec, ", gather_read_req_out, gather_read_resp_in"), """
        );
        (
          request_in,
          startup_in,
          egress_out,
    """,
        "\n", lists:join("\n", [["      ", Name, ","]
            || Name <- RamNames]),
        ?REDUCTION_SERVICE:shared_config_endpoint(Reductions, SharedService),
        xls_scheduler_observation:config_value(Spec), xls_collection_observation:config_value(Spec),
    """
          dispatch_p,
          executor_result_c,
        )
      }

      init {
        (join(), SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
          instance_id: INSTANCE_ID,
          phase: SharedPhase::BOOT,
          ..zero!<SharedState<ACTOR_COUNT, PRODUCER_COUNT>>()
        })
      }

      next(prior: (token, SharedState<ACTOR_COUNT, PRODUCER_COUNT>)) {
        let (memory_tok, state) = prior;
    """,
        "\n", xls_scheduler_observation:sample(Spec), xls_collection_observation:sample(Spec),
    """
        // Each producer is visited once. Select one slot's value before
        // updating the array, keeping unrolled type inference linear.
        let capture_enabled = state.phase == SharedPhase::RUN;
        let (capture_tok, captured_pending, captured_pending_valid) =
          unroll_for! (producer, acc):
              (u32, (
                token,
                ScheduledRequest[PRODUCER_COUNT],
                u1[PRODUCER_COUNT]
              )) in u32:0..PRODUCER_COUNT {
            let (next_tok, request, captured) =
              recv_if_non_blocking(
                acc.0,
                request_in[producer],
                capture_enabled && !state.pending_valid[producer],
                zero!<ScheduledRequest>());
            (
              next_tok,
              update(acc.1, producer,
                if captured { request } else { state.pending[producer] }),
              update(acc.2, producer, state.pending_valid[producer] || captured)
            )
          }((memory_tok, state.pending, state.pending_valid));
    """,
        xls_shared_collection_codegen:capture(Spec),
        ?REDUCTION_SERVICE:shared_capture(Reductions, SharedService),
    """
        match state.phase {
          SharedPhase::BOOT => {
            let write_tok = send(
    """,
        "\n          ",
        ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService),
        ",\n",
    """
              ram_write_req_out,
              machine_write(state.cursor as u32, initial_shared_machine()));
            let (_done, _) = recv(write_tok, ram_write_resp_in);
            let entry_probes = update(
              state.entry_probes, state.cursor as u32, u1:1);
            let cursor = scheduler::advance_cursor<ACTOR_COUNT>(
              state.cursor, true, state.cursor as u32);
            let next_state = if (state.cursor as u32) == ACTOR_COUNT - u32:1 {
              SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
                phase: if STARTUP_COUNT == u32:0 {
                  SharedPhase::RUN
                } else {
                  SharedPhase::STARTUP
                },
                cursor,
                entry_probes,
                ..state
              }
            } else {
              SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
                cursor,
                entry_probes,
                ..state
              }
            };
            (write_tok, next_state)
          },
          SharedPhase::STARTUP => {
            let (tok, request) = recv(
    """,
        ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService),
        ", startup_in);\n",
    """
            let physical = state.occupied[request.slot];
            let write_tok = send(
              tok,
              mailbox_write_req_out,
              mailbox::write(
                request.slot, physical, mailbox::physical_stride(ACTOR_COUNT, MAILBOX_DEPTH), request.frame));
            let (_done, _) = recv(write_tok, mailbox_write_resp_in);
            let occupied = update(
              state.occupied, request.slot, physical + u8:1);
            let row = update(
              state.order[request.slot], physical as u32, physical);
            let order = update(state.order, request.slot, row);
            let used = update(state.used, request.slot,
              update(state.used[request.slot], physical as u32, true));
            let mail_candidates = update(
              state.mail_candidates, request.slot, u1:1);
            let startup_seen = state.startup_seen + u32:1;
            let next_state = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
              phase: if startup_seen == STARTUP_COUNT {
                SharedPhase::RUN
              } else {
                SharedPhase::STARTUP
              },
              startup_seen,
              occupied,
              order,
              used,
              mail_candidates,
              ..state
            };
            (write_tok, next_state)
          },
          SharedPhase::RUN => {
            // Return credits must already occupy a pending receptacle.
            // Using a newly captured credit here closes a combinational path
            // through result retirement, the router, and its credit output.
            let (credit_pending_valid, credit_busy, credit_outboxes) =
              if PER_ACTOR_EGRESS {
                let (pending, busy) = mailbox::collect_actor_credits(
                  state.pending, state.pending_valid,
                  captured_pending_valid, state.outbox_busy);
                (pending, u1:0, busy)
              } else {
                let (pending, busy) = mailbox::collect_credit(
                  state.pending, state.pending_valid,
                  captured_pending_valid, state.egress_busy);
                (pending, busy, state.outbox_busy)
              };
            let buffered_can_retire = state.completed_valid &&
              (!state.completed.effects_valid || !credit_busy);
            let accept_executor_result =
              !state.completed_valid || buffered_can_retire;
            let (executor_result_tok, incoming_result, incoming_valid) =
              recv_if_non_blocking(
    """,
        "\n            ",
        ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService),
        ",\n",
    """
                executor_result_in,
                accept_executor_result,
                zero!<SharedExecutorResult>());
            // Every executor result crosses the retained completion boundary.
            // An empty slot must not bypass arithmetic into commit/publication.
            let result = state.completed;
            let retire_valid = buffered_can_retire;
            let resolved = SharedStep {
    """, "          machine: ", decode_machine(Spec, "result.machine", "result.slot"), ",\n", """
              effects: result.effects,
              effects_valid: result.effects_valid,
              dispatched: result.dispatched,
              directive: result.directive,
              phase_boundary: result.phase_boundary,
              egress_blocked: result.egress_blocked,
            };
    """, xls_shared_collection_codegen:resolve(Spec), xls_indexed_collection_codegen:resolve(Spec), """
            let credited = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
    """, xls_shared_collection_codegen:captured_field(Spec), """
              pending: captured_pending,
              pending_valid: credit_pending_valid,
              egress_busy: !PER_ACTOR_EGRESS &&
                (credit_busy || (retire_valid && resolved.effects_valid)),
              outbox_busy: if PER_ACTOR_EGRESS && retire_valid && resolved.effects_valid {
                update(credit_outboxes, result.slot, u1:1)
              } else { credit_outboxes },
    """,
        "\n          ..",
        ?REDUCTION_SERVICE:shared_state_source(Reductions, SharedService),
        "\n        };\n",
            ?REDUCTION_SERVICE:shared_retire_binding(Reductions,
                xls_shared_collection_codegen:retire_binding(Spec)),
            xls_shared_collection_codegen:retire(Spec),
            xls_shared_gather_codegen:retire(Spec),
            xls_indexed_collection_codegen:retire(Spec),
    """
            let retired_in_flight = if retire_valid {
              update(retired.in_flight, result.slot, u1:0)
            } else {
              retired.in_flight
            };
            let completed_valid = if accept_executor_result {
              incoming_valid
            } else { state.completed_valid };
            let completed = if incoming_valid { incoming_result }
              else { state.completed };
    """,
            "\n",
            xls_shared_gather_codegen:issue_bindings(Spec),
    """
            let (received, order_index, mailbox_index) =
              mailbox::select(
                state.order[read_slot], state.occupied[read_slot],
                state.postponed[read_slot]);
            let (state_completion_tok, _) = recv_if(
              join(), ram_write_resp_in, state.state_write_pending,
              zero!<MachineRamWriteResp>());
            let (mailbox_completion_tok, _) = recv_if(
              join(), mailbox_write_resp_in,
              state.mailbox_write_pending,
              zero!<MailboxRamWriteResp>());
    """, xls_indexed_memory_codegen:optional(Spec,
        "        let (gather_completion_tok, _) = recv_if(join(), gather_write_resp_in,\n"
        "          state.gather_write_pending, zero!<GatherRamWriteResp>());\n"), """
            // Both arbiters see only committed metadata and registered inputs.
            // Apply this intent after retirement; never replace a whole stale row.
            // An already-free cell cannot alias the live message in a dispatch
            // ticket, so admission does not depend on this cycle's actor choice.
    """, xls_shared_collection_codegen:selection(Spec), xls_shared_collection_codegen:admit(Spec), xls_indexed_collection_codegen:admit(Spec), """
            let admission = mailbox::Admission {
    """, "          valid: intent.valid", xls_shared_collection_codegen:admission_guard(Spec), " && !(retire_valid &&\n", """
                hls_failure::failed(resolved.machine.failure) && intent.slot == result.slot),
              ..intent
            };
            let reservation = mailbox::apply_admission(
              retired.occupied, retired.order, retired.used, retired.mail_candidates,
              state.admission_cursor, credit_pending_valid, admission);
            let reserved = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
              pending: captured_pending,
              pending_valid: reservation.pending_valid,
              occupied: reservation.occupied,
              order: reservation.order,
              used: reservation.used,
              mail_candidates: reservation.mail_candidates,
              admission_cursor: reservation.cursor,
              ..retired
            };
    """,
            xls_shared_collection_codegen:commit(Spec),
            xls_indexed_collection_codegen:commit(Spec),
            xls_shared_collection_codegen:issue(Spec),
            xls_indexed_collection_codegen:issue(Spec),
            ?REDUCTION_SERVICE:shared_post_issue_state(
                Reductions, SharedService
            ),
    """
            let issued_in_flight = if issue_valid {
              update(retired_in_flight, read_slot, u1:1)
            } else {
              retired_in_flight
            };
            let cursor = scheduler::advance_cursor<ACTOR_COUNT>(
              state.cursor, issue_valid, read_slot);
            let selection_state = SharedState<
                ACTOR_COUNT, PRODUCER_COUNT> {
              in_flight: issued_in_flight,
    """,
            "\n          ..",
            ?REDUCTION_SERVICE:shared_post_issue_state_name(
                Reductions, SharedService
            ),
            "\n",
    """
            };
            let ticket = SharedDispatchTicket {
              slot: read_slot,
    """,
            "\n",
            ?REDUCTION_SERVICE:shared_executor_request_value(
                Reductions, SharedService
            ),
            xls_shared_collection_codegen:ticket_value(Spec),
            xls_indexed_collection_codegen:ticket_value(Spec),
    """
              received: read_mailbox && received,
              mailbox_index,
              order_index,
            };
            // Preserve the write-visibility fence before transferring read ownership.
            let dispatch_tok = send_if(
              join(memory_tok, state_completion_tok, mailbox_completion_tok
    """, xls_indexed_memory_codegen:optional(Spec, ", gather_completion_tok"), """
              ),
              dispatch_out, issue_valid, ticket);
            let scheduled = ScheduledEffects {
              slot: result.slot,
              effects: result.effects,
            };
            let egress_tok = send_if(
              executor_result_tok,
              egress_out,
              retire_valid && resolved.effects_valid,
              scheduled);
            let state_write_tok = send_if(
              join(memory_tok, egress_tok),
              ram_write_req_out,
              retire_valid,
              machine_write(result.slot, resolved.machine));
            // Admission selects only registered-valid producers; capture cannot
            // replace that producer's frame until a later iteration.
            let admission_frame =
              state.pending[reservation.admission.producer].frame;
            let mailbox_write_tok = send_if(
              join(memory_tok, egress_tok),
              mailbox_write_req_out,
              reservation.admission.valid,
              mailbox::write(
                reservation.admission.slot,
                reservation.admission.physical,
                mailbox::physical_stride(ACTOR_COUNT, MAILBOX_DEPTH),
                admission_frame));
    """, xls_indexed_memory_codegen:optional(Spec,
        "        let gather_write_tok = send_if(join(memory_tok, gather_completion_tok),\n"
        "          gather_write_req_out, indexed_admission.write_valid, indexed_admission.write);\n"), """
            let _done = join(
              state_write_tok,
              mailbox_write_tok,
              dispatch_tok,
              state_completion_tok,
              mailbox_completion_tok
    """, xls_indexed_memory_codegen:optional(Spec, ", gather_completion_tok, gather_write_tok"), """
              );
            let next_state = SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
              in_flight: issued_in_flight,
              completed_valid,
              completed,
              cursor,
              state_write_pending: retire_valid,
              mailbox_write_pending: reservation.admission.valid,
    """, xls_indexed_memory_codegen:optional(Spec, "          gather_write_pending: indexed_admission.write_valid,\n"), """
              ..selection_state
            };
            (join(state_write_tok, mailbox_write_tok
    """, xls_indexed_memory_codegen:optional(Spec, ", gather_write_tok"), """
            ), next_state)
          },
        }
      }
    }

    """
    ].

%% The selector is present for finite events and for the shared retained-call outcome.
-spec event_width(map()) -> 0 | 8.
event_width(Spec) -> case maps:get(continuations, Spec, []) =/= [] orelse xls_statem_reply_codegen:enabled(Spec) of true -> 8; false -> 0 end.

%% A reply precedes phase entry; that entry remains pending for the next activation.
-spec shared_reply_effect(map()) -> iodata().
shared_reply_effect(Spec) -> case xls_statem_reply_codegen:enabled(Spec) of
    false -> [];
    true -> ["if dispatched.reply_valid { SharedStep { machine: dispatched.machine, effects: ",
        xls_statem_reply_codegen:effect(Spec), ", effects_valid: true, ..zero!<SharedStep>() } } else { "]
end.
