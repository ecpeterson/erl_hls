-module(phi_source_xls_parse_tests).

-include_lib("eunit/include/eunit.hrl").

%% Both non-reduction actor lowerings retain their independently checked DSLX fixtures.
-spec non_reduction_actor_goldens_test() -> ok.
non_reduction_actor_goldens_test() ->
    Sources = [
        "workloads/hls_phi/src/phenom_data_cell.erl",
        "workloads/hls_phi/src/phenom_syndrome_cell.erl"
    ],
    lists:foreach(
        fun(Source) ->
            {ok, Expected} = file:read_file(Source ++ ".x"),
            Generated = iolist_to_binary(xls_parse:to_xls(Source)),
            ?assertEqual(Expected, Generated)
        end,
        Sources
    ).

%% The dedicated distance-three noise topology keeps its source-adjacent DSLX contract.
-spec dedicated_noise_topology_golden_test() -> ok.
dedicated_noise_topology_golden_test() ->
    {ok, Expected} = file:read_file("workloads/hls_phi/src/phi_noise_topology.x"),
    Generated = iolist_to_binary(phi_noise_topology_dslx:to_dslx()),
    ?assertEqual(Expected, Generated).
