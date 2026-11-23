-module(hls_mailbox_debug_fixture).
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, producer/3, waiting/3, draining/3, done/3]).
-hls_data(cell).
-hls_phases([boot, producer, waiting, draining, done]).
-hls_mailbox_capacity(3).
-hls_tags([configure, work, advance, report]).
-hls_outputs([work_a, work_b, blocked_0, blocked_1, blocked_2, blocked_3, blocked_4, blocked_5, blocked_6, blocked_7, blocked_8, blocked_9, blocked_10, blocked_11, advance]).
-record(cell, {sum = hls_type:zero() :: hls_nums:u32()}).
-record(configure, {role = hls_type:zero() :: hls_nums:u32()}).
-record(work, {value = hls_type:zero() :: hls_nums:u32()}).
-record(advance, {value = hls_type:zero() :: hls_nums:u32()}).
-record(report, {value = hls_type:zero() :: hls_nums:u32()}).

init([]) -> {ok, boot, #cell{}}.
boot(enter, _, Cell) -> {Cell, []};
boot(cast, #configure{role = 0}, Cell) -> {producer, Cell, consume};
boot(cast, #configure{role = 1}, Cell) -> {waiting, Cell, consume}.
producer(enter, _, Cell) ->
    %% Reports fill the external holding slots before advance can leave.
    %% Port aliases preserve this order in the common source-effect batch.
    {Cell, [{cast, work_a, #work{value = 1}},
            {cast, work_b, #work{value = 2}},
            {cast, blocked_0, #report{value = 0}},
            {cast, blocked_1, #report{value = 1}},
            {cast, blocked_2, #report{value = 2}},
            {cast, blocked_3, #report{value = 3}},
            {cast, blocked_4, #report{value = 4}},
            {cast, blocked_5, #report{value = 5}},
            {cast, blocked_6, #report{value = 6}},
            {cast, blocked_7, #report{value = 7}},
            {cast, blocked_8, #report{value = 8}},
            {cast, blocked_9, #report{value = 9}},
            {cast, blocked_10, #report{value = 10}},
            {cast, blocked_11, #report{value = 11}},
            {cast, advance, #advance{}}]};
producer(cast, #work{}, Cell) -> {producer, Cell, consume}.
waiting(enter, _, Cell) -> {Cell, []};
waiting(cast, #work{}, Cell) -> {waiting, Cell, postpone};
waiting(cast, #advance{}, Cell) -> {draining, Cell, consume}.
draining(enter, _, Cell) -> {Cell, []};
draining(cast, #work{value = Value}, Cell) ->
    Sum = Cell#cell.sum + Value,
    if Sum =:= 3 -> {done, Cell#cell{sum = Sum}, consume};
       true -> {draining, Cell#cell{sum = Sum}, consume}
    end.
done(enter, _, Cell) ->
    true = Cell#cell.sum =:= 3,
    {Cell, []};
done(cast, #work{}, Cell) -> {done, Cell, fail}.
