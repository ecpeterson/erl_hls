-module(snowflake_barrier).
-moduledoc """
Combines one contiguous group of up to six vertex completions.

Every member must report once per epoch. Completions agree on phase kind;
the coordinator remains responsible for checking it against its command.
The output preserves the epoch and kind, substitutes the group's source
identity, and ORs busy flags. Publication completes before another epoch
can be collected.
""".
-behaviour(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, configuring/3, starting/3, collecting/3, publishing/3, commanded/3]).
-hls_data(barrier).
-hls_phases([configuring, starting, collecting, publishing, commanded]).
-hls_outputs([status]).
-hls_mailbox_capacity(8).
-include("snowflake_actor_protocol.hrl").
-if(?SNOWFLAKE_ACK_REDUCTION).
-export([reduce/3]).
-endif.
-include("snowflake_barrier.hrl").

%% Startup publishes readiness once; later publications delimit completion sets.
-type phase() :: configuring | starting | collecting | publishing | commanded.

-doc "Starts without a member assignment; early readiness waits for configuration.".
-spec init([]) -> {ok, configuring, #barrier{}}.
init([]) -> {ok, configuring, #barrier{}}.

-doc "Assigns the group identity and member interval; rejects empty or overflowing groups.".
-spec configuring
    (enter, phase(), #barrier{}) -> hls_statem:enter_result(#barrier{});
    (cast, #sf_barrier_config{} | #sf_ready{}, #barrier{}) ->
        hls_statem:cast_result(phase(), #barrier{}).
configuring(enter, _, Cell) ->
    {Cell, []};
%% A later configuration unblocks already queued startup acknowledgments.
configuring(cast, #sf_barrier_config{source = Source, first = First, count = Count}, Cell) ->
    true = Count > 0 andalso Count =< 6,
    End = hls_type:as(hls_nums:u16(), First) + hls_type:as(hls_nums:u16(), Count),
    true = End =< 256,
    true = (not ?SNOWFLAKE_ACK_REDUCTION) orelse End =< ?SNOWFLAKE_BARRIER_SOURCES,
    {starting,
        Cell#barrier{
            source = Source,
            first = First,
            count = Count,
            members = hls_nums:wrap(
                hls_nums:uN(?SNOWFLAKE_BARRIER_SOURCES),
                ((hls_type:as(hls_nums:uN(?SNOWFLAKE_BARRIER_SOURCES), 1) bsl Count) - 1) bsl First
            )
        },
        consume};
configuring(cast, #sf_ready{}, Cell) ->
    {configuring, Cell, postpone}.

-doc "Waits for every configured member's unique startup acknowledgment.".
-spec starting
    (enter, phase(), #barrier{}) -> hls_statem:enter_result(#barrier{});
    (cast, #sf_ready{}, #barrier{}) -> hls_statem:cast_result(phase(), #barrier{}).
starting(enter, _, Cell) ->
    {Cell, []};
starting(cast, #sf_ready{source = Source}, Cell) ->
    Next = acknowledge(Source, Cell),
    case Next#barrier.received =:= Next#barrier.count of
        true -> {collecting, Next#barrier{received = 0, seen = 0}, consume};
        false -> {starting, Next, consume}
    end.

-doc "Publishes group readiness, then collects the first epoch without admitting partial completion.".
-spec collecting
    (enter, phase(), #barrier{}) -> hls_statem:enter_result(#barrier{});
    (cast, #sf_done{} | #sf_phase{}, #barrier{}) -> hls_statem:cast_result(phase(), #barrier{}).
collecting(enter, _, Cell) ->
    {Cell, [{cast, status, #sf_ready{source = Cell#barrier.source}}]};
%% The startup command determines which locally advanced phase must complete.
collecting(cast, _Command = #sf_phase{kind = _Kind}, Cell) ->
    ?SF_ADVANCE_SELECT(
        begin
            true = _Kind =:= 0,
            {commanded, arm(_Command, Cell), consume}
        end,
        {collecting, Cell, fail}
    );
collecting(cast, Message = #sf_done{}, Cell) ->
    ?SF_ADVANCE_SELECT(
        begin
            true = early_completion(Message, Cell),
            {collecting, Cell, postpone}
        end,
        begin
            Next = collect(Message, Cell),
            case Next#barrier.received =:= Next#barrier.count of
                true -> {publishing, Next, consume};
                false -> {collecting, Next, consume}
            end
        end
    ).

-doc "Publishes one full completion set before clearing it and accepting the next sequential epoch.".
-spec publishing
    (enter, phase(), #barrier{}) -> hls_statem:enter_result(#barrier{});
    (cast, #sf_done{} | #sf_phase{}, #barrier{}) -> hls_statem:cast_result(phase(), #barrier{}).
publishing(enter, _, Cell) ->
    Message = #sf_done{
        source = Cell#barrier.source,
        epoch = Cell#barrier.epoch,
        kind = Cell#barrier.kind,
        busy = Cell#barrier.busy
    },
    Next = Cell#barrier{
        epoch = (Cell#barrier.epoch + 1) band 16#ffffffff,
        received = 0,
        seen = 0,
        busy = false
    },
    {Next, [{cast, status, Message}]};
%% Global busy may differ from this group's busy value; learn the actual root decision.
publishing(cast, _Command = #sf_phase{kind = _Kind}, Cell) ->
    ?SF_ADVANCE_SELECT(
        begin
            true =
                case Cell#barrier.kind of
                    2 -> _Kind =:= 2 orelse _Kind =:= 3;
                    4 -> _Kind =:= 4 orelse _Kind =:= 0
                end,
            {commanded, arm(_Command, Cell), consume}
        end,
        {publishing, Cell, fail}
    );
publishing(cast, Message = #sf_done{}, Cell) ->
    ?SF_ADVANCE_SELECT(
        begin
            true = early_completion(Message, Cell),
            {publishing, Cell, postpone}
        end,
        begin
            Next = collect(Message, Cell),
            case Next#barrier.received =:= Next#barrier.count of
                true -> {repeat_phase, Next, consume};
                false -> {publishing, Next, consume}
            end
        end
    ).

-if(?SNOWFLAKE_ACK_REDUCTION).
-doc "Opens one keyed member set; completes only when its kind agrees with the root command.".
-spec commanded
    (enter, phase(), #barrier{}) -> hls_statem:enter_result(#barrier{});
    (cast, #sf_done{}, #barrier{}) -> hls_statem:cast_result(phase(), #barrier{});
    (internal, hls_statem:reduction_complete(), #barrier{}) ->
        hls_statem:internal_result(phase(), #barrier{}).
commanded(enter, _, Cell) ->
    {Cell, [
        {open_reduction, acknowledgments, Cell#barrier.epoch,
            {members_mask, ?SNOWFLAKE_BARRIER_SOURCES, Cell#barrier.members},
            {commutative_monoid, #ack_sum{kinds = 0, busy = false}}}
    ]};
commanded(
    cast,
    #sf_done{source = Source, epoch = Epoch, kind = Kind, busy = Busy},
    Cell = #barrier{epoch = Epoch}
) when Kind < 5 ->
    {commanded, Cell,
        {contribute, acknowledgments, Epoch, hls_type:as(hls_nums:u32(), Source), #ack_sum{
            kinds = hls_type:as(hls_nums:u8(), 1) bsl Kind, busy = Busy
        }}};
commanded(cast, #sf_done{}, Cell) ->
    {commanded, Cell, fail};
commanded(
    internal,
    {reduction_complete, acknowledgments, Epoch, #ack_sum{kinds = Kinds, busy = Busy}},
    Cell = #barrier{epoch = Epoch}
) ->
    true = Kinds =:= hls_type:as(hls_nums:u8(), 1) bsl Cell#barrier.kind,
    {publishing, Cell#barrier{busy = Busy}, consume}.

-doc "Combines completion kinds and busy flags independently of arrival order.".
-spec reduce(acknowledgments, #ack_sum{}, #ack_sum{}) -> #ack_sum{}.
reduce(acknowledgments, #ack_sum{kinds = A, busy = X}, #ack_sum{kinds = B, busy = Y}) ->
    #ack_sum{kinds = A bor B, busy = X orelse Y}.
-else.
-doc "Collects only the exact terminal epoch and kind authorized by the root command.".
-spec commanded
    (enter, phase(), #barrier{}) -> hls_statem:enter_result(#barrier{});
    (cast, #sf_done{}, #barrier{}) -> hls_statem:cast_result(phase(), #barrier{}).
commanded(enter, _, Cell) ->
    {Cell, []};
commanded(cast, Message = #sf_done{kind = Kind}, Cell = #barrier{kind = Kind}) ->
    Next = collect(Message, Cell),
    case Next#barrier.received =:= Next#barrier.count of
        true -> {publishing, Next, consume};
        false -> {commanded, Next, consume}
    end.

-endif.

-if(?SNOWFLAKE_LOCAL_ADVANCE).
%% A command fixes both terminal tags without relying on local convergence.
-spec arm(#sf_phase{}, #barrier{}) -> #barrier{}.
arm(#sf_phase{epoch = Epoch, kind = Kind}, Cell = #barrier{epoch = Epoch}) ->
    Terminal =
        case Kind of
            0 -> 2;
            3 -> 4;
            _ -> Kind
        end,
    Cell#barrier{
        epoch = hls_serial:add(hls_serial:counter(32), Epoch, Terminal - Kind),
        kind = Terminal
    }.

%% A racing report may match only a legal next global decision; the command later resolves it.
-spec early_completion(#sf_done{}, #barrier{}) -> boolean().
early_completion(#sf_done{source = Source, epoch = Epoch, kind = Kind}, Cell) ->
    true = Source >= Cell#barrier.first andalso Source - Cell#barrier.first < Cell#barrier.count,
    Allowed =
        case Cell#barrier.kind of
            0 ->
                Kind =:= 2 andalso
                    Epoch =:= hls_serial:add(hls_serial:counter(32), Cell#barrier.epoch, 2);
            2 ->
                (Kind =:= 2 andalso Epoch =:= Cell#barrier.epoch) orelse
                    (Kind =:= 4 andalso
                        Epoch =:= hls_serial:add(hls_serial:counter(32), Cell#barrier.epoch, 1));
            4 ->
                (Kind =:= 4 andalso Epoch =:= Cell#barrier.epoch) orelse
                    (Kind =:= 2 andalso
                        Epoch =:= hls_serial:add(hls_serial:counter(32), Cell#barrier.epoch, 2))
        end,
    Allowed.
-endif.

-if(not ?SNOWFLAKE_ACK_REDUCTION orelse not ?SNOWFLAKE_LOCAL_ADVANCE).
%% The first completion fixes this epoch's kind; every later member must agree.
-spec collect(#sf_done{}, #barrier{}) -> #barrier{}.
collect(
    #sf_done{source = Source, epoch = Epoch, kind = Kind, busy = Busy},
    Cell = #barrier{epoch = Epoch}
) ->
    true = Kind < 5,
    true = Cell#barrier.received =:= 0 orelse Kind =:= Cell#barrier.kind,
    Next = acknowledge(Source, Cell),
    Next#barrier{kind = Kind, busy = Next#barrier.busy orelse Busy}.

-endif.

%% Source bounds precede the narrow mask shift; duplicate members never count twice.
-spec acknowledge(hls_nums:u8(), #barrier{}) -> #barrier{}.
acknowledge(Source, Cell) ->
    true = Source >= Cell#barrier.first,
    Offset = Source - Cell#barrier.first,
    true = Offset < Cell#barrier.count,
    Bit = hls_nums:wrap(hls_nums:uN(6), 1) bsl Offset,
    false = Cell#barrier.seen band Bit =/= 0,
    Cell#barrier{seen = Cell#barrier.seen bor Bit, received = Cell#barrier.received + 1}.
