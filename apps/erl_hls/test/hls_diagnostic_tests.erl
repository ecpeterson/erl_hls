-module(hls_diagnostic_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Nested owners enrich defaults without replacing specific evidence or the original stack.
-spec context_and_stack_test() -> ok.
context_and_stack_test() ->
    {Diagnostic, Stack} = try hls_diagnostic:with_context(#{source => "outer.erl", role => board}, fun() ->
        try hls_diagnostic:raise(actor_source, too_wide, <<"Message is too wide">>,
                #{source => "included.hrl", width => 128})
        catch error:{hls_diagnostic, Inner}:Original ->
            erlang:raise(error, {hls_diagnostic, Inner#{context := (maps:get(context, Inner))#{original_stack => Original}}}, Original)
        end
    end)
    catch error:{hls_diagnostic, Result}:ResultStack -> {Result, ResultStack} end,
    #{context := #{source := "included.hrl", role := board, width := 128, original_stack := OriginalStack}} = Diagnostic,
    ?assertEqual(OriginalStack, Stack),
    ?assertEqual(42, hls_diagnostic:with_context(#{unused => true}, fun() -> 42 end)),
    ?assertError({hls_diagnostic, #{context := #{}}}, hls_diagnostic:raise(test, clean, <<"Clean context">>, #{})).

%% Untagged errors, throws and exits retain their exact class and reason.
-spec unexpected_exception_test() -> ok.
unexpected_exception_test() ->
    ?assertError(bug, hls_diagnostic:with_context(#{stage => ignored}, fun() -> error(bug) end)),
    ?assertThrow(expected_throw, hls_diagnostic:with_context(#{}, fun() -> throw(expected_throw) end)),
    ?assertExit(expected_exit, hls_diagnostic:with_context(#{}, fun() -> exit(expected_exit) end)),
    ?assertThrow({hls_diagnostic, deliberate_throw},
        hls_diagnostic:with_context(#{}, fun() -> throw({hls_diagnostic, deliberate_throw}) end)).

%% JSON preserves scalar evidence and marks compound keys, tuples and non-text bytes explicitly.
-spec structured_json_test() -> ok.
structured_json_test() ->
    Diagnostic = #{stage => placement, code => duplicate_actor, message => <<"Actor assigned twice">>,
        context => #{source => <<"actor.erl">>, actor => {cell, 3}, count => 2,
            fraction => 0.25, flags => [true, false], raw => <<255>>, mapping => #{{cell, 3} => board}}},
    #{<<"stage">> := <<"placement">>, <<"context">> := Context} = json:decode(hls_diagnostic:json(Diagnostic)),
    ?assertEqual(<<"actor.erl">>, maps:get(<<"source">>, Context)),
    ?assertEqual([32, 33], hls_diagnostic:json_value([32, 33])),
    ?assertEqual([65], hls_diagnostic:json_value([65])),
    ?assertMatch(#{<<"$map">> := _}, hls_diagnostic:json_value(#{"key" => 1})),
    ?assertEqual(2, maps:get(<<"count">>, Context)),
    ?assertEqual(0.25, maps:get(<<"fraction">>, Context)),
    ?assertEqual([true, false], maps:get(<<"flags">>, Context)),
    ?assertEqual(#{<<"$tuple">> => [<<"cell">>, 3]}, maps:get(<<"actor">>, Context)),
    ?assertEqual(#{<<"$binary_hex">> => <<"ff">>}, maps:get(<<"raw">>, Context)),
    ?assertEqual(#{<<"$map">> => [[#{<<"$tuple">> => [#{<<"$atom">> => <<"cell">>}, 3]}, <<"board">>]]},
        maps:get(<<"mapping">>, Context)),
    #{<<"$map">> := CollisionPairs} = hls_diagnostic:json_value(#{key => 1, <<"key">> => 2}),
    ?assert(lists:member([#{<<"$atom">> => <<"key">>}, 1], CollisionPairs)),
    ?assert(lists:member([<<"key">>, 2], CollisionPairs)),
    ?assertMatch(#{<<"$term">> := _}, hls_diagnostic:json_value([head | tail])),
    ?assertMatch(#{<<"$term">> := _}, hls_diagnostic:json_value(self())),
    ?assertMatch({_, _}, binary:match(iolist_to_binary(hls_diagnostic:format(Diagnostic)), <<"placement/duplicate_actor">>)).

%% Compound keys cannot collapse atoms and binary text after JSON conversion.
-spec compound_map_key_identity_test() -> ok.
compound_map_key_identity_test() ->
    Keys = [{tag}, {<<"tag">>}, [tag], [<<"tag">>],
        #{tag => value}, #{<<"tag">> => value}, #{tag => <<"value">>}],
    Term = maps:from_list([{Key, Index} || {Index, Key} <- lists:enumerate(Keys)]),
    #{<<"$map">> := Pairs} = hls_diagnostic:json_value(Term),
    EncodedKeys = [Key || [Key, _] <- Pairs],
    ?assertEqual(length(Keys), length(lists:usort(EncodedKeys))),
    ?assertEqual(lists:seq(1, length(Keys)), lists:sort([Index || [_, Index] <- Pairs])).
