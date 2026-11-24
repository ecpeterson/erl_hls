-module(xls_local_owner).
-moduledoc "Renders receipt/action functions and the single-actor DSLX clock owner used by hls_local_actor and source transport. Mailbox selection remains external; importing a checked owner preserves its exact failure codebook.".

%% Local clock-owner rendering.
-export([ports/1, ports/2]).

%% Composition with an existing actor artifact.
-export([import_owner/2]).

-doc "Emits receipt, callback-action, entry/publication and clock-owner DSLX beside the ordinary activation reference. Handled receipts either finish an effect-free activation or retain the final gather head for deferred completion. The slow port composes local_action_at with local_enter_at and requires receipt interception and no received frame during pending internal work. A separated caller must retain the complete action and its actor slot through blocked publication, with no intervening activation or mailbox retirement. Retained replies are part of the registered action and publish before any following entry.".
-spec ports(xls_actor_codegen:spec()) -> iodata().
ports(Spec) -> ports(Spec, local).

-doc "Emits the same source functions with local or externally granted scalar completion. The shared mode is internal to the freshly validated arithmetic-group builder: its owner waits for the group grant and registers that action before entry. Public local_action_at/local_slow_step_at remain the ordinary source references. Only the shared owner disables local scalar dispatch and consumes local_reduce_action_at from its group. No saved artifact or caller-supplied action is accepted by the network builder.".
-spec ports(xls_actor_codegen:spec(), local | shared) -> iodata().
ports(
    Spec = #{
        message_names := Names,
        message_words := Words,
        reductions := Reductions,
        gathers := Gathers
    },
    Mode
) ->
    Tag = xls_actor_codegen:input_tag_ok(Spec, Names, Words),
    [
        template("local_protocol", [
            {<<"@@SCALAR@@">>, scalar(Reductions)},
            {<<"@@GATHER@@">>, gather(Gathers)},
            {<<"@@TAG_OK@@">>, Tag}
        ]),
        template("local_slow", [
            {<<"@@PLAIN_FUNCTION@@">>, plain_dispatch(Spec, Tag)},
            {<<"@@REPLY_FIELDS@@">>, reply(Spec, fields)},
            {<<"@@REPLY_CAPTURE@@">>, reply(Spec, capture)},
            {<<"@@REPLY_ENTER@@">>, reply(Spec, enter)},
            {<<"@@REPLY_ENTER_END@@">>, reply(Spec, enter_end)},
            {<<"@@ATOMIC_REPLY@@">>, reply(Spec, atomic)},
            {<<"@@ATOMIC_REPLY_END@@">>, reply(Spec, atomic_end)},
            {<<"@@SELECTED@@">>, dispatch(Spec)}
        ]),
        template("local_owner", [
            {<<"@@SHARED_INPUTS@@">>, shared(Mode, inputs)},
            {<<"@@LOCAL_COMPLETION@@">>,
                case Mode of
                    local -> "true";
                    shared -> "false"
                end},
            {<<"@@SHARED_COMPLETION@@">>, shared(Mode, completion)},
            {<<"@@SHARED_FUNCTIONS@@">>,
                case Mode of
                    local ->
                        [];
                    shared ->
                        template(
                            "local_arithmetic",
                            [
                                {<<"@@NO_EVENT@@">>,
                                    xls_statem_event_codegen:optional(
                                        Spec, " && machine.next_event == u8:0"
                                    )}
                            ]
                        )
                end}
        ])
    ].

-doc "Renders a receiver's import facade for an already emitted owner. File is the relative owner DSLX path from the same trusted transport build; its module basename and actor/helper byte hashes bind the import. Retains and rebinds the owner's checked failure codebook and dependencies without source reads.".
-spec import_owner(hls_local_actor:artifact(), binary()) -> hls_local_actor:artifact().
import_owner(Owner = #{emitted := Emitted}, File) ->
    Bytes = xls_emitted:bytes(Emitted),
    Name = filename:basename(binary_to_list(File), ".x"),
    Imported = template("local_owner_import", [{<<"@@MODULE@@">>, Name}]),
    Owner#{
        emitted := xls_emitted:with_bytes(Emitted, Imported),
        owner_import => #{
            file => File,
            dslx_sha256 => binary:encode_hex(crypto:hash(sha256, Bytes), lowercase),
            dslx_dependencies => maps:from_list([
                {unicode:characters_to_binary(Dependency), hls_generated_files:hash(Data)}
             || {Dependency, Data} <- maps:to_list(xls_emitted:dependencies(Emitted))
            ])
        }
    }.

%% ActorState and source callback types are local to the generated module, so
%% these fragments fill typed declaration slots rather than rewrite generated code.
-spec template(string(), [{binary(), iodata()}]) -> binary().
template(Name, Bindings) ->
    Path = filename:join(code:priv_dir(hls_target), "xls/templates/" ++ Name ++ ".x.in"),
    {ok, Bytes} = file:read_file(Path),
    xls_template:render(Bytes, Bindings).

%% Scalar completion remains an ordinary later activation; receipt storage does not publish.
-spec scalar(none | map()) -> iodata().
scalar(none) ->
    "// No scalar collection; retain ordinary dispatch.\n"
    "fn local_protocol_scalar(machine: ActorState, frame: axis::Frame) -> LocalProtocolResult { local_protocol_unhandled(machine) }\n";
