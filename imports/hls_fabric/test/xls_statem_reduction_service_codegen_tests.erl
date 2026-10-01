-module(xls_statem_reduction_service_codegen_tests).

-include_lib("eunit/include/eunit.hrl").

%% Completion arithmetic must have one syntactic call site across both requests.
-spec aggregate_and_internal_share_completion_test() -> ok.
aggregate_and_internal_share_completion_test() ->
    Dispatch = iolist_to_binary(
        xls_shared_reduction_service_codegen:shared_executor_dispatch(
            reduction, aggregate_only)),
    ?assertEqual(1, length(binary:matches(Dispatch, <<"shared_machine_complete(">>))),
    ?assertEqual(nomatch, binary:match(aggregate_only_support(),
        <<"shared_machine_complete(ActorState">>)).

%% Dispatch predicates must not reintroduce current retirement/capture feedback.
-spec issue_uses_committed_metadata_test() -> ok.
issue_uses_committed_metadata_test() ->
    lists:foreach(fun(Mode) ->
        Bindings = iolist_to_binary(
            xls_shared_reduction_service_codegen:shared_issue_bindings(reduction, Mode)),
        lists:foreach(fun(Forbidden) ->
            ?assertEqual(nomatch, binary:match(Bindings, Forbidden))
        end, [<<"retired">>, <<"incoming">>, <<"completion_blocked">>])
    end, [ordinary, aggregate_only]).

%% Checks that aggregate delivery has the required private state and entry points.
-spec aggregate_only_support() -> binary().
aggregate_only_support() ->
    iolist_to_binary(
        xls_shared_reduction_service_codegen:shared_machine_support(
            reduction, aggregate_only)).
