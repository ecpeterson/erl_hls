-module(xls_scheduler_codegen).
-moduledoc "Finalizes channel-scheduler actor artifacts for xls_scheduler_actor. Renders RAM loading, selection, tickets and publication around xls_machine_codegen; source callbacks remain compiler-owned and topology renderers connect the resulting proc interfaces.".

%% Structured scheduler artifacts and byte output.
-export([artifact/1, emit/1]).

%% Shared publication interface dimension.
-export([publication_depth/0]).
-define(REDUCTION_SERVICE, xls_reduction_service_codegen).
%% Checked actor artifact augmented with private physical options.
-type spec() :: xls_actor_codegen:spec().

-doc "Returns the shared publication FIFO capacity; service and router each retain an additional command slot.".
-spec publication_depth() -> pos_integer().
publication_depth() -> 2.

-doc "Renders the main module bytes for RAM-backed shared execution of a validated actor artifact. Use artifact/1 to retain generated helper imports and their failure metadata.".
-spec emit(spec()) -> binary().
emit(Spec) -> xls_emitted:bytes(artifact(Spec)).

-doc "Renders one specialized shared actor and retains its generated helper modules and allocated failure codebook beside the exact main-module bytes.".
-spec artifact(spec()) -> xls_emitted:artifact().
artifact(Spec) ->
    ok = xls_machine_names:validate(Spec),
    Reductions = maps:get(reductions, Spec, none),
    Mode = maps:get(shared_service, Spec, ordinary),
    xls_actor_codegen:artifact(
        xls_exclusive_collection_codegen:actor_spec(Spec),
        [bram, mailbox, scheduler, arbitration, std, direct_mailbox_observation] ++
            xls_scheduler_observation:imports(Spec) ++ xls_indexed_collection_codegen:imports(Spec),
        [
            xls_reduction_codegen:declarations(Reductions, Mode),
            xls_exclusive_collection_codegen:declarations(Spec),
            xls_indexed_collection_codegen:declarations(Spec),
            machine_declarations(Spec),
            xls_state_projection:functions(Spec),
            xls_machine_codegen:codec(Spec),
            machine_access(),
            xls_collection_codegen:helpers(Spec),
            xls_indexed_collection_codegen:helpers(Spec),
            xls_collection_observation:declarations(Spec),
            "fn initial_shared_machine() -> ActorState { initial_actor_state() }\n\n",
            xls_reduction_codegen:functions(Reductions, Mode),
            xls_gather_codegen:helpers(Spec),
            command_helpers(),
            xls_gather_codegen:selection_helpers(Spec),
            scheduled_effect_function(Spec),
            xls_publication_codegen:helpers(Spec),
            xls_machine_codegen:step(Spec),
            xls_machine_codegen:execute(Spec),
            executor_proc(Spec),
            shared_loader(Spec),
            shared_service(Spec),
            xls_statem_codegen:body(Spec),
            xls_direct_collection_codegen:body(Spec)
        ]
    ).
