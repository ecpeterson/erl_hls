-module(xls_dslx_imports_shared_tests).

-include_lib("eunit/include/eunit.hrl").

%% A provider whose declarations can exercise malformed metadata as well as
%% multiple dependencies without creating an implementation for each import.

-spec both_statem_artifacts_import_companions_test() -> 'ok'.
both_statem_artifacts_import_companions_test() ->
    lists:foreach(fun(Mode) ->
        Generated = iolist_to_binary(xls_shared_parse:to_xls(
            "src/examples/phi_decoder/phi_halo_cell.erl",
            #{shared_service => Mode})),
        ?assertEqual(1, length(binary:matches(Generated, <<"import phi_field;">>))),
        ?assertNotEqual(nomatch, binary:match(Generated, <<"phi_field::relax(">>))
    end, [ordinary, aggregate_only]).
