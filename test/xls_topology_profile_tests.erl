-module(xls_topology_profile_tests).

-include_lib("eunit/include/eunit.hrl").

%% Exact and compact family graphs share one physical option contract.
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

physical_option_errors_are_representation_independent_test_() ->
    Cases = [{scheduler_groups, [], {scheduler_groups, []}},
        {reduction_placements, [], {reduction_placements, []}},
        {effect_window_partition, invalid, {effect_window_partition, invalid}}],
    [?_assertError(Error, xls_topology_dslx:emit(Plan, (profile())#{Key => Value}))
        || {_Kind, Plan} <- plans(), {Key, Value, Error} <- Cases].

explicit_physical_defaults_preserve_output_test_() ->
    [?_assertEqual(emit(Plan, profile()), emit(Plan, (profile())#{
        scheduler_groups => #{}, reduction_placements => #{},
        effect_window_partition => global})) || {_Kind, Plan} <- plans()].

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
