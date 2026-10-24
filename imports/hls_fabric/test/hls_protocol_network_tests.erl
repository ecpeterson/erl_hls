-module(hls_protocol_network_tests).
-moduledoc "Public network boundary rejects unsupported activation before source or filesystem work.".
-include_lib("eunit/include/eunit.hrl").

%% An invalid mode cannot be silently interpreted as automatic activation.
-spec unsupported_activation_test() -> ok.
unsupported_activation_test() ->
    ?assertError({unsupported_protocol_activation,pause},
        hls_protocol_network:write(#{activation=>pause},"unused")),
    ?assertError({unsupported_protocol_activation,<<"explicit_start">>},
        hls_protocol_network:write(#{activation=><<"explicit_start">>},"unused")).

%% One source definition backs several independent inbox owners, bound by hash.
-spec imported_owner_test() -> ok.
imported_owner_test() ->
    Config = #{sources => [{"test/hls_protocol_boundary_fixture.erl", []}],
        topology => {hls_protocol_boundary_fixture, topology, []}, actor_limit => 4},
    Plan = hls_protocol_transport:descriptor(hls_protocol_transport:plan(Config)),
    #{actor_functions := [#{file := File, manifest := #{dslx_sha256 := Hash}}],
        receivers := Receivers} = Plan,
    ?assertEqual([0, 1, 2, 3], [I || #{index := I} <- Receivers]),
    lists:foreach(fun(#{manifest := #{owner_import := Import, inbox := Inbox}}) ->
        ?assertEqual(#{file => File, dslx_sha256 => Hash}, Import),
        ?assert(maps:get(mask_bits, Inbox) > 0)
    end, Receivers).
