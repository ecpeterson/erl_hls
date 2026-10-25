-module(xls_shared_codegen).
-moduledoc false.
-export([publication_depth/0, emit/1, execution/1, shared_machine_width/1, shared_machine_width/2, shared_machine_width/3, shared_machine_layout/2, shared_machine_layout/3]).
-define(REDUCTION_SERVICE, xls_shared_reduction_service_codegen).
%% Checked actor artifact augmented with private physical options.
-type spec() :: map().

-doc "Returns the shared publication FIFO capacity; service and router each retain an additional command slot.".
-spec publication_depth() -> pos_integer().
publication_depth() -> 2.

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
         command_helpers(), xls_shared_gather_codegen:selection_helpers(Spec),
         scheduled_effect_function(Spec), xls_publication_codegen:helpers(Spec), shared_machine_step_function(Spec),
         shared_executor(Spec), shared_loader(Spec), shared_service(Spec), xls_statem_codegen:body(Spec), xls_direct_collection_codegen:body(Spec)]).
-doc "Emits the ordinary source-derived activation semantics without a RAM owner, loader or topology. Accepts a closed actor artifact with an optional source-validated constant projection for instance zero; retained replies and physical service options are rejected. Callers must reserve state/effect storage and preserve mailbox order. This reference boundary does not establish a local protocol specialization.".
-spec execution(xls_actor_codegen:spec()) -> iolist().
execution(Closed) ->
    case maps:keys(Closed) -- [source, failure_sites, imports, capacity, phases,
            message_names, message_words, output_names, max_entry_effects,
            data_name, data_width, record_declarations, helper_functions, init,
            entries, casts, continuations, retained_calls, internal_steps,
            reductions, gathers, state_projection] of
        [] -> ok;
        Unknown -> error({local_execution_requires_closed_artifact, Unknown})
    end,
    Spec = Closed#{shared_service => ordinary},
    case maps:get(retained_calls, Spec) of
        none -> ok;
        _ -> error(local_execution_retained_calls_unsupported)
    end,
    case maps:find(state_projection, Spec) of
        {ok, #{rows := Rows}} ->
            case lists:usort([I || #{instance := I} <- Rows]) of
                [0] -> ok;
                _ -> error(local_execution_requires_instance_zero)
            end;
        error -> ok
    end,
    xls_actor_codegen:emit(Spec, [bram, mailbox, scheduler, arbitration, std],
        [machine_declarations(Spec), xls_state_projection:functions(Spec), machine_codec(Spec),
         xls_shared_gather_codegen:helpers(Spec),
         shared_machine_step_function(Spec), shared_executor(Spec),
         execution_ports(Spec)]).

%% Fill the ordinary activation API without selecting application-specific callbacks or storage.
-spec execution_ports(spec()) -> iodata().
execution_ports(Spec = #{reductions := Reduction, continuations := Events}) ->
    ReductionPending = case Reduction of none -> []; _ ->
        " || machine.reduction.status == ReductionStatus::COMPLETE" end,
    Pending = ["machine.enter_pending", case Events of [] -> []; _ -> " || machine.next_event != u8:0" end,
        case maps:get(gathers, Spec, none) of none -> []; _ ->
            " || machine.gather.progress.status == GatherStatus::COMPLETE" end, ReductionPending],
    {Decode, Execute} = case maps:is_key(state_projection, Spec) of
        true -> {"machine_from_bits<u32:0>(raw, slot)", "shared_execute<u32:0>(request)"};
        false -> {"machine_from_bits(raw)", "shared_execute(request)"}
    end,
    Internal = case Reduction of none -> []; _ ->
        "internal: !machine.enter_pending && machine.reduction.status == ReductionStatus::COMPLETE," end,
    Path = filename:join(code:priv_dir(hls_fabric), "xls/templates/local_execution.x.in"),
    {ok, Template} = file:read_file(Path),
    xls_template:render(Template, [{<<"@@DECODE@@">>, Decode}, {<<"@@EXECUTE@@">>, Execute},
        {<<"@@PENDING@@">>, Pending}, {<<"@@INTERNAL@@">>, Internal}]).

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
        "// One router slot is reserved for the existing borrowed lookahead credit.\n",
        "const PUBLICATION_CAPACITY = u2:", integer_to_list(publication_depth() + 1), ";\n",
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
        "  admission_cursor: u32,\n  ordinary_intent: mailbox::Admission,\n",
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
        "  publication_outstanding: u2,\n",
        "  outbox_busy: u1[ACTOR_COUNT],\n",
        "  write_machine_valid: bool,\n  write_machine_slot: u32,\n  write_machine: MachineRamWriteReq,\n",
        "  write_mailbox_valid: bool,\n  write_mailbox_slot: u32,\n  write_mailbox: MailboxRamWriteReq,\n",
        "  publish_valid: bool,\n  publish: ScheduledEffects,\n",
        xls_indexed_memory_codegen:optional(Spec,
            "  write_gather_valid: bool,\n  write_gather_slot: u32,\n  write_gather_addr: u32,\n  write_gather_mask: bits[INDEXED_CAPACITY],\n  write_gather_value: bits[INDEXED_ELEMENT_BITS],\n"),
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

%% The RAM owner keeps its owner phases in DSLX; bindings specialize only feature hooks.
-spec shared_service(spec()) -> iodata().
shared_service(Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    Mode = maps:get(shared_service, Spec, ordinary),
    Path = filename:join(code:priv_dir(hls_fabric), "xls/templates/shared_service.x.in"),
    {ok, Template} = file:read_file(Path),
    Bindings = service_ports(Spec, Reductions, Mode) ++
        service_capture(Spec, Reductions, Mode) ++
        service_retirement(Spec, Reductions, Mode) ++
        service_admission(Spec, Reductions, Mode) ++ service_memory(Spec),
    [?REDUCTION_SERVICE:shared_service_helpers(Reductions, Mode),
        xls_template:render(Template, Bindings)].

%% Slots carry DSLX fragments, not actor options or a second validation authority.
-type service_bindings() :: [{binary(), iodata()}].

%% Wire RAM ownership and optional observation/aggregate channels. Indexed preparation
%% supplies the loader directly; ordinary actors retain the request-stage boundary.
-spec service_ports(spec(), none | map(), ordinary | aggregate_only) -> service_bindings().
service_ports(Spec, Reductions, SharedService) ->
    RamParameters = xls_scheduler_ram_dslx:parameters(write, [], [], Spec),
    RamConfigParameters = xls_scheduler_ram_dslx:parameters(all, [], [], Spec),
    RamNames = xls_scheduler_ram_dslx:names(write, [], Spec),
    [
        {<<"@@PROC_PORTS@@">>, [
            lists:join("\n", [["  ", Parameter, ";"] || Parameter <- RamParameters]),
            ?REDUCTION_SERVICE:shared_proc_field(Reductions, SharedService),
            xls_scheduler_observation:proc_field(Spec),
            xls_collection_observation:proc_field(Spec)]},
        {<<"@@CONFIG_PORTS@@">>, [
            lists:join(",\n", [["      ", Parameter] || Parameter <- RamConfigParameters]),
            ?REDUCTION_SERVICE:shared_config_parameter(Reductions, SharedService),
            xls_scheduler_observation:config_parameter(Spec),
            xls_collection_observation:config_parameter(Spec)]},
        {<<"@@REQUEST_STAGE_CHANNEL@@">>, case maps:get(gather_collection, Spec, false) of
            true -> [];
            false ->
                "    let (queued_ticket_p, queued_ticket_c) = "
                "chan<SharedDispatchTicket, u32:1>(\"queued_ticket\");\n"
        end},
        {<<"@@EXECUTOR_INSTANCE@@">>, xls_state_projection:argument(Spec)},
        {<<"@@REQUEST_STAGE_SPAWN@@">>, case maps:get(gather_collection, Spec, false) of
            true -> [];
            false -> "    spawn SharedRequestStage(dispatch_c, queued_ticket_p);\n"
        end},
        {<<"@@LOADER_INPUT@@">>, case maps:get(gather_collection, Spec, false) of
            true -> "      dispatch_c";
            false -> "      queued_ticket_c"
        end},
        {<<"@@LOADER_GATHER_PORTS@@">>, xls_indexed_memory_codegen:optional(Spec,
            ", gather_read_req_out, gather_read_resp_in")},
        {<<"@@CONFIG_VALUES@@">>, [
            lists:join("\n", [["      ", Name, ","] || Name <- RamNames]),
            ?REDUCTION_SERVICE:shared_config_endpoint(Reductions, SharedService),
            xls_scheduler_observation:config_value(Spec),
            xls_collection_observation:config_value(Spec)]}
    ].

%% Sample prior state and capture producers independently of loader responses. Aggregate
%% capture extends the token chain used by BOOT, STARTUP and result reception.
-spec service_capture(spec(), none | map(), ordinary | aggregate_only) -> service_bindings().
service_capture(Spec, Reductions, SharedService) ->
    [
        {<<"@@OBSERVATIONS@@">>, [
            xls_scheduler_observation:sample(Spec),
            xls_collection_observation:sample(Spec)]},
        {<<"@@CAPTURE_INPUTS@@">>, [
            xls_shared_collection_codegen:capture(Spec),
            ?REDUCTION_SERVICE:shared_capture(Reductions, SharedService)]},
        {<<"@@BOOT_TOKEN@@">>, ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService)},
        {<<"@@STARTUP_TOKEN@@">>, ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService)},
        {<<"@@RESULT_TOKEN@@">>, ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService)}
    ].

%% Merge captured inputs with prior credits, resolve the held result, then retire metadata. Incoming
%% results cannot bypass completion storage; failed reply actors must drain retained replies.
-spec service_retirement(spec(), none | map(), ordinary | aggregate_only) -> service_bindings().
service_retirement(Spec, Reductions, SharedService) ->
    [
        {<<"@@REPLY_PHASE_FAILURE@@">>, xls_statem_reply_codegen:optional(Spec,
            " || hls_failure::failed(stepped.machine.failure)")},
        {<<"@@FAILURE_RETIRES@@">>, case xls_statem_reply_codegen:enabled(Spec) of
            true -> "false";
            false -> "hls_failure::failed(stepped.machine.failure)"
        end},
        {<<"@@CONTINUATION_PENDING@@">>, [
            xls_statem_event_codegen:optional(Spec,
                " || stepped.machine.next_event != u8:0"),
            xls_statem_reply_codegen:optional(Spec,
                " || (hls_failure::failed(stepped.machine.failure) && "
                "hls_reply::first(stepped.machine.replies.slots, true).0)")]},
        {<<"@@INDEXED_RETIREMENT_READY@@">>, xls_indexed_memory_codegen:optional(Spec,
            "          state.indexed_retirement_valid &&\n")},
        {<<"@@DECODE_RESULT@@">>, decode_machine(Spec, "result.machine", "result.slot")},
        {<<"@@RESOLVE_RESULT@@">>, [
            xls_shared_collection_codegen:resolve(Spec),
            xls_indexed_collection_codegen:resolve(Spec)]},
        {<<"@@CAPTURED_FIELDS@@">>, xls_shared_collection_codegen:captured_field(Spec)},
        {<<"@@CREDITED_SOURCE@@">>, ?REDUCTION_SERVICE:shared_state_source(Reductions, SharedService)},
        {<<"@@RETIRE_METADATA@@">>, [
            ?REDUCTION_SERVICE:shared_retire_binding(Reductions,
                xls_shared_collection_codegen:retire_binding(Spec)),
            xls_shared_collection_codegen:retire(Spec),
            xls_shared_gather_codegen:retire(Spec),
            xls_indexed_collection_codegen:retire(Spec)]}
    ].

%% Select from prior snapshots, apply admission to retired metadata, then reserve dispatch.
%% Exclusive collection selects from its own unmasked snapshot; opportunistic collection
%% uses ordinary intent. Indexed preparation reserves its actor before payload loading.
-spec service_admission(spec(), none | map(), ordinary | aggregate_only) -> service_bindings().
service_admission(Spec, Reductions, SharedService) ->
    [
        {<<"@@SELECT_ACTOR@@">>, xls_shared_gather_codegen:issue_bindings(Spec)},
        {<<"@@SELECT_ADMISSION@@">>, [
            ordinary_selection(Spec),
            xls_shared_collection_codegen:admit(Spec),
            xls_indexed_collection_codegen:admit(Spec)]},
        {<<"@@COLLECTED_GUARD@@">>, xls_shared_collection_codegen:admission_guard(Spec)},
        {<<"@@ADMIT_AND_ISSUE@@">>, [
            xls_shared_collection_codegen:commit(Spec),
            xls_indexed_collection_codegen:commit(Spec),
            xls_shared_collection_codegen:issue(Spec),
            xls_indexed_collection_codegen:issue(Spec),
            ?REDUCTION_SERVICE:shared_post_issue_state(Reductions, SharedService)]},
        {<<"@@ISSUE_OWNERSHIP@@">>, issue_ownership(Spec)},
        {<<"@@ISSUED_SOURCE@@">>,
            ?REDUCTION_SERVICE:shared_post_issue_state_name(Reductions, SharedService)},
        {<<"@@TICKET_FIELDS@@">>, [
            ?REDUCTION_SERVICE:shared_executor_request_value(Reductions, SharedService),
            xls_shared_collection_codegen:ticket_value(Spec),
            xls_indexed_collection_codegen:ticket_value(Spec)]}
    ].

%% Acknowledge prior writes before dispatch; send old commands and register new ones.
%% Indexed payload RAM participates in the same write-visibility fence and memory-token chain.
-spec service_memory(spec()) -> service_bindings().
service_memory(Spec) ->
    [
        {<<"@@GATHER_COMPLETION@@">>, xls_indexed_memory_codegen:optional(Spec,
            "        let (gather_completion_tok, _) = recv_if(join(), gather_write_resp_in,\n"
            "          state.gather_write_pending, zero!<GatherRamWriteResp>());\n")},
        {<<"@@GATHER_DISPATCH_FENCE@@">>,
            xls_indexed_memory_codegen:optional(Spec, ", gather_completion_tok")},
        {<<"@@GATHER_WRITE@@">>, xls_indexed_memory_codegen:optional(Spec,
            "        let gather_write_tok = send_if(join(memory_tok, gather_completion_tok),\n"
            "          gather_write_req_out, state.write_gather_valid, GatherRamWriteReq {\n"
            "            addr: state.write_gather_addr, mask: state.write_gather_mask,\n"
            "            data: indexed_write_data(state.write_gather_value) });\n")},
        {<<"@@GATHER_DONE@@">>, xls_indexed_memory_codegen:optional(Spec,
            ", gather_completion_tok, gather_write_tok")},
        {<<"@@GATHER_NEXT_COMMANDS@@">>, xls_indexed_memory_codegen:optional(Spec,
            "          gather_write_pending: state.write_gather_valid,\n"
            "          write_gather_valid: indexed_admission.write_valid,\n"
            "          write_gather_slot: indexed_intent.slot,\n"
            "          write_gather_addr: indexed_admission.write.addr,\n"
            "          write_gather_mask: indexed_admission.write.mask,\n"
            "          write_gather_value: indexed_transport_contribution(state.indexed_input.frame).value,\n")},
        {<<"@@GATHER_MEMORY_TOKEN@@">>, xls_indexed_memory_codegen:optional(Spec, ", gather_write_tok")}
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

%% Retained physical writes own visibility until sent; read tickets then join acknowledgments.
-spec command_helpers() -> iodata().
command_helpers() ->
    """
    // A new activation cannot read a row whose command has not reached RAM.
    fn shared_write_mask<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>) -> bool[ACTOR_COUNT] {
      unroll_for! (actor, flags): (u32, bool[ACTOR_COUNT]) in u32:0..ACTOR_COUNT {
        update(flags, actor, state.in_flight[actor] ||
          (state.write_machine_valid && state.write_machine_slot == actor) ||
          (state.write_mailbox_valid && state.write_mailbox_slot == actor))
      }(state.in_flight)
    }

    // Retain a producer and free cell without allowing a second reservation of
    // that actor before the first intent commits. Retirement only frees cells.
    fn ordinary_selection_source<ACTOR_COUNT: u32, PRODUCER_COUNT: u32>(
        state: SharedState<ACTOR_COUNT, PRODUCER_COUNT>) -> SharedState<ACTOR_COUNT, PRODUCER_COUNT> {
      let pending_valid = unroll_for! (producer, flags):
          (u32, bool[PRODUCER_COUNT]) in u32:0..PRODUCER_COUNT {
        let held = state.ordinary_intent;
        update(flags, producer, state.pending_valid[producer] && !(held.valid &&
          (held.producer == producer || held.slot == state.pending[producer].slot)))
      }(state.pending_valid);
      SharedState<ACTOR_COUNT, PRODUCER_COUNT> { pending_valid, ..state }
    }

    """.

%% Grant an ordinary mailbox cell before applying the retained intent at a later edge.
-spec ordinary_selection(spec()) -> iodata().
ordinary_selection(Spec) ->
    Selected = xls_shared_collection_codegen:selection(Spec, #{
        ordinary_state => "admission_snapshot", collection_state => "state",
        ordinary_result => "next_intent"}),
    Source = case maps:get(gather_collection, Spec, false) of
        true -> "indexed_preparation_source(state, prepare_valid, prepare_slot)";
        false -> "state"
    end,
    ["\n        let admission_snapshot = ordinary_selection_source(", Source, ");\n", Selected,
     "        let intent = state.ordinary_intent;\n"].

%% Indexed actors reserve at preparation and release only on cancellation or
%% retirement. Their cursor advances across empty probes as well as real work.
-spec issue_ownership(spec()) -> iodata().
issue_ownership(Spec) ->
    case maps:get(gather_collection, Spec, false) of
        true ->
            "        let issued_in_flight = indexed_prepared_in_flight(state, retired_in_flight,\n"
            "          finish_prepared, issue_valid, prepare_valid, prepare_slot);\n"
            "        let cursor = scheduler::advance_cursor<ACTOR_COUNT>(\n"
            "          state.cursor, prepare_valid, prepare_slot);\n";
        false ->
            "        let issued_in_flight = if issue_valid {\n"
            "          update(retired_in_flight, read_slot, u1:1)\n"
            "        } else { retired_in_flight };\n"
            "        let cursor = scheduler::advance_cursor<ACTOR_COUNT>(\n"
            "          state.cursor, issue_valid, read_slot);\n"
    end.
