-module(xls_scheduler_ram_v_tests).
-moduledoc false.
-include_lib("eunit/include/eunit.hrl").

%% Padding may simplify addresses only when physical memory depth is unchanged.
-spec mailbox_padding_uses_existing_rows_test() -> ok.
mailbox_padding_uses_existing_rows_test() ->
    ?assertEqual(32, xls_scheduler_ram_v:mailbox_stride(6, 24)),
    ?assertEqual(32, xls_scheduler_ram_v:mailbox_stride(3, 24)),
    ?assertEqual(24, xls_scheduler_ram_v:mailbox_stride(5, 24)),
    ?assertEqual(5, xls_scheduler_ram_v:mailbox_stride(5, 5)),
    ?assertEqual(1, xls_scheduler_ram_v:mailbox_stride(1, 1)).

%% Bindings expose the selected layout while retaining the minimum RAM width.
-spec mailbox_binding_records_stride_test() -> ok.
mailbox_binding_records_stride_test() ->
    [Binding] = xls_scheduler_ram_v:bindings(#{groups => [#{
        state => #{width => 32}, slot_count => 6, mailbox_capacity => 24}]}),
    ?assertEqual(32, maps:get(mailbox_stride, Binding)),
    ?assertEqual(8, maps:get(mailbox_address_width, Binding)).

%% Exhaustive small plans cover every supported mailbox capacity and both layouts.
-spec mailbox_padding_never_grows_memory_test() -> ok.
mailbox_padding_never_grows_memory_test() ->
    lists:foreach(fun({Slots, Capacity}) ->
        Stride = xls_scheduler_ram_v:mailbox_stride(Slots, Capacity),
        ?assert(Stride >= Capacity),
        ?assert(Stride =:= Capacity orelse Stride band (Stride - 1) =:= 0),
        ?assertEqual(width(Slots * Capacity), width(Slots * Stride))
    end, [{Slots, Capacity} || Slots <- lists:seq(1, 64), Capacity <- lists:seq(1, 255)]).

%% Match the RAM's minimum one-bit address bus without reusing the production helper.
-spec width(pos_integer()) -> pos_integer().
width(Count) -> max(1, length(integer_to_list(Count - 1, 2))).
