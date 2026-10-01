-module(hls_mixed_collector).
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, collecting/3, reporting/3]).
-hls_data(cell).
-hls_phases([collecting, reporting]).
-hls_outputs([report, feedback]).
-hls_mailbox_capacity(4).
-include("hls_mixed_protocol.hrl").
-record(cell, {round = hls_type:zero() :: hls_nums:u32(),
               count = hls_type:zero() :: hls_nums:u32(),
               sum = hls_type:zero() :: hls_nums:u32(),
               seen = hls_type:zero() :: hls_nums:u32()}).

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {'ok','collecting',#cell{}}.
init([]) -> {ok, collecting, #cell{}}.
-doc "Accumulates the fixture's expected contributions before reporting.".
-spec collecting('cast' | 'enter',term(),term()) -> {term(),[]} | {'collecting',#cell{round::integer(),count::number(),sum::number(),seen::integer()},'consume'} | {'reporting',#cell{round::integer(),count::number(),sum::number(),seen::integer()},'consume'}.
collecting(enter, _, Cell) -> {Cell, []};
collecting(cast, Result = #result{}, Cell) ->
    Next = accept(Result, Cell),
    if Next#cell.count =:= 20 -> {reporting, Next, consume};
       true -> {collecting, Next, consume}
    end.
-doc "Publishes the completed fixture result through its declared output.".
-spec reporting('cast' | 'enter',term(),#cell{round::number(),sum::number(),seen::integer()}) -> {#cell{round::number(),count::0,sum::0,seen::0},[{'cast','feedback' | 'report',{term(),term()} | {term(),term(),term()}},...]} | {'collecting',#cell{round::integer(),count::number(),sum::number(),seen::integer()},'consume'}.
reporting(enter, _, Cell) ->
    true = Cell#cell.seen =:= 1048575,
    true = Cell#cell.sum =:= 80 * Cell#cell.round + 30,
    {Cell#cell{round = Cell#cell.round + 1, count = 0, sum = 0, seen = 0},
        [{cast, report, #report{round = Cell#cell.round, sum = Cell#cell.sum}},
         {cast, feedback, #kick{round = Cell#cell.round + 1}}]};
reporting(cast, Result = #result{}, Cell) ->
    Next = accept(Result, Cell),
    {collecting, Next, consume}.

%% Adds one accepted result to the fixture's collection state.
-spec accept(#result{}, #cell{}) -> #cell{}.
accept(#result{id = Id, sequence = Sequence}, Cell) ->
    true = Id < 5,
    true = Sequence div 4 =:= Cell#cell.round,
    Bit = hls_type:as(hls_nums:u32(), 1) bsl (Id + 5 * (Sequence band 3)),
    true = Cell#cell.seen band Bit =:= 0,
    true = (Sequence band 3 =:= 0) orelse (Cell#cell.seen band (Bit bsr 5) =/= 0),
    Cell#cell{count = Cell#cell.count + 1, sum = Cell#cell.sum + Sequence,
        seen = Cell#cell.seen bor Bit}.
