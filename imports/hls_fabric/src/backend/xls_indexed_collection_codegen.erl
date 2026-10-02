-module(xls_indexed_collection_codegen).
-moduledoc "Emits source-checked indexed gather ownership independently of scalar reduction collectors.".
-export([validate/2, imports/1, declarations/1, helpers/1, state_fields/1,
    ticket_field/1, ticket_value/1, resolve/1,
    retire/1, admit/1, commit/1, issue/1]).

-doc "Requires one numeric-member gather with message-only lifting and an ordinary shared executor; warns about asserted overlap and key-uniform eligibility.".
-spec validate(map(), map()) -> ok.
validate(Spec, Options) ->
    case maps:get(gather_collection, Options, maps:get(gather_collection, Spec, false)) of
        false -> ok;
        true ->
            case {maps:get(shared_service, Options, ordinary), maps:get(gathers, Spec, none),
                    xls_statem_reply_codegen:enabled(Spec)} of
                {ordinary, #{sites := [#{population := #{mode := members}} = Site]}, false} ->
                    Cs = maps:get(contributions, Site),
                    Tags = [maps:get(tag, C) || C <- Cs],
                    true = Tags =/= [],
                    case length(Tags) =:= length(lists:usort(Tags)) of
                        true -> ok;
                        false -> error(indexed_gather_ambiguous_transport)
                    end,
                    lists:foreach(fun require_lift/1, Cs),
                    logger:warning("gather_collection asserts exclusive reserved tags, key-uniform postponement except member checks, at most two live keys, and bounded stale-ticket age; these protocol properties are not compile-time verified"),
                    ok;
                _ -> error(indexed_gather_requires_one_ordinary_member_site)
            end;
        Other -> error({gather_collection, Other})
    end.

%% A partial message-only lift remains checked; a data-dependent lift is unsupported.
-spec require_lift(map()) -> ok.
require_lift(#{tag := Tag} = Contribution) ->
    case maps:get(independent_lift, Contribution, maps:get(transport, Contribution, none)) of
        #{body := _, result := _} ->
            case maps:get(source_capture_total, Contribution, false) of
                true -> ok;
                false -> logger:warning("indexed gather reserved tag ~p has a partial source lift; rejected frames remain protocol failures", [Tag])
            end;
        _ -> error({indexed_gather_state_dependent_lift, Tag})
    end.

-doc "Lists the payload-free ownership kernel and masked memory channel library.".
-spec imports(map()) -> [atom()].
imports(Spec) -> case enabled(Spec) of
    true -> [indexed_collection_core, indexed_gather_ram];
    false -> []
end.

-doc "Defines narrow ownership, dispatch tickets and independent payload-memory channel types.".
-spec declarations(map()) -> iodata().
declarations(Spec) -> optional(Spec, fun() ->
    #{gathers := #{sites := [Site]}} = Spec,
    #{population := #{size := Capacity}, element := Element, phase := Phase} = Site,
    Width = xls_statem_reduction_ir:type_width(Element),
    ["const INDEXED_CAPACITY = u32:", integer_to_list(Capacity), ";\n",
     "const INDEXED_ELEMENT_BITS = u32:", integer_to_list(Width), ";\n",
     "const INDEXED_SITE = GatherSite::", xls_names:enum_member(Phase), ";\n",
     "type IndexedBanks = indexed_collection_core::State<INDEXED_CAPACITY>;\n",
     "type IndexedLease = indexed_collection_core::Lease;\n",
     "pub type GatherRamReadReq = indexed_gather_ram::ReadReq;\n",
     "pub type GatherRamReadResp = indexed_gather_ram::ReadResp<INDEXED_ELEMENT_BITS, INDEXED_CAPACITY>;\n",
     "pub type GatherRamWriteReq = indexed_gather_ram::WriteReq<INDEXED_ELEMENT_BITS, INDEXED_CAPACITY>;\n",
     "pub type GatherRamWriteResp = indexed_gather_ram::WriteResp;\n\n",
     "// Shadow fields are used only for source eligibility; XLS removes unused payload/state fields.\n",
     "struct IndexedContext { initialized: bool, machine: ActorState, banks: IndexedBanks, representatives: axis::Frame[2], representative_valid: bool[2], actor_opened: bool, consuming: bool, lease: IndexedLease, deferred_failure: hls_failure::Code, deferred_frame: axis::Frame, deferred_frame_valid: bool, failure: hls_failure::Code }\n",
     "struct IndexedInput { reserved: bool, frame_valid: bool, contribution: GatherContribution }\n",
     "struct IndexedEligibility { waiting: bool, current: bool, provisional: bool, failure: hls_failure::Code }\n",
     "struct IndexedTicket { valid: bool, progress: GatherProgress, lease: IndexedLease, failure: hls_failure::Code }\n",
     "// Retained-frame commands share the incoming frame; context remains the complete pure result.\n",
     "struct IndexedAdmission { consumed: bool, context: IndexedContext, write_valid: bool, write: GatherRamWriteReq,\n",
     "  representative_write: bool, representative_bank: u1, deferred_write: bool, frame: axis::Frame }\n\n"]
end).

-doc "Emits source predicates and pure shared-scheduler ownership/admission helpers.".
-spec helpers(map()) -> iodata().
helpers(Spec) -> optional(Spec, fun() ->
    #{gathers := #{sites := [Site]}, message_words := Words} = Spec,
    Tags = lists:usort([maps:get(tag, C) || C <- maps:get(contributions, Site)]),
    [transport(Site), reserved_dispatch(Tags, maps:get(data_name, Spec)), selected_frame(Tags),
     "// Reserved tags cannot fall back to a second ordinary accumulator.\n",
     "fn indexed_reserved(frame: axis::Frame) -> bool {\n  ",
     lists:join(" || ", [["frame.header.op == Tag::", xls_names:enum_member(Tag), " as u8"] || Tag <- Tags]),
     "\n}\n\n",
     "// Frame and codec checks match ordinary actor input validation.\n",
     "fn indexed_frame_valid(frame: axis::Frame) -> bool {\n  ",
     xls_actor_codegen:input_tag_ok(Spec, Tags, Words), "\n}\n\n",
     "// Entry and private continuations run before mailbox eligibility is reconsidered.\n",
     "fn indexed_stable(machine: ActorState) -> bool { !machine.enter_pending",
     xls_statem_event_codegen:optional(Spec, " && machine.next_event == u8:0"), " }\n\n",
     template()]
end).

%% Constant tag branches retain source failures without instantiating unrelated handlers.
-spec reserved_dispatch([atom()], atom()) -> iodata().
reserved_dispatch(Tags, DataName) ->
    ["// Check source postponement/failure only for this collector's reserved tags.\n",
     "fn indexed_dispatch(frame: axis::Frame, phase: Phase, data: ", xls_names:record_type(DataName),
     ") -> (Directive, hls_failure::Code) {\n",
     "  match frame.header.op as Tag {\n",
     [["    Tag::", xls_names:enum_member(Tag), " => {\n",
       "      let selected = axis::Frame { header: axis::Header { op: Tag::",
       xls_names:enum_member(Tag), " as u8, ..frame.header }, ..frame };\n",
       "      let result = dispatch(selected, phase, data);\n",
       "      (result.2, result.4)\n    },\n"] || Tag <- Tags],
     "    _ => (Directive::FAIL, hls_failure::INVALID_MESSAGE),\n  }\n}\n\n"].

%% A same-state selection proves the sole tag; multiple tags retain their runtime discriminator.
-spec selected_frame([atom()]) -> iodata().
selected_frame([Tag]) ->
    ["// Same-state indexed_select provenance makes this frame byte-identical.\n",
     "fn indexed_selected_frame(frame: axis::Frame) -> axis::Frame {\n",
     "  axis::Frame { header: axis::Header { op: Tag::", xls_names:enum_member(Tag),
     " as u8, ..frame.header }, ..frame }\n}\n\n"];
selected_frame(_Tags) ->
    "// Multiple reserved tags retain the selected opcode.\n"
    "fn indexed_selected_frame(frame: axis::Frame) -> axis::Frame { frame }\n\n".

%% Transport construction never grants key eligibility; the original callback still does that.
-spec transport(map()) -> iodata().
transport(Site = #{contributions := Contributions, element := #{name := Element}}) ->
    Codec = xls_names:record_codec(Element),
    ["// Decode one held frame independently of mutable actor state.\n",
     "fn indexed_transport_contribution(frame: axis::Frame) -> GatherContribution {\n",
     "  match frame.header.op as Tag {\n",
     [begin
        #{tag := Tag} = C,
        #{body := Body, result := Result} = maps:get(independent_lift, C, maps:get(transport, C, none)),
        ["    Tag::", xls_names:enum_member(Tag), " => {\n",
         "      let message = ", xls_names:record_codec(Tag), "_from_bits(frame.payload);\n",
         "      let built = {\n", xls_parse_io:indent(Body, 8), "        ", Result, "\n      };\n",
         "      GatherContribution { valid: built.0, site: GatherSite::", xls_names:enum_member(maps:get(phase, Site)),
         ", key: built.1, member: built.2, value: bits_from_", Codec, "(built.3) }\n    },\n"]
      end || C <- Contributions],
     "    _ => zero!<GatherContribution>(),\n  }\n}\n\n"].

-doc "Adds two metadata banks and completion readiness per actor; payloads remain in RAM.".
-spec state_fields(map()) -> iodata().
state_fields(Spec) -> optional(Spec, fun() ->
    "  indexed_context: IndexedContext[ACTOR_COUNT],\n"
    "  indexed_candidates: bool[ACTOR_COUNT],\n"
    "  indexed_cursor: u32,\n"
end).

-doc "Carries one borrowed completion identity and progress without its payload row.".
-spec ticket_field(map()) -> iodata().
ticket_field(Spec) -> optional(Spec, fun() ->
    "  gather_valid: bool,\n  gather_progress: GatherProgress,\n"
    "  gather_lease: IndexedLease,\n  gather_failure: hls_failure::Code,\n"
end).

-doc "Uses the committed completion ticket bound by issue/1 for the shared dispatch reservation.".
-spec ticket_value(map()) -> iodata().
ticket_value(Spec) -> optional(Spec, fun() ->
    "              gather_valid: selected_indexed_ticket.valid,\n"
    "              gather_progress: selected_indexed_ticket.progress,\n"
    "              gather_lease: selected_indexed_ticket.lease,\n"
    "              gather_failure: selected_indexed_ticket.failure,\n"
end).

-doc "Suppresses retiring effects when a previously committed indexed protocol fault is visible.".
-spec resolve(map()) -> iodata().
resolve(Spec) -> optional(Spec, fun() ->
    "        let resolved = indexed_resolve(state, result.slot, resolved);\n"
end).

-doc "Reconciles the retiring context, opening and borrowed completion with current indexed ownership.".
-spec retire(map()) -> iodata().
retire(Spec) -> optional(Spec, fun() ->
    "        let retired = indexed_retire(retired, retire_valid, result.slot, resolved.machine);\n"
end).

-doc "Selects one reserved input and emits at most one checked member write intent.".
-spec admit(map()) -> iodata().
admit(Spec) -> optional(Spec, fun() ->
    "        let indexed_intent = indexed_select(state);\n"
    "        let indexed_admission = indexed_admit(state, indexed_intent, retire_valid, result.slot);\n"
end).

-doc "Merges one accepted input after unrelated retirement without replacing stale actor state.".
-spec commit(map()) -> iodata().
commit(Spec) -> optional(Spec, fun() ->
    "        let admitted = indexed_commit(state, admitted, indexed_intent, indexed_admission);\n"
end).

-doc "Binds the committed dispatch ticket and borrows only its sealed completion; admission faults remain checked.".
-spec issue(map()) -> iodata().
issue(Spec) -> optional(Spec, fun() ->
    "        let selected_indexed_ticket = indexed_selected_ticket(state.indexed_context, read_slot);\n"
    "        let admitted = indexed_issue(state, admitted, indexed_intent, indexed_admission, issue_valid, read_slot);\n"
end).

%% Disabled artifacts retain their existing actor and scalar-reduction behavior.
-spec enabled(map()) -> boolean().
enabled(Spec) -> maps:get(gather_collection, Spec, false) =:= true.

%% Delay shape-dependent rendering until the corresponding option is enabled.
-spec optional(map(), fun(() -> iodata())) -> iodata().
optional(Spec, Render) -> case enabled(Spec) of true -> Render(); false -> [] end.

%% Proc-independent ownership logic stays readable in a static DSLX template.
-spec template() -> binary().
template() ->
    {ok, Text} = file:read_file(filename:join([code:priv_dir(hls_fabric), "xls", "templates", "indexed_collection.x.in"])),
    Text.
