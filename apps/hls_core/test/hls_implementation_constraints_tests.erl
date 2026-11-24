-module(hls_implementation_constraints_tests).

-include_lib("eunit/include/eunit.hrl").

%% Common normalization retains backend extras while owning shared defaults and bounds.
-spec topology_normalization_test() -> ok.
topology_normalization_test() ->
    Profile = #{
        name => example,
        channel_depth => 2,
        actor_egress_depth => burst,
        backend_option => retained
    },
    Normal = hls_implementation_constraints:normalize_topology(
        Profile,
        [backend_option],
        fun(Name, Context) ->
            hls_implementation_constraints:identifier(Name, Context, fun(_, _) -> false end)
        end
    ),
    ?assertEqual("example", maps:get(name, Normal)),
    ?assertEqual(3, maps:get(frame_payload_words, Normal)),
    ?assertEqual(retained, maps:get(backend_option, Normal)),
    ?assertEqual(4, hls_implementation_constraints:egress_depth(burst, 5)),
    ?assertEqual(7, hls_implementation_constraints:egress_depth(7, 0)).

%% Shared structural failures preserve the profile diagnostics used by both backends.
-spec topology_rejection_test() -> ok.
topology_rejection_test() ->
    Validator = fun(Name, Context) ->
        hls_implementation_constraints:identifier(Name, Context, fun(_, _) -> false end)
    end,
    Base = #{name => example, channel_depth => 1, actor_egress_depth => burst},
    ?assertError(
        {invalid_dslx_profile_keys, [], [unknown]},
        hls_implementation_constraints:normalize_topology(
            Base#{unknown => true}, [], Validator
        )
    ),
    ?assertError(
        {invalid_dslx_channel_depth, 0},
        hls_implementation_constraints:normalize_topology(
            Base#{channel_depth := 0}, [], Validator
        )
    ),
    ?assertError({egress_depth, -1}, hls_implementation_constraints:egress_depth(-1, 0)),
    ?assertError(
        {invalid_dslx_identifier, topology_name, "Invalid"},
        hls_implementation_constraints:normalize_topology(
            Base#{name := 'Invalid'}, [], Validator
        )
    ).

%% Target wrappers supply only their reserved-name set; spelling has one authority.
-spec identifier_policy_test() -> ok.
identifier_policy_test() ->
    Keyword = fun(Name) -> Name =:= "reserved" end,
    Reserved = fun(Name, Context) ->
        hls_implementation_constraints:reserved_identifier(
            Name, Context, Keyword, [scheduler_module], ["scheduler_support"]
        )
    end,
    ?assertEqual(
        "legal_name",
        hls_implementation_constraints:identifier(legal_name, topology_name, Reserved)
    ),
    ?assertError(
        {reserved_dslx_identifier, topology_name, "reserved"},
        hls_implementation_constraints:identifier(reserved, topology_name, Reserved)
    ),
    ?assertEqual(
        "reserved",
        hls_implementation_constraints:identifier(reserved, external_id, Reserved)
    ),
    ?assertError(
        {reserved_dslx_identifier, scheduler_module, "scheduler_support"},
        hls_implementation_constraints:identifier(
            scheduler_support, scheduler_module, Reserved
        )
    ).

%% Schedule renderers preserve each existing bundle's flag order from one checked schedule.
-spec schedule_encoding_test() -> ok.
schedule_encoding_test() ->
    Schedule = hls_implementation_constraints:channel_schedule(#{pipeline_stages => 4}),
    ?assertEqual(
        [
            <<"--pipeline_stages=4">>,
            <<"--delay_model=unit">>,
            <<"--flop_inputs=false">>,
            <<"--flop_outputs=true">>,
            <<"--use_system_verilog=false">>,
            <<"--reset=reset">>,
            <<"--fifo_module=">>,
            <<"--worst_case_throughput=1">>
        ],
        hls_implementation_constraints:schedule_flags(Schedule, channel)
    ),
    Standalone = hls_implementation_constraints:standalone_topology_schedule(4),
    ?assertEqual(
        [
            <<"--pipeline_stages=4">>,
            <<"--delay_model=unit">>,
            <<"--worst_case_throughput=1">>,
            <<"--flop_inputs=false">>,
            <<"--flop_outputs=true">>,
            <<"--use_system_verilog=false">>,
            <<"--reset=reset">>,
            <<"--fifo_module=">>
        ],
        hls_implementation_constraints:schedule_flags(Standalone, standalone_topology)
    ).

%% Standalone and scheduler counts reject at the shared constraint boundary.
-spec schedule_rejection_test() -> ok.
schedule_rejection_test() ->
    ?assertException(
        error,
        {hls_diagnostic, #{stage := topology_build, code := pipeline_stages}},
        hls_implementation_constraints:standalone_topology_schedule(0)
    ),
    ?assertException(
        error,
        {hls_diagnostic, #{stage := configuration, code := invalid_schedule_option}},
        hls_implementation_constraints:channel_schedule(#{pipeline_stages => (1 bsl 32)})
    ).
