%%%% phi_memory_runner
%%%%
%%%% ERTS coordinator for one directly attached phi memory experiment.

-module(phi_memory_runner).
-moduledoc """
Runs one phi memory closeout over an `hls_fabric` process.

The runner owns every routed phi output, continuously decodes those streams,
feeds `phi_memory_experiment`, and submits each returned spatial command before
processing another event. It performs no retry: a malformed frame, failed
write, fabric exit, or timeout terminates the experiment result. A fabric exit
is reported as `{error, {fabric_down, Reason}}`, where `Reason` is its OTP exit
reason. In particular, a Pauli update is never repeated after ambiguous
transport failure.

The simulation releases reset before ERTS connects. Its gateway holds every
topology output until the first valid host command, and the runner chooses a
future cutoff step so the command can take effect before that round. A real
loader should make activation an explicit manifest-owned handshake and replace
the explicit distance argument without changing the reducer.

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
    result = running :: running | {ok, 0 | 1} | {error, term()},
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
-spec await(pid()) -> {ok, 0 | 1} | {error, term()}.
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

handle_cast(
    {?FABRIC_RX, Route, Header, Payload},
    State = #state{result = running, boundary = Boundary}
) ->
    case phi_memory_wire:decode_event(Route, Header, Payload, Boundary) of
        {ok, Stream, Event} ->
            consume(Stream, Event, State);
        {error, Reason} ->
            {noreply, finish({error, {wire, Reason}}, State)}
    end;
handle_cast({?FABRIC_RX, _Route, _Header, _Payload}, State) ->
    {noreply, State};
handle_cast(_Message, State = #state{result = Result})
        when Result =/= running ->
    {noreply, State};
handle_cast(Message, State = #state{result = running}) ->
    {noreply, finish({error, {cast, Message}}, State)}.

handle_info(experiment_timeout, State = #state{result = running}) ->
    {noreply, finish({error, timeout}, State)};
handle_info(experiment_timeout, State) ->
    {noreply, State};
handle_info(
    {'DOWN', Monitor, process, Fabric, Reason},
    State = #state{
        result = running,
        fabric = Fabric,
        fabric_monitor = Monitor
    }
) ->
    {noreply, finish({error, {fabric_down, Reason}}, State)};
handle_info({'DOWN', _Monitor, process, _Pid, _Reason}, State) ->
    {noreply, State};
handle_info(_Message, State = #state{result = Result})
        when Result =/= running ->
    {noreply, State};
handle_info(Message, State = #state{result = running}) ->
    {noreply, finish({error, {info, Message}}, State)}.

terminate(_Reason, #state{timer = Timer, fabric_monitor = Monitor}) ->
    erlang:cancel_timer(Timer),
    demonitor(Monitor, [flush]),
    ok.

start_experiment(Fabric, Options, Boundary, Timeout) ->
    FabricMonitor = monitor(process, Fabric),
    {Experiment, Commands} = phi_memory_experiment:new(Options),
    case send_commands(Commands, Fabric, Boundary) of
        ok ->
            Timer = erlang:send_after(Timeout, self(), experiment_timeout),
            {ok, #state{
                fabric = Fabric,
                fabric_monitor = FabricMonitor,
                boundary = Boundary,
                experiment = Experiment,
                timer = Timer
            }};
        {error, Reason} ->
            {stop, {send, Reason}}
    end.

consume(Stream, Event, State = #state{
    experiment = Experiment,
    fabric = Fabric,
    boundary = Boundary
}) ->
    case phi_memory_experiment:event(Stream, Event, Experiment) of
        {Updated, Commands} ->
            case send_commands(Commands, Fabric, Boundary) of
                ok -> {noreply, State#state{experiment = Updated}};
                {error, Reason} ->
                    {noreply, finish({error, {send, Reason}}, State)}
            end;
        {done, Parity, Updated} ->
            Done = State#state{experiment = Updated},
            {noreply, finish({ok, Parity}, Done)};
        {error, Reason, Updated} ->
            Failed = State#state{experiment = Updated},
            {noreply, finish({error, {experiment, Reason}}, Failed)}
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

send_commands(Commands, Fabric, Boundary) ->
    lists:foldl(
        fun
            (Command, ok) -> send_command(Command, Fabric, Boundary);
            (_Command, {error, _Reason} = Error) -> Error
        end,
        ok,
        Commands
    ).

send_command(Command, Fabric, Boundary) ->
    case phi_memory_wire:encode_command(Command, Boundary) of
        {ok, Route, Header, Payload} ->
            hls_fabric:send(Fabric, Route, Header, Payload);
        {error, _Reason} = Error ->
            Error
    end.

finish(Result, State = #state{timer = Timer, waiters = Waiters}) ->
    erlang:cancel_timer(Timer),
    lists:foreach(fun(From) -> gen_server:reply(From, Result) end, Waiters),
    State#state{result = Result, waiters = []}.
