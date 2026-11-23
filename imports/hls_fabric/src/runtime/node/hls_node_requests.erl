-module(hls_node_requests).
-moduledoc "Request ownership shared by the node's legacy wire channels and managed actor endpoints. Waiting admission consumes connection credit; admitted calls retain completion ownership bounded per target for managed endpoints and per channel for legacy wire actors. This value owns no process, device or retry policy.".

%% Connection-owned request lifecycle and inspection.
-export([
    new/0,
    enqueue/4,
    head/2,
    submit/2,
    admit/2,
    retry/2,
    finish/2,
    remove_target/2,
    find/2,
    groups/1,
    waiting/1, waiting/2,
    waiting_target/2,
    calls/2,
    pending/2
]).
-export_type([state/0, group/0, operation/0, entry/0]).

-doc "One managed actor or one legacy application/debug channel; independent groups may admit concurrently.".
-type group() :: {domain, pid()} | {application | debug, hls_nums:u16()}.
-doc "Calls and acknowledged casts retain their distribution reply address; ordinary casts use none.".
-type operation() :: {call | cast, gen_server:from() | none, term()}.
-doc "One immutable caller/target binding plus its admission phase.".
-type entry() :: #{
    target := pid(),
    group := group(),
    operation := operation(),
    phase := queued | submitting | admitted
}.
%% Queues retain their head until admission, allowing safe non-send retries without reordering.
-record(requests, {
    entries = #{} :: #{reference() => entry()},
    queues = #{} :: #{group() => queue:queue(reference())},
    active = #{} :: #{group() => reference()},
    waiting = 0 :: non_neg_integer(),
    calls = #{} :: #{pid() => non_neg_integer()}
}).
-doc "Bounded by connection admission and the adapter's per-target or per-channel completion limits.".
-opaque state() :: #requests{}.

-doc "Creates empty ownership; callers set admission bounds before enqueueing.".
-spec new() -> state().
new() -> #requests{}.

-doc "Appends one operation in its group's order and allocates a fresh local token.".
-spec enqueue(group(), pid(), operation(), state()) -> {reference(), state()}.
enqueue(
    Group,
    Target,
    Operation = {Mode, _, _},
    State = #requests{entries = Entries, queues = Queues, waiting = Waiting, calls = Calls}
) ->
    Token = make_ref(),
    Entry = #{target => Target, group => Group, operation => Operation, phase => queued},
    Queue = queue:in(Token, maps:get(Group, Queues, queue:new())),
    Counts =
        case Mode of
            call -> Calls#{Target => maps:get(Target, Calls, 0) + 1};
            cast -> Calls
        end,
    {Token, State#requests{
        entries = Entries#{Token => Entry},
        queues = Queues#{Group => Queue},
        waiting = Waiting + 1,
        calls = Counts
    }}.

