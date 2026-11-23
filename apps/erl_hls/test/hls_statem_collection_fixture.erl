-module(hls_statem_collection_fixture).
-moduledoc "CPU fixture for mutually exclusive collection openings and reduction continuations.".
-behaviour(hls_statem).
-export([init/1, idle/3, reducing/3, finishing/3, finished/3, reduce/3]).
-hls_continuations([finish]).

-doc "Starts before either collection has been opened.".
-spec init(atom()) -> {ok, idle, map()}.
init(Mode) -> {ok, idle, #{mode => Mode, value => 0}}.

-doc "Moves to the entry whose complete action list is validated atomically.".
-spec idle(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map());
    (cast, open, map()) -> hls_statem:cast_result(map()).
idle(enter, _, Data) -> {Data, []};
idle(cast, open, Data) -> {reducing, Data, consume}.

-doc "Completes a scalar reduction through a continuation, or presents conflicting entry actions.".
-spec reducing(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map());
    (cast, {value, integer()}, map()) -> hls_statem:cast_result(map());
    (internal, hls_statem:reduction_complete(), map()) -> hls_statem:internal_result(map()).
reducing(enter, _, Data = #{mode := Mode}) ->
    Reduction = {open_reduction, sum, 0, {count, 1}, {commutative_monoid, 0}},
    Gather = {open_gather, items, 0, {members_mask, 2, 0}, padding},
    Actions = case Mode of
        reduction_first -> [Reduction, Gather];
        gather_first -> [Gather, Reduction];
        _ -> [Reduction]
    end,
    {Data, Actions};
reducing(cast, {value, Value}, Data) -> {reducing, Data, {contribute, sum, 0, Value}};
reducing(internal, {reduction_complete, sum, 0, Value}, Data) ->
    {finishing, Data#{value := Value}, consume, [{next_event, internal, finish}]}.

-doc "Runs phase entry before the completion's requested internal event.".
-spec finishing(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map());
    (internal, finish, map()) -> hls_statem:internal_result(map()).
finishing(enter, _, Data) -> {Data, [{cast, out, reduced_entry}]};
finishing(internal, finish, Data) -> {finished, Data, consume}.

-doc "Publishes the reduction value from the continuation's successor phase.".
-spec finished(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map()).
finished(enter, _, Data = #{value := Value}) -> {Data, [{cast, out, {reduced, Value}}]}.

-doc "Combines bounded witness inputs with the scalar identity.".
-spec reduce(sum, integer(), integer()) -> integer().
reduce(sum, Left, Right) -> Left + Right.
