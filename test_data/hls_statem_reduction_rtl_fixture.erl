%%%% hls_statem_reduction_rtl_fixture
%%%%
%%%% Small generated-RTL witness for actor-local count and member reductions.

-module(hls_statem_reduction_rtl_fixture).

-hls_data(cell).
-hls_phases([counting, collecting_members, done]).
-hls_outputs([out]).
-hls_mailbox_capacity(4).
-hls_tags([count_value, member_value, observation, escape]).

-record(count_value, {
    key = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(member_value, {
    key = hls_type:zero() :: hls_nums:u32(),
    member = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(observation, {
    stage = hls_type:zero() :: hls_nums:u32(),
    count_total = hls_type:zero() :: hls_nums:u32(),
    member_total = hls_type:zero() :: hls_nums:u32()
}).

-record(escape, {}).

-record(cell, {
    key = hls_type:zero() :: hls_nums:u32(),
    count_total = hls_type:zero() :: hls_nums:u32(),
    member_total = hls_type:zero() :: hls_nums:u32(),
    entries = hls_type:zero() :: hls_nums:u32()
}).

%% Private accumulator state; this record deliberately has no wire tag.
-record(sum, {
    value = hls_type:zero() :: hls_nums:u32(),
    contributions = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    {ok, counting, #cell{key = 17}}.

counting(enter, _OldPhase, Cell) ->
    {Cell#cell{entries = Cell#cell.entries + 1}, [
        {open_reduction, sum, Cell#cell.key, {count, 2},
            {commutative_monoid,
                #sum{value = 0, contributions = 0}}}
    ]};
counting(cast, #count_value{key = Key, value = Value}, Cell) ->
    {counting, Cell,
        {contribute, sum, Key,
            #sum{value = Value, contributions = 1}}};
counting(cast, #escape{}, Cell) ->
    %% A focused RTL negative test uses this otherwise ordinary transition to
    %% prove that a partial reduction cannot be abandoned at a phase boundary.
    {done, Cell, consume};
counting(internal,
        {reduction_complete, sum, Key,
            #sum{value = 99, contributions = 2}},
        Cell = #cell{key = Key}) ->
    %% The magic test total asks for a second epoch in the same phase.  A value
    %% for Key + 1 can arrive early, be postponed, and then contribute after
    %% repeat_phase opens this next reduction.
    {repeat_phase, Cell#cell{key = Key + 1}, consume};
counting(internal,
        {reduction_complete, sum, Key,
            #sum{value = Total, contributions = 2}},
        Cell = #cell{key = Key}) ->
    {collecting_members, Cell#cell{count_total = Total}, consume}.

collecting_members(enter, _OldPhase, Cell) ->
    {Cell#cell{entries = Cell#cell.entries + 1}, [
        {open_reduction, sum, Cell#cell.key, {members, [9, 2, 7]},
            {commutative_monoid,
                #sum{value = 0, contributions = 0}}},
        {cast, out, #observation{
            stage = (Cell#cell.entries + 1) * 10 + 1,
            count_total = Cell#cell.count_total,
            member_total = 0
        }}
    ]};
collecting_members(cast,
        #member_value{key = Key, member = Member, value = Value}, Cell) ->
    {collecting_members, Cell,
        {contribute, sum, Key, Member,
            #sum{value = Value, contributions = 1}}};
collecting_members(internal,
        {reduction_complete, sum, Key,
            #sum{value = Total, contributions = 3}},
        Cell = #cell{key = Key}) ->
    {done, Cell#cell{member_total = Total}, consume}.

done(enter, _OldPhase, Cell) ->
    {Cell, [{cast, out, #observation{
        stage = Cell#cell.entries * 10 + 2,
        count_total = Cell#cell.count_total,
        member_total = Cell#cell.member_total
    }}]}.

reduce(sum,
        #sum{value = Left, contributions = LeftCount},
        #sum{value = Right, contributions = RightCount}) ->
    #sum{
        value = Left + Right,
        contributions = LeftCount + RightCount
    }.