-doc "Returns an eligible head; an in-flight admission or capacity wait excludes later operations in that group.".
-spec head(group(), state()) -> none | {reference(), entry()}.
head(Group, #requests{active = Active}) when is_map_key(Group, Active) -> none;
head(Group, #requests{queues = Queues, entries = Entries}) ->
    case queue:peek(maps:get(Group, Queues, queue:new())) of
        empty -> none;
        {value, Token} -> {Token, maps:get(Token, Entries)}
    end.

-doc "Marks the queue head as the group's sole admission attempt; this does not release connection credit.".
-spec submit(reference(), state()) -> state().
submit(Token, State = #requests{entries = Entries, active = Active}) ->
    Entry = #{group := Group, phase := queued} = maps:get(Token, Entries),
    {Token, Entry} = head(Group, State),
    State#requests{
        entries = Entries#{Token := Entry#{phase := submitting}}, active = Active#{Group => Token}
    }.

-doc "Releases admission credit once. A call remains owned until its final result or target retirement.".
-spec admit(reference(), state()) -> state().
admit(Token, State = #requests{entries = Entries, waiting = Waiting}) ->
    case maps:find(Token, Entries) of
        {ok, Entry = #{phase := submitting}} ->
            Next = dequeue(Token, Entry, State),
            Next#requests{
                entries = Entries#{Token := Entry#{phase := admitted}}, waiting = Waiting - 1
            };
        _ ->
            State
    end.

-doc "Makes an explicitly non-admitted head eligible after capacity notification; never use for uncertain or accepted work.".
-spec retry(reference(), state()) -> state().
retry(Token, State = #requests{entries = Entries, active = Active}) ->
    case maps:find(Token, Entries) of
        {ok, Entry = #{phase := submitting, group := Group}} ->
            State#requests{
                entries = Entries#{Token := Entry#{phase := queued}},
                active = maps:remove(Group, Active)
            };
        _ ->
            State
    end.

-doc "Retires one local observer after a final result, proven non-admission or target retirement; duplicate completions are ignored.".
-spec finish(reference(), state()) -> {none | entry(), state()}.
finish(Token, State = #requests{entries = Entries, waiting = Waiting, calls = Calls}) ->
    case maps:take(Token, Entries) of
        error ->
            {none, State};
        {Entry = #{target := Target, operation := {Mode, _, _}, phase := Phase}, Rest} ->
            Next =
                case Phase of
                    admitted -> State;
                    _ -> dequeue(Token, Entry, State)
                end,
            Remaining =
                Waiting -
                    case Phase of
                        admitted -> 0;
                        _ -> 1
                    end,
            Counts =
                case Mode of
                    cast ->
                        Calls;
                    call ->
                        case maps:get(Target, Calls) of
                            1 -> maps:remove(Target, Calls);
                            N -> Calls#{Target := N - 1}
                        end
                end,
            {Entry, Next#requests{entries = Rest, waiting = Remaining, calls = Counts}}
    end.

-doc "Drops a retired target's local observers and unsent queue entries without asserting cancellation of device work.".
-spec remove_target(pid(), state()) -> state().
remove_target(Target, State = #requests{entries = Entries}) ->
    lists:foldl(
        fun(Token, Acc) ->
            {_, Next} = finish(Token, Acc),
            Next
        end,
        State,
        [Token || {Token, #{target := T}} <- maps:to_list(Entries), T =:= Target]
    ).

-doc "Looks up only current local ownership; a missing token cannot regain capacity or deliver a reply.".
-spec find(reference(), state()) -> {ok, entry()} | error.
find(Token, #requests{entries = Entries}) -> maps:find(Token, Entries).

-doc "Enumerates groups with waiting work; one pump round may attempt each independently.".
-spec groups(state()) -> [group()].
groups(#requests{queues = Queues}) -> maps:keys(Queues).

-doc "Counts queued and in-flight admission work, excluding admitted unfinished calls.".
-spec waiting(state()) -> non_neg_integer().
waiting(#requests{waiting = Waiting}) -> Waiting.

-doc "Counts one group's queued and in-flight admissions.".
-spec waiting(group(), state()) -> non_neg_integer().
waiting(Group, #requests{queues = Queues}) -> queue:len(maps:get(Group, Queues, queue:new())).

-doc "Counts one target's queued and in-flight admissions, including shared legacy channels.".
-spec waiting_target(pid(), state()) -> non_neg_integer().
waiting_target(Target, #requests{entries = Entries}) ->
    length([
        ok
     || #{target := T, phase := Phase} <- maps:values(Entries),
        T =:= Target,
        Phase =/= admitted
    ]).

-doc "Counts calls to one target across admission and completion phases.".
-spec calls(pid(), state()) -> non_neg_integer().
calls(Target, #requests{calls = Calls}) -> maps:get(Target, Calls, 0).

-doc "Counts current observers for one adapter class, including admitted unfinished calls.".
-spec pending(domain | application | debug, state()) -> non_neg_integer().
pending(Kind, #requests{entries = Entries}) ->
    length([ok || #{group := {K, _}} <- maps:values(Entries), K =:= Kind]).

%% Removal also supports retiring one target from an interleaved legacy channel queue.
-spec dequeue(reference(), entry(), state()) -> state().
dequeue(Token, #{group := Group}, State = #requests{queues = Queues, active = Active}) ->
    Queue = queue:from_list([
        T
     || T <- queue:to_list(maps:get(Group, Queues, queue:new())), T =/= Token
    ]),
    NextQueues =
        case queue:is_empty(Queue) of
            true -> maps:remove(Group, Queues);
            false -> Queues#{Group := Queue}
        end,
    NextActive =
        case maps:find(Group, Active) of
            {ok, Token} -> maps:remove(Group, Active);
            _ -> Active
        end,
    State#requests{queues = NextQueues, active = NextActive}.
