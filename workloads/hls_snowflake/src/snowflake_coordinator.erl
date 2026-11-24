-module(snowflake_coordinator).
-moduledoc "Advances a bounded Snowflake actor window from committed vertex acknowledgments.".
-behavior(hls_statem).
-compile({parse_transform, hls_pack}).
-export([init/1, configuring/3, ready/3, executing/3, bounds/0]).
-hls_data(controller).
-hls_phases([configuring, ready, executing]).
-hls_outputs([command, report]).
%% Build-time population limits retain the same checks with bounded storage.
-ifndef(SNOWFLAKE_COORDINATOR_SOURCES).
-define(SNOWFLAKE_COORDINATOR_SOURCES, 255).
-endif.
-ifndef(SNOWFLAKE_COORDINATOR_MAILBOX).
-define(SNOWFLAKE_COORDINATOR_MAILBOX, 64).
-endif.
-hls_mailbox_capacity(?SNOWFLAKE_COORDINATOR_MAILBOX).
-include("snowflake_actor_protocol.hrl").
-if(?SNOWFLAKE_ACK_REDUCTION).
-export([reduce/3]).
-endif.

%% One barrier owns each source bit until all configured vertices commit.
-record(controller, {
    count = hls_type:zero() :: hls_nums:u16(),
    height = hls_type:zero() :: hls_nums:u8(),
    members = hls_type:zero() :: hls_nums:uN(?SNOWFLAKE_COORDINATOR_SOURCES),
    terminal_epoch = hls_type:zero() :: hls_nums:u32(),
    received = hls_type:zero() :: hls_nums:u16(),
    seen = hls_type:zero() :: hls_nums:uN(?SNOWFLAKE_COORDINATOR_SOURCES),
    epoch = hls_type:zero() :: hls_nums:u32(),
    kind = hls_type:zero() :: hls_nums:u8(),
    sheet = hls_type:zero() :: hls_nums:u32(),
    mask = hls_type:zero() :: hls_nums:u32(),
    busy = hls_type:zero() :: hls_bool:bool(),
    merge_count = hls_type:zero() :: hls_nums:u16(),
    publish = hls_type:zero() :: hls_bool:bool(),
    report_sheet = hls_type:zero() :: hls_nums:u32(),
    report_epoch = hls_type:zero() :: hls_nums:u32()
}).

%% Finite control separates startup, sheet admission and phase completion.
-type phase() :: configuring | ready | executing.

-doc "Returns the compiled maximum acknowledgment population and mailbox capacity.".
-spec bounds() -> #{sources := pos_integer(), mailbox := pos_integer()}.
bounds() ->
    #{
        sources => ?SNOWFLAKE_COORDINATOR_SOURCES,
        mailbox => ?SNOWFLAKE_COORDINATOR_MAILBOX
    }.

