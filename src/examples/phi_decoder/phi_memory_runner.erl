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
""".

-behavior(gen_server).

-export([start_link/3, stop/1, await/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

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

init({Fabric, Options = #{distance := Distance}, Timeout})
        when Timeout > 0 ->
    Boundary = phi_memory_boundary:contract(Distance),
    case register_routes(Fabric, Boundary) of
        ok ->
            start_experiment(Fabric, Options, Boundary, Timeout);
        {error, Reason} ->
            {stop, {routes, Reason}}
    end.

handle_call(await, From, State = #state{result = running, waiters = Waiters}) ->
    {noreply, State#state{waiters = [From | Waiters]}};
handle_call(await, _From, State = #state{result = Result}) ->
    {reply, Result, State};
handle_call(Request, _From, State) ->
    {reply, {error, {call, Request}}, State}.

handle_cast({?FABRIC_RX, Receipt, Route, Header, Payload},
        State = #state{result = running, events = Events}) ->
    {noreply, advance(State#state{events = queue:in({Receipt, Route, Header, Payload}, Events)})};
handle_cast({?FABRIC_RX, Receipt, _Route, _Header, _Payload}, State = #state{fabric = Fabric}) ->
    hls_fabric:ack(Fabric, Receipt),
    {noreply, State};
handle_cast(_Message, State = #state{result = Result}) when Result =/= running ->
    {noreply, State};
handle_cast(Message, State) -> {noreply, finish({error, {cast, Message}}, State)}.

handle_info(experiment_timeout, State = #state{result = running}) ->
    {noreply, finish({error, timeout}, State)};
handle_info(experiment_timeout, State) -> {noreply, State};
handle_info({'DOWN', Monitor, process, Fabric, Reason},
        State = #state{result = running, fabric = Fabric, fabric_monitor = Monitor}) ->
    {noreply, finish({error, {fabric_down, Reason}}, State)};
handle_info(_Message, State = #state{result = Result}) when Result =/= running ->
    {noreply, State};
handle_info(Message, State = #state{sending = Request}) when Request =/= none ->
    case gen_server:check_response(Message, Request) of
        {reply, ok} -> {noreply, advance(State#state{sending = none})};
        {reply, {error, Reason}} -> {noreply, finish({error, {send, Reason}}, State#state{sending = none})};
        {error, {Reason, _Fabric}} -> {noreply, finish({error, {fabric_down, Reason}}, State#state{sending = none})};
        no_reply -> {noreply, finish({error, {info, Message}}, State)}
    end;
handle_info(Message, State) -> {noreply, finish({error, {info, Message}}, State)}.

terminate(_Reason, #state{timer = Timer, fabric_monitor = Monitor, sending = Request}) ->
    erlang:cancel_timer(Timer),
    abandon_send(Request),
    demonitor(Monitor, [flush]),
    ok.

start_experiment(Fabric, Options, Boundary, Timeout) ->
    FabricMonitor = monitor(process, Fabric),
    {Experiment, Commands} = phi_memory_experiment:new(Options),
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    Timer = erlang:send_after(Timeout, self(), experiment_timeout),
    {ok, advance(#state{fabric = Fabric, fabric_monitor = FabricMonitor,
        boundary = Boundary, experiment = Experiment, timer = Timer,
        deadline = Deadline, commands = Commands})}.

%% Serialize command completion with experiment events, while always returning
%% to the gen_server loop to service deadlines, monitors, and bounded receipts.
advance(State = #state{result = running, sending = none, commands = [Command | Rest],
        fabric = Fabric, boundary = Boundary, deadline = Deadline}) ->
    case phi_memory_wire:encode_command(Command, Boundary) of
        {ok, Route, Header, Payload} ->
            Request = hls_fabric:send_request(Fabric, Route, Header, Payload, {abs, Deadline}),
            State#state{commands = Rest, sending = Request};
        {error, Reason} -> finish({error, {send, Reason}}, State)
    end;
advance(State = #state{result = running, sending = none, commands = [], events = Events,
        fabric = Fabric, boundary = Boundary}) ->
    case queue:out(Events) of
        {empty, _} -> State;
        {{value, {Receipt, Route, Header, Payload}}, Rest} ->
            Next = case phi_memory_wire:decode_event(Route, Header, Payload, Boundary) of
                {ok, Stream, Event} -> consume(Stream, Event, State#state{events = Rest});
                {error, Reason} -> finish({error, {wire, Reason}}, State#state{events = Rest})
            end,
            hls_fabric:ack(Fabric, Receipt),
            advance(Next)
    end;
advance(State) -> State.

consume(Stream, Event, State = #state{experiment = Experiment}) ->
    case phi_memory_experiment:event(Stream, Event, Experiment) of
        {Updated, Commands} -> State#state{experiment = Updated, commands = Commands};
        {done, Witness, Updated} -> finish({ok, Witness}, State#state{experiment = Updated});
        {error, Reason, Updated} -> finish({error, {experiment, Reason}}, State#state{experiment = Updated})
    end.

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

finish(Result, State = #state{timer = Timer, waiters = Waiters, events = Events,
        fabric = Fabric, sending = Request}) ->
    erlang:cancel_timer(Timer),
    abandon_send(Request),
    [hls_fabric:ack(Fabric, Receipt) || {Receipt, _, _, _} <- queue:to_list(Events)],
    lists:foreach(fun(From) -> gen_server:reply(From, Result) end, Waiters),
    State#state{result = Result, waiters = [], events = queue:new(), commands = [], sending = none}.

abandon_send(none) -> ok;
abandon_send(Request) -> gen_server:receive_response(Request, 0), ok.
