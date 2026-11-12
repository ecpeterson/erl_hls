-module(hls_supervisor_lifecycle).
-moduledoc """
Finite one-for-one supervision shared by native execution and compiled control.

A checked static declaration supplies reset-safe children, their immutable
permanent/temporary policy and dormant-template flag, intensity
0..16 and a positive period in seconds. The composer selects one child per edge,
keeps this state outside every child's reset region, and supplies ordered child
lifecycle observations plus a local monotonic seconds clock. Commands connect
through that child's sole ordered lifecycle lane. Repeated phase observations
may lag commands; an emitted startup is never cancelled from an unbound snapshot.
Initial children start in declaration order. Initial failure retires the subtree;
failed restart attempts consume the same sliding-window budget as later faults.
Independent replacements may initialize concurrently; unlike synchronous OTP child
startup, waiting for one completion need not defer another child's failure handling.
Temporary children are never restarted. Initially absent temporary templates skip
startup; ordinary declared temporary children start normally. Explicit admission
requires a vacant slot, its exact last incarnation and a reusable observation from
the transport boundary. A slot becomes vacant only after core retirement and that
observation; its last incarnation remains as a stale-command tombstone. No callback
normal-exit directive is introduced: completed work may be explicitly stopped.
An abort before reset can retain an unresolved old/current and new/target pair;
that uncertainty cannot release the slot or substitute for a confirmed fence.

A start installs a non-reused supervisor incarnation and a durably reserved finite
identity interval. Repetition cannot rewind it. Resetting this allocator requires
a fresh grant from surviving authority; forgetting all state cannot detect an old
grant. No application history, replay, physical reset or delivery-frontier guarantee
is supplied here. Host transport loss is not an input and does not stop recovery.
""".
-behaviour(hls_gs).
-hls_data(supervisor_service).
-hls_tags([supervisor_input, supervisor_output, unsupported_cast]).
-hls_replies([{supervisor_input, [supervisor_output]}]).
-include_lib("hls_runtime/include/hls_supervisor_lifecycle.hrl").

%% Native and compiled policy interface.
-export([new/0, step/2]).
-export_type([state/0, child/0, child_phase/0, status/0, input/0, output/0]).
%% Optional compiler service callbacks.
-export([init/1, handle_call/2, handle_cast/2]).