scalar(_) ->
    template("local_protocol_scalar", []).

%% Only a final indexed receipt needs a private state and a still-owned mailbox head.
-spec gather(none | map()) -> iodata().
gather(none) ->
    "// No indexed collection; try the scalar receipt path.\n"
    "fn local_protocol_gather(machine: ActorState, frame: axis::Frame) -> LocalProtocolResult { local_protocol_scalar(machine, frame) }\n";
gather(_) ->
    template("local_protocol_gather", []).

%% Reuse ordinary callback generators and preserve gather/event/scalar priority.
-spec dispatch(xls_actor_codegen:spec()) -> iodata().
dispatch(Spec = #{reductions := Reductions, gathers := Gathers}) ->
    Plain = "local_plain_dispatch(machine, axis::frame_from_bits(frame), received)",
    Ordinary =
        case Reductions of
            none ->
                Plain;
            _ ->
                [
                    "if complete_locally && !machine.enter_pending && machine.reduction.status == ReductionStatus::COMPLETE { shared_machine_complete(machine) } else { ",
                    Plain,
                    " }"
                ]
        end,
    Events = [
        xls_statem_event_codegen:optional(
            Spec,
            "if !hls_failure::failed(machine.failure) && !machine.enter_pending && machine.next_event != u8:0 { actor_next_event(machine) } else "
        ),
        "{ ",
        Ordinary,
        " }"
    ],
    case Gathers of
        none -> Events;
        _ -> template("local_slow_gather", [{<<"@@EVENTS@@">>, Events}])
    end.

%% Only shared owners expose a completion input and wait before ordinary dispatch.
-spec shared(local | shared, inputs | completion) -> iodata().
shared(local, _) -> [];
shared(shared, inputs) -> "  completion_granted: bool,\n  completion_action: LocalAction,\n";
shared(shared, completion) -> template("local_arithmetic_owner", []).

%% Retained calls reuse the common admission/reply implementation unchanged.
-spec plain_dispatch(xls_actor_codegen:spec(), iodata()) -> iodata().
plain_dispatch(Spec = #{reductions := Reductions}, Tag) ->
    case xls_statem_reply_codegen:enabled(Spec) of
        true ->
            "// Common dispatch owns bounded call handles and validates replies.\n"
            "fn local_plain_dispatch(machine: ActorState, frame: axis::Frame, received: bool)\n"
            "    -> ActorDispatch {\n"
            "  if hls_failure::failed(machine.failure) { actor_reply_failure(machine, frame, received) }\n"
            "  else { shared_machine_dispatch(machine, frame, received) }\n"
            "}\n";
        false ->
            template("local_plain", [
                {<<"@@TAG_OK@@">>, Tag},
                {<<"@@BINDINGS@@">>,
                    xls_reduction_service_codegen:shared_dispatch_bindings(none, ordinary, Spec)},
                {<<"@@EFFECTIVE@@">>,
                    xls_reduction_service_codegen:shared_dispatch_effective_binding(
                        Reductions, ordinary, Spec
                    )},
                {<<"@@FAILED@@">>,
                    xls_reduction_service_codegen:shared_dispatch_failed_binding(
                        Reductions, ordinary, Spec
                    )},
                {<<"@@NEXT_EVENT@@">>,
                    xls_statem_event_codegen:optional(
                        Spec,
                        "      next_event: if effective && !failed { next_event } else { u8:0 },"
                    )},
                {<<"@@DISPATCHED@@">>,
                    xls_reduction_service_codegen:shared_dispatch_dispatched_field(
                        Reductions, ordinary, Spec
                    )}
            ])
    end.

%% The bounded reply is reserved with its callback action until output storage exists.
-spec reply(xls_actor_codegen:spec(), fields | capture | enter | enter_end | atomic | atomic_end) ->
    iodata().
reply(#{retained_calls := none}, _) ->
    [];
reply(_Spec, fields) ->
    "  reply: axis::Frame,\n  reply_valid: bool,\n";
reply(_Spec, capture) ->
    "    reply: dispatched.reply, reply_valid: dispatched.reply_valid,\n";
reply(Spec, enter) ->
    [
        "  if action.reply_valid {\n",
        "    LocalStepResult { machine: action.private_machine,\n",
        "      effect_payload: axis::bits_from_frame(action.reply) as bits[ENTRY_EFFECT_PAYLOAD_BITS],\n",
        "      effect_layout: u8:",
        integer_to_list(xls_statem_reply_codegen:layout(Spec)),
        ", effect_count: u8:1, effects_valid: effects_reserved,\n",
        "      dispatched: action.dispatched, directive: action.directive,\n",
        "      phase_boundary: action.phase_boundary, egress_blocked: !effects_reserved }\n",
        "  } else {\n"
    ];
reply(_Spec, enter_end) ->
    "  }\n";
reply(_Spec, atomic) ->
    "  // The atomic reference cannot retain an uncommitted reply action.\n"
    "  if action.reply_valid && !effects_reserved {\n"
    "    local_step_at(raw, frame, received, effects_reserved, slot)\n"
    "  } else {\n";
reply(_Spec, atomic_end) ->
    "  }\n".
