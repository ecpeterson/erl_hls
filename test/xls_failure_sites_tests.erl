-module(xls_failure_sites_tests).
-moduledoc "Checks retained failure references and their source provenance without recovering metadata from emitted text.".
-include_lib("eunit/include/eunit.hrl").

%% Preprocessing annotations retain include origins independently of possible failure kinds.
-spec include_origins_and_real_annotations_test() -> ok.
include_origins_and_real_annotations_test() ->
    {ok, Forms} = hls_source:parse_file("test/hls_actor_debug_fixture.erl"),
    Functions = [F || F = {function, _, _, _, _} <- Forms],
    Annotations = lists:append([erl_parse:fold_anno(fun(A, Acc) -> [A | Acc] end, [], F)
        || F <- Functions]),
    ?assert(lists:all(fun is_integer/1, Annotations)),
    {Prepared, Locations} = xls_failure_sites:prepare(Forms),
    [{clause, Anno, _, _, _}] = hls_source:find_function(Prepared, included_inner, 1),
    ?assertEqual("hls_actor_debug_helpers.hrl", erl_anno:file(Anno)),
    ?assertEqual(6, erl_anno:line(Anno)),
    ?assert(lists:member(#{file => <<"hls_actor_debug_helpers.hrl">>, line => 7}, Locations)),
    ?assert(lists:member(#{file => <<"hls_actor_debug_fixture.erl">>, line => 30}, Locations)),
    ?assert(lists:all(fun(Location) -> lists:sort(maps:keys(Location)) =:= [file, line] end,
        Locations)).

%% Relative and absolute spellings of the same source produce the same location inventory.
-spec absolute_source_spelling_keeps_codebook_test() -> ok.
absolute_source_spelling_keeps_codebook_test() ->
    Source = "test/hls_actor_debug_fixture.erl",
    {ok, Relative} = hls_source:parse_file(Source),
    {ok, Absolute} = hls_source:parse_file(filename:absname(Source)),
    {_, Expected} = xls_failure_sites:prepare(Relative),
    {_, Actual} = xls_failure_sites:prepare(Absolute),
    ?assertEqual(Expected, Actual).

%% Selected BEAM exceptions identify the same file, line and kind as retained failures.
-spec beam_reports_the_same_selected_origins_test() -> ok.
beam_reports_the_same_selected_origins_test() ->
    Source = "test/hls_actor_debug_fixture.erl",
    {ok, Forms} = hls_source:parse_file(Source),
    {_, Locations} = xls_failure_sites:prepare(Forms),
    Sites = xls_emitted:sites(xls_parse:to_artifact(Source), Locations),
    lists:foreach(fun({Value, Kind}) ->
        try hls_actor_debug_fixture:active(enter, boot, {cell, Value}) of
            _ -> error(expected_failure)
        catch error:Reason:Stack ->
            ?assertEqual(Kind, beam_kind(Reason)),
            {hls_actor_debug_fixture, _, _, Location} =
                lists:keyfind(hls_actor_debug_fixture, 1, Stack),
            File = list_to_binary(filename:basename(proplists:get_value(file, Location))),
            Line = proplists:get_value(line, Location),
            ?assertMatch([_], [Site || Site = #{file := F, line := L, kind := K} <- Sites,
                {F, L, K} =:= {File, Line, Kind}])
        end
    end, [{0, case_clause}, {2, match_failure}, {6, if_clause}, {8, badarith}, {9, badarith},
        {11, badarg}, {12, badarg}, {13, badarg}]).

%% BEAM exception terms select the corresponding finite hardware failure kind.
-spec beam_kind(term()) -> atom().
beam_kind({case_clause, _}) -> case_clause;
beam_kind({badmatch, _}) -> match_failure;
beam_kind(if_clause) -> if_clause;
beam_kind(badarith) -> badarith;
beam_kind(badarg) -> badarg.

%% Strings, comments and longer identifiers never become references by looking like generated names.
-spec token_looking_text_does_not_retain_sites_test() -> ok.
token_looking_text_does_not_retain_sites_test() ->
    Locations = [#{file => <<"fixture.erl">>, line => 7}],
    Ref = failure(function_clause, 7),
    Name = iolist_to_binary(xls_dslx:render(Ref)),
    Text = ["// ", Name, "\nlet ", Name, "_suffix = u16:0;\n\"", Name, "\"\n"],
    ?assertEqual([], xls_failure_sites:allocate(Locations, Text)),
    Literal = xls_emitted:new(Locations, Text),
    ?assertEqual([], xls_emitted:sites(Literal, Locations)),
    ?assertEqual(iolist_to_binary(Text), xls_emitted:bytes(Literal)),
    Document = [Text, xls_dslx:indent(xls_dslx:bind("failure", Ref), 2)],
    ?assertMatch([#{code := 17, kind := function_clause, line := 7}],
        xls_failure_sites:allocate(Locations, Document)).

%% Pruning and child traversal order cannot change the canonical numbering of retained origins.
-spec deterministic_retained_numbering_test() -> ok.
deterministic_retained_numbering_test() ->
    Locations = [#{file => <<"fixture.erl">>, line => L} || L <- [3, 7, 9]],
    First = failure(badarg, 3),
    SameLine = failure(case_clause, 3),
    Last = failure(explicit_fail, 7),
    Document = xls_dslx:choose("take", xls_dslx:tuple([Last, First]), SameLine),
    Sites = xls_failure_sites:allocate(Locations, Document),
    ?assertEqual([#{code => 30, kind => badarg, file => <<"fixture.erl">>, line => 3},
        #{code => 36, kind => case_clause, file => <<"fixture.erl">>, line => 3},
        #{code => 54, kind => explicit_fail, file => <<"fixture.erl">>, line => 7}], Sites),
    ?assertEqual(Sites, xls_failure_sites:allocate(lists:reverse(Locations),
        [SameLine, First, Last, First])),
    ?assertEqual(Sites, xls_emitted:sites(xls_emitted:new(Locations, Document), Locations)).

%% Each actor carries final bytes with a compact, source-checked retained codebook.
-spec generated_failure_metadata_test_() -> [{file:filename(), fun(() -> ok)}].
generated_failure_metadata_test_() ->
    [{File, fun() ->
        {ok, Forms} = hls_source:parse_file(File),
        {_, Locations} = xls_failure_sites:prepare(Forms),
        Module = xls_parse:to_artifact(File),
        ?assert(is_binary(xls_emitted:bytes(Module))),
        Sites = xls_emitted:sites(Module, Locations),
        ?assertEqual(lists:seq(1, length(Sites)), [C bsr 4 || #{code := C} <- Sites]),
        lists:foreach(fun(#{code := C, kind := K, file := F, line := L}) ->
            ?assertEqual(K, proplists:get_value(C band 15, xls_failure_sites:generic())),
            ?assert(lists:member(#{file => F, line => L}, Locations))
        end, Sites)
    end} || File <- ["src/examples/regsvc/regsvc.erl",
        "src/examples/phi_decoder/phenom_data_cell.erl",
        "src/examples/phi_decoder/phenom_syndrome_cell.erl",
        "src/examples/phi_decoder/phi_halo_cell.erl",
        "test/hls_actor_debug_fixture.erl"]].

%% A large source inventory exhausts the namespace only if more than 4095 sites survive lowering.
-spec capacity_applies_only_to_retained_sites_test() -> ok.
capacity_applies_only_to_retained_sites_test() ->
    Forms = [{attribute, 1, file, {"fixture.erl", 1}},
        {function, 1, cpu_only, 0, [{clause, 1, [], [],
            [{integer, L, L} || L <- lists:seq(1, 5000)]}]}],
    {_, Locations} = xls_failure_sites:prepare(Forms),
    ?assert(length(Locations) > 4095),
    ?assertMatch([#{code := 22, line := 5000}],
        xls_failure_sites:allocate(Locations, failure(explicit_fail, 5000))),
    Full = xls_failure_sites:allocate(Locations,
        [failure(explicit_fail, L) || L <- lists:seq(1, 4095)]),
    ?assertEqual(65526, maps:get(code, lists:last(Full))),
    ?assertError({failure_site_capacity, 4096, 4095},
        xls_failure_sites:allocate(Locations,
            [failure(explicit_fail, L) || L <- lists:seq(1, 4096)])).

%% A provider's fallible contract supplies its kind; no provider-specific source scan is required.
-spec custom_provider_retains_call_origin_test() -> ok.
custom_provider_retains_call_origin_test() ->
    Forms = [form("-file(\"fixture.erl\", 1)."), form("-module(fixture)."),
        form("probe(X) ->\n xls_failure_provider_fixture:checked(X).")],
    {Prepared, Locations} = xls_failure_sites:prepare(Forms),
    [Clause] = hls_source:find_function(Prepared, probe, 1),
    #{body := Body, failure := Failure, result := Result} =
        xls_clause_lower:clause_outcome(Clause, ["value"], cell, #{}),
    Module = xls_emitted:new(Locations, [Body, xls_dslx:tuple([Result, Failure])]),
    ?assertMatch([#{code := 30, file := <<"fixture.erl">>, line := 2, kind := badarg}],
        xls_emitted:sites(Module, Locations)),
    ?assertEqual(3, xls_failure_provider_fixture:checked(3)),
    ?assertError(badarg, xls_failure_provider_fixture:checked(0)).

%% A lowerer cannot attach a retained failure to a file or line absent from the prepared source.
-spec unknown_source_location_is_rejected_test() -> ok.
unknown_source_location_is_rejected_test() ->
    Locations = [#{file => <<"fixture.erl">>, line => 1}],
    ?assertError({unknown_failure_sites, [_]}, xls_emitted:new(Locations, failure(case_clause, 2))),
    Unknown = xls_failure_sites:at(case_clause,
        erl_anno:set_file("absent.erl", erl_anno:new(1))),
    ?assertError({unknown_failure_sites, [_]}, xls_failure_sites:allocate(Locations, Unknown)).

%% Sidecar corruption cannot silently bind bytes to a different retained codebook.
-spec changed_artifact_bytes_or_sites_are_rejected_test() -> ok.
changed_artifact_bytes_or_sites_are_rejected_test() ->
    Locations = [#{file => <<"fixture.erl">>, line => 7}],
    Module = xls_emitted:new(Locations, failure(badarg, 7)),
    #{dslx := Bytes, sites := [Site]} = Raw = binary_to_term(term_to_binary(Module)),
    lists:foreach(fun(Bad) ->
        ?assertError(emitted_module_mismatch, xls_emitted:bytes(Bad)),
        ?assertError(emitted_module_mismatch, xls_emitted:sites(Bad)),
        ?assertError(emitted_module_mismatch, xls_emitted:sites(Bad, Locations)),
        ?assertError(emitted_module_mismatch, xls_emitted:with_bytes(Bad, Bytes))
    end, [Raw#{dslx := <<Bytes/binary, "// changed\n">>},
        Raw#{sites := []}, Raw#{sites := [Site#{kind := badarith}]}]).

%% Even a consistent digest cannot legitimize noncanonical codes, unknown locations or kinds.
-spec source_and_codebook_validation_are_independent_of_digest_test() -> ok.
source_and_codebook_validation_are_independent_of_digest_test() ->
    Locations = [#{file => <<"fixture.erl">>, line => 7}],
    Module = xls_emitted:new(Locations, failure(badarg, 7)),
    [Site] = xls_emitted:sites(Module, Locations),
    ?assertEqual([Site], xls_emitted:sites(Module)),
    Bytes = xls_emitted:bytes(Module),
    ?assertError(failure_codebook_mismatch,
        xls_emitted:sites(sidecar(Bytes, [Site#{code := 46}]))),
    ?assertError({unknown_failure_sites, [_]}, xls_emitted:sites(Module, [])),
    ?assertError(failure_codebook_mismatch,
        xls_emitted:sites(sidecar(Bytes, [Site#{code := 46}]), Locations)),
    ?assertError(duplicate_failure_origin,
        xls_emitted:sites(sidecar(Bytes, [Site, Site]), Locations)),
    ?assertError({failure_kind, unregistered_failure},
        xls_emitted:sites(sidecar(Bytes, [Site#{kind := unregistered_failure}]), Locations)).

%% Trusted composition changes bytes and their seal while preserving the allocated codebook.
-spec trusted_composition_preserves_metadata_test() -> ok.
trusted_composition_preserves_metadata_test() ->
    Locations = [#{file => <<"fixture.erl">>, line => 7}],
    Module = xls_emitted:new(Locations, failure(badarg, 7)),
    Bytes = [xls_emitted:bytes(Module), "\n// enclosing generated module\n"],
    Composed = xls_emitted:with_bytes(Module, Bytes),
    ?assertEqual(iolist_to_binary(Bytes), xls_emitted:bytes(Composed)),
    ?assertEqual(xls_emitted:sites(Module, Locations), xls_emitted:sites(Composed, Locations)).

%% Runtime JSON metadata is checked against source locations and canonical generic/site codes.
-spec runtime_catalog_rejects_changed_origins_and_codes_test() -> ok.
runtime_catalog_rejects_changed_origins_and_codes_test() ->
    Locations = [#{file => <<"fixture.erl">>, line => 7}],
    Sites = xls_failure_sites:allocate(Locations, failure(badarg, 7)),
    Catalog = json:decode(iolist_to_binary(json:encode(xls_actor_debug:failures(Sites)))),
    ?assertEqual(Sites, xls_failure_sites:from_catalog(Locations, Catalog)),
    Entry = maps:get(<<"30">>, Catalog),
    ?assertError({unknown_failure_sites, [_]}, xls_failure_sites:from_catalog(Locations,
        Catalog#{<<"30">> := Entry#{<<"file">> := <<"absent.erl">>}})),
    ?assertError(failure_codebook_mismatch, xls_failure_sites:from_catalog(Locations,
        (maps:remove(<<"30">>, Catalog))#{<<"46">> => Entry})),
    ?assertError(failure_codebook_mismatch, xls_failure_sites:from_catalog(Locations,
        maps:remove(<<"1">>, Catalog))),
    ?assertError({failure_kind, <<"unregistered_failure">>},
        xls_failure_sites:from_catalog(Locations,
            Catalog#{<<"30">> := Entry#{<<"kind">> := <<"unregistered_failure">>}})).

%% Model an externally supplied term: a digest is a consistency check, never source authority.
-spec sidecar(binary(), [map()]) -> term().
sidecar(Bytes, Sites) ->
    #{dslx => Bytes, sites => Sites,
        sha256 => crypto:hash(sha256, term_to_binary({Bytes, Sites}, [deterministic]))}.

%% Construct a typed reference without depending on its emitted identifier spelling.
-spec failure(xls_failure_sites:kind(), pos_integer()) -> xls_dslx:value().
failure(Kind, Line) ->
    xls_failure_sites:at(Kind, erl_anno:set_file("fixture.erl", erl_anno:new(Line))).

%% Parse a compact synthetic source form while retaining its real line annotations.
-spec form(string()) -> hls_source:form().
form(Source) ->
    {ok, Tokens, _} = erl_scan:string(Source),
    {ok, Form} = erl_parse:parse_form(Tokens),
    Form.