-doc "Starts disconnected from phase execution until every vertex reports its configuration.".
-spec init([]) -> {ok, configuring, #controller{}}.
init([]) -> {ok, configuring, #controller{}}.

-doc "Collects unique startup acknowledgments; offered sheets wait for the configured population.".
-spec configuring
    (enter, term(), #controller{}) -> hls_statem:enter_result(#controller{});
    (cast, #sf_coordinator_config{} | #sf_ready{} | #sf_input{}, #controller{}) ->
        hls_statem:cast_result(phase(), #controller{}).
configuring(enter, _, Cell) ->
    {Cell, []};
configuring(
    cast,
    #sf_coordinator_config{count = Count, height = Height},
    Cell = #controller{count = 0}
) ->
    true = Count > 0 andalso Count =< ?SNOWFLAKE_COORDINATOR_SOURCES andalso Height > 0,
    true = Cell#controller.seen bsr Count =:= 0,
    Next = Cell#controller{
        count = Count,
        height = Height,
        members = hls_nums:wrap(
            hls_nums:uN(?SNOWFLAKE_COORDINATOR_SOURCES),
            (hls_type:as(hls_nums:uN(?SNOWFLAKE_COORDINATOR_SOURCES), 1) bsl Count) - 1
        )
    },
    case Next#controller.received =:= Count of
        true -> {ready, Next#controller{received = 0, seen = 0}, consume};
        false -> {repeat_phase, Next, consume}
    end;
configuring(cast, #sf_ready{source = Source}, Cell) ->
    Next = acknowledge(Source, Cell),
    case Next#controller.count > 0 andalso Next#controller.received =:= Next#controller.count of
        true -> {ready, Next#controller{received = 0, seen = 0}, consume};
        false -> {configuring, Next, consume}
    end;
configuring(cast, #sf_input{}, Cell) ->
    {configuring, Cell, postpone}.

-doc "Publishes completed work and admits the next sequential syndrome sheet.".
-spec ready
    (enter, term(), #controller{}) -> hls_statem:enter_result(#controller{});
    (cast, #sf_input{}, #controller{}) -> hls_statem:cast_result(phase(), #controller{}).
ready(enter, _, Cell) ->
    Actions =
        case Cell#controller.publish of
            true ->
                [
                    {cast, report, #sf_round{
                        sheet = Cell#controller.report_sheet,
                        epoch = Cell#controller.report_epoch
                    }}
                ];
            false ->
                []
        end,
    {Cell#controller{publish = false}, Actions};
ready(cast, #sf_input{sheet = Sheet, mask = Mask}, Cell = #controller{sheet = Sheet}) ->
    {executing,
        arm(Cell#controller{
            kind = 0,
            mask = Mask,
            received = 0,
            seen = 0,
            busy = false,
            merge_count = 0
        }), consume}.

-if(?SNOWFLAKE_ACK_REDUCTION).
-doc "Opens one completion set and broadcasts its command; input sheets wait until the set completes.".
-spec executing
    (enter, term(), #controller{}) -> hls_statem:enter_result(#controller{});
    (cast, #sf_done{} | #sf_input{}, #controller{}) ->
        hls_statem:cast_result(phase(), #controller{});
    (internal, hls_statem:reduction_complete(), #controller{}) ->
        hls_statem:internal_result(phase(), #controller{}).
executing(enter, _, Cell) ->
    {Cell, [
        {open_reduction, acknowledgments, Cell#controller.terminal_epoch,
            {members_mask, ?SNOWFLAKE_COORDINATOR_SOURCES, Cell#controller.members},
            {commutative_monoid, #ack_sum{kinds = 0, busy = false}}},
        {cast, command, #sf_phase{
            epoch = Cell#controller.epoch,
            kind = Cell#controller.kind,
            mask = Cell#controller.mask
        }}
    ]};
executing(cast, #sf_input{}, Cell) ->
    {executing, Cell, postpone};
executing(
    cast,
    #sf_done{source = Source, epoch = Epoch, kind = Kind, busy = Busy},
    Cell = #controller{terminal_epoch = Epoch}
) when Kind < 5 ->
    {executing, Cell,
        {contribute, acknowledgments, Epoch, hls_type:as(hls_nums:u32(), Source), #ack_sum{
            kinds = hls_type:as(hls_nums:u8(), 1) bsl Kind, busy = Busy
        }}};
executing(cast, #sf_done{}, Cell) ->
    {executing, Cell, fail};
executing(
    internal,
    {reduction_complete, acknowledgments, Epoch, #ack_sum{kinds = Kinds, busy = Busy}},
    Cell = #controller{terminal_epoch = Epoch}
) ->
    true = Kinds =:= hls_type:as(hls_nums:u8(), 1) bsl terminal_kind(Cell#controller.kind),
    Next = complete(Cell#controller{busy = Busy}, Epoch, terminal_kind(Cell#controller.kind)),
    case Next#controller.publish of
        true -> {ready, Next, consume};
        false -> {repeat_phase, Next, consume}
    end.

-doc "Combines completion kinds and busy flags independently of arrival order.".
-spec reduce(acknowledgments, #ack_sum{}, #ack_sum{}) -> #ack_sum{}.
reduce(acknowledgments, #ack_sum{kinds = A, busy = X}, #ack_sum{kinds = B, busy = Y}) ->
    #ack_sum{kinds = A bor B, busy = X orelse Y}.
-else.
-doc "Broadcasts one algorithm phase and advances only after all vertex and edge commits.".
-spec executing
    (enter, term(), #controller{}) -> hls_statem:enter_result(#controller{});
    (cast, #sf_done{} | #sf_input{}, #controller{}) ->
        hls_statem:cast_result(phase(), #controller{}).
executing(enter, _, Cell) ->
    {Cell, [
        {cast, command, #sf_phase{
            epoch = Cell#controller.epoch,
            kind = Cell#controller.kind,
            mask = Cell#controller.mask
        }}
    ]};
executing(cast, #sf_input{}, Cell) ->
    {executing, Cell, postpone};
executing(
    cast,
    #sf_done{source = Source, epoch = Epoch, kind = Kind, busy = Busy},
    Cell = #controller{epoch = CurrentEpoch, kind = CurrentKind}
) when
    (Epoch =:= CurrentEpoch andalso Kind =:= CurrentKind) orelse ?SNOWFLAKE_LOCAL_ADVANCE
->
    ExpectedKind = terminal_kind(Cell#controller.kind),
    ExpectedEpoch = hls_serial:add(
        hls_serial:counter(32),
        Cell#controller.epoch,
        ExpectedKind - Cell#controller.kind
    ),
    true = Epoch =:= ExpectedEpoch andalso Kind =:= ExpectedKind,
    Collected = acknowledge(Source, Cell),
    Next = Collected#controller{busy = Collected#controller.busy orelse Busy},
    case Next#controller.received =:= Next#controller.count of
        false ->
            {executing, Next, consume};
        true ->
            Completed = complete(Next, Epoch, Kind),
            case Completed#controller.publish of
                true -> {ready, Completed, consume};
                false -> {repeat_phase, Completed, consume}
            end
    end.

-endif.

%% Decide the successor only after the complete checked set has been combined.
-spec complete(#controller{}, hls_nums:u32(), hls_nums:u8()) -> #controller{}.
complete(Next, Epoch, Kind) ->
    NextEpoch = (Epoch + 1) band 16#ffffffff,
    Again = (Kind =:= 2 orelse Kind =:= 4) andalso Next#controller.busy,
    true = (not Again) orelse Next#controller.merge_count < 9999,
    case Kind =:= 4 andalso (not Next#controller.busy) of
        true ->
            Next#controller{
                received = 0,
                seen = 0,
                busy = false,
                epoch = NextEpoch,
                sheet = (Next#controller.sheet + 1) band 16#ffffffff,
                publish = true,
                report_sheet = Next#controller.sheet,
                report_epoch = Epoch
            };
        false ->
            NextKind =
                case Again of
                    true -> Kind;
                    false -> Kind + 1
                end,
            NextCount =
                case Again of
                    true -> Next#controller.merge_count + 1;
                    false -> 0
                end,
            arm(Next#controller{
                received = 0,
                seen = 0,
                busy = false,
                epoch = NextEpoch,
                kind = NextKind,
                merge_count = NextCount
            })
    end.

%% Early startup acknowledgments have a finite source bound; configuration later validates their population.
-spec acknowledge(hls_nums:u8(), #controller{}) -> #controller{}.
acknowledge(Source, Cell) ->
    Limit =
        case Cell#controller.count of
            0 -> ?SNOWFLAKE_COORDINATOR_SOURCES;
            Count -> Count
        end,
    true = Source < Limit,
    Bit = hls_nums:wrap(hls_nums:uN(?SNOWFLAKE_COORDINATOR_SOURCES), 1) bsl Source,
    false = Cell#controller.seen band Bit =/= 0,
    Cell#controller{
        seen = Cell#controller.seen bor Bit,
        received = Cell#controller.received + 1
    }.

%% An unconditional local chain ends at the next globally decided merge.
-spec terminal_kind(hls_nums:u8()) -> hls_nums:u8().
terminal_kind(Kind) ->
    ?SF_ADVANCE_SELECT(
        case Kind of
            0 -> 2;
            3 -> 4;
            _ -> Kind
        end,
        Kind
    ).

%% Capture the terminal tag before entry opens the keyed reduction.
-spec arm(#controller{}) -> #controller{}.
arm(Cell) ->
    Cell#controller{
        terminal_epoch = hls_serial:add(
            hls_serial:counter(32),
            Cell#controller.epoch,
            terminal_kind(Cell#controller.kind) - Cell#controller.kind
        )
    }.
