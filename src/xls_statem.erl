%%%% xls_statem
%%%%
%% TODO: Add a fixed-shape synchronous call/reply contract once its response
%% path and bounded lifetime have a lowerable representation.
%% TODO: Evaluate bounded subsets of gen_statem timeouts and next_event
%% actions instead of growing ad hoc alternatives.

-module(xls_statem).
-moduledoc """
A bounded CPU reference scheduler for XLS state machines.

An `xls_statem` callback separates its finite-control `Phase` atom from its
rich `Data` value. The CPU scheduler in this module defines the ordering and
postponement rules shared with the generated implementation.

## Callbacks

`init/1` returns the initial phase and data:

```
{ok, Phase, Data}
```

The initial phase is entered when the output ports are connected. Every later
change of the phase atom also invokes `handle_enter/3` once, before postponed
messages are retried:

```
handle_enter(OldPhase, Phase, Data) -> {NextData, Casts}
```

`OldPhase` equals `Phase` for the initial entry. `Casts` is a bounded list of
`{cast, Port, Message}` actions. Each configured port may occur at most once
in an entry. On the CPU each action is delivered with `gen_server:cast/2` to
the PID configured for that port.

Passing `{outputs, Map}` in the options to `start_link/3` connects and enters
the initial phase immediately. A cyclic CPU topology can instead start all of
its machines without that option and then call `connect/2` on each one. Casts
received before connection occupy the bounded mailbox and are processed after
initial entry.
Disconnection is a scheduler lifecycle state separate from the callback phase;
no application callback is dispatched while the machine is disconnected.
The generated implementation has statically connected ports and therefore
enters its initial phase on startup.

`handle_cast/3` receives one application message and returns one fixed-shape
conclusion:

```
{NextPhase, NextData, Directive}
```

It may instead request an explicit same-phase scheduling boundary:

```
{repeat_phase, NextData, consume}
```

This consumes the input, invokes `handle_enter(Phase, Phase, NextData)` once,
and then retries all postponed inputs in arrival order. `repeat_phase` is a
reserved result atom and may only be combined with `consume`. Returning the
current phase in the ordinary conclusion does not enter it again or retry
postponed input. This is deliberately stronger than `gen_statem`'s
`repeat_state`: `repeat_phase` begins a new postponement generation, while
`repeat_state` does not make postponed events eligible.

Clauses for the same message record and phase are tried in source order. The
body of the first clause whose supported head and guard sequence match is
selected; a failure in that body does not resume the clause search.

The directive determines what happens to the input:

  * `consume` removes it from the bounded mailbox.
  * `postpone` retains it until a real phase change or an explicit
    `repeat_phase` boundary.
  * `fail` installs the returned phase and data for diagnostics, then stops.

This API borrows phase-entry and postponed-event ordering from `gen_statem`,
but it is deliberately smaller and is not callback-compatible with OTP.

## Postponement

The scheduler tries the oldest eligible input. Changing `Data`, or returning
the same phase in an ordinary conclusion, does not retry a postponed message.
On a real phase change or an explicit `repeat_phase` boundary, the phase is
entered first and all postponed messages then become eligible again in arrival
order.

## Capacity and failure

Postponed messages retain mailbox capacity. The configured capacity must leave
room for a message capable of advancing the phase, or the protocol can deadlock
under backpressure. On the CPU, mailbox overflow stops the process. Missing
callback clauses, callback exceptions, ordinary non-cast process messages,
invalid callback results, and `fail` directives stop it as well.

The ordinary BEAM mailbox sits in front of this bounded queue, so this module
models scheduling semantics rather than host-side admission guarantees.
""".

-behavior(gen_server).

-export([start_link/3, connect/2, stop/1, cast/2, info/1]).
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).
-export_type([
    phase/0,
    output_port/0,
    directive/0,
    conclusion/0,
    cast_action/0,
    enter_result/0
]).

%%%
%%% Callback contract
%%%

