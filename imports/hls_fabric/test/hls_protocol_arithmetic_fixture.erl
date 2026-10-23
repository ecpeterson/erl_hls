-module(hls_protocol_arithmetic_fixture).
-moduledoc "Independent scalar actors with different operands and one source-completion multiply each.".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, collecting/3, reporting/3, reduce/3, topology/1]).
-hls_data(cell).
-hls_phases([collecting, reporting]).
-hls_outputs([out]).
-hls_tags([piece, result]).
-hls_mailbox_capacity(4).

%% The output stays actor-local until the reporting entry publishes it.
-record(cell, {value = hls_type:zero() :: hls_nums:u16()}).
%% Both operands travel through ordinary typed receipts, never testbench state injection.
-record(piece, {key = hls_type:zero() :: hls_nums:u32(),
    left = hls_type:zero() :: hls_nums:u16(), right = hls_type:zero() :: hls_nums:u16()}).
%% Scalar accumulator is private and is not a wire schema.
-record(sum, {left = hls_type:zero() :: hls_nums:u16(), right = hls_type:zero() :: hls_nums:u16()}).
%% Ordinary external output exposes the source result.
-record(result, {value = hls_type:zero() :: hls_nums:u16()}).

-doc "Starts the ordinary scalar opening entry.".
-spec init([]) -> {ok, collecting, #cell{}}.
init([]) -> {ok, collecting, #cell{}}.

-doc "Collects two receipts, then multiplies their scalar totals in the completion callback.".
-spec collecting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{}, #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, {reduction_complete, sum, non_neg_integer(), #sum{}}, #cell{}) -> hls_statem:cast_result(#cell{}).
collecting(enter, _, C) -> {C, [{open_reduction, sum, 0, {count, 2}, {commutative_monoid, #sum{left = 0, right = 0}}}]};
collecting(cast, #piece{key = Key, left = A, right = B}, C) ->
    {collecting, C, {contribute, sum, Key, #sum{left = A, right = B}}};
collecting(internal, {reduction_complete, sum, 0, #sum{left = A, right = B}}, C) ->
    {reporting, C#cell{value = A * B}, consume}.

-doc "Publishes one result, then consumes unused receipts without reopening the collection.".
-spec reporting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, #piece{}, #cell{}) -> hls_statem:cast_result(#cell{}).
reporting(enter, _, C) -> {C, [{cast, out, #result{value = C#cell.value}}]};
reporting(cast, #piece{}, C) -> {reporting, C, consume}.

-doc "Combines the two independent operand sums; this reducer contains no multiply.".
-spec reduce(sum, #sum{}, #sum{}) -> #sum{}.
reduce(sum, #sum{left = A, right = B}, #sum{left = C, right = D}) ->
    #sum{left = A + C, right = B + D}.

-doc "Instantiates two or three homogeneous actors with distinct operands and independent output stalls.".
-spec topology(2..3) -> map().
topology(N) when N >= 2, N =< 3 ->
    Ids = lists:seq(0, N - 1),
    #{version => 1, actors => maps:from_list([{I, ?MODULE} || I <- Ids]), families => #{},
      ingresses => [], route_relations => [], externals => [{I, out, [result]} || I <- Ids],
      startup => [{I, [#piece{left = I + 2}, #piece{right = I + 5}]} || I <- Ids],
      routes => [{{I, out}, [{external, I}]} || I <- Ids]}.
