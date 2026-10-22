-module(hls_protocol_capture_fixture).
-moduledoc "Complete two-phase source for capture derivation and generated-codec witnesses.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, first/3, second/3]).
-hls_data(cell).
-hls_phases([first, second]).
-hls_outputs([unaligned, full, constant, small, varying, conditional, partial, state_value]).
-hls_tags([unaligned, full, constant, small]).
-hls_mailbox_capacity(2).

%% Constants border unaligned, independently variable fields.
-record(unaligned, {id = hls_type:zero() :: hls_nums:uN(3),
    epoch = hls_type:zero() :: hls_nums:uN(13), value = hls_type:zero() :: hls_nums:uN(46),
    flag = hls_type:zero() :: hls_nums:uN(1)}).
%% These schemas cover the largest payload, a constant-only frame and a small exhaustive domain.
-record(full, {value = hls_type:zero() :: hls_nums:uN(96)}).
-record(constant, {id = hls_type:zero() :: hls_nums:uN(3)}).
-record(small, {value = hls_type:zero() :: hls_nums:uN(5)}).
%% Initial state values do not by themselves authorize field omission.
-record(cell, {epoch = hls_type:zero() :: hls_nums:uN(13),
    value = hls_type:zero() :: hls_nums:uN(46), wide = hls_type:zero() :: hls_nums:uN(96),
    small = hls_type:zero() :: hls_nums:uN(5), id = hls_type:zero() :: hls_nums:uN(3)}).

-doc "Starts in the first publishing phase with a fixed initial identity.".
-spec init([]) -> {ok, first, #cell{}}.
init([]) -> {ok, first, #cell{id = 6}}.

-doc "Publishes fixed, variable, conditional and partially known fields; a command advances phase.".
-spec first(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #full{} | #unaligned{} | #constant{} | #small{}, #cell{}) -> hls_statem:cast_result(#cell{}).
%% Both conditional send arms must participate, even though they share a port and schema.
first(enter, _, C) ->
    Conditional = case C#cell.small of
        0 -> [{cast, conditional, #constant{id = 1}}];
        _ -> [{cast, conditional, #constant{id = 2}}]
    end,
    {C, [{cast, unaligned, #unaligned{id = 5, epoch = C#cell.epoch, value = C#cell.value, flag = 1}},
         {cast, full, #full{value = C#cell.wide}},
         {cast, constant, #constant{id = 6}},
         {cast, small, #small{value = C#cell.small}},
         {cast, varying, #constant{id = 1}},
         {cast, partial, #small{value = C#cell.small band 3}},
         {cast, state_value, #constant{id = C#cell.id}}] ++ Conditional};
%% Runtime state changes are outside constant-literal analysis.
first(cast, #full{value = V}, C) -> {second, C#cell{wide = V}, consume};
%% Other schemas exercise closed routes without changing the publishing state.
first(cast, #unaligned{}, C) -> {first, C, consume};
first(cast, #constant{}, C) -> {first, C, consume};
first(cast, #small{}, C) -> {first, C, consume}.

-doc "Publishes a different identity on the same channel, preventing first-phase-only elision.".
-spec second(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #full{} | #unaligned{} | #constant{} | #small{}, #cell{}) -> hls_statem:cast_result(#cell{}).
second(enter, _, C) -> {C, [{cast, varying, #constant{id = 2}}]};
second(cast, #full{value = V}, C) -> {first, C#cell{wide = V}, consume};
%% Other schemas exercise closed routes without changing the publishing state.
second(cast, #unaligned{}, C) -> {second, C, consume};
second(cast, #constant{}, C) -> {second, C, consume};
second(cast, #small{}, C) -> {second, C, consume}.
