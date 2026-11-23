-module(hls_cross_domain_consumer).
-moduledoc "Source receiver for the cross-domain witness. Closed-phase items postpone until a later open; public reports retain the postponed count and ordered running total.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-hls_data(cell).
-hls_phases([closed, closed_report, opened, opened_report]).
-hls_outputs([out]).
-hls_tags([item, open, read, explode, received]).
-hls_mailbox_capacity(4).

%% Source state-machine callbacks.
-export([init/1, closed/3, closed_report/3, opened/3, opened_report/3]).

%% Deferred records actual closed-phase dispatch, not inferred transport timing.
-record(cell, {request = hls_type:zero() :: hls_nums:u32(),
    total = hls_type:zero() :: hls_nums:u32(), deferred = hls_type:zero() :: hls_nums:u32()}).
-record(item, {request = hls_type:zero() :: hls_nums:u32(), value = hls_type:zero() :: hls_nums:u32()}).
-record(open, {request = hls_type:zero() :: hls_nums:u32(), unused = hls_type:zero() :: hls_nums:u32()}).
-record(read, {request = hls_type:zero() :: hls_nums:u32(), unused = hls_type:zero() :: hls_nums:u32()}).
-record(explode, {request = hls_type:zero() :: hls_nums:u32(), unused = hls_type:zero() :: hls_nums:u32()}).
-record(received, {request = hls_type:zero() :: hls_nums:u32(),
    total = hls_type:zero() :: hls_nums:u32(), deferred = hls_type:zero() :: hls_nums:u32()}).

-doc "Starts closed and silent so the first source item must postpone.".
-spec init([]) -> {ok, closed, #cell{}}.
init([]) -> {ok, closed, #cell{}}.

-doc "Retains items, opens on a distinct class, exposes a readout or fails through the source directive.".
-spec closed(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #item{} | #open{} | #read{} | #explode{}, #cell{}) -> hls_statem:cast_result(#cell{}).
closed(enter, _, Cell) -> {Cell, []};
closed(cast, #item{}, Cell) -> {closed, Cell#cell{deferred = Cell#cell.deferred + 1}, postpone};
closed(cast, #open{}, Cell) -> {opened, Cell, consume};
closed(cast, #read{request = Request}, Cell) -> {closed_report, Cell#cell{request = Request}, consume};
closed(cast, #explode{}, Cell) -> {closed, Cell, fail}.

-doc "Reports while preserving closed-state postponement and explicit opening behavior.".
-spec closed_report(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #item{} | #open{} | #read{} | #explode{}, #cell{}) -> hls_statem:cast_result(#cell{}).
closed_report(enter, _, Cell) ->
    {Cell, [{cast, out, #received{request = Cell#cell.request, total = Cell#cell.total, deferred = Cell#cell.deferred}}]};
closed_report(cast, #item{}, Cell) -> {closed_report, Cell#cell{deferred = Cell#cell.deferred + 1}, postpone};
closed_report(cast, #open{}, Cell) -> {opened, Cell, consume};
closed_report(cast, #read{request = Request}, Cell) -> {repeat_phase, Cell#cell{request = Request}, consume};
closed_report(cast, #explode{}, Cell) -> {closed_report, Cell, fail}.

-doc "Consumes retained and subsequent items in sender order, reporting the new running total.".
-spec opened(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #item{} | #open{} | #read{} | #explode{}, #cell{}) -> hls_statem:cast_result(#cell{}).
opened(enter, _, Cell) -> {Cell, []};
opened(cast, #item{request = Request, value = Value}, Cell) ->
    {opened_report, Cell#cell{request = Request, total = Cell#cell.total + Value}, consume};
opened(cast, #open{}, Cell) -> {opened, Cell, consume};
opened(cast, #read{request = Request}, Cell) -> {opened_report, Cell#cell{request = Request}, consume};
opened(cast, #explode{}, Cell) -> {opened, Cell, fail}.

-doc "Publishes each consumed value exactly once and repeats entry for later readouts or items.".
-spec opened_report(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #item{} | #open{} | #read{} | #explode{}, #cell{}) -> hls_statem:cast_result(#cell{}).
opened_report(enter, _, Cell) ->
    {Cell, [{cast, out, #received{request = Cell#cell.request, total = Cell#cell.total, deferred = Cell#cell.deferred}}]};
opened_report(cast, #item{request = Request, value = Value}, Cell) ->
    {repeat_phase, Cell#cell{request = Request, total = Cell#cell.total + Value}, consume};
opened_report(cast, #open{}, Cell) -> {opened_report, Cell, consume};
opened_report(cast, #read{request = Request}, Cell) -> {repeat_phase, Cell#cell{request = Request}, consume};
opened_report(cast, #explode{}, Cell) -> {opened_report, Cell, fail}.
