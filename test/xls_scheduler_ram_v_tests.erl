-module(xls_scheduler_ram_v_tests).

-include_lib("eunit/include/eunit.hrl").

zero_reduction_width_preserves_legacy_machine_width_test() ->
    StateWidth = 37,
    [Binding] = xls_scheduler_ram_v:bindings(plan(StateWidth, #{})),
    ?assertEqual(
        xls_statem_codegen:shared_machine_width(StateWidth),
        maps:get(state_width, Binding)
    ).

reduction_storage_is_part_of_each_actor_ram_row_test() ->
    StateWidth = 37,
    ReductionWidth = 19,
    [Binding] = xls_scheduler_ram_v:bindings(plan(StateWidth, #{
        reduction_storage_width => ReductionWidth
    })),
    ?assertEqual(
        xls_statem_codegen:shared_machine_width(StateWidth, ReductionWidth),
        maps:get(state_width, Binding)
    ),
    ?assertEqual(
        xls_statem_codegen:shared_machine_width(StateWidth) + ReductionWidth,
        maps:get(state_width, Binding)
    ).

plan(StateWidth, Extra) ->
    Group = maps:merge(#{
        state => #{width => StateWidth},
        slot_count => 3,
        mailbox_capacity => 2
    }, Extra),
    #{groups => [Group]}.
