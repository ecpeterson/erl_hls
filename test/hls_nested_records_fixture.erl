-module(hls_nested_records_fixture).
-moduledoc "A small actor whose state, messages and helpers share ordinary record values.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, boot/3, active/3]).
-hls_data(cell).
-hls_phases([boot, active]).
-hls_outputs([out]).
-hls_mailbox_capacity(2).
-hls_tags([snapshot, report]).

%% Coordinates have a dense signed/unsigned wire layout.
-record(vector2, {
    x = hls_type:zero() :: hls_nums:uN(5),
    y = hls_type:zero() :: hls_nums:sN(7)
}).
%% Samples exercise a second nesting level and a non-byte-aligned field.
-record(sample, {
    position = hls_type:zero() :: #vector2{},
    valid = hls_type:zero() :: hls_bool:bool()
}).
%% Only this outer state record carries the actor-state tag in DSLX.
-record(cell, {
    current = hls_type:zero() :: #sample{},
    previous = hls_type:zero() :: #sample{}
}).
%% Message tags belong to the outer record, never to its sample value.
-record(snapshot, {sample = hls_type:zero() :: #sample{}}).
%% Both copies use the same nested codecs as actor state.
-record(report, {
    current = hls_type:zero() :: #sample{},
    previous = hls_type:zero() :: #sample{}
}).

-doc "Starts with recursively zeroed samples.".
-spec init([]) -> {ok, boot, #cell{}}.
init([]) -> {ok, boot, #cell{}}.

-doc "Accepts the first sample and schedules its report.".
-spec boot(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #snapshot{}, #cell{}) -> hls_statem:cast_result(active, #cell{}).
boot(enter, _Old, Cell) -> {Cell, []};
%% Nested head patterns expose the sample as an ordinary helper argument.
boot(cast, #snapshot{sample = Sample}, Cell) ->
    {active, remember(Sample, Cell), consume}.

-doc "Reports the current and previous samples, and accepts further updates.".
-spec active(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #snapshot{}, #cell{}) -> hls_statem:cast_result(active, #cell{}).
active(enter, _Old, Cell) ->
    {Cell, [{cast, out, #report{current = Cell#cell.current, previous = Cell#cell.previous}}]};
%% Keep subsequent samples in the same phase without publishing another entry.
active(cast, #snapshot{sample = Sample}, Cell) ->
    {active, remember(Sample, Cell), consume}.

%% A helper can mix tagged actor data with ordinary internal record arguments.
-spec remember(#sample{}, #cell{}) -> #cell{}.
remember(Sample, Cell) ->
    Updated = advance(Sample),
    #sample{position = Position} = Updated,
    case Position of
        #vector2{y = 0} -> Cell#cell{current = Updated, previous = Cell#cell.current};
        #vector2{} -> Cell#cell{current = Updated#sample{valid = true}, previous = Cell#cell.current}
    end.

%% Patterned internal helper arguments, nested projections and updates share one value shape.
-spec advance(#sample{}) -> #sample{}.
advance(Sample = #sample{valid = true, position = Vector = #vector2{x = X}}) ->
    Sample#sample{position = Vector#vector2{x = hls_nums:wrap(hls_nums:uN(5), X + 1)}};
advance(Sample = #sample{}) ->
    Sample#sample{position = #vector2{x = 3, y = (Sample#sample.position)#vector2.y}}.
