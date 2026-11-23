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

-doc "Returns the fixture's declared initial callback state.".
-spec init([]) -> {'ok','idle',map()}.
init([]) ->
    {ok, idle, data()}.

-doc "Waits for the fixture's command before opening a reduction window.".
-spec idle('cast' | 'enter',term(),term()) -> {term(),[]} | {'chain',map(),'consume'} | {'collecting_members',map(),'consume'} | {'counting',map(),'consume'} | {'idle',term(),{'contribute','sum',term(),term()}}.
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

-doc "Counts accepted contributions before delivering the private completion event.".
-spec counting('cast' | 'enter' | 'internal',term(),term()) -> {map(),[{'open_reduction','sum',term(),{term(),term()},{term(),term()}},...]} | {'complete',term(),'consume' | {'contribute','sum',term(),term()}} | {'counting',term(),'consume' | {'contribute','sum',term(),term()}} | {'repeat_phase',term(),'consume'}.
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

-doc "Accepts the fixed-member reduction's explicitly identified contributions.".
-spec collecting_members('cast' | 'enter' | 'internal',term(),term()) -> {map(),[{'open_reduction','sum',term(),{term(),term()},{term(),term()}},...]} | {'collecting_members',term(),{'contribute','sum',term(),term()} | {'contribute','sum',term(),term(),term()}} | {'complete',map(),'consume'}.
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

-doc "Transitions from one completed reduction into the next fixture phase.".
-spec chain('cast' | 'enter' | 'internal',term(),term()) -> {map(),[{'open_reduction','sum',term(),{term(),term()},{term(),term()}},...]} | {'chain',term(),{'contribute','sum',term(),term()}} | {'complete',map(),'consume'} | {'repeat_phase',map(),'consume'}.
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

-doc "Handles the private reduction completion and commits its result.".
-spec complete('cast' | 'enter',term(),term()) -> {map(),[{'cast','out',{term(),term(),term(),term(),term()}},...]} | {'reported',term(),'consume'}.
complete(enter, _OldPhase, Data) ->
    {Data, [{cast, out, observation(1, Data)}]};
complete(cast, probe, Data) ->
    {reported, Data, consume}.

-doc "Retains the fixture's terminal state after publishing the report.".
-spec reported('enter',term(),map()) -> {map(),[{'cast','out',{term(),term(),term(),term(),term()}},...]}.
reported(enter, _OldPhase, Data) ->
    {Data, [{cast, out, observation(2, Data)}]}.

-doc "Combines fixture contributions using its declared bounded arithmetic.".
-spec reduce('sum',number(),number()) -> number().
reduce(sum, Left, Right) ->
    Left + Right.

%% Returns the fixture's expected initialized application record.
-spec data() -> map().
data() ->
    #{
        key => 0,
        value => 0,
        prior => 0,
        completions => 0,
        unrelated => false
    }.

%% Encodes the reference fields compared with a hardware snapshot.
-spec observation(1 | 2,map()) -> {'observation',1 | 2,term(),term(),term()}.
observation(Stage, #{
    value := Value,
    prior := Prior,
    completions := Completions
}) ->
    {observation, Stage, Value, Prior, Completions}.