-type phase() :: atom().
-type lifecycle() :: disconnected | connected.
-type output_port() :: atom().
-type data() :: term().
-type directive() :: consume | postpone | fail.
-type conclusion() ::
    {
        NextPhase :: phase(),
        NextData :: data(),
        directive()
    } |
    {
        repeat_phase,
        NextData :: data(),
        consume
    }.
-type cast_action() :: {cast, output_port(), term()}.
-type enter_result() :: {NextData :: data(), [cast_action()]}.
-type start_option() ::
    {mailbox_capacity, 1..255} |
    {outputs, #{output_port() := pid()}}.

-callback init(term()) -> {
    ok,
    InitialPhase :: phase(),
    InitialData :: data()
}.
-callback handle_enter(OldPhase :: phase(), phase(), data()) -> enter_result().
-callback handle_cast(term(), phase(), data()) -> conclusion().
-callback terminate(term(), phase(), data()) -> term().

-optional_callbacks([terminate/3]).

-record(runtime, {
    module :: module(),
    lifecycle = disconnected :: lifecycle(),
    phase :: phase(),
    data :: data(),
    outputs = #{} :: #{output_port() := pid()},
    mailbox :: xls_mailbox:mailbox(),
    postponed = #{} :: #{non_neg_integer() => true},
    next_message_id = 0 :: non_neg_integer()
}).

%%%
%%% Client interface
%%%

-doc "Starts a machine with a required mailbox capacity and optional outputs.".
-spec start_link(module(), term(), [start_option()]) ->
    gen_server:start_ret().
start_link(Module, Arg, Options) ->
    {Capacity, Outputs} = start_options(Options),
    gen_server:start_link(?MODULE, {Module, Arg, Capacity, Outputs}, []).

-doc "Connects deferred outputs and enters the initial phase.".
%% TODO: Define topology ownership and reconnection after a supervised restart;
%% a restarted deferred machine has no output map until it is connected again.
-spec connect(pid(), #{output_port() := pid()}) ->
    ok | {error, already_connected}.
connect(PID, Outputs) ->
    case valid_outputs(Outputs) of
        true -> gen_server:call(PID, {connect, Outputs});
        false -> error(badarg)
    end.

-spec stop(pid()) -> ok.
stop(PID) ->
    gen_server:stop(PID).

-doc "Asynchronously casts one application message to the CPU scheduler.".
-spec cast(pid(), term()) -> ok.
cast(PID, Message) ->
    gen_server:cast(PID, Message).

-doc "Returns the lifecycle, phase, callback data, and queue counters.".
-spec info(pid()) -> map().
info(PID) ->
    format_info(sys:get_state(PID)).

%%%
%%% gen_server callbacks
%%%

init({Module, Arg, Capacity, Outputs}) ->
    {ok, Phase, Data} = Module:init(Arg),
    ok = validate_phase(Phase),
    {Lifecycle, OutputMap} = case Outputs of
        undefined -> {disconnected, #{}};
        _ -> {connected, Outputs}
    end,
    Runtime0 = #runtime{
        module = Module,
        lifecycle = Lifecycle,
        phase = Phase,
        data = Data,
        outputs = OutputMap,
        mailbox = xls_mailbox:new(Capacity)
    },
    case Lifecycle of
        disconnected -> {ok, Runtime0};
        connected -> {ok, enter_phase(Phase, Runtime0)}
    end.

%% Synchronous calls deliberately fail instead of masquerading as casts.
%% The TODO at the top records the missing lowerable call/reply contract.
handle_call({connect, Outputs}, _From,
        Runtime0 = #runtime{lifecycle = disconnected, phase = Phase}) ->
    Connected = Runtime0#runtime{
        lifecycle = connected,
        outputs = Outputs
    },
    Runtime1 = enter_phase(Phase, Connected),
    case process_messages(Runtime1) of
        {ok, Runtime2} -> {reply, ok, Runtime2};
        {stop, Reason, Runtime2} ->
            {stop, Reason, {error, Reason}, Runtime2}
    end;
handle_call({connect, _Outputs}, _From, Runtime) ->
    {reply, {error, already_connected}, Runtime};
handle_call(Request, _From, Runtime) ->
    {stop, {unsupported_xls_statem_call, Request},
        {error, unsupported_call}, Runtime}.

handle_cast(Message, Runtime0) ->
    admit_and_process(Message, Runtime0).

handle_info(Message, Runtime) ->
    {stop, {unsupported_xls_statem_info, Message}, Runtime}.

terminate(Reason, #runtime{
    module = Module,
    phase = Phase,
    data = Data
}) ->
    %% Host-side diagnostic hook; it is not part of the lowered callback.
    case erlang:function_exported(Module, terminate, 3) of
        true -> Module:terminate(Reason, Phase, Data);
        false -> ok
    end.

code_change(_OldVersion, _Runtime, _Extra) ->
    {error, xls_statem_code_change_not_supported}.

%%%
%%% Bounded scheduling
%%%

admit_and_process(Message, Runtime0 = #runtime{lifecycle = disconnected}) ->
    case enqueue(Message, Runtime0) of
        {ok, Runtime1} -> {noreply, Runtime1};
        {error, full} -> {stop, {mailbox_full, Message}, Runtime0}
    end;
admit_and_process(Message, Runtime0 = #runtime{lifecycle = connected}) ->
    case enqueue(Message, Runtime0) of
        {ok, Runtime1} ->
            case process_messages(Runtime1) of
                {ok, Runtime2} -> {noreply, Runtime2};
                {stop, Reason, Runtime2} -> {stop, Reason, Runtime2}
            end;
        {error, full} ->
            {stop, {mailbox_full, Message}, Runtime0}
    end.

enqueue(Message, Runtime = #runtime{
    mailbox = Mailbox0,
    next_message_id = MessageID
}) ->
    Generation = maps:get(generation, xls_mailbox:info(Mailbox0)),
    case xls_mailbox:reserve(Generation, self(), Mailbox0) of
        {error, full, _Mailbox} ->
            {error, full};
        {ok, Reservation, Mailbox1} ->
            Entry = {MessageID, Message},
            {ok, Mailbox2} = xls_mailbox:commit(
                Reservation,
                Entry,
                Mailbox1
            ),
            {ok, Runtime#runtime{
                mailbox = Mailbox2,
                next_message_id = MessageID + 1
            }}
    end.

process_messages(Runtime = #runtime{
    mailbox = Mailbox,
    postponed = Postponed
}) ->
    Eligible = fun({MessageID, _Message}) ->
        not maps:is_key(MessageID, Postponed)
    end,
    case xls_mailbox:select([Eligible], Mailbox) of
        none ->
            {ok, Runtime};
        {ok, Selection, 1, Entry} ->
            process_message(Selection, Entry, Runtime)
    end.

