-module(xls_template_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Explicit slots must remain a checked interface between templates and emitters.
-spec slots_test() -> ok.
slots_test() ->
    ?assertEqual(<<"a+b">>, xls_template:render(<<"@@A@@+@@B@@">>,
        [{<<"@@A@@">>, ["a"]}, {<<"@@B@@">>, <<"b">>}])),
    ?assertError({template_slot_count, <<"@@A@@">>, 0},
        xls_template:render(<<"none">>, [{<<"@@A@@">>, "a"}])),
    ?assertError({template_slot_count, <<"@@A@@">>, 2},
        xls_template:render(<<"@@A@@@@A@@">>, [{<<"@@A@@">>, "a"}])),
    ?assertError({unresolved_template_slot, <<"@@A@@">>},
        xls_template:render(<<"@@A@@">>, [])).
