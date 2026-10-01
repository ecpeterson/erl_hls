-module(xls_statem_gather_codegen).
-moduledoc "Emits typed indexed collection storage and completion callbacks with separately injectable payloads.".
-export([declarations/1, functions/1, progress_width/1, payload_width/1, storage_width/1,
    optional/2, field/1, copy/1, entry_fields/3, entry_bindings/1,
    dispatch_bindings/1, ordinary_dispatch/2, direct_complete/1, direct_effective/2,
    direct_failure/2, next_field/1, entry_commit/1, receive_gate/1, tags/2]).

-doc "Emits a fragment only when the actor declares indexed gathers.".
-spec optional(map(), iodata()) -> iodata().
optional(Spec, Text) -> case maps:get(gathers, Spec, none) of none -> []; _ -> Text end.

-doc "Reports the packed progress width independently of element payloads.".
-spec progress_width(none | map()) -> non_neg_integer().
progress_width(none) -> 0;
progress_width(G) -> 66 + 2 * capacity(G).

-doc "Reports the largest per-site ordered payload width.".
-spec payload_width(none | map()) -> non_neg_integer().
payload_width(none) -> 0;
payload_width(#{sites := Sites}) -> lists:max([element_width(S) * maps:get(size, maps:get(population, S)) || S <- Sites]).

-doc "Reports ordinary actor storage; physical collectors may retain only progress in actor RAM.".
-spec storage_width(none | map()) -> non_neg_integer().
storage_width(none) -> 0;
storage_width(G) -> progress_width(G) + payload_width(G).

%% The shared progress mask covers each site's fixed numeric capacity.
-spec capacity(map()) -> pos_integer().
capacity(#{sites := Sites}) -> lists:max([maps:get(size, maps:get(population, S)) || S <- Sites]).
%% Record codecs define the physical element width and bit interpretation.
-spec element_width(map()) -> non_neg_integer().
element_width(#{element := E}) -> xls_statem_reduction_ir:type_width(E).
%% Decimal constants never inherit host locale.
-spec n(integer()) -> string().
n(N) -> integer_to_list(N).
%% Site labels follow the existing phase namespace.
-spec label(map()) -> string().
label(#{phase := Phase}) -> xls_names:enum_member(Phase).
%% Site helpers use source phase names checked against generated namespaces.
-spec stem(map()) -> string().
stem(#{phase := Phase}) -> atom_to_list(Phase).

-doc "Defines progress, ordinary storage, narrow contributions and payload-independent completion results.".
-spec declarations(none | map()) -> iodata().
declarations(none) -> [];
declarations(G = #{data := #{dslx_type := Data}, sites := Sites}) ->
    ["enum GatherStatus : u2 { IDLE = u2:0, OPEN = u2:1, COMPLETE = u2:2 }\n",
     "enum GatherSite : u8 {\n", [["  ",label(S)," = u8:",n(maps:get(id,S)),",\n"] || S <- Sites], "}\n",
     "type GatherMembers = bits[",n(capacity(G)),"];\n",
     "type GatherValues = bits[",n(payload_width(G)),"];\n",
     "struct GatherProgress { status: GatherStatus, site: GatherSite, key: u32, remaining: u8, expected: GatherMembers, seen: GatherMembers, failure: hls_failure::Code }\n",
     "struct GatherState { progress: GatherProgress, values: GatherValues }\n",
     "struct GatherContribution { valid: bool, site: GatherSite, key: u32, member: u32, value: bits[",
         n(lists:max([element_width(S)||S<-Sites])),"] }\n",
     "enum GatherOutcome : u3 { NOT_CANDIDATE=u3:0, MISMATCH=u3:1, PENDING=u3:2, COMPLETE=u3:3, UNEXPECTED_MEMBER=u3:4, DUPLICATE_MEMBER=u3:5 }\n",
     "struct GatherApply { state: GatherState, outcome: GatherOutcome }\n",
     "struct GatherDispatch { progress: GatherProgress, phase: Phase, data: ",Data,", directive: Directive, repeat_phase: bool, failure: hls_failure::Code, dispatched: bool, next_event: u8 }\n\n"].

-doc "Emits gather codecs, member placement, checked contribution dispatch and transient completion consumers.".
-spec functions(map()) -> iodata().
functions(Spec) -> case maps:get(gathers,Spec,none) of
    none -> [];
    G = #{sites := Sites} -> [codecs(G), [site_functions(S,G)||S<-Sites], contribution(G), apply_function(Sites), completion(G), actor_completion(Spec)]
end.

%% Member zero occupies the least-significant element slice in every payload representation.
-spec codecs(map()) -> iodata().
codecs(G) ->
    C=capacity(G), W=progress_width(G),
    ["fn bits_from_gather_progress(p: GatherProgress) -> bits[",n(W),"] { p.failure ++ p.seen ++ p.expected ++ p.remaining ++ p.key ++ (p.site as u8) ++ (p.status as u2) }\n",
     "fn gather_progress_from_bits(raw: bits[",n(W),"]) -> GatherProgress { GatherProgress { status: raw[0:2] as GatherStatus, site: raw[2:10] as GatherSite, key: raw[10:42], remaining: raw[42:50], expected: raw[50+:","bits[",n(C),"]], seen: raw[",n(50+C),"+:bits[",n(C),"]], failure: raw[",n(50+2*C),"+:bits[16]] } }\n",
     "fn bits_from_gather_state(s: GatherState) -> bits[",n(storage_width(G)),"] { s.values ++ bits_from_gather_progress(s.progress) }\n",
     "fn gather_state_from_bits(raw: bits[",n(storage_width(G)),"]) -> GatherState { GatherState { progress: gather_progress_from_bits(raw[0:",n(W),"]), values: raw[",n(W),":] } }\n\n"].

%% Per-site typed helpers keep padding and element codecs out of physical storage policy.
-spec site_functions(map(),map()) -> iodata().
site_functions(S=#{element:=#{name:=Name,dslx_type:=Type},population:=#{size:=N},padding:=#{body:=PadBody,result:=PadResult}},_G) ->
    W=element_width(S), Codec=xls_names:record_codec(Name), Stem=stem(S),
    ["fn gather_values_",Stem,"(raw: GatherValues, members: GatherMembers) -> ",Type,"[",n(N),"] {\n  let padding = {\n",PadBody,PadResult,"\n  };\n  [",
     lists:join(", ",[["if (members & (GatherMembers:1 << u32:",n(I),")) != GatherMembers:0 { ",Codec,"_from_bits(raw[",n(I*W),"+:bits[",n(W),"]]) } else { padding }"] || I<-lists:seq(0,N-1)]),"]\n}\n",
     "fn gather_open_",Stem,"(key: u32, zero: ",Type,", expected: GatherMembers) -> GatherState {\n",
     "  let count = unroll_for! (i, count): (u32,u8) in u32:0..u32:",n(N)," { count + ((expected >> i) as u1 as u8) }(u8:0);\n",
     "  let payload = unroll_for! (i, payload): (u32,GatherValues) in u32:0..u32:",n(N)," { bit_slice_update(payload, i * u32:",n(W),", bits_from_",Codec,"(zero)) }(zero!<GatherValues>());\n",
     "  GatherState { progress: GatherProgress { status: if count == u8:0 { GatherStatus::COMPLETE } else { GatherStatus::OPEN }, site: GatherSite::",label(S),", key, remaining: count, expected, ..zero!<GatherProgress>() }, values: payload }\n}\n\n"].

%% Original callback predicates decide whether a frame contributes; lifts remain separately available in the IR.
-spec contribution(map()) -> iodata().
contribution(#{data:=#{dslx_type:=Data},sites:=Sites}) ->
    ["fn gather_contribution(frame: axis::Frame, phase: Phase, data: ",Data,") -> GatherContribution {\n  match (frame.header.op as Tag, phase) {\n",
     [["    (Tag::",xls_names:enum_member(Tag),", Phase::",label(S),") => {\n      let message = ",xls_names:record_codec(Tag),"_from_bits(frame.payload);\n      let built = {\n",Body,Result,"\n      };\n      GatherContribution { valid: built.0, site: GatherSite::",label(S),", key: built.1, member: built.2, value: bits_from_",xls_names:record_codec(maps:get(name,maps:get(element,S))),"(built.3) as bits[",n(lists:max([element_width(T)||T<-Sites])),"] }\n    },\n"] || S<-Sites,#{tag:=Tag,build:=#{body:=Body,result:=Result}}<-maps:get(contributions,S)],
     "    _ => zero!<GatherContribution>(),\n  }\n}\n\n"].

%% Membership is checked before the sole indexed write. Duplicate values never overwrite a slot.
-spec apply_function([map()]) -> iodata().
apply_function(Sites) ->
    ["fn gather_apply(state: GatherState, input: GatherContribution) -> GatherApply {\n",
     "  let p = state.progress;\n  if !input.valid { GatherApply { state, outcome: GatherOutcome::NOT_CANDIDATE } }\n",
     "  else if p.status != GatherStatus::OPEN || p.site != input.site || p.key != input.key { GatherApply { state, outcome: GatherOutcome::MISMATCH } }\n",
     "  else {\n    let member_bit = GatherMembers:1 << input.member;\n",
     "    if member_bit == GatherMembers:0 || (p.expected & member_bit) == GatherMembers:0 { GatherApply { state, outcome: GatherOutcome::UNEXPECTED_MEMBER } }\n",
     "    else if (p.seen & member_bit) != GatherMembers:0 { GatherApply { state, outcome: GatherOutcome::DUPLICATE_MEMBER } }\n",
     "    else {\n      let remaining = p.remaining - u8:1;\n      let values = match p.site {\n",
     [["        GatherSite::",label(S)," => bit_slice_update(state.values, input.member * u32:",n(element_width(S)),", input.value[0+:bits[",n(element_width(S)),"]]),\n"]||S<-Sites],
     "      };\n      GatherApply { state: GatherState { progress: GatherProgress { status: if remaining == u8:0 { GatherStatus::COMPLETE } else { GatherStatus::OPEN }, remaining, seen: p.seen | member_bit, ..p }, values }, outcome: if remaining == u8:0 { GatherOutcome::COMPLETE } else { GatherOutcome::PENDING } }\n    }\n  }\n}\n\n"].

%% Completion consumes ordered values without requiring those values in its output state.
-spec completion(map()) -> iodata().
completion(#{data:=#{dslx_type:=Data},sites:=Sites,continuations:=Names}) ->
    ["fn gather_dispatch_completion(progress: GatherProgress, payload: GatherValues, phase: Phase, data: ",Data,") -> GatherDispatch {\n",
     "  if progress.status != GatherStatus::COMPLETE { GatherDispatch { progress, phase, data, ..zero!<GatherDispatch>() } } else if hls_failure::failed(progress.failure) { GatherDispatch { progress, phase, data, failure: progress.failure, directive: Directive::FAIL, dispatched: true, ..zero!<GatherDispatch>() } } else {\n",
     "    let key = progress.key;\n    match (progress.site, phase) {\n",
     [["      (GatherSite::",label(S),", Phase::",label(S),") => {\n        let members = progress.expected as bits[",n(maps:get(size,maps:get(population,S))),"];\n        let values = gather_values_",stem(S),"(payload, progress.expected);\n",source_values(S),"        let conclusion = {\n",maps:get(body,maps:get(completion,S)),maps:get(result,maps:get(completion,S)),"\n        };\n        GatherDispatch { progress: zero!<GatherProgress>(), phase: conclusion.0, data: conclusion.1, directive: conclusion.2, repeat_phase: conclusion.3, failure: conclusion.4, dispatched: true, next_event: ",case Names of []->"u8:0";_->"conclusion.5" end," }\n      },\n"]||S<-Sites],
     "      _ => GatherDispatch { progress, phase, data, directive: Directive::FAIL, failure: hls_failure::REDUCTION_PROTOCOL, dispatched: true, ..zero!<GatherDispatch>() },\n    }\n  }\n}\n\n"].

%% Existing wire record types keep their tagged source representation inside helper arrays.
-spec source_values(map()) -> iodata().
source_values(#{representation := value}) -> [];
source_values(#{representation := Representation, element := #{name := Name}, population := #{size := Size}}) ->
    ["        let values = [", lists:join(", ", [["(Tag::", xls_names:enum_member(Name),
        ", values[u32:", n(I), "]", case Representation of data -> []; tagged ->
            [", bits_from_", xls_names:record_codec(Name), "(values[u32:", n(I), "])"] end,
        ")"] || I <- lists:seq(0, Size - 1)]), "];\n"].

%% The same source consumer is used by ordinary direct execution and physical completion injection.
-spec actor_completion(map()) -> iodata().
actor_completion(Spec) ->
    ["fn actor_gather_complete(machine: ActorState) -> ActorDispatch {\n",
     "  let c = gather_dispatch_completion(machine.gather.progress, machine.gather.values, machine.phase, machine.data);\n",
     "  let invalid = c.repeat_phase && (c.directive != Directive::CONSUME || c.phase != machine.phase);\n",
     "  let effective = c.dispatched && !invalid;\n  let failure = hls_failure::completion(c.dispatched, invalid, c.failure);\n",
     "  let boundary = effective && c.directive != Directive::FAIL && (c.phase != machine.phase || c.repeat_phase);\n",
     "  ActorDispatch { machine: ActorState { phase: if effective { c.phase } else { machine.phase }, entered_from: if boundary { machine.phase } else { machine.entered_from }, data: if effective { c.data } else { machine.data }, gather: GatherState { progress: c.progress, values: if c.progress.status == GatherStatus::IDLE { zero!<GatherValues>() } else { machine.gather.values } },\n",
     xls_statem_event_codegen:optional(Spec,"    next_event: if effective && !hls_failure::failed(failure) { c.next_event } else { u8:0 },\n"),
     "    enter_pending: boundary && !hls_failure::failed(failure), failure, ..machine }, dispatched: c.dispatched && !invalid, directive: c.directive, phase_boundary: boundary, ..zero!<ActorDispatch>() }\n}\n\n"].

-doc "Adds ordinary gather storage to an actor or entry outcome.".
-spec field(map()) -> iodata().
field(Spec) -> optional(Spec,"  gather: GatherState,\n").
-doc "Copies ordinary gather storage between direct and callback-state representations.".
-spec copy(map()) -> iodata().
copy(Spec) -> optional(Spec,"    gather: machine.gather,\n").

-doc "Initializes the selected gather from its transactional entry value.".
-spec entry_fields(map(), none | map(), atom()) -> iodata().
entry_fields(Spec, #{kind:=gather,identity_expression:=Zero}, Phase) ->
    Suffix=case Zero of {record,_,{value,_},_}->[];_->".1" end,
    optional(Spec,["    gather: gather_open_",atom_to_list(Phase),"(evaluated.1.0, evaluated.1.1",Suffix,", evaluated.1.2 as GatherMembers),\n"]);
entry_fields(Spec, _, _) -> optional(Spec,"    gather: zero!<GatherState>(),\n").

-doc "Rejects concurrent logical collections before committing entry data or effects.".
-spec entry_bindings(map()) -> iodata().
entry_bindings(Spec) ->
    R=maps:get(reductions,Spec,none), G=maps:get(gathers,Spec,none),
    case {R,G} of
        {_,none}->xls_statem_reduction_service_codegen:entry_bindings(R);
        _ ->
            ActiveR=case R of none->"false";_->"machine.reduction.status != ReductionStatus::IDLE" end,
            OpensR=case R of none->"false";_->"outcome.reduction.status != ReductionStatus::IDLE" end,
            ["    let opens_gather = outcome.gather.progress.status != GatherStatus::IDLE;\n",
             "    let opens_reduction = ",OpensR,";\n",
             "    let entry_failure = hls_failure::first(outcome.failure, hls_failure::check((opens_gather || opens_reduction) && (machine.gather.progress.status != GatherStatus::IDLE || ",ActiveR,"), hls_failure::REDUCTION_PROTOCOL));\n",
             "    let entry_failed = hls_failure::failed(entry_failure);\n",
             "    let entered_gather = if opens_gather { outcome.gather } else { machine.gather };\n",
             case R of none->[];_->"    let entered_reduction = if opens_reduction { outcome.reduction } else { machine.reduction };\n" end]
    end.

-doc "Evaluates one potential gather contribution before ordinary callback dispatch.".
-spec dispatch_bindings(map()) -> iodata().
dispatch_bindings(Spec) -> optional(Spec,
    "      let gather_applied = gather_apply(machine.gather, gather_contribution(selected_frame, machine.phase, machine.data));\n"
    "      let gather_candidate = dispatchable && gather_applied.outcome != GatherOutcome::NOT_CANDIDATE;\n"
    "      let gather_accepted = gather_candidate && (gather_applied.outcome == GatherOutcome::PENDING || gather_applied.outcome == GatherOutcome::COMPLETE);\n"
    "      let next_gather = if gather_accepted { gather_applied.state } else { machine.gather };\n").

-doc "Selects a checked gather directive or preserves ordinary dispatch when its predicates do not match.".
-spec ordinary_dispatch(map(), iodata()) -> iodata().
ordinary_dispatch(Spec, Ordinary) -> case maps:get(gathers,Spec,none) of none -> Ordinary; _ ->
    ["if gather_candidate { (machine.phase, machine.data, if gather_applied.outcome == GatherOutcome::MISMATCH { Directive::POSTPONE } else if gather_accepted { Directive::CONSUME } else { Directive::FAIL }, false, if gather_applied.outcome == GatherOutcome::UNEXPECTED_MEMBER || gather_applied.outcome == GatherOutcome::DUPLICATE_MEMBER { hls_failure::REDUCTION_PROTOCOL } else { hls_failure::NONE }",xls_statem_event_codegen:optional(Spec,", u8:0"),") } else { ",Ordinary," }"]
end.

-doc "Runs a completed gather only after all opening entry effects have committed.".
-spec direct_complete(map()) -> iodata().
direct_complete(Spec) -> optional(Spec,
    "  } else if !machine.enter_pending && machine.gather.progress.status == GatherStatus::COMPLETE {\n"
    "    let step = actor_gather_complete(actor_state(machine));\n"
    "    let slots = unroll_for! (i, slots): (u32, MailboxSlot[MAILBOX_DEPTH]) in u32:0..MAILBOX_DEPTH { update(slots, i, MailboxSlot { postponed: if step.phase_boundary { false } else { slots[i].postponed }, ..slots[i] }) }(machine.slots);\n"
    "    MachineStep { machine: Machine { phase: step.machine.phase, entered_from: step.machine.entered_from, data: step.machine.data, gather: step.machine.gather, enter_pending: step.machine.enter_pending, failure: step.machine.failure, slots, " ) ++
    optional(Spec,[xls_statem_event_codegen:optional(Spec,"next_event: step.machine.next_event, "),"..machine }, ..zero!<MachineStep>() }\n"]).

-doc "Prevents ordinary callbacks from crossing an incomplete gather boundary.".
-spec direct_effective(map(), iodata()) -> iodata().
direct_effective(Spec, Ordinary) -> case maps:get(gathers,Spec,none) of none->Ordinary;_->
    [Ordinary,"      let incomplete_gather = dispatchable && (next_phase != machine.phase || repeat_phase) && directive != Directive::FAIL && machine.gather.progress.status == GatherStatus::OPEN;\n      let effective = effective && !incomplete_gather;\n"]
end.

-doc "Propagates incomplete gather boundaries through the ordinary dispatch failure priority.".
-spec direct_failure(map(), iodata()) -> iodata().
direct_failure(Spec, Ordinary) -> case maps:get(gathers,Spec,none) of none->Ordinary;_->
    ["      let failure = hls_failure::dispatch(invalid_input, invalid_repeat, incomplete_gather || ",
        case maps:get(reductions, Spec, none) of none -> "false"; _ -> "incomplete_boundary" end,
        ", effective, dispatch_failure);\n      let failed = hls_failure::failed(failure);\n"]
end.

-doc "Commits an accepted member update with its consumed mailbox message.".
-spec next_field(map()) -> iodata().
next_field(Spec) -> optional(Spec,"        gather: next_gather,\n").
-doc "Commits the gather opening only after every entry effect has advanced.".
-spec entry_commit(map()) -> iodata().
entry_commit(Spec) -> optional(Spec,"      gather: if entry_complete { entered_gather } else { machine.gather },\n").
-doc "Reserves completion precedence over newly received external input.".
-spec receive_gate(map()) -> iodata().
receive_gate(Spec) -> optional(Spec," && machine.gather.progress.status != GatherStatus::COMPLETE").

-doc "Allocates internal element-record tags without changing public message selectors.".
-spec tags(map(), [atom()]) -> iodata().
tags(Spec, Messages) ->
    Elements=xls_statem_gather_lower:records(maps:get(gathers,Spec,none)),
    Acc=case maps:get(reductions,Spec,none) of none->[];#{accumulator:=#{name:=Name}}->[Name] end,
    Used=[maps:get(data_name,Spec)|Messages]++Acc,
    Extra=Elements--Used,
    case length(Messages)+length(Acc)+length(Extra)=<253 of true->ok;false->error(too_many_gather_record_tags) end,
    [["  ",xls_names:enum_member(E)," = u8:",n(I),",\n"] || {I,E}<-lists:enumerate(3+length(Messages)+length(Acc),Extra)].