%% Defines accepted-work tickets, RAM row types and scheduler-owned metadata.
-spec machine_declarations(spec()) -> iodata().
machine_declarations(#{capacity := Capacity} = Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    SharedService = maps:get(shared_service, Spec, ordinary),
    MachineBits = xls_machine_layout:width(xls_machine_layout:from_spec(Spec)),
    [
        "// One router slot is reserved for the existing borrowed lookahead credit.\n",
        "const PUBLICATION_CAPACITY = u2:",
        integer_to_list(publication_depth() + 1),
        ";\n",
        xls_machine_codegen:state_type(Spec),
        "pub type MachineRamReadReq = bram::ReadReq;\n",
        "pub type MachineRamReadResp = bram::ReadResp<u32:",
        integer_to_list(MachineBits),
        ">;\n",
        "pub type MachineRamWriteReq = bram::WriteReq<u32:",
        integer_to_list(MachineBits),
        ">;\n",
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
        xls_machine_codegen:step_type(),
        "// Immutable selection; actor ownership and result storage are already reserved.\n",
        "struct SharedDispatchTicket {\n",
        "  slot: u32,\n  received: u1,\n  mailbox_index: u8,\n  order_index: u8,\n",
        ?REDUCTION_SERVICE:shared_executor_request_field(Reductions, SharedService),
        xls_collection_codegen:ticket_field(Spec),
        xls_indexed_collection_codegen:ticket_field(Spec),
        "}\n\n",
        xls_machine_codegen:executor_types(Spec),
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
        xls_collection_codegen:state_fields(Spec),
        xls_gather_codegen:state_fields(Spec),
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
        "  order: u8[",
        integer_to_list(Capacity),
        "][ACTOR_COUNT],\n",
        "  used: bool[",
        integer_to_list(Capacity),
        "][ACTOR_COUNT],\n",
        "  postponed: u1[",
        integer_to_list(Capacity),
        "][ACTOR_COUNT],\n",
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
        xls_indexed_memory_codegen:optional(
            Spec,
            "  write_gather_valid: bool,\n  write_gather_slot: u32,\n  write_gather_addr: u32,\n  write_gather_mask: bits[INDEXED_CAPACITY],\n  write_gather_value: bits[INDEXED_ELEMENT_BITS],\n"
        ),
        "  state_write_pending: u1,\n",
        "  mailbox_write_pending: u1,\n",
        "}\n\n"
    ].

%% RAM wrappers adapt the common row codec to the scheduler's explicit memory ports.
-spec machine_access() -> iodata().
machine_access() ->
    [
        "fn machine_read(slot: u32) -> MachineRamReadReq {\n",
        "  bram::read(slot)\n}\n\n",
        "fn machine_write(\n",
        "    slot: u32, machine: ActorState) -> MachineRamWriteReq {\n",
        "  bram::write(slot, bits_from_machine(machine))\n}\n\n"
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
scheduled_reduction_prefix_function(#{
    shared_service := aggregate_only,
    reductions := #{sites := Sites},
    entries := Entries
}) ->
    [
        "pub fn scheduled_reduction_prefix(\n",
        "    scheduled: ScheduledEffects) -> (u1, u8, u1) {\n",
        "  let count = entry_effect_count(scheduled.effects);\n",
        "  match scheduled.effects.layout {\n",
        [
            scheduled_reduction_prefix_arm(Site, Layout)
         || Site = #{phase := Phase} <- Sites,
            Layout = #{phase := LayoutPhase} <- lists:append([
                maps:get(layouts, Entry)
             || Entry <- Entries
            ]),
            LayoutPhase =:= Phase
        ],
        "    _ => (u1:0, u8:0, u1:0),\n",
        "  }\n",
        "}\n\n"
    ];
scheduled_reduction_prefix_function(_Spec) ->
    [].

%% Selects the captured contribution prefix for one entry layout.
-spec scheduled_reduction_prefix_arm(map(), map()) -> [string(), ...].
scheduled_reduction_prefix_arm(
    #{population := #{size := Size}},
    #{layout := Layout, actions := Effects}
) ->
    Valid =
        case length(Effects) >= Size of
            true -> "u1:1";
            false -> "u1:0"
        end,
    [
        "    u8:",
        integer_to_list(Layout),
        " => (",
        Valid,
        ", u8:",
        integer_to_list(Size),
        ", count == u8:",
        integer_to_list(Size),
        "),\n"
    ].

%% The channel wrapper evaluates already-reserved work; the RAM service owns issue and retirement.
-spec executor_proc(spec()) -> iodata().
executor_proc(Spec) ->
    [
        "pub proc SharedExecutor",
        xls_state_projection:parameter(Spec),
        """
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
        """,
        "    let _done = send(tok, result_out, shared_execute",
        xls_state_projection:argument(Spec),
        "(issued));\n",
        """
            state
          }
        }

        """
    ].

