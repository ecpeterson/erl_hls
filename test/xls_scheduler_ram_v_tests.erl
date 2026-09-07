-module(xls_scheduler_ram_v_tests).

-include_lib("eunit/include/eunit.hrl").

zero_reduction_width_preserves_legacy_machine_width_test() ->
    StateWidth = 37,
    [Binding] = xls_scheduler_ram_v:bindings(plan(StateWidth, #{})),
    ?assertEqual(
        xls_statem_codegen:shared_machine_width(StateWidth),
        maps:get(state_width, Binding)
    ),
    ?assertNot(maps:is_key(reduction_width, Binding)),
    ?assertEqual(
        nomatch,
        binary:match(rendered(Binding), <<"scheduler_0_reduction">>)
    ).

reduction_storage_remains_inside_the_scheduler_test() ->
    StateWidth = 37,
    [Binding] = xls_scheduler_ram_v:bindings(plan(StateWidth, #{
        reduction_storage_width => 19
    })),
    ?assertEqual(
        xls_statem_codegen:shared_machine_width(StateWidth),
        maps:get(state_width, Binding)
    ),
    ?assertNot(maps:is_key(reduction_width, Binding)),
    ?assertNot(maps:is_key(reduction_address_width, Binding)),
    Rendered = rendered(Binding),
    ?assertEqual(nomatch, binary:match(
        Rendered, <<"scheduler_0_reduction">>
    )).

rendered(Binding) ->
    iolist_to_binary([
        xls_scheduler_ram_v:wires([Binding]),
        xls_scheduler_ram_v:application_ports([Binding]),
        xls_scheduler_ram_v:instances([Binding], "clk")
    ]).

plan(StateWidth, Extra) ->
    Group = maps:merge(#{
        state => #{width => StateWidth},
        slot_count => 3,
        mailbox_capacity => 2
    }, Extra),
    #{groups => [Group]}.
