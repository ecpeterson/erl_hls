-module(xls_statem_reduction_service_codegen_tests).

-include_lib("eunit/include/eunit.hrl").

%% Completion arithmetic must have one syntactic call site across both requests.
-spec aggregate_and_internal_share_completion_test() -> ok.
aggregate_and_internal_share_completion_test() ->
    Dispatch = iolist_to_binary(
        xls_statem_reduction_service_codegen:shared_executor_dispatch(
            reduction, aggregate_only)),
    ?assertEqual(1, length(binary:matches(Dispatch, <<"shared_machine_complete(">>))),
    ?assertEqual(nomatch, binary:match(aggregate_only_support(),
        <<"shared_machine_complete(SharedMachine">>)).

aggregate_arrival_has_same_activation_issue_path_test() ->
    Bindings = aggregate_only_issue_bindings(),
    ?assertNotEqual(nomatch, binary:match(Bindings,
        <<"let (fast_ready, fast_slot) = reduction_ready_selection(\n"
          "          retired, state.cursor, fast_in_flight);">>)),
    ?assertNotEqual(nomatch, binary:match(Bindings,
        <<"let fast_issue = !prior_issue_valid &&\n"
          "          !completion_blocked && fast_ready;">>)),
    ?assertNotEqual(nomatch, binary:match(Bindings,
        <<"let issue_valid = prior_issue_valid || fast_issue;">>)).

fast_issue_excludes_a_concurrently_retiring_slot_test() ->
    Bindings = aggregate_only_issue_bindings(),
    ?assertNotEqual(nomatch, binary:match(Bindings,
        <<"let fast_in_flight = if retire_valid {\n"
          "          update(retired_in_flight, result.slot, u1:1)">>)),
    ?assertNotEqual(nomatch, binary:match(Bindings,
        <<"retired, state.cursor, fast_in_flight">>)).

ordinary_shared_service_has_no_fast_issue_path_test() ->
    Ordinary = iolist_to_binary(
        xls_statem_reduction_service_codegen:shared_issue_bindings(
            reduction, ordinary)),
    ?assertEqual(nomatch, binary:match(Ordinary, <<"fast_issue">>)),
    ?assertNotEqual(nomatch, binary:match(Ordinary,
        <<"state.next_valid && !completion_blocked">>)).

aggregate_only_support() ->
    iolist_to_binary(
        xls_statem_reduction_service_codegen:shared_machine_support(
            reduction, aggregate_only)).

aggregate_only_issue_bindings() ->
    iolist_to_binary(
        xls_statem_reduction_service_codegen:shared_issue_bindings(
            reduction, aggregate_only)).
