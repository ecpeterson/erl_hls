-module(xls_parse_shared_tests).

-include_lib("eunit/include/eunit.hrl").


%% Checks ordinary shared service option preserves default output.
-spec ordinary_shared_service_option_preserves_default_output_test() -> 'ok'.
ordinary_shared_service_option_preserves_default_output_test() ->
    Sources = [
        "src/examples/regsvc/regsvc.erl",
        "test_data/hls_statem_reduction_lower_fixture.erl"
    ],
    lists:foreach(fun(Source) ->
        ?assertEqual(
            iolist_to_binary(xls_shared_parse:to_xls(Source)),
            iolist_to_binary(xls_shared_parse:to_xls(
                Source, #{shared_service => ordinary}))
        )
    end, Sources).

%% Checks shared service options are exact and validated.
-spec shared_service_options_are_exact_and_validated_test() -> 'ok'.
shared_service_options_are_exact_and_validated_test() ->
    Path = "src/examples/regsvc/regsvc.erl",
    ?assertError(
        {invalid_xls_shared_service, speculative},
        xls_shared_parse:to_xls(Path, #{shared_service => speculative})
    ),
    ?assertError(
        {invalid_xls_options, [extra]},
        xls_shared_parse:to_xls(Path,
            #{shared_service => ordinary, extra => true})
    ),
    ?assertError(
        {invalid_xls_options, [shared_service_mode]},
        xls_shared_parse:to_xls(Path, #{shared_service_mode => ordinary})
    ),
    ?assertError(
        {unsupported_hls_gs_shared_service, aggregate_only},
        xls_shared_parse:to_xls(Path, #{shared_service => aggregate_only})
    ).

%% Checks aggregate only requires an actor reduction.
-spec aggregate_only_requires_an_actor_reduction_test() -> 'ok'.
aggregate_only_requires_an_actor_reduction_test() ->
    ?assertError(
        aggregate_only_requires_reductions,
        xls_shared_parse:to_xls(
            "test_data/hls_tags_statem_fixture.erl",
            #{shared_service => aggregate_only}
        )
    ).

%% Checks aggregate only emits only the transport artifact surface.
-spec aggregate_only_emits_only_the_transport_artifact_surface_test() -> 'ok'.
aggregate_only_emits_only_the_transport_artifact_surface_test() ->
    Path = "test_data/hls_statem_reduction_lower_fixture.erl",
    Ordinary = iolist_to_binary(xls_shared_parse:to_xls(Path)),
    AggregateOnly = iolist_to_binary(xls_shared_parse:to_xls(
        Path, #{shared_service => aggregate_only})),
    ?assertEqual(nomatch,
        binary:match(Ordinary, <<"ReductionAggregateRequest">>)),
    ?assertEqual(nomatch,
        binary:match(Ordinary, <<"reduction_aggregate_batch">>)),
    ?assertNotEqual(nomatch,
        binary:match(AggregateOnly, <<"ReductionAggregateRequest">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"pub fn reduction_aggregate_batch<COUNT: u32>(">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"fn reduction_apply_complete_aggregate(">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"pub fn scheduled_reduction_prefix(\n"
          "    scheduled: ScheduledEffects) -> (u1, u8, u1)">>)).

%% Checks aggregate only uses one pending receptacle per actor.
-spec aggregate_only_uses_one_pending_receptacle_per_actor_test() -> 'ok'.
aggregate_only_uses_one_pending_receptacle_per_actor_test() ->
    Path = "test_data/hls_statem_reduction_lower_fixture.erl",
    AggregateOnly = iolist_to_binary(xls_shared_parse:to_xls(
        Path, #{shared_service => aggregate_only})),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"aggregate_pending: ReductionAggregateRequest[ACTOR_COUNT]">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"aggregate_pending_valid: u1[ACTOR_COUNT]">>)),
    ?assertEqual(nomatch, binary:match(AggregateOnly,
        <<"aggregate_pending: ReductionAggregateRequest,\n">>)),
    ?assertEqual(nomatch, binary:match(AggregateOnly,
        <<"aggregate_pending_valid: u1,\n">>)),
    %% Aggregate capture never waits on a different actor's receptacle. The
    %% one-open-window causal invariant normally excludes duplicates, while a
    %% violated invariant or invalid slot poisons the captured aggregate.
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"aggregate_in,\n        capture_enabled,\n">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"let aggregate_protocol_error = incoming_aggregate_valid">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"state.aggregate_pending_valid[aggregate_slot]">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"ReductionAggregate {\n          failure: hls_failure::REDUCTION_PROTOCOL">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"update(state.aggregate_pending_valid, aggregate_slot, u1:1)">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"aggregate: state.aggregate_pending_valid,">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"state.aggregate_pending[read_slot]">>)),
    ?assertNotEqual(nomatch, binary:match(AggregateOnly,
        <<"admitted.aggregate_pending_valid, aggregate_active, read_slot">>)).

%% Generated entry batches retain their order and exclude occupied actor outboxes.
-spec state_machine_entry_actions_use_one_source_ordered_egress_test() -> ok.
state_machine_entry_actions_use_one_source_ordered_egress_test() ->
    Path = filename:join("_build", "ordered_egress_fixture.erl"),
    ok = filelib:ensure_dir(Path),
    Source = <<
        "-module(ordered_egress_fixture).\n"
        "-hls_data(cell).\n"
        "-hls_phases([waiting]).\n"
        "-hls_outputs([first, second, third]).\n"
        "-hls_mailbox_capacity(1).\n"
        "-hls_tags([message, wide_message]).\n"
        "-record(message, {value = hls_type:zero() :: hls_nums:u32()}).\n"
        "-record(wide_message, {\n"
        "  low = hls_type:zero() :: hls_nums:u32(),\n"
        "  high = hls_type:zero() :: hls_nums:u32()\n"
        "}).\n"
        "-record(cell, {value = hls_type:zero() :: hls_nums:u32()}).\n"
        "init([]) -> {ok, waiting, #cell{}}.\n"
        "waiting(enter, _Old, Cell) ->\n"
        "  {Cell, [\n"
        "    {cast, third, #message{value = 3}},\n"
        "    {cast, first, #wide_message{low = 1, high = 4}},\n"
        "    {cast, second, #message{value = 2}}\n"
        "  ]};\n"
        "waiting(cast, #message{value = Value}, Cell) ->\n"
        "  {waiting, Cell#cell{value = Value}, consume};\n"
        "waiting(cast, #wide_message{low = Value}, Cell) ->\n"
        "  {waiting, Cell#cell{value = Value}, consume}.\n"
    >>,
    ok = file:write_file(Path, Source),
    try
        XLS = iolist_to_binary(xls_shared_parse:to_xls(Path)),
        ?assertNotEqual(nomatch, binary:match(XLS, <<"import bram;">>)),
        ?assertNotEqual(nomatch, binary:match(XLS, <<"import mailbox;">>)),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"pub type MachineRamReadReq = bram::ReadReq;">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"pub type MailboxRamWriteReq = mailbox::RamWriteReq;">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"mailbox::write(\n">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"request.slot, physical, mailbox::physical_stride(ACTOR_COUNT, MAILBOX_DEPTH)">>
        )),
        ?assertEqual(nomatch, binary:match(
            XLS,
            <<"pub struct MachineRamReadReq">>
        )),
        ?assertEqual(nomatch, binary:match(XLS, <<"fn mailbox_addr(">>)),
        {Third, _} = binary:match(
            XLS, <<"port: OutputPort::THIRD">>
        ),
        {First, _} = binary:match(
            XLS, <<"port: OutputPort::FIRST">>
        ),
        {Second, _} = binary:match(
            XLS, <<"port: OutputPort::SECOND">>
        ),
        ?assert(Third < First),
        ?assert(First < Second),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"pub const EGRESS_DEPTH = u32:3;">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"pub const ENTRY_EFFECT_CAPACITY = u32:3;">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"pub const ENTRY_EFFECT_PAYLOAD_BITS = u32:1;">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"payloads: bits[1]">>
        )),
        ?assertEqual(nomatch, binary:match(
            XLS,
            <<"values: Egress[3]">>
        )),
        ?assertEqual(nomatch, binary:match(
            XLS,
            <<"effects.payloads[32:96]">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"chan<Egress, EGRESS_DEPTH>(\"egress\")">>
        )),
        %% The direct service keeps resumable per-effect progression. A shared
        %% scheduler instead commits one complete ordered batch per entry.
        ?assertEqual(1, length(binary:matches(
            XLS,
            <<"egress_valid: has_effect && can_advance">>
        ))),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"fn entry_effects_valid(effects: EntryEffects) -> u1">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"effects_valid: effects_valid && can_advance">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"fn shared_machine_dispatch(\n">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"fn shared_machine_enter(machine: ActorState, "
              "egress_ready: u1)">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"enter_pending: effective && phase_boundary && !failed">>
        )),
        ?assertEqual(nomatch, binary:match(
            XLS,
            <<"let fuse_entry =">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"egress_out, stepped.egress_valid, stepped.egress">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"pub proc SharedService<\n"
              "    ACTOR_COUNT: u32,\n"
              "    PRODUCER_COUNT: u32,\n"
              "    STARTUP_COUNT: u32,\n"
              "    INSTANCE_ID: u32">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"pub struct ScheduledEffects {\n  slot: u32">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"machine: if can_advance || entry_failed { advanced_machine }">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"mailbox_read_req_out: chan<MailboxRamReadReq> out">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"mailbox_write_req_out: chan<MailboxRamWriteReq> out">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"ram_read_req_out: chan<MachineRamReadReq> out">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"ram_write_req_out: chan<MachineRamWriteReq> out">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"let reservation = mailbox::apply_admission(">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"mail_candidates: u1[ACTOR_COUNT]">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"entry_probes: u1[ACTOR_COUNT]">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"egress_waiters: u1[ACTOR_COUNT]">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"state_write_pending: u1">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"mailbox_write_pending: u1">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"pub proc SharedExecutor">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"in_flight: u1[ACTOR_COUNT]">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"completed: SharedExecutorResult">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"reservation.admission.valid">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"let capture_enabled = state.phase == SharedPhase::RUN">>
        )),
        ?assertEqual(nomatch, binary:match(XLS, <<"SharedPhase::COLLECT">>)),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"let dispatched = shared_machine_dispatch(\n">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"fn ready_selection<ACTOR_COUNT: u32, "
              "PRODUCER_COUNT: u32>">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"scheduler::exclude_reserved(in_flight, state.outbox_busy)">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"egress_blocked: effects_valid && !egress_ready">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"retire_valid && resolved.effects_valid">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"proc EgressDemux {">>
        )),
        ?assertNotEqual(nomatch, binary:match(
            XLS,
            <<"spawn EgressDemux(egress_c, first_p, second_p, third_p)">>
        ))
    after
        ok = file:delete(Path)
    end.

