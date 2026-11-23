-module(hls_protocol_mixed_admission).
-moduledoc """
hls_protocol_mixed_stream uses this admission state for actual hls_statem actors. It mediates their input ownership while the stream queue separately manages framed-device credits and retirement.

Single-owner admission into actual hls_statem actors without changing their runtime. The owner is the exclusive input writer, including setup, control and host-host routes. Other processes are trusted not to bypass it; this module does not isolate PIDs.
""".
%% Admission state and actor delivery.
-export([new/2, deliver/3]).
%% Actor failure and incarnation retirement.
-export([down/3, retire/1]).
%% Admission diagnostics.
-export([info/1]).
-export_type([state/0, bindings/0, report/0]).

%% Logical actor indices select exact local PID/capacity bindings.
-type actor() :: non_neg_integer().
%% Runtime capacity is checked at both sides of each admitted cast.
-type binding() :: #{pid := pid(), capacity := 1..((1 bsl 8) - 1)}.
-doc "Exact local actors and source mailbox capacities; new/2 rejects duplicate PIDs and installs owner-held lifetime monitors.".
-type bindings() :: #{actor() => binding()}.

%% Monitor ownership and admission accounting stay local to the creating process.
-record(state, {
    owner :: pid(),
    live = true :: boolean(),
    actors = #{} :: bindings(),
    monitors = #{} :: #{reference() => actor()},
    timeout :: pos_integer(),
    admitted = 0 :: non_neg_integer()
}).
-doc "Private single-writer admission state. Only the creating process may deliver, process monitor notifications or retire; retain the newest returned value.".
-opaque state() :: #state{}.
-doc "Payload-free lifecycle, bound actor count and confirmed admission count.".
-type report() :: #{live := boolean(), actors := non_neg_integer(), admitted := non_neg_integer()}.

-doc "Binds exact local PIDs and source capacities, installing lifetime monitors. Caller serializes all actor input through deliver/3 and processes monitor notifications. Actors may initially be disconnected for setup. Timeout bounds each public runtime barrier; finite callback work and same-sender order are required. No hardware session is activated.".
-spec new(bindings(), pos_integer()) -> state().
new(Bindings, Timeout) when map_size(Bindings) > 0, Timeout > 0 ->
    Pids = [Pid || #{pid := Pid} <- maps:values(Bindings)],
    true = length(Pids) =:= map_size(Bindings),
    true = length(Pids) =:= length(lists:usort(Pids)),
    true = lists:all(fun(Pid) -> is_pid(Pid) andalso node(Pid) =:= node() end, Pids),
    true = lists:all(
        fun(#{capacity := Capacity}) ->
            is_integer(Capacity) andalso Capacity > 0 andalso Capacity =< 255
        end,
        maps:values(Bindings)
    ),
    Monitors = maps:from_list([
        {monitor(process, Pid), I}
     || {I, #{pid := Pid}} <- maps:to_list(Bindings)
    ]),
    State = #state{owner = self(), actors = Bindings, monitors = Monitors, timeout = Timeout},
    try
        maps:foreach(fun(_, Actor) -> available(Actor, Timeout) end, Bindings),
        State
    catch
        Class:Reason:Stack ->
            retire(State),
            erlang:raise(Class, Reason, Stack)
    end.

-doc "Admits a record or returns busy without sending when the actor mailbox is full. A same-owner runtime barrier follows the cast; only ok permits a delivery ACK and means admission, not consumption. Timeout/death after sending is ambiguous and retires the state permanently; never replay. Exclusive writer and finite runtime work are composition assumptions.".
-spec deliver(actor(), tuple(), state()) ->
    {ok, state()} | {busy, state()} | {error, term(), state()}.
deliver(
    Id, Message, State = #state{owner = Owner, live = true, actors = Actors, timeout = Timeout}
) when
    Owner =:= self()
->
    try
        Actor = maps:get(Id, Actors),
        case available(Actor, Timeout) of
            0 -> {busy, State};
            Free when Free > 0 -> admit(Actor, Message, State)
        end
    catch
        Class:Reason ->
            {error, {admission_failed, Class, Reason}, retire(State)}
    end.

%% Read capacity through the public runtime barrier; no private record layout is inspected.
-spec available(binding(), pos_integer()) -> non_neg_integer().
available(#{pid := Pid, capacity := Capacity}, Timeout) ->
    #{
        mailbox := #{
            capacity := Capacity,
            occupied := Occupied,
            available := Available,
            committed := Occupied,
            reserved := 0
        }
    } = hls_statem:info(Pid, Timeout),
    true = Occupied >= 0 andalso Available >= 0 andalso Occupied + Available =:= Capacity,
    Available.

%% The post-cast barrier makes admission definite before accounting or a delivery ACK can advance.
-spec admit(binding(), tuple(), state()) -> {ok, state()}.
admit(Actor = #{pid := Pid}, Message, State = #state{timeout = Timeout, admitted = Count}) ->
    ok = hls_statem:cast(Pid, Message),
    _ = available(Actor, Timeout),
    {ok, State#state{admitted = Count + 1}}.

-doc "Retires every binding on a known actor monitor notification and ignores unrelated monitors. The transport owner also retires on broker/connection death and stops acknowledging hardware packets.".
-spec down(reference(), term(), state()) -> {unrelated, state()} | {error, term(), state()}.
down(Ref, Reason, State = #state{owner = Owner, live = true, monitors = Monitors}) when
    Owner =:= self()
->
    case maps:find(Ref, Monitors) of
        error -> {unrelated, State};
        {ok, Id} -> {error, {actor_down, Id, Reason}, retire(State)}
    end.

-doc "Permanently releases monitors and actor bindings without stopping actors or undoing admitted/ambiguous casts. Caller cancels transport ownership separately; a retired state cannot admit another record.".
-spec retire(state()) -> state().
retire(State = #state{owner = Owner, monitors = Monitors}) when Owner =:= self() ->
    maps:foreach(fun(Ref, _) -> demonitor(Ref, [flush]) end, Monitors),
    State#state{live = false, actors = #{}, monitors = #{}}.

-doc "Reports lifecycle, actor count and completed admissions, excluding payloads, PID bindings and monitor references.".
-spec info(state()) -> report().
info(#state{live = Live, actors = Actors, admitted = Count}) ->
    #{live => Live, actors => map_size(Actors), admitted => Count}.