process_message(
    Selection,
    {MessageID, Message},
    Runtime = #runtime{
        module = Module,
        phase = Phase,
        data = Data,
        mailbox = Mailbox0,
        postponed = Postponed0
    }
) ->
    case Module:handle_cast(Message, Phase, Data) of
        {repeat_phase, NextData, consume} ->
            {ok, {MessageID, Message}, Mailbox1} =
                xls_mailbox:consume(Selection, Mailbox0),
            finish_repeat(
                Phase,
                Runtime#runtime{
                    data = NextData,
                    mailbox = Mailbox1,
                    postponed = maps:remove(MessageID, Postponed0)
                }
            );
        {repeat_phase, _NextData, Directive} ->
            error({bad_xls_statem_conclusion, repeat_phase, Directive});
        {NextPhase, NextData, Directive} ->
            ok = validate_conclusion(NextPhase, Directive),
            NextRuntime0 = Runtime#runtime{
                phase = NextPhase,
                data = NextData
            },
            case Directive of
                fail ->
                    {stop, {xls_statem_failure, Message}, NextRuntime0};
                postpone ->
                    finish_transition(
                        Phase,
                        NextRuntime0#runtime{
                            postponed = Postponed0#{MessageID => true}
                        }
                    );
                consume ->
                    {ok, {MessageID, Message}, Mailbox1} =
                        xls_mailbox:consume(Selection, Mailbox0),
                    finish_transition(
                        Phase,
                        NextRuntime0#runtime{
                            mailbox = Mailbox1,
                            postponed = maps:remove(MessageID, Postponed0)
                        }
                    )
            end
    end.

