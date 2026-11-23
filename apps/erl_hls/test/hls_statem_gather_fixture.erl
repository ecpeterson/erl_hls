-module(hls_statem_gather_fixture).
-moduledoc "Generic CPU fixture for indexed membership, entry atomicity and private completion.".
-behaviour(hls_statem).
-export([init/1, idle/3, collecting/3, finishing/3, finished/3, observed/3]).
-hls_continuations([finish]).

-doc "Starts with configurable bounded membership and no observable collected values.".
-spec init(map()) -> {ok, hls_statem:phase(), map()}.
init(Options) ->
    Data = maps:merge(#{key => 7, mask => 13, capacity => 4, mode => normal,
        values => hidden, completions => 0, entry_committed => false}, Options),
    {ok, maps:get(initial, Options, idle), Data}.

-doc "Opens on command; earlier indexed traffic remains postponed without invoking a reducer.".
-spec idle(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map());
    (cast, term(), map()) -> hls_statem:cast_result(map()).
idle(enter, _, Data) -> {Data, []};
idle(cast, open, Data) -> {collecting, Data, consume};
idle(cast, {value, Name, Key, Member, Value}, Data) ->
    {idle, Data, {gather, Name, Key, Member, Value}}.

-doc "Captures the mask at entry and exposes only a completed immutable indexed list.".
-spec collecting(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map());
    (cast, term(), map()) -> hls_statem:cast_result(map());
    (internal, hls_statem:gather_complete(), map()) -> hls_statem:internal_result(map()).
collecting(enter, _, Data = #{key := Key, capacity := Capacity, mask := Mask, mode := Mode}) ->
    Open = {open_gather, items, Key, {members_mask, Capacity, Mask}, padding},
    Actions = case Mode of
        invalid_tail -> [Open, {cast, out, leaked}, {cast, missing, rejected}];
        double_gather -> [Open, Open];
        mixed_collection -> [Open, {open_reduction, sum, Key, {count, 1}, {commutative_monoid, 0}}];
        late_open -> [{cast, out, leaked}, Open];
        _ -> [Open]
    end,
    {Data#{entry_committed := true}, Actions};
collecting(cast, {value, Name, Key, Member, Value}, Data) ->
    {collecting, Data, {gather, Name, Key, Member, Value}};
collecting(cast, change_mask, Data) ->
    {collecting, Data#{mask := 0}, consume};
collecting(cast, leave, Data) -> {finished, Data, consume};
collecting(cast, repeat, Data) -> {repeat_phase, Data, consume};
collecting(cast, fail, Data) -> {collecting, Data, fail};
collecting(cast, {mutate, Member}, Data = #{key := Key}) ->
    {collecting, Data#{values := leaked}, {gather, items, Key, Member, mutated}};
collecting(internal, {gather_complete, items, Key, Mask, Values},
        Data = #{key := Key, entry_committed := true, completions := Count, mode := Mode}) ->
    Next = Data#{values := Values, completed_mask => Mask, completions := Count + 1},
    case {Mode, Count} of
        {chain, 0} -> {repeat_phase, Next#{key := Key + 1}, consume};
        {completion_failure, _} -> error(completion_failed);
        {completion_reply, _} -> {finishing, Next, consume, [{reply, 0, unsupported}]};
        _ -> {finishing, Next, consume, [{next_event, internal, finish}]}
    end.

-doc "Publishes completed data on entry before the requested continuation executes.".
-spec finishing(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map());
    (internal, finish, map()) -> hls_statem:internal_result(map()).
finishing(enter, _, Data = #{values := Values}) ->
    {Data, [{cast, out, {entry, Values}}]};
finishing(internal, finish, Data) -> {finished, Data, consume}.

-doc "Publishes the continuation boundary before any queued probe can execute.".
-spec finished(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map());
    (cast, probe, map()) -> hls_statem:cast_result(map()).
finished(enter, _, Data = #{values := Values}) -> {Data, [{cast, out, {finished, Values}}]};
finished(cast, probe, Data) -> {observed, Data, consume}.

-doc "Exposes that the queued probe ran after entry and private continuation.".
-spec observed(enter, hls_statem:phase(), map()) -> hls_statem:enter_result(map()).
observed(enter, _, Data) -> {Data, [{cast, out, probe}]}.
