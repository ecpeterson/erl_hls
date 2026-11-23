%%%% phi_memory_runner
%%%%
%%%% ERTS coordinator for one directly attached phi memory experiment.

-module(phi_memory_runner).
-moduledoc """
Runs one phi memory closeout over the call protocol exposed by `hls_fabric`.

A physical `hls_fabric` connects that protocol to FIFO, DMA, or simulation
transport. The example-local `phi_memory_cpu_fabric` implements the same calls
and routed frame codec around ordinary `hls_statem` actors, so both backends
use this coordinator and the same `phi_memory_experiment` reducer.

The runner owns every routed phi output, continuously decodes those streams,
feeds `phi_memory_experiment`, and completes each returned spatial write before
processing another event. Writes are asynchronous, so its deadline and fabric
monitor remain live during transport stalls. Receive receipts bound the hardware
frames waiting for those writes. It performs no retry: a malformed frame, failed
write, fabric exit, or timeout terminates the experiment result. A fabric exit
is reported as `{error, {fabric_down, Reason}}`, where `Reason` is its OTP exit
reason. In particular, a Pauli update is never repeated after ambiguous
transport failure.

The simulation releases reset before ERTS connects. Its gateway holds every
topology output until the first valid host command, and the runner chooses a
future cutoff step so the command can take effect before that round. A real
loader should make activation an explicit manifest-owned handshake and replace
the explicit distance argument without changing the reducer. The CPU
realization queues the first cutoff before activating its actors.

This coordinator remains an ordinary `gen_server`: it needs delayed replies,
timer and monitor messages, and unsolicited streams, while `hls_gs` currently
models transaction-correlated call and cast traffic intended for lowering.

Payload encoding and event decoding belong to phi_memory_wire; phi_memory_experiment decides the next closeout commands.
""".

-behavior(gen_server).

%% Host experiment lifecycle and completion.
-export([start_link/3, stop/1, await/1]).

%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% Terminal result delivered identically to every await caller.
-type completion() :: {ok, phi_memory_experiment:witness()} | {error, term()}.

-define(FABRIC_RX, '$hls_fabric_frame').

-record(state, {
    fabric :: pid(),
    fabric_monitor :: reference(),
    boundary :: map(),
    experiment :: phi_memory_experiment:state(),
    timer :: reference(),
    deadline :: integer(),
    sending = none :: none | gen_server:request_id(),
    commands = [] :: [term()],
    events = queue:new() :: queue:queue(term()),
    result = running ::
        running | {ok, phi_memory_experiment:witness()} | {error, term()},
    waiters = [] :: [gen_server:from()]
}).

-doc "Starts one closeout and arms its timeout in milliseconds.".
-spec start_link(pid(), phi_memory_experiment:options(), pos_integer()) ->
    gen_server:start_ret().
start_link(Fabric, Options, Timeout) ->
    gen_server:start_link(?MODULE, {Fabric, Options, Timeout}, []).

-doc "Stops a runner after its result has been collected.".
-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:stop(Pid).

-doc "Waits until the experiment completes, fails, or reaches its timeout.".
-spec await(pid()) ->
    {ok, phi_memory_experiment:witness()} | {error, term()}.
await(Pid) ->
    gen_server:call(Pid, await, infinity).

