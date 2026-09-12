-module(xls_failure_sites_tests).
-include_lib("eunit/include/eunit.hrl").

include_origins_and_real_annotations_test() ->
    {ok, Forms} = xls_parse:parse_file("test/hls_actor_debug_fixture.erl"),
    Functions = [F || F = {function, _, _, _, _} <- Forms],
    Annotations = lists:append([erl_parse:fold_anno(fun(A, Acc) -> [A | Acc] end, [], F)
        || F <- Functions]),
    %% epp's actual input to this pass uses line numbers and file attributes.
    ?assert(lists:all(fun is_integer/1, Annotations)),
    {Prepared, Sites} = xls_failure_sites:prepare(Forms),
    [{clause, Anno, _, _, _}] = xls_parse:find_function(Prepared, included_inner, 1),
    ?assertEqual("hls_actor_debug_helpers.hrl", erl_anno:file(Anno)),
    ?assertEqual(6, erl_anno:line(Anno)),
    ?assertMatch([_], [S || S = #{file := <<"hls_actor_debug_helpers.hrl">>,
        line := 7, kind := case_clause} <- Sites]),
    ?assertMatch([_], [S || S = #{file := <<"hls_actor_debug_fixture.erl">>,
        line := 28, kind := match_failure} <- Sites]),
    Codes = [Code || #{code := Code} <- Sites],
    ?assertEqual(length(Codes), length(lists:usort(Codes))),
    lists:foreach(fun(#{code := Code, kind := Kind}) ->
        ?assert(Code >= 16 andalso Code =< 65535),
        ?assertEqual(Kind, proplists:get_value(Code band 15, xls_failure_sites:generic()))
    end, Sites).

absolute_source_spelling_keeps_codebook_test() ->
    Source = "test/hls_actor_debug_fixture.erl",
    {ok, Relative} = xls_parse:parse_file(Source),
    {ok, Absolute} = xls_parse:parse_file(filename:absname(Source)),
    {_, Expected} = xls_failure_sites:prepare(Relative),
    {_, Actual} = xls_failure_sites:prepare(Absolute),
    ?assertEqual(Expected, Actual).

beam_reports_the_same_selected_origins_test() ->
    {ok, Forms} = xls_parse:parse_file("test/hls_actor_debug_fixture.erl"),
    {_, Sites} = xls_failure_sites:prepare(Forms),
    lists:foreach(fun({Value, Kind}) ->
        try hls_actor_debug_fixture:active(enter, boot, {cell, Value}) of
            _ -> error(expected_failure)
        catch error:Reason:Stack ->
            ?assertEqual(Kind, beam_kind(Reason)),
            {hls_actor_debug_fixture, _, _, Location} = hd(Stack),
            File = list_to_binary(filename:basename(proplists:get_value(file, Location))),
            Line = proplists:get_value(line, Location),
            ?assertMatch([_], [Site || Site = #{file := F, line := L, kind := K} <- Sites,
                {F, L, K} =:= {File, Line, Kind}])
        end
    end, [{0, case_clause}, {2, match_failure}, {6, if_clause}]).

beam_kind({case_clause, _}) -> case_clause;
beam_kind({badmatch, _}) -> match_failure;
beam_kind(if_clause) -> if_clause.
