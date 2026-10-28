-module(xls_machine_codegen).
-moduledoc "Renders the common actor-machine representation and execution functions used by activation and scheduler codegen. xls_machine_layout supplies complete row slices; callback lowering remains compiler-owned, and each execution owner supplies its own storage and selection.".

%% Physical machine types and codecs.
-export([state_type/1, step_type/0, executor_types/1, codec/1, decode/3]).

%% Common actor transition functions.
-export([step/1, execute/1]).
-define(REDUCTION_SERVICE, xls_reduction_service_codegen).
%% Checked actor semantics with optional backend-selected projection/completion annotations.
-type spec() :: xls_actor_codegen:spec().

-doc "Declares packed actor state using the canonical machine-row layout, without storage ownership.".
-spec state_type(spec()) -> iodata().
state_type(Spec) ->
    MachineBits = xls_machine_layout:width(xls_machine_layout:from_spec(Spec)),
    [
        "pub type MachineBits = bits[", integer_to_list(MachineBits), "];\n\n"
    ].

-doc "Declares one atomic activation outcome before physical row encoding.".
-spec step_type() -> iodata().
step_type() ->
    [
        "struct SharedStep {\n",
        "  machine: ActorState,\n",
        "  effects: EntryEffects,\n",
        "  effects_valid: u1,\n",
        "  dispatched: u1,\n",
        "  directive: Directive,\n",
        "  phase_boundary: u1,\n",
        "  egress_blocked: u1,\n",
        "}\n\n"
    ].

-doc "Declares the pure executor request/result ABI, including checked optional completion inputs. The caller owns request ordering and result storage.".
-spec executor_types(spec()) -> iodata().
executor_types(Spec) ->
    Reductions = maps:get(reductions, Spec, none),
    SharedService = maps:get(shared_service, Spec, ordinary),
    [
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
        "}\n\n"
    ].

-doc "Renders the canonical row codec with semantic slot/phase reconstruction; no RAM access is emitted.".
-spec codec(spec()) -> iodata().
codec(Spec) ->
    Layout = #{fields := Fields} = xls_machine_layout:from_spec(Spec),
    [
        xls_struct_codec:declaration("MachineRow", Layout),
        "\n",
        xls_struct_codec:decoder("MachineRow", "machine_row_from_bits", Layout),
        "\n",
        xls_struct_codec:encoder("MachineRow", "bits_from_machine_row", Layout),
        "\n",
        "fn machine_from_bits",
        xls_state_projection:parameter(Spec),
        "(raw: MachineBits",
        case maps:is_key(state_projection, Spec) of
            true -> ", slot: u32";
            false -> ""
        end,
        ") -> ActorState {\n",
        "  let row = machine_row_from_bits(raw);\n",
        "  ActorState {\n",
        [
            [
                "    ",
                atom_to_list(Name),
                ": ",
                machine_value(
                    Spec,
                    Name,
                    hls_type:dslx_to_bits(Type, ["row.", atom_to_list(Name)])
                ),
                ",\n"
            ]
         || #{name := Name, type := Type, width := Width} <- Fields,
            Name =:= data orelse Width > 0
        ],
        "  }\n}\n\n",
        "fn bits_from_machine(machine: ActorState) -> MachineBits {\n",
        "  bits_from_machine_row(MachineRow {\n",
        [
            [
                "    ",
                atom_to_list(Name),
                ": ",
                hls_type:dslx_from_bits(
                    Type,
                    case Width of
                        0 -> "zero!<bits[0]>()";
                        _ -> machine_bits(Spec, Name)
                    end
                ),
                ",\n"
            ]
         || #{name := Name, type := Type, width := Width} <- Fields
        ],
        "  })\n}\n\n"
    ].

%% Row data reconstruction alone needs instance, slot and decoded phase context.
-spec machine_value(spec(), xls_machine_layout:name(), iodata()) -> iodata().
machine_value(_Spec, Name, Raw) when Name =:= phase; Name =:= entered_from ->
    [Raw, " as Phase"];
machine_value(Spec, data, Raw) ->
    xls_state_projection:decode(Spec, Raw, "slot", "row.phase as Phase");
machine_value(_Spec, reduction, Raw) ->
    ["reduction_state_from_bits(", Raw, ")"];
machine_value(Spec, gather, Raw) ->
    xls_gather_codegen:decode(Spec, Raw);
machine_value(_Spec, replies, Raw) ->
    ["hls_reply::from_bits<REPLY_CAPACITY>(", Raw, ")"];
machine_value(_Spec, _Name, Raw) ->
    Raw.

%% Feature codecs convert semantic values; the row schema determines their placement.
-spec machine_bits(spec(), xls_machine_layout:name()) -> iodata().
machine_bits(Spec, data) ->
    xls_state_projection:encode(Spec, "machine.data");
machine_bits(_Spec, reduction) ->
    "bits_from_reduction_state(machine.reduction)";
