-module(hls_domain_erts).
-moduledoc """
ERTS lifecycle backend for one statically closed domain of source state machines.

This is a management process, not an actor scheduler or message relay. The
hls_domain owner calls it to attach, inspect lifecycle state, request replacement
and resolve an incarnation's actor PID. Its other inputs are phase-worker results
and actor/owner monitor events. Application callers use resolved PIDs directly;
source actors send directly to their configured peers and external recipients.

The process owns exclusive control authority and serializes lifecycle/failure
observations. hls_domain_lifecycle makes the finite decisions; linked workers
retire old actors and perform effect-free setup before new PIDs are published.
A native local monitor revokes control authority when the owner dies. Actors and
accepted lifecycle work survive by default; owner_loss => fail explicitly retires
them instead. Stopping this backend still terminates its actors. A hardware backend
must distinguish management connection loss from actual actor failure too.

The source catalog is trusted build input. Initializers must be finite; setup may
update private state but may not publish messages or replies. Direct Erlang side
effects outside the supported callback interface are not intercepted. Both this
management mailbox and the source actors' incoming BEAM mailboxes are ordinary,
unbounded ERTS queues. The finite hls_mailbox inside a source actor constrains its
modeled admission, not messages already waiting in the outer BEAM mailbox. Native
simulation therefore does not establish physical bandwidth or bounded backlog.
""".
-behaviour(gen_server).
-behaviour(hls_domain_backend).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Deployment backend lifecycle and incarnation-specific endpoint access.
-export([start_link/1, attach/2, status/1, request/3, endpoint/4, send_request/2, stop/1]).

%% gen_server implementation callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% Checked source catalog and observed backend state.
-export_type([specification/0, snapshot/0]).

%% Each actor starts from its checked init([]), with finite mailbox capacity.
-type actor_specification() :: #{module := module(), mailbox_capacity := 1..255}.
%% Fixed output routes stay inside the domain or terminate at an explicitly external PID.
-type destination() :: {actor, term()} | {external, pid()}.
-doc "One closed actor group, explicit routes and finite effect-free startup messages; no dynamic actor creation.".
-type specification() :: #{
    actors := #{term() => actor_specification()},
    routes => #{term() => #{atom() => destination()}},
    startup => #{term() => [term()]},
    owner_loss => hls_domain_backend:owner_loss()
}.
-doc "Current finite controller state, private/live actor identities, first native failure and completed reset count.".
-type snapshot() :: #{
    state := hls_domain_lifecycle:state(),
    actors := #{term() => pid()},
    fault_reason := term(),
    reset_count := non_neg_integer()
}.

%% A phase worker is linked so abandoning initialization kills its unadopted actors.
-record(work, {pid :: pid(), reference :: reference(), action :: hls_domain_lifecycle:action()}).
%% Host-only ownership and monitoring complement, but never duplicate, the finite kernel state.
-record(backend, {
    spec :: specification(),
    state = #domain_state{} :: hls_domain_lifecycle:state(),
    owner = undefined :: undefined | pid(),
    owner_monitor = undefined :: undefined | reference(),
    authority = undefined :: undefined | reference(),
    actors = #{} :: #{term() => pid()},
    monitors = #{} :: #{reference() => term()},
    worker = none :: none | #work{},
    fault_reason = none :: term(),
    reset_count = 0 :: non_neg_integer()
}).

-doc "Starts an unbound backend after checking the fixed source catalog; does not start application actors.".
-spec start_link(specification()) -> gen_server:start_ret().
start_link(Spec) ->
    gen_server:start_link(?MODULE, normalize(Spec), []).

-doc "Attaches one local owner without resetting a domain; another live owner is rejected.".
-spec attach(pid(), pid()) -> {ok, hls_domain_backend:authority()} | {error, term()}.
attach(Backend, Owner) -> gen_server:call(Backend, {attach, Owner}).