%% The compiler service retains only shared manager state; the composer owns child slots.
-record(supervisor_service, {supervisor = #supervisor_state{} :: #supervisor_state{}}).
%% Cast invocation is unsupported by this management-only service.
-record(unsupported_cast, {unused = 0 :: hls_nums:u32()}).

-doc "Shared bounded restart window, immutable identity grant and subtree shutdown state.".
-type state() :: #supervisor_state{}.
-doc "One child's current startup/replacement/retirement ownership outside its reset region.".
-type child() :: #supervisor_child{}.
-doc "The selected slot's startup, occupancy or retirement phase; vacant preserves its last incarnation.".
-type child_phase() :: supervisor_child_phase().
-doc "Immediate control disposition; accepted does not imply asynchronous startup or retirement completed.".
-type status() :: supervisor_status().
-doc "An explicit control request and one current child observation; time is monotonic seconds.".
-type input() :: #supervisor_input{}.
-doc "Updated shared/selected-child state and at most one synchronous lifecycle command.".
-type output() :: #supervisor_output{}.

-doc "Returns an unbound supervisor which issues no child commands until a valid grant starts it.".
-spec new() -> #supervisor_state{}.
new() -> #supervisor_state{}.

-doc "Applies control or advances one selected child. Callers preserve slot identity, provide ordered observations from exclusively controlled children, and preserve command order. A backwards/exhausted clock fails closed; no timeout stands in for retirement. A supplied timestamp at the restart-window boundary remains inside the window, matching OTP's inclusive period.".
-spec step(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
step(Input, State) ->
    case Input#supervisor_input.op of
        start -> start(Input, State);
        stop -> stop(Input, State);
        start_child -> child_request(Input, State);
        stop_child -> child_request(Input, State);
        inspect -> advance(Input, State);
        reject -> result(invalid, State, Input#supervisor_input.child)
    end.

%% Exact repetitions preserve both spent IDs and restart timestamps.
-spec start(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
start(Input, State) ->
    case State#supervisor_state.phase of
        unbound ->
            install(Input, State);
        _ ->
            Same =
                Input#supervisor_input.epoch =:= State#supervisor_state.epoch andalso
                    Input#supervisor_input.first =:= State#supervisor_state.first andalso
                    Input#supervisor_input.last =:= State#supervisor_state.last andalso
                    Input#supervisor_input.children =:= State#supervisor_state.children andalso
                    Input#supervisor_input.intensity =:= State#supervisor_state.intensity andalso
                    Input#supervisor_input.period =:= State#supervisor_state.period,
            result(
                case Same of
                    true -> replay;
                    false -> stale
                end,
                State,
                Input#supervisor_input.child
            )
    end.

%% The highest u64 value is reserved as the exhausted allocator sentinel.
-spec install(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
install(Input, State) ->
    Valid =
        Input#supervisor_input.epoch =/= 0 andalso
            Input#supervisor_input.first =/= 0 andalso
            Input#supervisor_input.last >= Input#supervisor_input.first andalso
            Input#supervisor_input.last < ((1 bsl 64) - 1) andalso
            Input#supervisor_input.children > 0 andalso
            Input#supervisor_input.intensity =< 16 andalso
            Input#supervisor_input.period > 0 andalso
            Input#supervisor_input.now < ((1 bsl 64) - 1),
    case Valid of
        false ->
            result(invalid, State, Input#supervisor_input.child);
        true ->
            result(
                accepted,
                State#supervisor_state{
                    phase = starting,
                    epoch = Input#supervisor_input.epoch,
                    first = Input#supervisor_input.first,
                    last = Input#supervisor_input.last,
                    next = Input#supervisor_input.first,
                    children = Input#supervisor_input.children,
                    intensity = Input#supervisor_input.intensity,
                    period = Input#supervisor_input.period,
                    last_time = Input#supervisor_input.now
                },
                Input#supervisor_input.child
            )
    end.

%% A stop changes policy immediately; later observations establish actual child retirement.
-spec stop(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
stop(Input, State) ->
    case
        Input#supervisor_input.epoch =:= State#supervisor_state.epoch andalso
            State#supervisor_state.epoch =/= 0
    of
        false ->
            result(stale, State, Input#supervisor_input.child);
        true ->
            case State#supervisor_state.phase of
                starting ->
                    result(accepted, closing(requested, State), Input#supervisor_input.child);
                running ->
                    result(accepted, closing(requested, State), Input#supervisor_input.child);
                _ ->
                    result(replay, State, Input#supervisor_input.child)
            end
    end.

%% Child admission is optional work: capacity or grant exhaustion leaves siblings running.
-spec child_request(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
child_request(Input, State) ->
    Child = Input#supervisor_input.child,
    Exact =
        State#supervisor_state.epoch =/= 0 andalso
            Input#supervisor_input.epoch =:= State#supervisor_state.epoch,
    case Exact of
        false ->
            result(stale, State, Child);
        true ->
            Valid =
                Input#supervisor_input.slot < State#supervisor_state.children andalso
                    Input#supervisor_input.policy =:= temporary,
            case Valid of
                false ->
                    result(invalid, State, Child);
                true ->
                    case State#supervisor_state.phase of
                        running -> timed_child_request(Input, State);
                        _ -> result(busy, State, Child)
                    end
            end
    end.

%% Explicit child controls obey the same monotonic clock as autonomous policy progress.
-spec timed_child_request(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
timed_child_request(Input, State) ->
    Child = Input#supervisor_input.child,
    ClockValid =
        Input#supervisor_input.now >= State#supervisor_state.last_time andalso
            Input#supervisor_input.now < ((1 bsl 64) - 1),
    case ClockValid of
        false ->
            (retire(Input, closing(clock_failure, State)))#supervisor_output{status = invalid};
        true ->
            Next = State#supervisor_state{last_time = Input#supervisor_input.now},
            OccupiedStart =
                Input#supervisor_input.op =:= start_child andalso
                    Child#supervisor_child.phase =/= vacant,
            case OccupiedStart of
                true ->
                    result(busy, Next, Child);
                false ->
                    case Input#supervisor_input.expected_child =:= Child#supervisor_child.target of
                        true -> temporary_request(Input, Next);
                        false -> result(stale, Next, Child)
                    end
            end
    end.

%% An occupied start is busy, not replay: independent callers must not share one admission.
-spec temporary_request(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
temporary_request(Input, State) ->
    Child = Input#supervisor_input.child,
    case Input#supervisor_input.op of
        start_child ->
            case Child#supervisor_child.phase of
                vacant -> admit(Input, State);
                _ -> result(busy, State, Child)
            end;
        _ ->
            case Child#supervisor_child.target =/= 0 of
                false ->
                    result(stale, State, Child);
                true ->
                    case Child#supervisor_child.phase of
                        running -> request_retirement(Input, State);
                        admitting -> request_retirement(Input, State);
                        retiring -> result(replay, State, Child);
                        vacant -> result(replay, State, Child);
                        _ -> result(busy, State, Child)
                    end
            end
    end.

%% Reservation precedes the command; only an exact terminal core and transport permit reuse.
-spec admit(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
admit(Input, State) ->
    Child = Input#supervisor_input.child,
    Observed = Input#supervisor_input.observed,
    NextId = State#supervisor_state.next,
    case Input#supervisor_input.reusable andalso terminal(Input) of
        false ->
            result(busy, State, Child);
        true ->
            case NextId =< State#supervisor_state.last of
                false ->
                    result(exhausted, State, Child);
                true ->
                    case
                        NextId > Observed#domain_state.target andalso
                            NextId > Child#supervisor_child.target
                    of
                        false ->
                            result(invalid, State, Child);
                        true ->
                            Reserved = #supervisor_child{
                                phase = admitting,
                                expected = Observed#domain_state.current,
                                target = NextId
                            },
                            (issue(State#supervisor_state{next = NextId + 1}, Reserved))#supervisor_output{
                                status = accepted
                            }
                    end
            end
    end.

%% Retiring retains the target even if the admitted start has not reached the observed core.
-spec request_retirement(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
request_retirement(Input, State) ->
    Child = Input#supervisor_input.child,
    (retire_selected(
        Input#supervisor_input{child = Child#supervisor_child{phase = retiring}}, State
    ))#supervisor_output{
        status = accepted
    }.

%% Terminal policy never acquires fresh work, and invalid selection cannot mutate a child slot.
-spec advance(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
advance(Input, State) ->
    Phase = State#supervisor_state.phase,
    case Phase =:= unbound orelse Phase =:= stopped orelse Phase =:= failed of
        true ->
            result(ok, State, Input#supervisor_input.child);
        false ->
            case Input#supervisor_input.slot < State#supervisor_state.children of
                false ->
                    result(invalid, State, Input#supervisor_input.child);
                true ->
                    ClockValid =
                        Input#supervisor_input.now >= State#supervisor_state.last_time andalso
                            Input#supervisor_input.now < ((1 bsl 64) - 1),
                    Next =
                        case ClockValid of
                            true -> State#supervisor_state{last_time = Input#supervisor_input.now};
                            false -> closing(clock_failure, State)
                        end,
                    selected(Input, Next)
            end
    end.

%% Startup is ordered; exits from earlier children wait until startup finishes, as in OTP init.
-spec selected(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
selected(Input, State) ->
    Child = Input#supervisor_input.child,
    case State#supervisor_state.phase of
        stopping ->
            retire(Input, State);
        starting ->
            case Child#supervisor_child.phase of
                fresh ->
                    case Input#supervisor_input.slot =:= State#supervisor_state.started of
                        true -> initial_child(Input, State);
                        false -> result(ok, State, Child)
                    end;
                starting ->
                    pending(Input, State);
                running ->
                    result(ok, State, Child);
                vacant ->
                    result(ok, State, Child);
                _ ->
                    retire(Input, closing(child_state_failure, State))
            end;
        running ->
            case Child#supervisor_child.phase of
                running ->
                    case healthy(Input) of
                        true -> result(ok, State, Child);
                        false -> exited(Input, State)
                    end;
                restarting ->
                    pending(Input, State);
                admitting ->
                    pending(Input, State);
                retiring ->
                    retire_selected(Input, State);
                vacant ->
                    result(ok, State, Child);
                _ ->
                    retire(Input, closing(child_state_failure, State))
            end;
        _ ->
            result(ok, State, Child)
    end.

%% Dormant templates consume declaration order but neither an identity nor restart allowance.
-spec initial_child(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
initial_child(Input, State) ->
    case Input#supervisor_input.dormant of
        false ->
            allocate(Input, State, false);
        true ->
            case Input#supervisor_input.policy of
                permanent ->
                    result(invalid, State, Input#supervisor_input.child);
                temporary ->
                    case Input#supervisor_input.reusable andalso terminal(Input) of
                        true ->
                            Child = Input#supervisor_input.child,
                            result(ok, started(State), Child#supervisor_child{phase = vacant});
                        false ->
                            result(ok, State, Input#supervisor_input.child)
                    end
            end
    end.

%% Both an initialized child and an intentionally empty template advance startup once.
-spec started(#supervisor_state{}) -> #supervisor_state{}.
started(State) ->
    Count = State#supervisor_state.started + 1,
    State#supervisor_state{
        started = Count,
        phase =
            case Count =:= State#supervisor_state.children of
                true -> running;
                false -> starting
            end
    }.

%% Temporary exits retire locally without consuming the permanent-child restart budget.
-spec exited(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
exited(Input, State) ->
    case Input#supervisor_input.policy of
        permanent ->
            restart(Input, State);
        temporary ->
            Child = Input#supervisor_input.child,
            Observed = Input#supervisor_input.observed,
            Exact =
                Observed#domain_state.current =:= Child#supervisor_child.target andalso
                    Observed#domain_state.target =:= Child#supervisor_child.target,
            Ended =
                Observed#domain_state.phase =:= failed orelse
                    Observed#domain_state.phase =:= stopped,
            case Exact andalso Ended of
                true ->
                    retire_selected(
                        Input#supervisor_input{child = Child#supervisor_child{phase = retiring}},
                        State
                    );
                false ->
                    retire(Input, closing(child_state_failure, State))
            end
    end.

%% A ready observation belongs to the exact reserved target, not merely to the selected slot.
-spec healthy(#supervisor_input{}) -> boolean().
healthy(Input) ->
    Observed = Input#supervisor_input.observed,
    Child = Input#supervisor_input.child,
    Observed#domain_state.phase =:= ready andalso
        Observed#domain_state.current =:= Child#supervisor_child.target andalso
        Child#supervisor_child.target =/= 0.

%% A current failed or explicitly stopped permanent child may be replaced; unexplained identity drift cannot.
-spec restart(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
restart(Input, State) ->
    Observed = Input#supervisor_input.observed,
    Child = Input#supervisor_input.child,
    Failed = Observed#domain_state.phase =:= failed orelse Observed#domain_state.phase =:= stopped,
    case Failed andalso Observed#domain_state.current =:= Child#supervisor_child.target of
        true -> allocate(Input, State, true);
        false -> retire(Input, closing(child_state_failure, State))
    end.

%% Record a fresh identity before exposing its command; no allocated ID returns to the grant.
-spec allocate(#supervisor_input{}, #supervisor_state{}, boolean()) -> #supervisor_output{}.
allocate(Input, State, Restart) ->
    Observed = Input#supervisor_input.observed,
    NextId = State#supervisor_state.next,
    CanStart =
        case Restart of
            true ->
                Observed#domain_state.phase =:= failed orelse
                    Observed#domain_state.phase =:= stopped;
            false ->
                Observed#domain_state.phase =:= unbound andalso Observed#domain_state.current =:= 0
        end,
    case
        CanStart andalso NextId > Observed#domain_state.target andalso
            NextId > Observed#domain_state.current
    of
        false ->
            retire(Input, closing(child_state_failure, State));
        true ->
            case NextId =< State#supervisor_state.last of
                false ->
                    retire(Input, closing(identities_exhausted, State));
                true ->
                    Budget =
                        case Restart of
                            true -> record_restart(Input#supervisor_input.now, State);
                            false -> State
                        end,
                    case Budget#supervisor_state.phase =:= stopping of
                        true ->
                            retire(Input, Budget);
                        false ->
                            Child = #supervisor_child{
                                phase =
                                    case Restart of
                                        true -> restarting;
                                        false -> starting
                                    end,
                                expected = Observed#domain_state.current,
                                target = NextId
                            },
                            issue(Budget#supervisor_state{next = NextId + 1}, Child)
                    end
            end
    end.

%% A full window overwrites only an expired oldest entry; simultaneous failures share this state.
-spec record_restart(hls_nums:u64(), #supervisor_state{}) -> #supervisor_state{}.
record_restart(Now, State) ->
    Count = State#supervisor_state.count,
    Intensity = State#supervisor_state.intensity,
    Head = State#supervisor_state.head,
    case Intensity =:= 0 of
        true ->
            closing(intensity_exhausted, State);
        false ->
            case Count < Intensity of
                true ->
                    Position = Head + Count,
                    Index =
                        case Position >= Intensity of
                            true -> Position - Intensity;
                            false -> Position
                        end,
                    State#supervisor_state{
                        count = Count + 1,
                        times = hls_vec:set(Index + 1, State#supervisor_state.times, Now)
                    };
                false ->
                    Oldest = hls_vec:nth(Head + 1, State#supervisor_state.times),
                    case Now >= Oldest andalso Now - Oldest > State#supervisor_state.period of
                        false ->
                            closing(intensity_exhausted, State);
                        true ->
                            State#supervisor_state{
                                head =
                                    case Head + 1 =:= Intensity of
                                        true -> 0;
                                        false -> Head + 1
                                    end,
                                times = hls_vec:set(Head + 1, State#supervisor_state.times, Now)
                            }
                    end
            end
    end.

%% Once the target is accepted, leave the management lane idle so backend completions progress.
-spec pending(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
pending(Input, State) ->
    Child = Input#supervisor_input.child,
    Observed = Input#supervisor_input.observed,
    Target = Child#supervisor_child.target,
    case healthy(Input) of
        true ->
            Running = Child#supervisor_child{phase = running},
            case Child#supervisor_child.phase of
                starting ->
                    result(ok, started(State), Running);
                _ ->
                    result(ok, State, Running)
            end;
        false ->
            case Observed#domain_state.target =:= Target of
                true ->
                    case Observed#domain_state.phase of
                        failed ->
                            case Child#supervisor_child.phase of
                                starting ->
                                    retire(Input, closing(initialization_failure, State));
                                admitting ->
                                    retire_selected(
                                        Input#supervisor_input{
                                            child = Child#supervisor_child{phase = retiring}
                                        },
                                        State
                                    );
                                _ ->
                                    allocate(Input, State, true)
                            end;
                        closing ->
                            result(ok, State, Child);
                        isolated ->
                            result(ok, State, Child);
                        initializing ->
                            result(ok, State, Child);
                        _ ->
                            retire(Input, closing(child_state_failure, State))
                    end;
                false ->
                    Retry =
                        Observed#domain_state.current =:= Child#supervisor_child.expected andalso
                            Observed#domain_state.target < Target andalso
                            (Observed#domain_state.phase =:= unbound orelse
                                Observed#domain_state.phase =:= failed orelse
                                Observed#domain_state.phase =:= stopped),
                    case Retry of
                        true -> issue(State, Child);
                        false -> retire(Input, closing(child_state_failure, State))
                    end
            end
    end.

%% Whole-subtree retirement follows OTP's reverse declaration order.
-spec retire(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
retire(Input, State) ->
    case
        Input#supervisor_input.slot =:=
            State#supervisor_state.children - 1 - State#supervisor_state.retired
    of
        true -> retire_selected(Input, State);
        false -> result(ok, State, Input#supervisor_input.child)
    end.

%% An emitted startup retains its target even when a registered observation still says unbound.
-spec retire_selected(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
retire_selected(Input, State) ->
    Child = Input#supervisor_input.child,
    Observed = Input#supervisor_input.observed,
    Pending =
        Child#supervisor_child.phase =:= starting orelse
            Child#supervisor_child.phase =:= restarting orelse
            Child#supervisor_child.phase =:= admitting orelse
            Child#supervisor_child.phase =:= retiring,
    case Pending andalso Observed#domain_state.target < Child#supervisor_child.target of
        true ->
            case Observed#domain_state.current =:= Child#supervisor_child.expected of
                true -> issue(State, Child);
                false -> result(ok, State, Child)
            end;
        false ->
            case State#supervisor_state.phase of
                stopping -> retire_observed(Input, State);
                _ -> vacate_observed(Input, State)
            end
    end.

%% An untouched child never owned an actor; failed first initialization published no incarnation.
-spec retire_observed(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
retire_observed(Input, State) ->
    Child = Input#supervisor_input.child,
    Observed = Input#supervisor_input.observed,
    case Child#supervisor_child.phase of
        retired ->
            result(ok, State, Child);
        _ ->
            Phase = Observed#domain_state.phase,
            Current = Observed#domain_state.current,
            Untouched =
                Child#supervisor_child.phase =:= fresh andalso Current =:= 0 andalso
                    Phase =:= unbound,
            FailedStart =
                Current =:= 0 andalso Phase =:= failed andalso
                    Observed#domain_state.target =:= Child#supervisor_child.target,
            case Untouched orelse FailedStart orelse terminal(Input) of
                true ->
                    Retired = State#supervisor_state.retired + 1,
                    Next = State#supervisor_state{
                        retired = Retired,
                        phase =
                            case Retired =:= State#supervisor_state.children of
                                true ->
                                    case State#supervisor_state.reason of
                                        requested -> stopped;
                                        _ -> failed
                                    end;
                                false ->
                                    stopping
                            end
                    },
                    result(ok, Next, Child#supervisor_child{phase = retired});
                false ->
                    CanStop =
                        Current =/= 0 andalso Observed#domain_state.target =:= Current andalso
                            (Phase =:= ready orelse Phase =:= failed),
                    case CanStop of
                        true ->
                            (result(ok, State, Child#supervisor_child{phase = retiring}))#supervisor_output{
                                command_valid = true,
                                command = #domain_input{
                                    op = stop,
                                    expected = Current,
                                    target = Current,
                                    transition = Current
                                }
                            };
                        false ->
                            result(ok, State, Child)
                    end
            end
    end.

%% Core terminal evidence is exact; a stopped earlier occupant cannot retire a reserved target.
-spec terminal(#supervisor_input{}) -> boolean().
terminal(Input) ->
    Child = Input#supervisor_input.child,
    Observed = Input#supervisor_input.observed,
    Target = Child#supervisor_child.target,
    case Observed#domain_state.phase of
        unbound ->
            Target =:= 0 andalso Observed#domain_state.current =:= 0 andalso
                Observed#domain_state.target =:= 0;
        failed ->
            Target =/= 0 andalso Observed#domain_state.current =:= 0 andalso
                Observed#domain_state.target =:= Target;
        stopped ->
            Target =/= 0 andalso Observed#domain_state.current =:= Target andalso
                Observed#domain_state.target =:= Target;
        _ ->
            false
    end.

%% Local retirement waits for the transport's old-output/watch boundary before releasing capacity.
-spec vacate_observed(#supervisor_input{}, #supervisor_state{}) -> #supervisor_output{}.
vacate_observed(Input, State) ->
    Child = Input#supervisor_input.child,
    Observed = Input#supervisor_input.observed,
    case terminal(Input) of
        true ->
            case Input#supervisor_input.reusable of
                true -> result(ok, State, Child#supervisor_child{phase = vacant});
                false -> result(ok, State, Child)
            end;
        false ->
            Target = Child#supervisor_child.target,
            CanStop =
                Target =/= 0 andalso Observed#domain_state.current =:= Target andalso
                    Observed#domain_state.target =:= Target andalso
                    (Observed#domain_state.phase =:= ready orelse
                        Observed#domain_state.phase =:= failed),
            case CanStop of
                true ->
                    (result(ok, State, Child#supervisor_child{phase = retiring}))#supervisor_output{
                        command_valid = true,
                        command = #domain_input{
                            op = stop, expected = Target, target = Target, transition = Target
                        }
                    };
                false ->
                    result(ok, State, Child)
            end
    end.

%% The first reason survives later observations and repeated shutdown requests.
-spec closing(supervisor_reason(), #supervisor_state{}) -> #supervisor_state{}.
closing(Reason, State) ->
    case State#supervisor_state.phase of
        stopping -> State;
        stopped -> State;
        failed -> State;
        _ -> State#supervisor_state{phase = stopping, reason = Reason}
    end.

%% Reissuing an unaccepted transition uses exactly the same reserved identity tuple.
-spec issue(#supervisor_state{}, #supervisor_child{}) -> #supervisor_output{}.
issue(State, Child) ->
    (result(ok, State, Child))#supervisor_output{
        command_valid = true,
        command = #domain_input{
            op =
                case Child#supervisor_child.expected of
                    0 -> activate;
                    _ -> replace
                end,
            expected = Child#supervisor_child.expected,
            target = Child#supervisor_child.target,
            transition = Child#supervisor_child.target
        }
    }.

%% Plain observations never imply command acceptance or child completion.
-spec result(supervisor_status(), #supervisor_state{}, #supervisor_child{}) -> #supervisor_output{}.
result(Status, State, Child) -> #supervisor_output{status = Status, state = State, child = Child}.

-doc "Initializes the optional compiled control-service wrapper.".
-spec init([]) -> #supervisor_service{}.
init([]) -> #supervisor_service{supervisor = new()}.

-doc "Runs the same finite supervisor transition used by native callers.".
-spec handle_call(#supervisor_input{}, #supervisor_service{}) ->
    {reply, #supervisor_output{}, #supervisor_service{}}.
handle_call(Input = #supervisor_input{}, State) ->
    Output = step(Input, State#supervisor_service.supervisor),
    {reply, Output, State#supervisor_service{supervisor = Output#supervisor_output.state}}.

-doc "Rejects accidental casts to the management-only compiled service.".
-spec handle_cast(#unsupported_cast{}, #supervisor_service{}) -> {noreply, #supervisor_service{}}.
handle_cast(#unsupported_cast{unused = Value}, State) ->
    false = Value =:= Value,
    {noreply, State}.