machine_bits(Spec, gather) ->
    xls_gather_codegen:encode(Spec, "machine.gather");
machine_bits(_Spec, replies) ->
    "hls_reply::to_bits(machine.replies)";
machine_bits(_Spec, Name) when Name =:= phase; Name =:= entered_from ->
    ["machine.", atom_to_list(Name), " as bits[8]"];
machine_bits(_Spec, Name) ->
    ["machine.", atom_to_list(Name)].

-doc "Emits mailbox dispatch and phase entry over actor state, preserving source failure and repeat semantics independently of the state owner.".
-spec step(spec()) -> iodata().
step(
    #{
        message_names := MessageNames,
        message_words := MessageWords
    } = Spec
) ->
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
        xls_actor_codegen:input_tag_ok(Spec, MessageNames, MessageWords),
        ";\n",
        xls_statem_reply_codegen:admit(Spec, "frame", "tag_ok"),
        ?REDUCTION_SERVICE:shared_dispatch_bindings(
            Reductions, SharedService, Spec
        ),
        "    let invalid_repeat = ",
        xls_statem_reply_codegen:optional(
            Spec, "(tag_ok && is_call(frame.header.op) && directive == Directive::POSTPONE) || "
        ),
        "tag_ok && repeat_phase &&\n",
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
        "      phase: if effective",
        xls_statem_reply_codegen:optional(Spec, " && !contract_fault"),
        " { next_phase } else { machine.phase },\n",
        "      entered_from: if phase_boundary {\n",
        "        machine.phase\n",
        "      } else { machine.entered_from },\n",
        "      data: if effective",
        xls_statem_reply_codegen:optional(Spec, " && !contract_fault"),
        " { next_data } else { machine.data },\n",
        xls_statem_reply_codegen:optional(Spec, "      replies: reply_book,\n"),
        xls_statem_event_codegen:optional(
            Spec, "      next_event: if effective && !failed { next_event } else { u8:0 },\n"
        ),
        ?REDUCTION_SERVICE:shared_dispatch_reduction_field(
            Reductions, SharedService
        ),
        "      enter_pending: effective && phase_boundary && !failed,\n",
        "      failure,\n",
        "      ..machine\n",
        "    };\n",
        "    ActorDispatch {\n",
        "      machine: next_machine,\n",
        xls_statem_reply_codegen:optional(
            Spec, "      reply: response, reply_valid: response_valid,\n"
        ),
        case xls_statem_reply_codegen:enabled(Spec) of
            true ->
                "      dispatched: failed || effective,\n      directive: if failed { Directive::CONSUME } else { directive },\n";
            false ->
                [
                    ?REDUCTION_SERVICE:shared_dispatch_dispatched_field(
                        Reductions, SharedService, Spec
                    ),
                    "      directive,\n"
                ]
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

-doc "Emits one pure activation over reserved state/effect storage. Preserves source dispatch, first failure, ordered effects and mailbox disposition; does not choose or issue work.".
-spec execute(spec()) -> iodata().
execute(Spec) ->
    [
        "pub fn shared_execute",
        xls_state_projection:parameter(Spec),
        """
        (request: SharedExecutorRequest) ->
            SharedExecutorResult {
        """,
        "  let machine = ",
        decode(Spec, "request.machine", "request.slot"),
        ";\n",
        "\n",
        xls_event_codegen:shared_dispatch(Spec),
        xls_statem_reply_codegen:optional(Spec, [
            "  let dispatched = if dispatched.reply_valid && !request.egress_ready {\n",
            "    ActorDispatch { machine, ..zero!<ActorDispatch>() }\n  } else { dispatched };\n"
        ]),
        """
        """,
        "  let entered = ",
        shared_reply_effect(Spec),
        "shared_machine_enter(\n",
        "    dispatched.machine, request.egress_ready)",
        xls_statem_reply_codegen:optional(Spec, " }"),
        ";\n",
        """
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

        """
    ].

-doc "Decodes one packed state with its explicit actor slot and selected projection instance.".
-spec decode(spec(), iodata(), iodata()) -> iodata().
decode(Spec, Raw, Slot) ->
    [
        "machine_from_bits",
        xls_state_projection:argument(Spec),
        "(",
        Raw,
        case maps:is_key(state_projection, Spec) of
            true -> [", ", Slot];
            false -> ""
        end,
        ")"
    ].

%% A reply precedes phase entry; that entry remains pending for the next activation.
-spec shared_reply_effect(map()) -> iodata().
shared_reply_effect(Spec) ->
    case xls_statem_reply_codegen:enabled(Spec) of
        false ->
            [];
        true ->
            [
                "if dispatched.reply_valid { SharedStep { machine: dispatched.machine, effects: ",
                xls_statem_reply_codegen:effect(Spec),
                ", effects_valid: true, ..zero!<SharedStep>() } } else { "
            ]
    end.
