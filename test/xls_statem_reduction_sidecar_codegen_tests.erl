-module(xls_statem_reduction_sidecar_codegen_tests).

-include_lib("eunit/include/eunit.hrl").

-define(FIXTURE, "test_data/hls_statem_reduction_lower_fixture.erl").

machine_and_reduction_storage_are_separate_test() ->
    Interface = xls_parse:actor_interface(?FIXTURE),
    StateWidth = maps:get(width, hls_actor_interface:state(Interface)),
    MachineWidth = xls_statem_codegen:shared_machine_width(StateWidth),
    ReductionWidth = hls_actor_interface:reduction_storage_width(Interface),
    Xls = generated_xls(),
    ?assertNotEqual(nomatch, binary:match(
        Xls,
        width_declaration("MachineBits", MachineWidth)
    )),
    ?assertNotEqual(nomatch, binary:match(
        Xls,
        width_declaration("ReductionBits", ReductionWidth)
    )),
    %% A reduction used to be appended to every actor-state RAM word.  Keep a
    %% direct regression check on that old combined width as well as checking
    %% the two positive declarations above.
    ?assertEqual(nomatch, binary:match(
        Xls,
        width_declaration("MachineBits", MachineWidth + ReductionWidth)
    )),
    MachineCodec = declaration_block(Xls, <<"fn bits_from_machine(">>),
    ?assertEqual(nomatch, binary:match(
        MachineCodec,
        <<"bits_from_reduction_state">>
    )).

shared_service_keeps_small_reduction_rows_in_registers_test() ->
    Xls = generated_xls(),
    SharedState = declaration_block(Xls, <<"struct SharedState<">>),
    SharedService = binary_from(Xls, <<"pub proc SharedService<">>),
    ?assertNotEqual(nomatch, binary:match(
        SharedState,
        <<"reductions: ReductionBits[ACTOR_COUNT]">>
    )),
    ?assertEqual(nomatch, binary:match(SharedService, <<"ReductionRam">>)),
    %% Ordinary application state remains on its independent external RAM.
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"ram_read_req_out: chan<MachineRamReadReq> out">>
    )).

fold_envelope_carries_only_sidecar_state_test() ->
    Xls = generated_xls(),
    Envelope = declaration_block(Xls, <<"struct FoldEnvelope {">>),
    ?assertNotEqual(nomatch, binary:match(
        Envelope,
        <<"reduction: ReductionBits">>
    )),
    ?assertEqual(nomatch, binary:match(Envelope, <<"MachineBits">>)),
    ?assertEqual(nomatch, binary:match(Envelope, <<"machine:">>)).

sidecar_contribution_classification_is_actor_data_independent_test() ->
    Xls = generated_xls(),
    Sidecar = declaration_block(
        Xls,
        <<"fn reduction_sidecar_contribution(">>
    ),
    %% The ordinary helper remains usable by the direct actor service, where
    %% actor data is already resident.  It is this sidecar projection that
    %% must be callable before an application-state RAM read.
    ?assertEqual(nomatch, binary:match(Sidecar, <<"data: Cell">>)),
    ?assertEqual(nomatch, binary:match(Sidecar, <<"data.">>)).

fused_phase_entry_dirties_reduction_receptacle_test() ->
    Xls = generated_xls(),
    Executor = declaration_block(Xls, <<"pub fn shared_execute(">>),
    %% A dispatched cast may establish enter_pending and have that entry
    %% executed in this same combinational executor call.  Looking only at
    %% the input machine silently loses a reduction opened by that entry.
    ?assertNotEqual(nomatch, binary:match(
        Executor,
        <<"machine.enter_pending ||\n"
          "        dispatched.machine.enter_pending">>
    )).

completion_visits_read_register_resident_reduction_state_test() ->
    Xls = generated_xls(),
    SharedState = declaration_block(Xls, <<"struct SharedState<">>),
    SharedService = binary_from(Xls, <<"pub proc SharedService<">>),
    ?assertEqual(nomatch, binary:match(
        SharedState,
        <<"completion_reduction">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"let reduction_bits = state.reductions[read_slot];">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"reduction: if private_active {">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"reduction_bits">>
    )).

register_write_does_not_force_an_acknowledgment_bubble_test() ->
    Xls = generated_xls(),
    FoldReady = declaration_block(Xls, <<"fn sidecar_fold_ready<">>),
    SharedService = binary_from(Xls, <<"pub proc SharedService<">>),
    ?assertEqual(nomatch, binary:match(
        FoldReady,
        <<"reduction_write_pending">>
    )),
    ?assertEqual(nomatch, binary:match(
        SharedService,
        <<"!state.next_fold || !state.reduction_write_pending">>
    )),
    ?assertEqual(nomatch, binary:match(
        SharedService,
        <<"reduction_write_resp_in">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"let reductions = apply_reduction_writes(">>
    )).