-doc "Returns the actual controller state; only ready actors are usable as application endpoints.".
-spec status(pid()) -> {ok, snapshot()}.
status(Backend) -> gen_server:call(Backend, status).

-doc "Starts a correlated management call without waiting; the backend authenticates the calling owner exactly as for synchronous requests.".
-spec send_request(pid(), hls_domain_backend:request()) -> gen_server:request_id().
send_request(Backend, Request) -> gen_server:send_request(Backend, Request).

-doc "Submits an authorized activate, replace, stop or inspect input and returns its immediate disposition; backend phase work completes asynchronously. Completion acknowledgements and source faults belong to the backend and cannot be supplied by the owner.".
-spec request(pid(), hls_domain_backend:authority(), hls_domain_lifecycle:input()) ->
    hls_domain_lifecycle:output() | {error, term()}.
request(Backend, Authority, Input) -> gen_server:call(Backend, {request, Authority, Input}).

-doc "Resolves a ready actor only for the current authority and nonzero incarnation; stale handles are never rebound.".
-spec endpoint(pid(), hls_domain_backend:authority(), hls_nums:u64(), term()) ->
    {ok, pid()} | {error, term()}.
endpoint(Backend, Authority, Incarnation, Actor) ->
    gen_server:call(Backend, {endpoint, Authority, Incarnation, Actor}).

-doc "Stops the backend and forcibly retires its actors and any unfinished initialization worker.".
-spec stop(pid()) -> ok.
stop(Backend) -> gen_server:stop(Backend).

