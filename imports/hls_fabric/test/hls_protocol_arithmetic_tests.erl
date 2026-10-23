-module(hls_protocol_arithmetic_tests).
-moduledoc "Fresh-source sharing checks reject ambiguous ownership and unsupported source families before emission.".
-include_lib("eunit/include/eunit.hrl").

%% Plans originate in an actual ordinary source compilation; indices follow the whole topology.
-spec source_bound_groups_test() -> ok.
source_bound_groups_test() ->
    A = hls_local_actor:compile("test/hls_protocol_arithmetic_fixture.erl", []),
    M = hls_protocol_arithmetic_fixture,
    Bundle = #{topology => #{actors => [#{id => I, module => M} || I <- [a,b,c]]}, modules => #{M => A}},
    [#{members := [2,0], cursor_bits := 1}] = hls_protocol_arithmetic:plan([[c,a]], Bundle, [0,1,2]),
    [#{cursor_bits := 2}] = hls_protocol_arithmetic:plan([[a,b,c]], Bundle, [0,1,2]),
    ?assertEqual([], hls_protocol_arithmetic:plan([], Bundle, [0,1,2])),
    ?assertError({arithmetic_group_size, [a]}, hls_protocol_arithmetic:plan([[a]], Bundle, [0,1,2])),
    ?assertError(overlapping_arithmetic_groups, hls_protocol_arithmetic:plan([[a,a]], Bundle, [0,1,2])),
    ?assertError(overlapping_arithmetic_groups, hls_protocol_arithmetic:plan([[a,b],[b,c]], Bundle, [0,1,2])),
    ?assertError({arithmetic_member_not_native,c}, hls_protocol_arithmetic:plan([[a,c]], Bundle, [0,1])),
    ?assertError({arithmetic_member_not_native,missing}, hls_protocol_arithmetic:plan([[a,missing]], Bundle, [0,1,2])),
    ?assertError({invalid_arithmetic_groups,all}, hls_protocol_arithmetic:plan(all, Bundle, [0,1,2])),
    Other = hls_local_actor:compile("test/hls_local_actor_fixture.erl", []),
    Mixed = Bundle#{topology := #{actors => [#{id => a,module => M},#{id => b,module => other}]}, modules := #{M => A,other => Other}},
    ?assertError({incompatible_arithmetic_group,[a,b]}, hls_protocol_arithmetic:plan([[a,b]], Mixed, [0,1])),
    Unsupported = Bundle#{modules := #{M => Other}},
    ?assertError({unsupported_shared_completion,M}, hls_protocol_arithmetic:plan([[a,b]], Unsupported, [0,1,2])),
    Groups = hls_protocol_arithmetic:plan([[a,b]], Bundle, [0,1,2]),
    ?assertEqual(A, hls_protocol_arithmetic:receiver(2, Groups, A)),
    #{completion := #{mode := shared, group := 0}} = hls_protocol_arithmetic:receiver(0, Groups, A),
    ok.