%% All physical service modes share bounded actor storage and explicit u32 boundaries.
-spec actor_cursor_storage_is_bounded_in_each_service_mode_test() -> ok.
actor_cursor_storage_is_bounded_in_each_service_mode_test() ->
    Cases = [
        {"test_data/hls_tags_statem_fixture.erl", #{}},
        {"test_data/hls_statem_reduction_lower_fixture.erl", #{}},
        {"test_data/hls_statem_reduction_lower_fixture.erl", #{shared_service => aggregate_only}},
        {"test/hls_indexed_adapter_fixture.erl", #{}},
        {"test/hls_indexed_adapter_fixture.erl", #{gather_collection => true}}
    ],
    lists:foreach(fun({Path, Options}) ->
        Generated = iolist_to_binary(xls_shared_parse:to_xls(Path, Options)),
        lists:foreach(fun(Fragment) ->
            ?assertNotEqual(nomatch, binary:match(Generated, Fragment))
        end, [
            <<"cursor: uN[std::max(u32:1, std::clog2(ACTOR_COUNT))]">>,
            <<"machine_write(state.cursor as u32, initial_shared_machine())">>,
            <<"(state.cursor as u32) == ACTOR_COUNT - u32:1">>,
            <<"state.cursor, true, state.cursor as u32">>,
            <<"state.cursor, issue_valid, read_slot">>,
            <<"(state, state.cursor as u32, state.in_flight)">>
        ])
    end, Cases).