-doc "Creates only management state; actor creation requires an explicit `activate/2` request.".
-spec init(specification()) -> {ok, #backend{}}.
init(Spec) ->
    process_flag(trap_exit, true),
    {ok, #backend{spec = Spec, state = hls_domain_lifecycle:new()}}.

-doc "Handles exclusive owner attachment, observations, lifecycle commands and endpoint lookup.".
-spec handle_call(term(), gen_server:from(), #backend{}) -> term().
%% An owner may repeat attachment without changing its authority or device state.
handle_call({attach, Owner}, {Owner, _}, Backend = #backend{owner = Owner, authority = Authority}) ->
    {reply, {ok, Authority}, Backend};
%% Only a local process can establish this backend's native-monitor failure detector.
handle_call({attach, Owner}, {Owner, _}, Backend = #backend{owner = undefined}) when
    node(Owner) =:= node()
->
    Authority = make_ref(),
    Monitor = monitor(process, Owner),
    {reply, {ok, Authority}, Backend#backend{
        owner = Owner, owner_monitor = Monitor, authority = Authority
    }};
%% Local death can be reconciled before its queued DOWN, avoiding a restart/attachment race.
handle_call(
    {attach, _Owner} = Request,
    From,
    Backend = #backend{owner = Previous, owner_monitor = Monitor}
) when is_pid(Previous) ->
    case is_process_alive(Previous) of
        true ->
            {reply, {error, owned}, Backend};
        false ->
            Reason =
                receive
                    {'DOWN', Monitor, process, Previous, Cause} -> Cause
                after 0 -> reason_unavailable
                end,
            demonitor(Monitor, [flush]),
            handle_call(Request, From, owner_lost(Reason, Backend))
    end;
%% Observing another PID does not convey permission to replace an attached owner.
handle_call({attach, _Owner}, _From, Backend) ->
    {reply, {error, owned}, Backend};
%% A local endpoint already known dead cannot remain ready while its DOWN is queued.
handle_call(status, _From, Previous) ->
    Backend = reconcile_ready(Previous),
    {reply, {ok, snapshot(Backend)}, Backend};
%% An authority is private to its live owner, not a freely transferable reset handle.
handle_call(
    {request, Authority, Input},
    {Owner, _},
    Backend = #backend{authority = Authority, owner = Owner, state = State}
) when is_reference(Authority) ->
    case Input#domain_input.op of
        Operation when
            Operation =:= activate;
            Operation =:= replace;
            Operation =:= stop;
            Operation =:= inspect
        ->
            Output = hls_domain_lifecycle:step(Input, State),
            Next = drive(Backend#backend{state = Output#domain_output.state}),
            {reply, Output, Next};
        _ ->
            {reply, {error, backend_completion_only}, Backend}
    end;
%% Ready incarnation identity is checked before returning a raw local actor PID.
handle_call(
    {endpoint, Authority, Incarnation, Actor},
    {Owner, _},
    Previous = #backend{authority = Authority, owner = Owner}
) when is_reference(Authority) ->
    Backend = reconcile_ready(Previous),
    #backend{state = State, actors = Actors} = Backend,
    Reply =
        case hls_domain_lifecycle:admitted(Incarnation, State) of
            true ->
                case maps:find(Actor, Actors) of
                    {ok, Pid} -> {ok, Pid};
                    error -> {error, unknown_actor}
                end;
            false ->
                {error, not_ready_or_stale}
        end,
    {reply, Reply, Backend};
%% Unrecognized or stale callers cannot mutate lifecycle or discover endpoints.
handle_call(_Request, _From, Backend) ->
    {reply, {error, unauthorized}, Backend}.

-doc "Rejects asynchronous management commands; lifecycle ownership is an acknowledged call interface.".
-spec handle_cast(term(), #backend{}) -> {noreply, #backend{}}.
handle_cast(_Message, Backend) -> {noreply, Backend}.

-doc "Adopts initialized actors, acknowledges completed physical phases, and observes local actor/owner loss.".
-spec handle_info(term(), #backend{}) -> {noreply, #backend{}}.
%% Track provisional actors before setup so a worker failure cannot leave unowned children.
handle_info({phase_actor, Ref, Id, Pid}, Backend = #backend{worker = #work{reference = Ref}}) ->
    link(Pid),
    Monitor = monitor(process, Pid),
    {noreply, Backend#backend{
        actors = (Backend#backend.actors)#{Id => Pid},
        monitors = (Backend#backend.monitors)#{Monitor => Id}
    }};
%% The worker remains linked until its result has been adopted or rejected.
handle_info(
    {phase_done, Ref},
    Backend = #backend{
        worker = #work{reference = Ref, pid = Pid, action = Action}, state = State
    }
) ->
    Operation = acknowledgement(Action),
    Input = transition_input(Operation, State),
    Output = hls_domain_lifecycle:step(Input, State),
    Pid ! {adopt, Ref},
    Resets =
        Backend#backend.reset_count +
            case Action of
                reset -> 1;
                _ -> 0
            end,
    Detail =
        case Action of
            reset -> none;
            _ -> Backend#backend.fault_reason
        end,
    Completed =
        case Action of
            fence ->
                clear_monitors(Backend#backend.monitors),
                Backend#backend{actors = #{}, monitors = #{}};
            _ ->
                Backend
        end,
    Next = Completed#backend{
        worker = none,
        state = Output#domain_output.state,
        reset_count = Resets,
        fault_reason = Detail
    },
    {noreply, drive(Next)};
%% Source startup failure abandons this transition and retires all provisional peers.
handle_info({'EXIT', Pid, Reason}, Backend = #backend{worker = #work{pid = Pid, action = Action}}) ->
    Detail =
        case Action of
            initialize -> {initialization, Reason};
            _ -> {lifecycle, Action, Reason}
        end,
    {noreply, fail_backend(Detail, Backend#backend{worker = none})};
%% Owner loss revokes authority; only an explicit fail policy also retires the actor group.
handle_info(
    {'DOWN', Monitor, process, _Pid, Reason},
    Backend = #backend{owner_monitor = Monitor}
) ->
    {noreply, owner_lost(Reason, Backend)};
%% Fencing intentionally retires actors; their DOWN observations are not fresh source failures.
handle_info(
    {'DOWN', Monitor, process, _Pid, _Reason},
    Backend = #backend{worker = #work{action = fence}}
) ->
    {noreply, forget_actor(Monitor, Backend)};
%% Every unexpected member death fails the incarnation and retires the remaining closed group.
handle_info(
    {'DOWN', Monitor, process, _Pid, Reason}, Backend = #backend{monitors = Monitors, state = State}
) ->
    case maps:find(Monitor, Monitors) of
        {ok, Actor} ->
            Detail =
                case State#domain_state.phase of
                    initializing -> {initialization, {actor, Actor, Reason}};
                    _ -> {actor, Actor, Reason}
                end,
            {noreply, fail_backend(Detail, forget_actor(Monitor, Backend))};
        error ->
            {noreply, Backend}
    end;
%% Late phase results and linked exits belong to already retired work.
handle_info(_Message, Backend) ->
    {noreply, Backend}.

-doc "Retires local resources; termination cannot restore or replay application work.".
-spec terminate(term(), #backend{}) -> ok.
terminate(_Reason, Backend) ->
    cancel_worker(Backend#backend.worker),
    retire(Backend#backend.actors),
    ok.

%% Check only the runtime catalog shape; source semantic qualification belongs to the build.
-spec normalize(specification()) -> specification().
normalize(Spec = #{actors := Actors}) when is_map(Actors), map_size(Actors) > 0 ->
    [] = maps:keys(Spec) -- [actors, routes, startup, owner_loss],
    OwnerLoss = maps:get(owner_loss, Spec, preserve),
    true = OwnerLoss =:= preserve orelse OwnerLoss =:= fail,
    Routes = maps:get(routes, Spec, #{}),
    Startup = maps:get(startup, Spec, #{}),
    true = is_map(Routes) andalso is_map(Startup),
    [] = maps:keys(Routes) -- maps:keys(Actors),
    [] = maps:keys(Startup) -- maps:keys(Actors),
    maps:foreach(
        fun(_Id, #{module := Module, mailbox_capacity := Capacity} = Actor) ->
            [] = maps:keys(Actor) -- [module, mailbox_capacity],
            true =
                is_atom(Module) andalso is_integer(Capacity) andalso Capacity > 0 andalso
                    Capacity =< 255
        end,
        Actors
    ),
    maps:foreach(
        fun(_Id, Ports) ->
            true = is_map(Ports),
            maps:foreach(
                fun(Port, Destination) ->
                    true = is_atom(Port),
                    ok = destination(Destination, Actors)
                end,
                Ports
            )
        end,
        Routes
    ),
    maps:foreach(
        fun(_Id, Messages) ->
            true = is_list(Messages) andalso length(Messages) =< 255
        end,
        Startup
    ),
    Spec#{routes => Routes, startup => Startup, owner_loss => OwnerLoss}.

%% No route can silently escape the domain except through a named external endpoint.
-spec destination(destination(), #{term() => actor_specification()}) -> ok.
destination({actor, Id}, Actors) ->
    true = maps:is_key(Id, Actors),
    ok;
destination({external, Pid}, _Actors) when is_pid(Pid) -> ok.

%% Only one worker can own a phase; duplicate management inputs observe its existing work.
-spec drive(#backend{}) -> #backend{}.
drive(Backend = #backend{worker = none, state = State}) ->
    case hls_domain_lifecycle:action(State) of
        none ->
            Backend;
        Action ->
            Ref = make_ref(),
            Parent = self(),
            Pid = spawn_link(fun() -> work(Parent, Ref, Action, Backend) end),
            Backend#backend{worker = #work{pid = Pid, reference = Ref, action = Action}}
    end;
drive(Backend) ->
    Backend.

%% Workers keep newly created children linked until the backend adopts the completed setup.
-spec work(pid(), reference(), hls_domain_lifecycle:action(), #backend{}) -> ok.
work(Parent, Ref, Action, Backend) ->
    Actors = perform(Parent, Ref, Action, Backend),
    Parent ! {phase_done, Ref},
    receive
        {adopt, Ref} ->
            maps:foreach(fun(_Id, Pid) -> unlink(Pid) end, Actors),
            ok
    end.

%% Fencing waits for actual local termination before its acknowledgement is generated.
-spec perform(pid(), reference(), hls_domain_lifecycle:action(), #backend{}) -> #{term() => pid()}.
perform(_Parent, _Ref, fence, #backend{actors = Actors}) ->
    retire(Actors),
    #{};
%% All local actors have terminated; the reset phase records only that completed boundary.
perform(_Parent, _Ref, reset, #backend{actors = Actors}) ->
    true = map_size(Actors) =:= 0,
    #{};
%% Start all endpoints before resolving any internal route, then run effect-free setup.
perform(Parent, Ref, initialize, #backend{spec = Spec, state = State}) ->
    #{actors := Definitions, routes := Routes, startup := Startup} = Spec,
    Actors = maps:map(
        fun(Id, #{module := Module, mailbox_capacity := Capacity}) ->
            {ok, Pid} = hls_statem:start_link(Module, [], [
                {mailbox_capacity, Capacity}, {generation, State#domain_state.current}
            ]),
            Parent ! {phase_actor, Ref, Id, Pid},
            Pid
        end,
        Definitions
    ),
    maps:foreach(
        fun(Id, Pid) ->
            Outputs = maps:map(
                fun(_Port, Target) -> target_pid(Target, Actors) end,
                maps:get(Id, Routes, #{})
            ),
            ok = hls_statem:setup(Pid, Outputs, maps:get(Id, Startup, []))
        end,
        Actors
    ),
    Actors.

%% Fixed local routes resolve only against the newly created incarnation's actor map.
-spec target_pid(destination(), #{term() => pid()}) -> pid().
target_pid({actor, Id}, Actors) -> maps:get(Id, Actors);
target_pid({external, Pid}, _Actors) -> Pid.

%% Phase operations have exactly one corresponding completion indication.
-spec acknowledgement(hls_domain_lifecycle:action()) -> hls_domain_lifecycle:operation().
acknowledgement(fence) -> fenced;
acknowledgement(reset) -> reset_done;
acknowledgement(initialize) -> initialized.

%% Echo the complete transition identity so late acknowledgements cannot advance another request.
-spec transition_input(hls_domain_lifecycle:operation(), hls_domain_lifecycle:state()) ->
    hls_domain_lifecycle:input().
transition_input(Op, #domain_state{previous = Old, target = Target, transition = Id}) ->
    #domain_input{op = Op, expected = Old, target = Target, transition = Id}.

%% Native local liveness closes the status-before-DOWN race; it is not a remote failure detector.
-spec reconcile_ready(#backend{}) -> #backend{}.
reconcile_ready(
    Backend = #backend{
        state = #domain_state{phase = ready},
        actors = Actors,
        monitors = Monitors
    }
) ->
    Dead = [{Id, Pid} || {Id, Pid} <- maps:to_list(Actors), not is_process_alive(Pid)],
    case Dead of
        [] ->
            Backend;
        [{Id, Pid} | _] ->
            [Monitor] = [Ref || {Ref, Actor} <- maps:to_list(Monitors), Actor =:= Id],
            Reason = observed_death(Monitor, Pid),
            fail_backend({actor, Id, Reason}, Backend)
    end;
reconcile_ready(Backend) ->
    Backend.

%% Preserve an already delivered native reason; liveness alone cannot reconstruct a missing cause.
-spec observed_death(reference(), pid()) -> term().
observed_death(Monitor, Pid) ->
    receive
        {'DOWN', Monitor, process, Pid, Reason} -> Reason
    after 0 -> {native_actor_dead, reason_unavailable}
    end.

%% Management authority ends with its owner; accepted actor/lifecycle work survives unless explicitly coupled.
-spec owner_lost(term(), #backend{}) -> #backend{}.
owner_lost(Reason, Backend) ->
    Next =
        case maps:get(owner_loss, Backend#backend.spec) of
            preserve -> Backend;
            fail -> fail_backend({owner_down, Reason}, Backend)
        end,
    Next#backend{owner = undefined, owner_monitor = undefined, authority = undefined}.

%% A source or owner fault closes admission before its peers are retired; no reset is inferred.
-spec fail_backend(term(), #backend{}) -> #backend{}.
fail_backend(Reason, Backend = #backend{state = State, fault_reason = Detail}) ->
    cancel_worker(Backend#backend.worker),
    Cause = fault_cause(Reason),
    Input =
        case hls_domain_lifecycle:action(State) of
            none ->
                #domain_input{
                    op = fault,
                    expected = State#domain_state.current,
                    fault = Cause
                };
            _ ->
                (transition_input(abort, State))#domain_input{fault = Cause}
        end,
    Output = hls_domain_lifecycle:step(Input, State),
    retire(Backend#backend.actors),
    clear_monitors(Backend#backend.monitors),
    First =
        case Detail of
            none -> Reason;
            _ -> Detail
        end,
    Backend#backend{
        state = Output#domain_output.state,
        worker = none,
        actors = #{},
        monitors = #{},
        fault_reason = First
    }.

%% A domain cause identifies the observed boundary, never a fabricated source expression.
-spec fault_cause(term()) -> hls_domain_lifecycle:fault().
fault_cause({actor, _Actor, _Reason}) -> actor_failure;
fault_cause({owner_down, _Reason}) -> owner_down;
fault_cause({initialization, _Reason}) -> initialization_failure;
fault_cause({lifecycle, _Action, _Reason}) -> lifecycle_failure.

%% Cancelled phase workers are killed, also terminating any not-yet-adopted linked actors.
-spec cancel_worker(none | #work{}) -> ok.
cancel_worker(none) ->
    ok;
cancel_worker(#work{pid = Pid}) ->
    exit(Pid, kill),
    ok.

%% A fresh monitor establishes retirement even if an earlier DOWN is still queued at the backend.
-spec retire(#{term() => pid()}) -> ok.
retire(Actors) ->
    maps:foreach(
        fun(_Id, Pid) ->
            Monitor = monitor(process, Pid),
            exit(Pid, shutdown),
            receive
                {'DOWN', Monitor, process, Pid, _} -> ok
            after 1000 ->
                exit(Pid, kill),
                receive
                    {'DOWN', Monitor, process, Pid, _} -> ok
                after 1000 -> error({domain_retirement_unconfirmed, Pid})
                end
            end
        end,
        Actors
    ).

%% Retired actor monitor messages cannot be mistaken for a later incarnation's failures.
-spec clear_monitors(#{reference() => term()}) -> ok.
clear_monitors(Monitors) ->
    maps:foreach(fun(Ref, _Id) -> demonitor(Ref, [flush]) end, Monitors).

%% Remove one exact monitor's actor; unrelated or stale DOWN observations are inert.
-spec forget_actor(reference(), #backend{}) -> #backend{}.
forget_actor(Monitor, Backend = #backend{monitors = Monitors, actors = Actors}) ->
    case maps:take(Monitor, Monitors) of
        {Id, Rest} -> Backend#backend{monitors = Rest, actors = maps:remove(Id, Actors)};
        error -> Backend
    end.

%% Host observations expose actual state; the public owner separately hides non-ready actor PIDs.
-spec snapshot(#backend{}) -> snapshot().
snapshot(#backend{state = State, actors = Actors, fault_reason = Reason, reset_count = Resets}) ->
    #{state => State, actors => Actors, fault_reason => Reason, reset_count => Resets}.