%% The loader has its own advance condition and owns no writable actor state.
-spec shared_loader(spec()) -> binary().
shared_loader(Spec) ->
    Path = filename:join([code:priv_dir(hls_lowering), "xls", "templates", "shared_loader.x.in"]),
    {ok, Template} = file:read_file(Path),
    Fields =
        case {maps:get(reductions, Spec, none), maps:get(shared_service, Spec, ordinary)} of
            {none, _} -> [];
            {_, ordinary} -> [internal];
            {_, aggregate_only} -> [internal, aggregate_request, aggregate_valid]
        end,
    Copy = iolist_to_binary([
        [atom_to_list(Field), ": ticket.", atom_to_list(Field), ",\n      "]
     || Field <- Fields
    ]),
    xls_template:render(Template, [
        {<<"@@REDUCTION_FIELDS@@">>, Copy},
        {<<"@@MACHINE_BITS@@">>, xls_collection_codegen:loader_value(Spec)}
        | xls_indexed_memory_codegen:loader_bindings(Spec)
    ]).

%% The RAM owner keeps its owner phases in DSLX; bindings specialize only feature hooks.
-spec shared_service(spec()) -> iodata().
shared_service(Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    Mode = maps:get(shared_service, Spec, ordinary),
    Path = filename:join(code:priv_dir(hls_lowering), "xls/templates/shared_service.x.in"),
    {ok, Template} = file:read_file(Path),
    Bindings =
        service_ports(Spec, Reductions, Mode) ++
            service_capture(Spec, Reductions, Mode) ++
            service_retirement(Spec, Reductions, Mode) ++
            service_admission(Spec, Reductions, Mode) ++ service_memory(Spec),
    [
        ?REDUCTION_SERVICE:shared_service_helpers(Reductions, Mode),
        xls_template:render(Template, Bindings)
    ].

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
            xls_collection_observation:proc_field(Spec)
        ]},
        {<<"@@CONFIG_PORTS@@">>, [
            lists:join(",\n", [["      ", Parameter] || Parameter <- RamConfigParameters]),
            ?REDUCTION_SERVICE:shared_config_parameter(Reductions, SharedService),
            xls_scheduler_observation:config_parameter(Spec),
            xls_collection_observation:config_parameter(Spec)
        ]},
        {<<"@@REQUEST_STAGE_CHANNEL@@">>,
            case maps:get(gather_collection, Spec, false) of
                true ->
                    [];
                false ->
                    "    let (queued_ticket_p, queued_ticket_c) = "
                    "chan<SharedDispatchTicket, u32:1>(\"queued_ticket\");\n"
            end},
        {<<"@@EXECUTOR_INSTANCE@@">>, xls_state_projection:argument(Spec)},
        {<<"@@REQUEST_STAGE_SPAWN@@">>,
            case maps:get(gather_collection, Spec, false) of
                true -> [];
                false -> "    spawn SharedRequestStage(dispatch_c, queued_ticket_p);\n"
            end},
        {<<"@@LOADER_INPUT@@">>,
            case maps:get(gather_collection, Spec, false) of
                true -> "      dispatch_c";
                false -> "      queued_ticket_c"
            end},
        {<<"@@LOADER_GATHER_PORTS@@">>,
            xls_indexed_memory_codegen:optional(
                Spec,
                ", gather_read_req_out, gather_read_resp_in"
            )},
        {<<"@@CONFIG_VALUES@@">>, [
            lists:join("\n", [["      ", Name, ","] || Name <- RamNames]),
            ?REDUCTION_SERVICE:shared_config_endpoint(Reductions, SharedService),
            xls_scheduler_observation:config_value(Spec),
            xls_collection_observation:config_value(Spec)
        ]}
    ].

