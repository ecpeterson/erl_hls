-module(hls_statem_reduction_fixture).

-behavior(hls_statem).

-export([
    init/1,
    idle/3,
    counting/3,
    collecting_members/3,
    chain/3,
    complete/3,
    reported/3,
    reduce/3
]).

init([]) ->
    {ok, idle, data()}.

idle(enter, _OldPhase, Data) ->
    {Data, []};
idle(cast, {begin_count, Key}, Data) ->
    {counting, Data#{key := Key}, consume};
idle(cast, {begin_members, Key}, Data) ->
    {collecting_members, Data#{key := Key}, consume};
idle(cast, {begin_chain, Key}, Data) ->
    {chain, Data#{key := Key}, consume};
idle(cast, {count, Key, Value}, Data) ->
    {idle, Data, {contribute, sum, Key, Value}}.

counting(enter, _OldPhase, Data = #{key := Key}) ->
    {Data, [
        {open_reduction, sum, Key, {count, 2},
            {commutative_monoid, 0}}
    ]};
counting(cast, {count, Key, Value}, Data) ->
    {counting, Data, {contribute, sum, Key, Value}};
counting(cast, same_phase, Data) ->
    {counting, Data#{unrelated := true}, consume};
counting(cast, {mutate_data, Key, Value}, Data) ->
    {counting, Data#{value := Value},
        {contribute, sum, Key, Value}};
counting(cast, {mutate_phase, Key, Value}, Data) ->
    {complete, Data, {contribute, sum, Key, Value}};
counting(cast, repeat, Data) ->
    {repeat_phase, Data, consume};
counting(cast, leave, Data) ->
    {complete, Data, consume};
counting(internal, {reduction_complete, sum, Key, Sum},
        Data = #{key := Key, completions := Completions}) ->
    {complete, Data#{value := Sum, completions := Completions + 1},
        consume}.

collecting_members(enter, _OldPhase, Data = #{key := Key}) ->
    {Data, [
        {open_reduction, sum, Key, {members, [0, 1, 2, 3]},
            {commutative_monoid, 0}}
    ]};
collecting_members(cast, {member, Key, Member, Value}, Data) ->
    {collecting_members, Data,
        {contribute, sum, Key, Member, Value}};
collecting_members(cast, {count, Key, Value}, Data) ->
    {collecting_members, Data, {contribute, sum, Key, Value}};
collecting_members(internal,
        {reduction_complete, sum, Key, Sum},
        Data = #{key := Key, completions := Completions}) ->
    {complete, Data#{value := Sum, completions := Completions + 1},
        consume}.

chain(enter, _OldPhase, Data = #{key := Key}) ->
    {Data, [
        {open_reduction, sum, Key, {count, 2},
            {commutative_monoid, 0}}
    ]};
chain(cast, {count, Key, Value}, Data) ->
    {chain, Data, {contribute, sum, Key, Value}};
chain(internal, {reduction_complete, sum, Key, Sum},
        Data = #{key := Key, completions := 0}) ->
    {repeat_phase,
        Data#{key := Key + 1, prior := Sum, completions := 1},
        consume};
chain(internal, {reduction_complete, sum, Key, Sum},
        Data = #{key := Key, completions := 1}) ->
    {complete, Data#{value := Sum, completions := 2}, consume}.

complete(enter, _OldPhase, Data) ->
    {Data, [{cast, out, observation(1, Data)}]};
complete(cast, probe, Data) ->
    {reported, Data, consume}.

reported(enter, _OldPhase, Data) ->
    {Data, [{cast, out, observation(2, Data)}]}.

reduce(sum, Left, Right) ->
    Left + Right.

data() ->
    #{
        key => 0,
        value => 0,
        prior => 0,
        completions => 0,
        unrelated => false
    }.

observation(Stage, #{
    value := Value,
    prior := Prior,
    completions := Completions
}) ->
    {observation, Stage, Value, Prior, Completions}.
