-module(hls_compiler_bootstrap_tests).
-moduledoc "Checks actor metadata generation with only the declared compiler bootstrap modules.".
-include_lib("eunit/include/eunit.hrl").

%% Cached application beams must not conceal missing parse-transform dependencies.
-spec isolated_interface_test() -> ok.
isolated_interface_test() ->
    {ok, Config} = file:consult("rebar.config"),
    %% Runtime is a complete dependency application before any compiler bootstrap file.
    {ok, [{application, hls_runtime, Runtime}]} = file:consult(
        filename:join([code:lib_dir(hls_runtime), "ebin", "hls_runtime.app"])),
    Modules = [list_to_atom(filename:basename(Path, ".erl"))
        || Path <- proplists:get_value(erl_first_files, Config)] ++
        proplists:get_value(modules, Runtime),
    Directory = filename:absname(filename:join("_build", "compiler-bootstrap-" ++
        integer_to_list(erlang:unique_integer([positive])))),
    ok = filelib:ensure_dir(filename:join(Directory, "placeholder")),
    try
        %% The fixture's numeric provider is available while compiling actors.
        lists:foreach(fun(Module) ->
            {ok, _} = file:copy(code:which(Module),
                filename:join(Directory, atom_to_list(Module) ++ ".beam"))
        end, lists:usort(Modules ++ [hls_nums, hls_codec])),
        {ok, Peer, _Node} = peer:start_link(#{connection => standard_io,
            args => ["+S", "1:1", "+A", "1", "-pa", Directory]}),
        try
            ?assertEqual(non_existing, peer:call(Peer, code, which, [xls_statem_codegen])),
            {ok, Forms} = epp:parse_file("test_data/hls_tags_statem_fixture.erl", [], []),
            Interface = peer:call(Peer, xls_statem_lower, interface, [Forms, [waiting]]),
            ?assertEqual(3, maps:get(mailbox_capacity, Interface)),
            Transformed = peer:call(Peer, hls_pack, parse_transform, [Forms, []]),
            ?assertEqual([Interface], [Value || {attribute, _, hls_actor_interface, Value}
                <- Transformed])
        after
            peer:stop(Peer)
        end
    after
        ok = file:del_dir_r(Directory)
    end.
