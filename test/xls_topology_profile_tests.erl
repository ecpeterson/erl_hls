-module(xls_topology_profile_tests).

-include_lib("eunit/include/eunit.hrl").

%% Exercise both public emitters: sharing a validator must not broaden the
%% scalar backend's options or lose the family backend's diagnostics.
common_profile_errors_test_() ->
    Profile = profile(),
    Cases = [
        {[], {invalid_dslx_profile, []}},
        {#{unexpected => true},
            {invalid_dslx_profile_keys,
                [actor_egress_depth, channel_depth, name], [unexpected]}},
        {Profile#{name := 'Invalid', channel_depth := 0},
            {invalid_dslx_identifier, topology_name, "Invalid"}},
        {Profile#{name := 'proc'},
            {reserved_dslx_identifier, topology_name, "proc"}},
        {Profile#{name := 42},
            {invalid_dslx_identifier, topology_name, 42}},
        {Profile#{channel_depth := 0}, {invalid_dslx_channel_depth, 0}},
        {Profile#{channel_depth := 1.0}, {invalid_dslx_channel_depth, 1.0}},
        {Profile#{channel_depth := 16#100000000},
            {invalid_dslx_channel_depth, 16#100000000}},
        {Profile#{actor_egress_depth := -1}, {egress_depth, -1}},
        {Profile#{actor_egress_depth := 16#100000000},
            {egress_depth, 16#100000000}}
    ],
    [{atom_to_list(Kind), [
        ?_assertError(Reason, xls_topology_dslx:emit(Plan, Input))
        || {Input, Reason} <- Cases
    ]} || {Kind, Plan} <- plans()].

family_options_remain_backend_specific_test_() ->
    [{scalar, Scalar}, {family, Family}] = plans(),
    Cases = [
        {scheduler_groups, [], {scheduler_groups, []}},
        {reduction_placements, [], {reduction_placements, []}},
        {effect_window_partition, invalid, {effect_window_partition, invalid}}
    ],
    [?_test(begin
        Profile = (profile())#{Key => Value},
        ?assertError({invalid_dslx_profile_keys, [], [Key]},
            xls_topology_dslx:emit(Scalar, Profile)),
        ?assertError(FamilyError, xls_topology_dslx:emit(Family, Profile))
    end) || {Key, Value, FamilyError} <- Cases].

explicit_family_defaults_preserve_output_test() ->
    {family, Family} = lists:keyfind(family, 1, plans()),
    Profile = profile(),
    ?assertEqual(emit(Family, Profile), emit(Family, Profile#{
        scheduler_groups => #{},
        reduction_placements => #{},
        effect_window_partition => global
    })).

atom_and_string_names_preserve_output_test_() ->
    [?_assertEqual(emit(Plan, profile()),
        emit(Plan, (profile())#{name := "profile_probe"}))
        || {_Kind, Plan} <- plans()].

profile_error_precedes_stale_lane_error_test() ->
    {scalar, Scalar} = lists:keyfind(scalar, 1, plans()),
    Stale = Scalar#{lanes := stale},
    ?assertError({invalid_dslx_channel_depth, 0},
        xls_topology_dslx:emit(Stale, (profile())#{channel_depth := 0})),
    try xls_topology_dslx:emit(Stale, profile()) of
        _ -> ?assert(false)
    catch
        error:{inconsistent_dslx_plan_lanes, [_ | _], stale} -> ok
    end.

plans() ->
    [
        {scalar, hls_topology:from_module(phi_phenom_topology)},
        {family, hls_topology:normalize(phi_torus_topology:topology(1, 1))}
    ].

profile() ->
    #{name => profile_probe, channel_depth => 1, actor_egress_depth => burst}.

emit(Plan, Profile) ->
    iolist_to_binary(xls_topology_dslx:emit(Plan, Profile)).