%% Sample prior state and capture producers independently of loader responses. Aggregate
%% capture extends the token chain used by BOOT, STARTUP and result reception.
-spec service_capture(spec(), none | map(), ordinary | aggregate_only) -> service_bindings().
service_capture(Spec, Reductions, SharedService) ->
    [
        {<<"@@OBSERVATIONS@@">>, [
            xls_scheduler_observation:sample(Spec),
            xls_collection_observation:sample(Spec)
        ]},
        {<<"@@CAPTURE_INPUTS@@">>, [
            xls_collection_codegen:capture(Spec),
            ?REDUCTION_SERVICE:shared_capture(Reductions, SharedService)
        ]},
        {<<"@@BOOT_TOKEN@@">>, ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService)},
        {<<"@@STARTUP_TOKEN@@">>,
            ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService)},
        {<<"@@RESULT_TOKEN@@">>, ?REDUCTION_SERVICE:shared_capture_token(Reductions, SharedService)}
    ].

%% Merge captured inputs with prior credits, resolve the held result, then retire metadata. Incoming
%% results cannot bypass completion storage; failed reply actors must drain retained replies.
-spec service_retirement(spec(), none | map(), ordinary | aggregate_only) -> service_bindings().
service_retirement(Spec, Reductions, SharedService) ->
    [
        {<<"@@REPLY_PHASE_FAILURE@@">>,
            xls_statem_reply_codegen:optional(
                Spec,
                " || hls_failure::failed(stepped.machine.failure)"
            )},
        {<<"@@FAILURE_RETIRES@@">>,
            case xls_statem_reply_codegen:enabled(Spec) of
                true -> "false";
                false -> "hls_failure::failed(stepped.machine.failure)"
            end},
        {<<"@@CONTINUATION_PENDING@@">>, [
            xls_statem_event_codegen:optional(
                Spec,
                " || stepped.machine.next_event != u8:0"
            ),
            pending_reply_drain(Spec)
        ]},
        {<<"@@INDEXED_RETIREMENT_READY@@">>,
            xls_indexed_memory_codegen:optional(
                Spec,
                "          state.indexed_retirement_valid &&\n"
            )},
        {<<"@@DECODE_RESULT@@">>,
            xls_machine_codegen:decode(Spec, "result.machine", "result.slot")},
        {<<"@@RESOLVE_RESULT@@">>, [
            xls_collection_codegen:resolve(Spec),
            xls_indexed_collection_codegen:resolve(Spec)
        ]},
        {<<"@@CAPTURED_FIELDS@@">>, xls_collection_codegen:captured_field(Spec)},
        {<<"@@CREDITED_SOURCE@@">>,
            ?REDUCTION_SERVICE:shared_state_source(Reductions, SharedService)},
        {<<"@@RETIRE_METADATA@@">>, [
            ?REDUCTION_SERVICE:shared_retire_binding(
                Reductions,
                xls_collection_codegen:retire_binding(Spec)
            ),
            xls_collection_codegen:retire(Spec),
            xls_gather_codegen:retire(Spec),
            xls_indexed_collection_codegen:retire(Spec)
        ]}
    ].

%% Select from prior snapshots, apply admission to retired metadata, then reserve dispatch.
%% Exclusive collection selects from its own unmasked snapshot; opportunistic collection
%% uses ordinary intent. Indexed preparation reserves its actor before payload loading.
-spec service_admission(spec(), none | map(), ordinary | aggregate_only) -> service_bindings().
service_admission(Spec, Reductions, SharedService) ->
    [
        {<<"@@SELECT_ACTOR@@">>, xls_gather_codegen:issue_bindings(Spec)},
        {<<"@@SELECT_ADMISSION@@">>, [
            ordinary_selection(Spec),
            xls_collection_codegen:admit(Spec),
            xls_indexed_collection_codegen:admit(Spec)
        ]},
        {<<"@@COLLECTED_GUARD@@">>, xls_collection_codegen:admission_guard(Spec)},
        {<<"@@ADMIT_AND_ISSUE@@">>, [
            xls_collection_codegen:commit(Spec),
            xls_indexed_collection_codegen:commit(Spec),
            xls_collection_codegen:issue(Spec),
            xls_indexed_collection_codegen:issue(Spec),
            ?REDUCTION_SERVICE:shared_post_issue_state(Reductions, SharedService)
        ]},
        {<<"@@ISSUE_OWNERSHIP@@">>, issue_ownership(Spec)},
        {<<"@@ISSUED_SOURCE@@">>,
            ?REDUCTION_SERVICE:shared_post_issue_state_name(Reductions, SharedService)},
        {<<"@@TICKET_FIELDS@@">>, [
            ?REDUCTION_SERVICE:shared_executor_request_value(Reductions, SharedService),
            xls_collection_codegen:ticket_value(Spec),
            xls_indexed_collection_codegen:ticket_value(Spec)
        ]}
    ].