finish_transition(PreviousPhase, Runtime0 = #runtime{phase = Phase}) ->
    Runtime1 = case Phase =/= PreviousPhase of
        true ->
            Entered = enter_phase(PreviousPhase, Runtime0),
            Entered#runtime{postponed = #{}};
        false ->
            Runtime0
    end,
    process_messages(Runtime1).

finish_repeat(Phase, Runtime0) ->
    Entered = enter_phase(Phase, Runtime0),
    process_messages(Entered#runtime{postponed = #{}}).

%%%
%%% Phase entry and validation
%%%

enter_phase(OldPhase, Runtime = #runtime{
    module = Module,
    lifecycle = connected,
    phase = Phase,
    data = Data,
    outputs = Outputs
}) ->
    {NextData, Casts} = Module:handle_enter(OldPhase, Phase, Data),
    ok = validate_casts(Casts, Outputs),
    lists:foreach(
        fun({cast, Port, Message}) ->
            gen_server:cast(maps:get(Port, Outputs), Message)
        end,
        Casts
    ),
    Runtime#runtime{data = NextData}.

validate_conclusion(NextPhase, Directive)
        when is_atom(NextPhase), NextPhase =/= repeat_phase,
             (Directive =:= consume orelse
              Directive =:= postpone orelse
              Directive =:= fail) ->
    ok;
validate_conclusion(NextPhase, Directive) ->
    error({bad_xls_statem_conclusion, NextPhase, Directive}).

validate_phase(Phase) when is_atom(Phase), Phase =/= repeat_phase ->
    ok;
validate_phase(Phase) ->
    error({bad_xls_statem_phase, Phase}).

validate_casts(Casts, Outputs) when is_list(Casts) ->
    Ports = lists:map(
        fun
            ({cast, Port, _Message}) when is_atom(Port) ->
                case maps:is_key(Port, Outputs) of
                    true -> Port;
                    false -> error({unknown_xls_statem_output, Port})
                end;
            (Action) ->
                error({bad_xls_statem_action, Action})
        end,
        Casts
    ),
    case length(Ports) =:= length(lists:usort(Ports)) of
        true -> ok;
        false -> error({duplicate_xls_statem_ports, Ports})
    end;
validate_casts(Actions, _Outputs) ->
    error({bad_xls_statem_actions, Actions}).

%%%
%%% Options and diagnostics
%%%

format_info(#runtime{
    lifecycle = Lifecycle,
    phase = Phase,
    data = Data,
    outputs = Outputs,
    mailbox = Mailbox,
    postponed = Postponed
}) ->
    #{
        lifecycle => Lifecycle,
        phase => Phase,
        data => Data,
        connected => Lifecycle =:= connected,
        outputs => output_names(Outputs),
        postponed => map_size(Postponed),
        mailbox => xls_mailbox:info(Mailbox)
    }.

start_options(Options) ->
    Known = lists:all(
        fun
            ({mailbox_capacity, _Capacity}) -> true;
            ({outputs, _Outputs}) -> true;
            (_Option) -> false
        end,
        Options
    ),
    Capacity = proplists:get_value(mailbox_capacity, Options),
    Outputs = proplists:get_value(outputs, Options, undefined),
    ValidOutputs = Outputs =:= undefined orelse valid_outputs(Outputs),
    case Known andalso
            is_integer(Capacity) andalso
            Capacity > 0 andalso Capacity =< 255 andalso
            ValidOutputs of
        true -> {Capacity, Outputs};
        false -> error(badarg)
    end.

valid_outputs(Outputs) when is_map(Outputs) ->
    maps:fold(
        fun(Port, PID, Valid) ->
            Valid andalso is_atom(Port) andalso is_pid(PID)
        end,
        true,
        Outputs
    );
valid_outputs(_Outputs) ->
    false.

output_names(Outputs) ->
    lists:sort(maps:keys(Outputs)).