-doc "Derives the boundary, claims all output routes, and starts one timed experiment; route registration errors stop startup.".
-spec init({pid(), phi_memory_experiment:options(), pos_integer()}) ->
    {ok, #state{}} | {stop, {routes, term()}}.
init({Fabric, Options = #{distance := Distance}, Timeout}) when
    Timeout > 0
->
    Boundary = phi_memory_boundary:contract(Distance),
    case register_routes(Fabric, Boundary) of
        ok ->
            start_experiment(Fabric, Options, Boundary, Timeout);
        {error, Reason} ->
            {stop, {routes, Reason}}
    end.

-doc "Retains await callers until closeout finishes, returns an existing result immediately, and rejects other calls.".
-spec handle_call(term(), gen_server:from(), #state{}) ->
    {noreply, #state{}} | {reply, completion(), #state{}}.
%% Hold each caller while the closeout result is still pending.
handle_call(await, From, State = #state{result = running, waiters = Waiters}) ->
    {noreply, State#state{waiters = [From | Waiters]}};
%% Repeated awaits observe the retained terminal result.
handle_call(await, _From, State = #state{result = Result}) ->
    {reply, Result, State};
%% Only await belongs to the runner call protocol.
handle_call(Request, _From, State) ->
    {reply, {error, {call, Request}}, State}.

-doc "Queues received frames during closeout and acknowledges late frames; an unexpected running-state cast fails the experiment.".
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
%% Retain the receive receipt until its event and resulting writes have been handled.
handle_cast(
    {?FABRIC_RX, Receipt, Route, Header, Payload},
    State = #state{result = running, events = Events}
) ->
    {noreply, advance(State#state{events = queue:in({Receipt, Route, Header, Payload}, Events)})};
%% Drain late frames after completion so the broker does not retain their receipts.
handle_cast({?FABRIC_RX, Receipt, _Route, _Header, _Payload}, State = #state{fabric = Fabric}) ->
    hls_fabric:ack(Fabric, Receipt),
    {noreply, State};
%% Ignore unrelated casts once a result has already been fixed.
handle_cast(_Message, State = #state{result = Result}) when Result =/= running ->
    {noreply, State};
%% Unexpected traffic during a live experiment is a protocol failure.
handle_cast(Message, State) ->
    {noreply, finish({error, {cast, Message}}, State)}.

-doc "Services deadlines, fabric death and asynchronous send completion while enforcing at-most-once command submission.".
-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
%% Bound nonconvergent decoders and stalled transports with the experiment deadline.
handle_info(experiment_timeout, State = #state{result = running}) ->
    {noreply, finish({error, timeout}, State)};
%% A cancelled timer may already have delivered its message.
handle_info(experiment_timeout, State) ->
    {noreply, State};
%% A transport exit invalidates the entire at-most-once experiment.
handle_info(
    {'DOWN', Monitor, process, Fabric, Reason},
    State = #state{result = running, fabric = Fabric, fabric_monitor = Monitor}
) ->
    {noreply, finish({error, {fabric_down, Reason}}, State)};
%% Terminal results cannot be changed by later mailbox traffic.
handle_info(_Message, State = #state{result = Result}) when Result =/= running ->
    {noreply, State};
%% Complete one asynchronous write before advancing queued events or commands.
handle_info(Message, State = #state{sending = Request}) when Request =/= none ->
    case gen_server:check_response(Message, Request) of
        {reply, ok} ->
            {noreply, advance(State#state{sending = none})};
        {reply, {error, Reason}} ->
            {noreply, finish({error, {send, Reason}}, State#state{sending = none})};
        {error, {Reason, _Fabric}} ->
            {noreply, finish({error, {fabric_down, Reason}}, State#state{sending = none})};
        no_reply ->
            {noreply, finish({error, {info, Message}}, State)}
    end;
%% There is no other unsolicited message in the running protocol.
handle_info(Message, State) ->
    {noreply, finish({error, {info, Message}}, State)}.

-doc "Cancels the deadline, abandons any outstanding response alias, and removes the fabric monitor.".
-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, #state{timer = Timer, fabric_monitor = Monitor, sending = Request}) ->
    erlang:cancel_timer(Timer),
    abandon_send(Request),
    demonitor(Monitor, [flush]),
    ok.

%% Monitor the transport before creating the reducer, then arm its deadline and submit the initial cutoff.
-spec start_experiment(
    pid(), phi_memory_experiment:options(), phi_memory_boundary:contract(), pos_integer()
) -> {ok, #state{}}.
start_experiment(Fabric, Options, Boundary, Timeout) ->
    FabricMonitor = monitor(process, Fabric),
    {Experiment, Commands} = phi_memory_experiment:new(Options),
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    Timer = erlang:send_after(Timeout, self(), experiment_timeout),
    {ok,
        advance(#state{
            fabric = Fabric,
            fabric_monitor = FabricMonitor,
            boundary = Boundary,
            experiment = Experiment,
            timer = Timer,
            deadline = Deadline,
            commands = Commands
        })}.

%% Serialize command completion with experiment events, while always returning
%% to the gen_server loop to service deadlines, monitors, and bounded receipts.
-spec advance(#state{}) -> #state{}.
advance(
    State = #state{
        result = running,
        sending = none,
        commands = [Command | Rest],
        fabric = Fabric,
        boundary = Boundary,
        deadline = Deadline
    }
) ->
    case phi_memory_wire:encode_command(Command, Boundary) of
        {ok, Route, Header, Payload} ->
            Request = hls_fabric:send_request(Fabric, Route, Header, Payload, {abs, Deadline}),
            State#state{commands = Rest, sending = Request};
        {error, Reason} ->
            finish({error, {send, Reason}}, State)
    end;
advance(
    State = #state{
        result = running,
        sending = none,
        commands = [],
        events = Events,
        fabric = Fabric,
        boundary = Boundary
    }
) ->
    case queue:out(Events) of
        {empty, _} ->
            State;
        {{value, {Receipt, Route, Header, Payload}}, Rest} ->
            Next =
                case phi_memory_wire:decode_event(Route, Header, Payload, Boundary) of
                    {ok, Stream, Event} -> consume(Stream, Event, State#state{events = Rest});
                    {error, Reason} -> finish({error, {wire, Reason}}, State#state{events = Rest})
                end,
            hls_fabric:ack(Fabric, Receipt),
            advance(Next)
    end;
advance(State) ->
    State.

%% Apply one decoded event to the pure reducer and retain its commands or finalize its terminal result.
-spec consume(phi_memory_experiment:stream(), tuple(), #state{}) -> #state{}.
consume(Stream, Event, State = #state{experiment = Experiment}) ->
    case phi_memory_experiment:event(Stream, Event, Experiment) of
        {Updated, Commands} ->
            State#state{experiment = Updated, commands = Commands};
        {done, Witness, Updated} ->
            finish({ok, Witness}, State#state{experiment = Updated});
        {error, Reason, Updated} ->
            finish({error, {experiment, Reason}}, State#state{experiment = Updated})
    end.

%% Claim each lossless output for this runner, stopping at the first broker registration error.
-spec register_routes(pid(), phi_memory_boundary:contract()) -> ok | {error, term()}.
register_routes(Fabric, Boundary) ->
    lists:foldl(
        fun
            ({Route, _Stream}, ok) ->
                hls_fabric:register_route(Fabric, Route, self());
            ({_Route, _Stream}, {error, _Reason} = Error) ->
                Error
        end,
        ok,
        phi_memory_wire:event_routes(Boundary)
    ).

%% Release buffered receive receipts and waiters, cancel outstanding work, and retain the same terminal result for later await calls.
-spec finish(completion(), #state{}) -> #state{}.
finish(
    Result,
    State = #state{
        timer = Timer,
        waiters = Waiters,
        events = Events,
        fabric = Fabric,
        sending = Request
    }
) ->
    erlang:cancel_timer(Timer),
    abandon_send(Request),
    [hls_fabric:ack(Fabric, Receipt) || {Receipt, _, _, _} <- queue:to_list(Events)],
    lists:foreach(fun(From) -> gen_server:reply(From, Result) end, Waiters),
    State#state{result = Result, waiters = [], events = queue:new(), commands = [], sending = none}.

%% Expire a pending request alias without waiting or retrying a command whose delivery may already have occurred.
-spec abandon_send(none | gen_server:request_id()) -> ok.
abandon_send(none) ->
    ok;
abandon_send(Request) ->
    gen_server:receive_response(Request, 0),
    ok.