%% Acknowledge prior writes before dispatch; send old commands and register new ones.
%% Indexed payload RAM participates in the same write-visibility fence and memory-token chain.
-spec service_memory(spec()) -> service_bindings().
service_memory(Spec) ->
    [
        {<<"@@GATHER_COMPLETION@@">>,
            xls_indexed_memory_codegen:optional(
                Spec,
                "        let (gather_completion_tok, _) = recv_if(join(), gather_write_resp_in,\n"
                "          state.gather_write_pending, zero!<GatherRamWriteResp>());\n"
            )},
        {<<"@@GATHER_DISPATCH_FENCE@@">>,
            xls_indexed_memory_codegen:optional(Spec, ", gather_completion_tok")},
        {<<"@@GATHER_WRITE@@">>,
            xls_indexed_memory_codegen:optional(
                Spec,
                "        let gather_write_tok = send_if(join(memory_tok, gather_completion_tok),\n"
                "          gather_write_req_out, state.write_gather_valid, GatherRamWriteReq {\n"
                "            addr: state.write_gather_addr, mask: state.write_gather_mask,\n"
                "            data: indexed_write_data(state.write_gather_value) });\n"
            )},
        {<<"@@GATHER_DONE@@">>,
            xls_indexed_memory_codegen:optional(
                Spec,
                ", gather_completion_tok, gather_write_tok"
            )},
        {<<"@@GATHER_NEXT_COMMANDS@@">>,
            xls_indexed_memory_codegen:optional(
                Spec,
                "          gather_write_pending: state.write_gather_valid,\n"
                "          write_gather_valid: indexed_admission.write_valid,\n"
                "          write_gather_slot: indexed_intent.slot,\n"
                "          write_gather_addr: indexed_admission.write.addr,\n"
                "          write_gather_mask: indexed_admission.write.mask,\n"
                "          write_gather_value: indexed_transport_contribution(state.indexed_input.frame).value,\n"
            )},
        {<<"@@GATHER_MEMORY_TOKEN@@">>,
            xls_indexed_memory_codegen:optional(Spec, ", gather_write_tok")}
    ].

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
    Selected = xls_collection_codegen:selection(Spec, #{
        ordinary_state => "admission_snapshot",
        collection_state => "state",
        ordinary_result => "next_intent"
    }),
    Source =
        case maps:get(gather_collection, Spec, false) of
            true -> "indexed_preparation_source(state, prepare_valid, prepare_slot)";
            false -> "state"
        end,
    [
        "\n        let admission_snapshot = ordinary_selection_source(",
        Source,
        ");\n",
        Selected,
        "        let intent = state.ordinary_intent;\n"
    ].

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

%% Only retained callers need follow-up scheduling after failure; immediate origins are not stored.
-spec pending_reply_drain(spec()) -> iodata().
pending_reply_drain(#{retained_calls := #{pending_calls := _}}) ->
    " || (hls_failure::failed(stepped.machine.failure) && hls_reply::first(stepped.machine.replies.slots, true).0)";
pending_reply_drain(_) ->
    [].