fold_probe_permits_same_slot_admission_test() ->
    Xls = generated_xls(),
    SharedService = binary_from(Xls, <<"pub proc SharedService<">>),
    %% A fold probe reads the selected occupied head.  Admission obtains a
    %% free physical row and appends it after the old logical tail, so the
    %% 1R and 1W may overlap even when their actor slot is the same.  Ordinary
    %% actor activation remains excluded because it can rewrite mailbox and
    %% actor state during retirement.
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"direct_pending_valid,\n"
          "          actor_issue_valid,\n"
          "          read_slot">>
    )),
    ?assertEqual(nomatch, binary:match(
        SharedService,
        <<"direct_pending_valid,\n"
          "          issue_valid,\n"
          "          read_slot">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        Xls,
        <<"let physical = free_mailbox_index(state, slot);">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"mailbox::read(read_slot, mailbox_index, MAILBOX_DEPTH)">>
    )).

failed_actor_disables_its_reduction_sidecar_test() ->
    Xls = generated_xls(),
    Retirement = declaration_block(
        Xls,
        <<"fn retire_reduction_actor<">>
    ),
    ?assertNotEqual(nomatch, binary:match(
        Retirement,
        <<"let machine_failed = machine_from_bits(result.machine).failed;">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        Retirement,
        <<"!machine_failed && reduction.status == ReductionStatus::OPEN">>
    )).

sender_addressed_fold_uses_only_safe_mailbox_scan_boundary_test() ->
    Xls = generated_xls(),
    Candidate = declaration_block(
        Xls,
        <<"pub fn direct_reduction_candidate(">>
    ),
    Direct = declaration_block(Xls, <<"fn reserve_direct_reduction<">>),
    SharedService = binary_from(Xls, <<"pub proc SharedService<">>),
    FoldRelay = binary_from(Xls, <<"proc FoldRelay">>),
    ?assertNotEqual(nomatch, binary:match(
        Candidate,
        <<"frame.header.op == (Tag::COUNT_VALUE as u8)">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        Candidate,
        <<"frame.header.op == (Tag::MEMBER_VALUE as u8)">>
    )),
    %% A direct contribution may pass physically older postponed mail, just
    %% as the ordinary mailbox scan does, but never an older event which is
    %% selectable in the current phase.
    ?assertNotEqual(nomatch, binary:match(
        Direct,
        <<"state.reduction_active[slot]">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        Direct,
        <<"!state.mail_candidates[slot]">>
    )),
    %% A semantic miss clears only the optimization hint, leaving the original
    %% request available to ordinary ordered mailbox admission.
    ?assertNotEqual(nomatch, binary:match(
        Direct,
        <<"let fallback_request = ScheduledRequest {">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        Direct,
        <<"direct_reduction: u1:0">>
    )),
    %% Sender-addressed traffic is folded before admission, while ordinary
    %% mailbox-head traffic retains its existing sidecar path. The relay is
    %% still only an elastic register and performs no reduction itself.
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"let direct_fold = reserve_direct_reduction(">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"let local_fold = shared_reduction_fold_result(">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"let reductions = apply_reduction_writes(">>
    )),
    %% A phase entry may open the receptacle in the same activation as its
    %% first direct contribution arrives. The newly retired word must feed
    %% that fold rather than the previous register-bank value.
    ?assertNotEqual(nomatch, binary:match(
        Direct,
        <<"if forwarded_valid && slot == forwarded_slot">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        Direct,
        <<"let applied = shared_reduction_sidecar_step(">>
    )),
    ?assertEqual(nomatch, binary:match(
        FoldRelay,
        <<"let applied = shared_reduction_sidecar_step(">>
    )).

generated_xls() ->
    iolist_to_binary(xls_parse:to_xls(?FIXTURE)).

width_declaration(Name, Width) ->
    iolist_to_binary([
        "pub type ", Name, " = bits[", integer_to_list(Width), "];"
    ]).

declaration_block(Xls, Marker) ->
    Tail = binary_from(Xls, Marker),
    {End, EndLength} = binary:match(Tail, <<"\n}\n">>),
    binary:part(Tail, 0, End + EndLength).

binary_from(Binary, Marker) ->
    {Start, _Length} = binary:match(Binary, Marker),
    binary:part(Binary, Start, byte_size(Binary) - Start).
