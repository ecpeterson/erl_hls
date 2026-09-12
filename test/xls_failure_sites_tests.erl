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
    ok = xls_failure_sites:validate_origins(Sites).


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

unused_sites_are_not_declared_test() ->
    {ok, Forms} = xls_parse:parse_file("test/hls_actor_debug_fixture.erl"),
    {Prepared, Sites} = xls_failure_sites:prepare(Forms),
    [{clause, Anno, _, _, _}] = xls_parse:find_function(Prepared, included_inner, 1),
    Name = iolist_to_binary(xls_failure_sites:at(function_clause, Anno)),
    %% A longer identifier must not accidentally keep this site's declaration.
    Other = [Name, "_suffix"],
    ?assertEqual(iolist_to_binary(Other),
        iolist_to_binary(xls_failure_sites:emit(Sites, Other))),
    [#{code := Code}] = xls_failure_sites:allocate(Sites, Name),
    ?assertEqual(17, Code),
    Emitted = iolist_to_binary(xls_failure_sites:emit(Sites, Name)),
    Expected = iolist_to_binary(["const ", Name, " = u16:", integer_to_list(Code), ";"]),
    ?assertMatch({_, _}, binary:match(Emitted, Expected)).

generated_failure_declarations_test_() ->
    [{File, fun() ->
        Source = iolist_to_binary(xls_parse:to_xls(File)),
        Pattern = <<"XLS_FAILURE_SITE_[A-Z_]+_[0-9A-F]{8}_L[0-9]+">>,
        Declarations = captures(Source, <<"^const (", Pattern/binary, ") =">>, [multiline]),
        Body = re:replace(Source, <<"^const ", Pattern/binary, " =[^\\n]*\\n">>,
            <<>>, [global, multiline, {return, binary}]),
        References = captures(Body, <<"\\b(", Pattern/binary, ")\\b">>, []),
        ?assertEqual(lists:usort(Declarations), lists:usort(References)),
        {ok, Forms} = xls_parse:parse_file(File),
        {_, Origins} = xls_failure_sites:prepare(Forms),
        Sites = xls_failure_sites:from_artifact(Origins, Source),
        ?assertEqual(lists:seq(1, length(Sites)), [C bsr 4 || #{code := C} <- Sites]),
        lists:foreach(fun(#{code := C, kind := K}) ->
            ?assertEqual(K, proplists:get_value(C band 15, xls_failure_sites:generic()))
        end, Sites)
    end} || File <- ["src/examples/regsvc/regsvc.erl",
        "src/examples/phi_decoder/phenom_data_cell.erl",
        "src/examples/phi_decoder/phenom_syndrome_cell.erl",
        "src/examples/phi_decoder/phi_halo_cell.erl",
        "test/hls_actor_debug_fixture.erl"]].

capacity_applies_only_to_retained_sites_test() ->
    %% A large CPU-only inventory cannot exhaust the hardware namespace.
    Forms = [{attribute, 1, file, {"large.erl", 1}},
        {function, 1, cpu_only, 0, [{clause, 1, [], [],
            [{tuple, L, [{atom, L, a}, {atom, L, b}, {atom, L, c}]}
                || L <- lists:seq(1, 5000)]}]}],
    {_, Origins} = xls_failure_sites:prepare(Forms),
    ?assert(length(Origins) > 4095),
    Name = fun(L) -> [xls_failure_sites:at(explicit_fail,
        erl_anno:set_file("large.erl", erl_anno:new(L))), "\n"] end,
    ?assertMatch([#{code := 22, line := 5000}],
        xls_failure_sites:allocate(Origins, Name(5000))),
    Full = xls_failure_sites:allocate(Origins, [Name(L) || L <- lists:seq(1, 4095)]),
    ?assertEqual(65526, maps:get(code, lists:last(Full))),
    ?assertError({failure_site_capacity, 4096, 4095},
        xls_failure_sites:allocate(Origins, [Name(L) || L <- lists:seq(1, 4096)])).

artifact_declarations_must_agree_with_codebook_test() ->
    {ok, Forms} = xls_parse:parse_file("test/hls_actor_debug_fixture.erl"),
    {_, Origins} = xls_failure_sites:prepare(Forms),
    Source = iolist_to_binary(xls_parse:to_xls("test/hls_actor_debug_fixture.erl")),
    Bad = re:replace(Source, <<"= u16:[0-9]+;">>, <<"= u16:65535;">>, [{return, binary}]),
    ?assertError(failure_codebook_mismatch, xls_failure_sites:from_artifact(Origins, Bad)),
    Unknown = xls_failure_sites:at(case_clause,
        erl_anno:set_file("absent.erl", erl_anno:new(1))),
    ?assertError({unknown_failure_sites, [_]}, xls_failure_sites:allocate(Origins, Unknown)).

specializations_use_their_own_artifact_codebook_test() ->
    File = "src/examples/phi_decoder/phi_halo_cell.erl",
    {ok, Forms} = xls_parse:parse_file(File),
    {_, Origins} = xls_failure_sites:prepare(Forms),
    lists:foreach(fun(Mode) ->
        Text = xls_parse:to_xls(File, #{shared_service => Mode}),
        ?assertMatch([_ | _], xls_failure_sites:from_artifact(Origins, Text))
    end, [ordinary, aggregate_only]).

captures(Source, Pattern, Options) ->
    case re:run(Source, Pattern, [global, {capture, [1], binary} | Options]) of
        {match, Matches} -> [Name || [Name] <- Matches];
        nomatch -> []
    end.
