-module(xls_failure_sites_shared_tests).
-include_lib("eunit/include/eunit.hrl").


%% Checks specializations use their own artifact codebook.
-spec specializations_use_their_own_artifact_codebook_test() -> 'ok'.
specializations_use_their_own_artifact_codebook_test() ->
    File = filename:join(code:lib_dir(erl_hls), "src/examples/phi_decoder/phi_halo_cell.erl"),
    {ok, Forms} = xls_parse:parse_file(File),
    {_, Origins} = xls_failure_sites:prepare(Forms),
    lists:foreach(fun(Mode) ->
        Text = xls_shared_parse:to_xls(File, #{shared_service => Mode}),
        ?assertMatch([_ | _], xls_failure_sites:from_artifact(Origins, Text))
    end, [ordinary, aggregate_only]).
