-module(hls_source_tests).

-include_lib("eunit/include/eunit.hrl").
-import(hls_source_fixture, [options/1, compile_actor/2, with_source/1]).

-define(MODULE_UNDER_TEST, hls_source_context_fixture).

build_context_agrees_with_source_and_dslx_test() ->
    with_source(fun(Path, Directory) ->
        lists:foreach(fun({Options, Width, Capacity}) ->
            compile_actor(Path, Options),
            Embedded = hls_actor_interface:from_module(?MODULE_UNDER_TEST),
            ?assertEqual(Embedded, xls_parse:actor_interface(Path, Options)),
            ?assertEqual(Width, maps:get(width, hls_actor_interface:state(Embedded))),
            ?assertEqual(Width, ?MODULE_UNDER_TEST:pack_width(cell)),
            ?assertEqual(Capacity, maps:get(mailbox_capacity, Embedded)),
            {ok, waiting, Initial} = ?MODULE_UNDER_TEST:init([]),
            ?assertEqual(<<7:Width/little>>, ?MODULE_UNDER_TEST:pack(Initial)),
            Generated = iolist_to_binary(xls_parse:to_xls(Path,
                #{source_options => Options})),
            ?assertNotEqual(nomatch, binary:match(Generated,
                iolist_to_binary(io_lib:format("value : u~B", [Width]))))
        end, [
            {options(Directory) ++ [{d, 'CAPACITY', 2}], 32, 2},
            {options(Directory) ++ [{d, 'CAPACITY', 5}, {d, 'WIDE'}], 64, 5}
        ])
    end).

captured_context_survives_working_directory_change_test() ->
    with_source(fun(Path, Directory) ->
        {ok, OriginalDirectory} = file:get_cwd(),
        try
            %% ?FILE can influence preprocessing, not just diagnostics.
            ok = file:write_file(filename:join([Directory, "headers", "config.hrl"]),
                "-if(?FILE =:= \"headers/config.hrl\").\n"
                "-define(WORD_TYPE, u64).\n-else.\n-define(WORD_TYPE, u32).\n-endif.\n"),
            ok = file:set_cwd(Directory),
            Relative = "src/hls_source_context_fixture.erl",
            Options = [{i, "headers"}, {d, 'CAPACITY', 3}, {d, 'INITIAL', 7}],
            compile_actor(Relative, Options),
            Expected = xls_parse:actor_interface(Relative, Options),
            ?assertEqual(64, maps:get(width, hls_actor_interface:state(Expected))),
            Generated = iolist_to_binary(xls_parse:to_xls(Relative,
                #{source_options => Options})),
            [Context] = proplists:get_value(hls_source_context,
                ?MODULE_UNDER_TEST:module_info(attributes)),
            ok = file:set_cwd(OriginalDirectory),
            ?assert(filelib:is_regular(Path)),
            ?assertEqual(Expected, hls_actor_interface:from_module(?MODULE_UNDER_TEST)),
            ?assertEqual(Generated, iolist_to_binary(xls_parse:to_xls(Relative,
                #{source_options => Context}))),
            ok = file:write_file(filename:join([Directory, "headers", "config.hrl"]),
                "this is invalid.\n"),
            ?assertMatch([{"headers/config.hrl", 1, erl_parse, _} | _],
                errors(fun() -> hls_actor_interface:from_module(?MODULE_UNDER_TEST) end)),
            ?assertEqual({ok, OriginalDirectory}, file:get_cwd())
        after
            ok = file:set_cwd(OriginalDirectory)
        end
    end).

changed_include_resolution_requires_rebuild_test() ->
    with_source(fun(Path, Directory) ->
        Options = options(Directory) ++ [{d, 'CAPACITY', 1}],
        compile_actor(Path, Options),
        Shadow = filename:join(filename:dirname(Path), "config.hrl"),
        ok = file:write_file(Shadow, "-define(WORD_TYPE, u32).\n"),
        %% The layout is unchanged, but the old BEAM resolved another header.
        try hls_actor_interface:from_module(?MODULE_UNDER_TEST) of
            _ -> ?assert(false)
        catch
            error:{source_origins, Expected, Actual} ->
                ?assertNot(lists:member(Shadow, Expected)),
                ?assert(lists:member(Shadow, Actual))
        end,
        compile_actor(Path, Options),
        ?assertEqual(32, maps:get(width, hls_actor_interface:state(
            hls_actor_interface:from_module(?MODULE_UNDER_TEST))))
    end).

feature_options_match_beam_preprocessing_test() ->
    with_source(fun(Path, Directory) ->
        Config = filename:join([Directory, "headers", "config.hrl"]),
        ok = file:write_file(Config,
            "-if(?FEATURE_ENABLED(maybe_expr)).\n-define(WORD_TYPE, u64).\n"
            "-else.\n-define(WORD_TYPE, u32).\n-endif.\n"),
        lists:foreach(fun({Mode, Width}) ->
            Options = options(Directory) ++ [{d, 'CAPACITY', 1}, {feature, maybe_expr, Mode}],
            compile_actor(Path, Options),
            Interface = hls_actor_interface:from_module(?MODULE_UNDER_TEST),
            ?assertEqual(Interface, xls_parse:actor_interface(Path, Options)),
            ?assertEqual(Width, maps:get(width, hls_actor_interface:state(Interface)))
        end, [{enable, 64}, {disable, 32}])
    end).

include_order_matches_beam_compiler_test() ->
    with_source(fun(Path, Directory) ->
        Other = filename:join(Directory, "other"),
        ok = filelib:ensure_dir(filename:join(Other, "config.hrl")),
        ok = file:write_file(filename:join(Other, "config.hrl"),
            "-define(WORD_TYPE, u16).\n"),
        lists:foreach(fun(Includes) ->
            Options = Includes ++ [{d, 'CAPACITY', 1}, {d, 'INITIAL', 7}],
            compile_actor(Path, Options),
            ?assertEqual(hls_actor_interface:from_module(?MODULE_UNDER_TEST),
                xls_parse:actor_interface(Path, Options))
        end, [
            [{i, Other}, {i, filename:join(Directory, "headers")}],
            [{i, filename:join(Directory, "headers")}, {i, Other}]
        ])
    end).

changed_transitive_header_rejects_stale_beam_test() ->
    with_source(fun(Path, Directory) ->
        Options = options(Directory) ++ [{d, 'CAPACITY', 1}],
        compile_actor(Path, Options),
        _ = hls_actor_interface:from_modules([?MODULE_UNDER_TEST]),
        Header = filename:join([Directory, "headers", "layout.hrl"]),
        ok = file:write_file(Header, "-define(WORD_TYPE, u64).\n"),
        ?assertError({stale_hls_actor_interface, ?MODULE_UNDER_TEST, Path},
            hls_actor_interface:from_modules([?MODULE_UNDER_TEST])),
        compile_actor(Path, Options),
        Interface = hls_actor_interface:from_module(?MODULE_UNDER_TEST),
        ?assertEqual(64, maps:get(width, hls_actor_interface:state(Interface)))
    end).

missing_header_and_syntax_errors_have_source_locations_test() ->
    with_source(fun(Path, Directory) ->
        Options = options(Directory) ++ [{d, 'CAPACITY', 1}],
        compile_actor(Path, Options),
        Config = filename:join([Directory, "headers", "config.hrl"]),
        ok = file:write_file(Config, "-include(\"missing.hrl\").\n"),
        Missing = errors(fun() -> hls_actor_interface:from_module(?MODULE_UNDER_TEST) end),
        ?assert(lists:member({Config, 1, epp, {include, file, "missing.hrl"}}, Missing)),
        ok = file:write_file(Config, "-define(WORD_TYPE, u32).\nthis is invalid.\n"),
        Syntax = errors(fun() -> xls_parse:to_xls(Path, #{source_options => Options}) end),
        ?assertMatch([{Config, 2, erl_parse, _}], Syntax)
    end).

source_less_and_deterministic_beams_use_embedded_interface_test() ->
    with_source(fun(Path, Directory) ->
        Options = options(Directory) ++ [{d, 'CAPACITY', 1}],
        Expected = xls_parse:actor_interface(Path, Options),
        compile_actor(Path, [deterministic | Options]),
        ?assertEqual(undefined, proplists:get_value(hls_source_context,
            ?MODULE_UNDER_TEST:module_info(attributes))),
        ?assertEqual(Expected, hls_actor_interface:from_module(?MODULE_UNDER_TEST)),
        compile_actor(Path, Options),
        ok = file:delete(Path),
        ?assertEqual(Expected, hls_actor_interface:from_module(?MODULE_UNDER_TEST))
    end).

source_options_are_checked_test() ->
    ?assertError({invalid_source_options, wrong}, hls_source:options("unused.erl", wrong)),
    lists:foreach(fun(Option) ->
        ?assertError({invalid_source_option, Option},
            xls_parse:to_xls("unused.erl", #{source_options => [Option]}))
    end, [{i, 7}, {d, "NAME"}, {feature, maybe_expr, wrong}, debug_info]),
    ?assertMatch([{_, _, epp, _} | _],
        errors(fun() -> xls_parse:actor_interface("test_data/hls_source_context_fixture.erl") end)).

errors(Fun) ->
    try Fun() of
        Value -> error({expected_source_error, Value})
    catch
        error:{source_errors, Errors} -> Errors
    end.
