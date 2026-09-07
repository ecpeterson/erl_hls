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

shared_service_exposes_a_distinct_reduction_ram_test() ->
    Xls = generated_xls(),
    SharedService = binary_from(Xls, <<"pub proc SharedService<">>),
    lists:foreach(
        fun(Declaration) ->
            %% Each endpoint occurs once on the proc and once in config.
            ?assertEqual(2, count(SharedService, Declaration))
        end,
        [
            <<"reduction_read_req_out: chan<ReductionRamReadReq> out">>,
            <<"reduction_read_resp_in: chan<ReductionRamReadResp> in">>,
            <<"reduction_write_req_out: chan<ReductionRamWriteReq> out">>,
            <<"reduction_write_resp_in: chan<ReductionRamWriteResp> in">>
        ]
    ),
    %% The application-state and reduction-state memories must not merely be
    %% aliases for one physical request stream.
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

fused_phase_entry_dirties_reduction_ram_test() ->
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

completion_visits_fetch_external_reduction_state_test() ->
    Xls = generated_xls(),
    SharedState = declaration_block(Xls, <<"struct SharedState<">>),
    SharedService = binary_from(Xls, <<"pub proc SharedService<">>),
    ?assertEqual(nomatch, binary:match(
        SharedState,
        <<"completion_reduction">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"reduction_read_needed = fold_issue_valid ||">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"private_active;">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"reduction: if private_active {">>
    )),
    ?assertNotEqual(nomatch, binary:match(
        SharedService,
        <<"reduction_response.data">>
    )).

acknowledged_write_does_not_force_a_global_fold_bubble_test() ->
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
        <<"credit_pending_valid,\n"
          "          actor_issue_valid,\n"
          "          read_slot">>
    )),
    ?assertEqual(nomatch, binary:match(
        SharedService,
        <<"credit_pending_valid,\n"
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

count(Binary, Needle) ->
    length(binary:matches(Binary, Needle)).
