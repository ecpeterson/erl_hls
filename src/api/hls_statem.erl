%%%% hls_statem
%%%%
%% TODO: Add a fixed-shape synchronous call/reply contract once its response
%% path and bounded lifetime have a lowerable representation.
%% TODO: Evaluate bounded subsets of gen_statem timeouts and next_event
%% actions instead of growing ad hoc alternatives.

-module(hls_statem).
-moduledoc """
A bounded CPU reference scheduler for HLS state machines.

An `hls_statem` callback separates its finite-control `Phase` atom from its
rich `Data` value. The CPU scheduler in this module defines the ordering and
postponement rules shared with the generated implementation.

## Callbacks

The callback module exports `init/1`, returning `{ok, Phase, Data}`, and one
`Phase/3` function for each application phase.

Initial entry and each phase boundary invoke `Module:Phase(enter, OldPhase,
Data)` before retrying postponed messages. Entry returns `{NextData, Casts}`.
`OldPhase` equals `Phase` for initial entry.

`Casts` is a bounded list of `{cast, Port, Message}` actions. A statically
placed `{cast_if, Condition, Port, Message}` retains its ordered position but
emits only when enabled. Ports and list shape remain static, and each port may
occur at most once in an entry. CPU output uses ordinary `gen_server:cast/2`.

Application input invokes `Module:Phase(cast, Message, Data)` and returns one
fixed-shape conclusion:

```
{NextPhase, NextData, consume | postpone | fail}
```

It may instead request an explicit same-phase scheduling boundary:

```
{repeat_phase, NextData, consume}
```

This consumes the input, enters the current phase again, then retries
postponed inputs in arrival order.
`consume` removes the input, `postpone` retains it until a phase boundary, and
`fail` installs the returned phase and diagnostic data before stopping with
`{hls_statem_failure, Message}`. `repeat_phase` is an HLS extension,
deliberately distinct from OTP's `repeat_state`, which does not release
postponed events. Returning the current phase in an ordinary conclusion does
not trigger entry or retries.
`repeat_phase` and `terminate` are reserved phase names; the latter would
collide with the optional diagnostic callback at arity three.

An overloaded Erlang specification can preserve the relationship between the
event kind and its result:

```
-spec waiting(enter, hls_statem:phase(), #cell{}) ->
        hls_statem:enter_result(#cell{});
    (cast, #message{}, #cell{}) ->
        hls_statem:cast_result(#cell{}).
```

The singleton first-argument types make the overload domains disjoint.
`when` cannot express this conditional relationship: it can only add `::`
subtype constraints to type variables. `callback_result/0,1` provide a union
for generic contexts, but that union does not retain the event/result pairing.

Clauses are tried in source order. A failure in a selected body does not resume
clause search. The lowered subset requires literal `enter`/`cast` heads,
record-shaped cast messages, and one unguarded entry clause per phase. A cast
conclusion must currently be the clause's final tuple, `case`, or `if`; the
pre-existing `repeat_phase` adapter cannot yet follow a result through a local
binding or helper call.

Passing `{outputs, Map}` to `start_link/3` connects and enters immediately.
Cyclic CPU topologies can start machines disconnected, then call `connect/2`.
Inputs received before connection occupy the bounded mailbox; no application
callback runs until initial entry. Hardware ports are statically connected.

The callback vocabulary is a restricted `gen_statem` state-functions style.
Calls, timeouts, `next_event`, reductions, and other OTP result/action forms
are not supported. See `docs/actor-reductions.md` for the staged reduction
design.

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
invalid callback results, and explicit failure results stop it as well.

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
    event_type/0,
    cast_result/0,
    cast_result/1,
    cast_result/2,
    callback_result/0,
    callback_result/1,
    cast_action/0,
    enter_result/0,
    enter_result/1
]).

%%%
%%% Callback contract
%%%

-type phase() :: atom().
-type lifecycle() :: disconnected | connected.
-type output_port() :: atom().
-type data() :: term().
-type event_type() :: enter | cast.
-type cast_action() ::
    {cast, output_port(), term()} |
    {cast_if, boolean(), output_port(), term()}.
-type cast_directive() :: consume | postpone | fail.
-type cast_result() :: cast_result(phase(), data()).
-type cast_result(DataType) :: cast_result(phase(), DataType).
-type cast_result(PhaseType, DataType) ::
    {
        NextPhase :: PhaseType,
        NextData :: DataType,
        Directive :: cast_directive()
    } |
    {repeat_phase, NextData :: DataType, consume}.
-type enter_result() :: enter_result(data()).
-type enter_result(DataType) :: {
    NextData :: DataType,
    Casts :: [cast_action()]
}.
-type callback_result() :: callback_result(data()).
-type callback_result(DataType) ::
    enter_result(DataType) | cast_result(DataType).
-type start_option() ::
    {mailbox_capacity, 1..255} |
    {outputs, #{output_port() := pid()}}.

-callback init(term()) -> {
    ok,
    InitialPhase :: phase(),
    InitialData :: data()
}.
-callback 'StateName'(
    enter,
    OldPhase :: phase(),
    Data :: DataType
) -> enter_result(DataType);
    (cast, Message :: term(), Data :: DataType) -> cast_result(DataType).
-callback terminate(term(), phase(), data()) -> term().

%% StateName/3 documents the dynamic callback contract. Every runtime phase
%% needs its own Phase/3 function, but none must literally be named StateName.
-optional_callbacks([terminate/3, 'StateName'/3]).

-record(runtime, {
    module :: module(),
    lifecycle = disconnected :: lifecycle(),
    phase :: phase(),
    data :: data(),
    outputs = #{} :: #{output_port() := pid()},
    mailbox :: hls_mailbox:mailbox(),
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
        mailbox = hls_mailbox:new(Capacity)
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
    {stop, {unsupported_hls_statem_call, Request},
        {error, unsupported_call}, Runtime}.

handle_cast(Message, Runtime0) ->
    admit_and_process(Message, Runtime0).

handle_info(Message, Runtime) ->
    {stop, {unsupported_hls_statem_info, Message}, Runtime}.

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
    {error, hls_statem_code_change_not_supported}.

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
    Generation = maps:get(generation, hls_mailbox:info(Mailbox0)),
    case hls_mailbox:reserve(Generation, self(), Mailbox0) of
        {error, full, _Mailbox} ->
            {error, full};
        {ok, Reservation, Mailbox1} ->
            Entry = {MessageID, Message},
            {ok, Mailbox2} = hls_mailbox:commit(
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
    case hls_mailbox:select([Eligible], Mailbox) of
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
    Result = Module:Phase(cast, Message, Data),
    {NextPhase, NextData, Directive, Repeat} =
        state_result(Result, Phase, Data),
    NextRuntime = Runtime#runtime{phase = NextPhase, data = NextData},
    case Directive of
        fail ->
            {stop, {hls_statem_failure, Message}, NextRuntime};
        postpone ->
            finish_transition(Phase, NextRuntime#runtime{
                postponed = Postponed0#{MessageID => true}
            });
        consume ->
            {ok, {MessageID, Message}, Mailbox1} =
                hls_mailbox:consume(Selection, Mailbox0),
            Consumed = NextRuntime#runtime{
                mailbox = Mailbox1,
                postponed = maps:remove(MessageID, Postponed0)
            },
            case Repeat of
                true -> finish_repeat(Phase, Consumed);
                false -> finish_transition(Phase, Consumed)
            end
    end.

state_result({repeat_phase, NextData, consume}, Phase, _Data) ->
    {Phase, NextData, consume, true};
state_result({repeat_phase, _NextData, Directive}, _Phase, _Data) ->
    error({bad_hls_statem_conclusion, repeat_phase, Directive});
state_result({NextPhase, NextData, Directive}, _Phase, _Data) ->
    ok = validate_conclusion(NextPhase, Directive),
    {NextPhase, NextData, Directive, false};
state_result(Result, _Phase, _Data) ->
    error({bad_hls_statem_result, Result}).

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
    Result = Module:Phase(enter, OldPhase, Data),
    {NextData, Casts} = enter_result(Result),
    ok = validate_casts(Casts, Outputs),
    lists:foreach(
        fun
            ({cast, Port, Message}) ->
                gen_server:cast(maps:get(Port, Outputs), Message);
            ({cast_if, true, Port, Message}) ->
                gen_server:cast(maps:get(Port, Outputs), Message);
            ({cast_if, false, _Port, _Message}) ->
                ok
        end,
        Casts
    ),
    Runtime#runtime{data = NextData}.

enter_result({NextData, Casts}) -> {NextData, Casts};
enter_result(Result) -> error({bad_hls_statem_enter_result, Result}).

validate_conclusion(NextPhase, Directive)
        when is_atom(NextPhase), NextPhase =/= repeat_phase,
             NextPhase =/= terminate,
             (Directive =:= consume orelse
              Directive =:= postpone orelse
              Directive =:= fail) ->
    ok;
validate_conclusion(NextPhase, Directive) ->
    error({bad_hls_statem_conclusion, NextPhase, Directive}).

validate_phase(Phase)
        when is_atom(Phase), Phase =/= repeat_phase, Phase =/= terminate ->
    ok;
validate_phase(Phase) ->
    error({bad_hls_statem_phase, Phase}).

validate_casts(Casts, Outputs) when is_list(Casts) ->
    Ports = lists:map(
        fun
            ({cast, Port, _Message}) when is_atom(Port) ->
                case maps:is_key(Port, Outputs) of
                    true -> Port;
                    false -> error({unknown_hls_statem_output, Port})
                end;
            ({cast_if, Enabled, Port, _Message})
                    when is_boolean(Enabled), is_atom(Port) ->
                case maps:is_key(Port, Outputs) of
                    true -> Port;
                    false -> error({unknown_hls_statem_output, Port})
                end;
            (Action) ->
                error({bad_hls_statem_action, Action})
        end,
        Casts
    ),
    case length(Ports) =:= length(lists:usort(Ports)) of
        true -> ok;
        false -> error({duplicate_hls_statem_ports, Ports})
    end;
validate_casts(Actions, _Outputs) ->
    error({bad_hls_statem_actions, Actions}).

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
        mailbox => hls_mailbox:info(Mailbox)
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
