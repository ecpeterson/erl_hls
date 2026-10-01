-module(hls_statem_reduction_lower_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([counting, collecting_members]).
-hls_outputs([out]).
-hls_mailbox_capacity(4).
-hls_tags([count_value, member_value]).

-export([init/1, counting/3, collecting_members/3, reduce/3]).

-record(count_value, {
    key = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(member_value, {
    key = hls_type:zero() :: hls_nums:u32(),
    member = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    key = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32(),
    entries = hls_type:zero() :: hls_nums:u8()
}).

%% Private reduction data: this deliberately does not appear in hls_tags.
-record(sum, {
    value = hls_type:zero() :: hls_nums:u32(),
    contributions = hls_type:zero() :: hls_nums:u8()
}).

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {ok, hls_statem:phase(), #cell{}}.
init([]) ->
    {ok, counting, #cell{}}.

-doc "Counts accepted contributions before delivering the private completion event.".
-spec counting(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) -> hls_statem:internal_result(#cell{}).
counting(enter, _OldPhase, Cell) ->
    {Cell#cell{entries = Cell#cell.entries + 1}, [
        {open_reduction, sum, Cell#cell.key, {count, 2},
            {commutative_monoid,
                #sum{value = 0, contributions = 0}}}
    ]};
counting(cast, #count_value{key = Key, value = Value}, Cell)
        when Value > 0 ->
    {counting, Cell,
        {contribute, sum, Key,
            #sum{value = Value, contributions = 1}}};
counting(cast, #count_value{}, Cell) ->
    {counting, Cell, consume};
counting(internal,
        {reduction_complete, sum, Key,
            #sum{value = Value, contributions = 2}},
        Cell = #cell{key = Key}) ->
    Result = {collecting_members, Cell#cell{value = Value}, consume},
    Result.

-doc "Accepts the fixed-member reduction's explicitly identified contributions.".
-spec collecting_members(enter, hls_statem:phase(), #cell{}) -> hls_statem:enter_result(#cell{});
    (cast, tuple(), #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) -> hls_statem:internal_result(#cell{}).
collecting_members(enter, _OldPhase, Cell) ->
    {Cell, [
        {open_reduction, sum, Cell#cell.key, {members, [9, 2, 7]},
            {commutative_monoid,
                #sum{value = 0, contributions = 0}}}
    ]};
collecting_members(cast,
        #member_value{key = Key, member = Member, value = Value}, Cell) ->
    {collecting_members, Cell,
        {contribute, sum, Key, Member,
            #sum{value = Value, contributions = 1}}};
collecting_members(internal,
        {reduction_complete, sum, Key,
            #sum{value = Value, contributions = 3}},
        Cell = #cell{key = Key}) ->
    Result = case Value of
        0 -> {counting, Cell#cell{value = 0}, consume};
        _ -> {counting, Cell#cell{value = Value}, consume}
    end,
    Alias = Result,
    Alias.

-doc "Combines fixture contributions using its declared bounded arithmetic.".
-spec reduce(atom(), #sum{}, #sum{}) -> #sum{}.
reduce(sum,
        #sum{value = Left, contributions = LeftCount},
        #sum{value = Right, contributions = RightCount}) ->
    #sum{
        value = Left + Right,
        contributions = LeftCount + RightCount
    }.
