-module(hls_statem_reduction_fixture).

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-hls_data(cell).
-hls_phases([
    idle,
    counting,
    collecting_members,
    chain_first,
    complete,
    reported,
    escaped
]).
-hls_outputs([out]).
-hls_mailbox_capacity(8).
-hls_tags([
    begin_count,
    begin_members,
    begin_chain,
    count_value,
    member_value,
    probe,
    escape,
    mutating_value,
    phase_mutating_value,
    observation
]).

-export([
    init/1,
    idle/3,
    counting/3,
    collecting_members/3,
    chain_first/3,
    complete/3,
    reported/3,
    escaped/3,
    reduce/3
]).

-export([
    start_link/1,
    start_link_disconnected/1,
    connect/2,
    begin_count/2,
    begin_members/2,
    begin_chain/2,
    count_value/3,
    member_value/4,
    probe/1,
    escape/1,
    repeat_phase/1,
    mutating_value/3,
    phase_mutating_value/3
]).

-record(begin_count, {
    key = hls_type:zero() :: hls_nums:u32()
}).

-record(begin_members, {
    key = hls_type:zero() :: hls_nums:u32()
}).

-record(begin_chain, {
    key = hls_type:zero() :: hls_nums:u32()
}).

-record(count_value, {
    key = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(member_value, {
    key = hls_type:zero() :: hls_nums:u32(),
    member = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(probe, {
    nonce = hls_type:zero() :: hls_nums:u32()
}).

-record(escape, {
    nonce = hls_type:zero() :: hls_nums:u32()
}).

-record(mutating_value, {
    key = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(phase_mutating_value, {
    key = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32()
}).

-record(observation, {
    stage = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32(),
    prior = hls_type:zero() :: hls_nums:u32(),
    completions = hls_type:zero() :: hls_nums:u32()
}).

-record(cell, {
    key = hls_type:zero() :: hls_nums:u32(),
    value = hls_type:zero() :: hls_nums:u32(),
    prior = hls_type:zero() :: hls_nums:u32(),
    completions = hls_type:zero() :: hls_nums:u32()
}).

start_link(Output) ->
    hls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, 8}, {outputs, #{out => Output}}]
    ).

start_link_disconnected(Capacity) ->
    hls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, Capacity}]
    ).

connect(PID, Output) ->
    hls_statem:connect(PID, #{out => Output}).

begin_count(PID, Key) ->
    hls_statem:cast(PID, #begin_count{key = Key}).

begin_members(PID, Key) ->
    hls_statem:cast(PID, #begin_members{key = Key}).

begin_chain(PID, Key) ->
    hls_statem:cast(PID, #begin_chain{key = Key}).

count_value(PID, Key, Value) ->
    hls_statem:cast(PID, #count_value{key = Key, value = Value}).

member_value(PID, Key, Member, Value) ->
    hls_statem:cast(PID, #member_value{
        key = Key,
        member = Member,
        value = Value
    }).

probe(PID) ->
    hls_statem:cast(PID, #probe{}).

escape(PID) ->
    hls_statem:cast(PID, #escape{}).

repeat_phase(PID) ->
    hls_statem:cast(PID, #escape{nonce = 1}).

mutating_value(PID, Key, Value) ->
    hls_statem:cast(PID, #mutating_value{key = Key, value = Value}).

phase_mutating_value(PID, Key, Value) ->
    hls_statem:cast(PID, #phase_mutating_value{
        key = Key,
        value = Value
    }).

init([]) ->
    {ok, idle, #cell{}}.

-spec idle(enter, hls_statem:phase(), #cell{}) ->
    hls_statem:enter_result(#cell{});
    (cast,
        #begin_count{} | #begin_members{} | #begin_chain{} | #count_value{},
        #cell{}) ->
        hls_statem:cast_result(#cell{}).
idle(enter, _OldPhase, Cell) ->
    {Cell, []};
idle(cast, #begin_count{key = Key}, Cell) ->
    {counting, Cell#cell{key = Key}, consume};
idle(cast, #begin_members{key = Key}, Cell) ->
    {collecting_members, Cell#cell{key = Key}, consume};
idle(cast, #begin_chain{key = Key}, Cell) ->
    {chain_first, Cell#cell{key = Key}, consume};
idle(cast, #count_value{key = Key, value = Value}, Cell) ->
    {idle, Cell, {contribute, sum, Key, Value}}.

-spec counting(enter, hls_statem:phase(), #cell{}) ->
    hls_statem:enter_result(#cell{});
    (cast,
        #count_value{} |
        #escape{} |
        #mutating_value{} |
        #phase_mutating_value{},
        #cell{}) ->
        hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(#cell{}).
counting(enter, _OldPhase, Cell = #cell{key = Key}) ->
    {Cell, [
        {open_reduction, sum, Key, {count, 2},
            {commutative_monoid, 0}}
    ]};
counting(cast, #count_value{key = Key, value = Value}, Cell) ->
    {counting, Cell, {contribute, sum, Key, Value}};
counting(cast, #mutating_value{key = Key, value = Value}, Cell) ->
    %% Contribution admission is an actor-runtime effect.  A callback cannot
    %% couple it to an application phase or data mutation.
    {counting, Cell#cell{value = Value},
        {contribute, sum, Key, Value}};
counting(cast, #phase_mutating_value{key = Key, value = Value}, Cell) ->
    {escaped, Cell, {contribute, sum, Key, Value}};
counting(cast, #escape{nonce = 1}, Cell) ->
    {repeat_phase, Cell, consume};
counting(cast, #escape{}, Cell) ->
    {escaped, Cell, consume};
counting(internal, {reduction_complete, sum, Key, Sum},
        Cell = #cell{key = Key, completions = Completions}) ->
    {complete, Cell#cell{
        value = Sum,
        completions = Completions + 1
    }, consume}.

-spec collecting_members(enter, hls_statem:phase(), #cell{}) ->
    hls_statem:enter_result(#cell{});
    (cast, #member_value{} | #escape{}, #cell{}) ->
        hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(#cell{}).
collecting_members(enter, _OldPhase, Cell = #cell{key = Key}) ->
    {Cell, [
        {open_reduction, sum, Key, {members, [0, 1, 2, 3]},
            {commutative_monoid, 0}}
    ]};
collecting_members(cast,
        #member_value{key = Key, member = Member, value = Value}, Cell) ->
    {collecting_members, Cell,
        {contribute, sum, Key, Member, Value}};
collecting_members(cast, #escape{}, Cell) ->
    {escaped, Cell, consume};
collecting_members(internal, {reduction_complete, sum, Key, Sum},
        Cell = #cell{key = Key, completions = Completions}) ->
    {complete, Cell#cell{
        value = Sum,
        completions = Completions + 1
    }, consume}.

-spec chain_first(enter, hls_statem:phase(), #cell{}) ->
    hls_statem:enter_result(#cell{});
    (cast, #count_value{}, #cell{}) -> hls_statem:cast_result(#cell{});
    (internal, hls_statem:reduction_complete(), #cell{}) ->
        hls_statem:internal_result(#cell{}).
chain_first(enter, _OldPhase, Cell = #cell{key = Key}) ->
    {Cell, [
        {open_reduction, sum, Key, {count, 2},
            {commutative_monoid, 0}}
    ]};
chain_first(cast, #count_value{key = Key, value = Value}, Cell) ->
    {chain_first, Cell, {contribute, sum, Key, Value}};
chain_first(internal, {reduction_complete, sum, Key, Sum},
        Cell = #cell{key = Key, completions = 0}) ->
    {repeat_phase, Cell#cell{
        key = Key + 1,
        prior = Sum,
        completions = 1
    }, consume};
chain_first(internal, {reduction_complete, sum, Key, Sum},
        Cell = #cell{key = Key, completions = 1}) ->
    {complete, Cell#cell{
        value = Sum,
        completions = 2
    }, consume}.

-spec complete(enter, hls_statem:phase(), #cell{}) ->
    hls_statem:enter_result(#cell{});
    (cast, #probe{}, #cell{}) -> hls_statem:cast_result(#cell{}).
complete(enter, _OldPhase, Cell = #cell{
    value = Value,
    prior = Prior,
    completions = Completions
}) ->
    {Cell, [{cast, out, #observation{
        stage = 1,
        value = Value,
        prior = Prior,
        completions = Completions
    }}]};
complete(cast, #probe{}, Cell) ->
    {reported, Cell, consume}.

-spec reported(enter, hls_statem:phase(), #cell{}) ->
    hls_statem:enter_result(#cell{}).
reported(enter, _OldPhase, Cell = #cell{
    value = Value,
    prior = Prior,
    completions = Completions
}) ->
    {Cell, [{cast, out, #observation{
        stage = 2,
        value = Value,
        prior = Prior,
        completions = Completions
    }}]}.

-spec escaped(enter, hls_statem:phase(), #cell{}) ->
    hls_statem:enter_result(#cell{}).
escaped(enter, _OldPhase, Cell) ->
    {Cell, []}.

-spec reduce(sum, hls_nums:u32(), hls_nums:u32()) -> hls_nums:u32().
reduce(sum, Left, Right) ->
    Left + Right.
