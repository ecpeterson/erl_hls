-module(hls_local_protocol).
-moduledoc "Splits collection receipts from source callbacks at the local actor boundary; includes the single-actor DSLX clock owner; mailbox selection remains external.".
-export([ports/1]).

-doc "Emits receipt, callback-action, entry/publication and clock-owner DSLX beside the ordinary activation reference. Handled receipts either finish an effect-free activation or retain the final gather head for deferred completion. The slow port composes local_action_at with local_enter_at and requires receipt interception and no received frame during pending internal work. A separated caller must retain the complete action and its actor slot through blocked publication, with no intervening activation or mailbox retirement. Retained calls are unsupported.".
-spec ports(xls_actor_codegen:spec()) -> iodata().
ports(Spec = #{message_names := Names, message_words := Words,
        reductions := Reductions, gathers := Gathers}) ->
    false = xls_statem_reply_codegen:enabled(Spec),
    Tag = xls_actor_codegen:input_tag_ok(Spec, Names, Words),
    [template("local_protocol", [{<<"@@SCALAR@@">>, scalar(Reductions)},
        {<<"@@GATHER@@">>, gather(Gathers)}, {<<"@@TAG_OK@@">>, Tag}]),
     template("local_slow", [{<<"@@TAG_OK@@">>, Tag},
        {<<"@@BINDINGS@@">>, xls_shared_reduction_service_codegen:shared_dispatch_bindings(none, ordinary, Spec)},
        {<<"@@EFFECTIVE@@">>, xls_shared_reduction_service_codegen:shared_dispatch_effective_binding(Reductions, ordinary, Spec)},
        {<<"@@FAILED@@">>, xls_shared_reduction_service_codegen:shared_dispatch_failed_binding(Reductions, ordinary, Spec)},
        {<<"@@NEXT_EVENT@@">>, xls_statem_event_codegen:optional(Spec,
            "      next_event: if effective && !failed { next_event } else { u8:0 },")},
        {<<"@@DISPATCHED@@">>, xls_shared_reduction_service_codegen:shared_dispatch_dispatched_field(Reductions, ordinary, Spec)},
        {<<"@@SELECTED@@">>, dispatch(Spec)}]), template("local_owner", [])].

%% ActorState and source callback types are local to the generated module, so
%% these fragments fill typed declaration slots rather than rewrite generated code.
-spec template(string(), [{binary(), iodata()}]) -> binary().
template(Name, Bindings) ->
    Path = filename:join(code:priv_dir(hls_fabric), "xls/templates/" ++ Name ++ ".x.in"),
    {ok, Bytes} = file:read_file(Path),
    xls_template:render(Bytes, Bindings).

%% Scalar completion remains an ordinary later activation; receipt storage does not publish.
-spec scalar(none | map()) -> iodata().
scalar(none) ->
    "// No scalar collection; retain ordinary dispatch.\n"
    "fn local_protocol_scalar(machine: ActorState, frame: axis::Frame) -> LocalProtocolResult { local_protocol_unhandled(machine) }\n";
scalar(_) -> template("local_protocol_scalar", []).

%% Only a final indexed receipt needs a private state and a still-owned mailbox head.
-spec gather(none | map()) -> iodata().
gather(none) ->
    "// No indexed collection; try the scalar receipt path.\n"
    "fn local_protocol_gather(machine: ActorState, frame: axis::Frame) -> LocalProtocolResult { local_protocol_scalar(machine, frame) }\n";
gather(_) -> template("local_protocol_gather", []).

%% Reuse ordinary callback generators and preserve gather/event/scalar priority.
-spec dispatch(xls_actor_codegen:spec()) -> iodata().
dispatch(Spec = #{reductions := Reductions, gathers := Gathers}) ->
    Plain = "local_plain_dispatch(machine, axis::frame_from_bits(frame), received)",
    Ordinary = case Reductions of
        none -> Plain;
        _ -> ["if !machine.enter_pending && machine.reduction.status == ReductionStatus::COMPLETE { shared_machine_complete(machine) } else { ", Plain, " }"]
    end,
    Events = [xls_statem_event_codegen:optional(Spec,
        "if !hls_failure::failed(machine.failure) && !machine.enter_pending && machine.next_event != u8:0 { actor_next_event(machine) } else "),
        "{ ", Ordinary, " }"],
    case Gathers of
        none -> Events;
        _ -> template("local_slow_gather", [{<<"@@EVENTS@@">>, Events}])
    end.
