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
Data)` before retrying postponed messages. Entry returns `{NextData, Actions}`.
`OldPhase` equals `Phase` for initial entry.

`Actions` is a bounded list. It may begin with one
`{open_reduction, Name, Key, Population, {commutative_monoid, Identity}}`
action, followed by `{cast, Port, Message}` actions. A statically
placed `{cast_if, Condition, Port, Message}` retains its ordered position but
emits only when enabled. Ports and list shape remain static, and each port may
occur at most once in an entry. CPU output uses ordinary `gen_server:cast/2`.

The complete entry callback must succeed before its actions can be emitted.
A disabled `cast_if` still evaluates its condition and message. In XLS, a
supported match failure anywhere in the callback preserves the incoming entry
data and reduction state, emits no effects from that entry, and latches the
actor's existing failed state until reset. Earlier successful entries are not
rolled back. The CPU runtime instead terminates on the callback exception.

Successful hardware entries retain ordered effect completion: the direct
service commits entry data and a new reduction after its last allocated effect
slot; shared execution commits them when its whole effect batch is accepted.
Both paths defer mailbox dispatch until entry finishes. See
`docs/entry-outcomes.md` for the entry execution contract and test procedure.

An open reduction accepts either a fixed contribution count or a fixed member
set. A cast clause contributes through the ordinary conclusion's directive:

```
{Phase, Data, {contribute, Name, Key, Value}}
{Phase, Data, {contribute, Name, Key, Member, Value}}
```

The phase and data must be unchanged. Accepted values are combined by the
callback module's `reduce(Name, Accumulator, Value)` function. The final value
is delivered privately as
`Phase(internal, {reduction_complete, Name, Key, Value}, Data)` before another
external mailbox entry is selected. Internal handlers use the ordinary fixed
conclusion shape, but may only consume, fail, change phase, or repeat it.

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
`repeat_phase`, `reduce`, and `terminate` are reserved phase names; the latter
two would collide with reduction and diagnostic callbacks at arity three.

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
for generic contexts, but that union does not retain the event/result pairing;
its `event_type/0` argument is intentionally an over-approximation. Only a
phase that can complete a reduction needs an `internal` clause.

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
Calls, timeouts, `next_event`, and other OTP result/action forms are not
supported. See `docs/actor-reductions.md` for reduction semantics and the
staged lowering design.

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
    entry_action/0,
    open_reduction_action/0,
    reduction_complete/0,
    reduction_population/0,
    reduction_operator/0,
    contribution/0,
    enter_result/0,
    enter_result/1,
    internal_result/0,
    internal_result/1,
    internal_result/2
]).

%%%
%%% Callback contract
%%%

-type phase() :: atom().
-type lifecycle() :: disconnected | connected.
-type output_port() :: atom().
-type data() :: term().
-type event_type() :: enter | cast | internal.
-type cast_action() ::
    {cast, output_port(), term()} |
    {cast_if, boolean(), output_port(), term()}.
-type reduction_population() ::
    {count, 1..255} |
    {members, [term(), ...]}.
-type reduction_operator() :: {
    commutative_monoid,
    Identity :: term()
}.
-type open_reduction_action() :: {
    open_reduction,
    Name :: atom(),
    Key :: term(),
    reduction_population(),
    reduction_operator()
}.
-type entry_action() :: cast_action() | open_reduction_action().
-type contribution() ::
    {contribute, Name :: atom(), Key :: term(), Value :: term()} |
    {
        contribute,
        Name :: atom(),
        Key :: term(),
        Member :: term(),
        Value :: term()
    }.
-type reduction_complete() :: {
    reduction_complete,
    Name :: atom(),
    Key :: term(),
    Accumulator :: term()
}.
-type cast_directive() :: consume | postpone | fail | contribution().
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
    Actions :: [entry_action()]
}.
-type internal_result() :: internal_result(phase(), data()).
-type internal_result(DataType) :: internal_result(phase(), DataType).
-type internal_result(PhaseType, DataType) ::
    {
        NextPhase :: PhaseType,
        NextData :: DataType,
        Directive :: consume | fail
    } |
    {repeat_phase, NextData :: DataType, consume}.
-type callback_result() :: callback_result(data()).
-type callback_result(DataType) ::
    enter_result(DataType) |
    cast_result(DataType) |
    internal_result(DataType).
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
    (cast, Message :: term(), Data :: DataType) -> cast_result(DataType);
    (internal, reduction_complete(), Data :: DataType) ->
        internal_result(DataType).
-callback reduce(
    Name :: atom(),
    Left :: Accumulator,
    Right :: Accumulator
) -> Accumulator when Accumulator :: term().
-callback terminate(term(), phase(), data()) -> term().

%% StateName/3 documents the dynamic callback contract. Every runtime phase
%% needs its own Phase/3 function, but none must literally be named StateName.
-optional_callbacks([reduce/3, terminate/3, 'StateName'/3]).

-record(runtime, {
    module :: module(),
    lifecycle = disconnected :: lifecycle(),
    phase :: phase(),
    data :: data(),
    outputs = #{} :: #{output_port() := pid()},
    mailbox :: hls_mailbox:mailbox(),
    postponed = #{} :: #{non_neg_integer() => true},
    next_message_id = 0 :: non_neg_integer(),
    reduction = none :: none | hls_reduction:reduction()
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
        postponed = Postponed0
    }
) ->
    Result = Module:Phase(cast, Message, Data),
    {NextPhase, NextData, Directive, Repeat} =
        state_result(Result, Phase, Data),
    NextRuntime = Runtime#runtime{
        phase = NextPhase,
        data = NextData
    },
    BoundaryStatus = reduction_boundary_status(
        Directive, Repeat, Phase, NextPhase, Runtime
    ),
    case {BoundaryStatus, Directive} of
        {{error, Status}, _} ->
            {stop,
                {hls_statem_reduction_incomplete, Status, Message},
                Runtime};
        {ok, fail} ->
            {stop, {hls_statem_failure, Message}, NextRuntime};
        {ok, postpone} ->
            finish_transition(Phase, NextRuntime#runtime{
                postponed = Postponed0#{MessageID => true}
            });
        {ok, {contribute, _Name, _Key, _Value} = Contribution} ->
            process_contribution(
                Contribution,
                Selection,
                {MessageID, Message},
                Phase,
                Data,
                NextRuntime
            );
        {ok, {contribute, _Name, _Key, _Member, _Value} = Contribution} ->
            process_contribution(
                Contribution,
                Selection,
                {MessageID, Message},
                Phase,
                Data,
                NextRuntime
            );
        {ok, consume} ->
            Consumed = consume_message(
                Selection,
                {MessageID, Message},
                NextRuntime
            ),
            case Repeat of
                true -> finish_repeat(Phase, Consumed);
                false -> finish_transition(Phase, Consumed)
            end
    end.

reduction_boundary_status(_Directive, _Repeat, _Phase, _NextPhase,
        #runtime{reduction = none}) ->
    ok;
reduction_boundary_status(fail, _Repeat, _Phase, _NextPhase, _Runtime) ->
    ok;
reduction_boundary_status(
    {contribute, _Name, _Key, _Value},
    _Repeat,
    _Phase,
    _NextPhase,
    _Runtime
) ->
    ok;
reduction_boundary_status(
    {contribute, _Name, _Key, _Member, _Value},
    _Repeat,
    _Phase,
    _NextPhase,
    _Runtime
) ->
    ok;
reduction_boundary_status(_Directive, Repeat, Phase, NextPhase,
        #runtime{reduction = Reduction}) ->
    case Repeat orelse NextPhase =/= Phase of
        true -> {error, hls_reduction:info(Reduction)};
        false -> ok
    end.

process_internal(Event, Runtime = #runtime{
    module = Module,
    phase = Phase,
    data = Data
}) ->
    Result = Module:Phase(internal, Event, Data),
    {NextPhase, NextData, Directive, Repeat} =
        internal_state_result(Result, Phase),
    NextRuntime = Runtime#runtime{phase = NextPhase, data = NextData},
    case Directive of
        fail ->
            {stop, {hls_statem_failure, Event}, NextRuntime};
        consume when Repeat ->
            finish_repeat(Phase, NextRuntime);
        consume ->
            finish_transition(Phase, NextRuntime)
    end.

process_contribution(
    Contribution,
    Selection,
    Entry = {MessageID, Message},
    Phase,
    Data,
    Runtime = #runtime{
        module = Module,
        phase = Phase,
        data = Data,
        reduction = Reduction,
        postponed = Postponed
    }
) ->
    case apply_contribution(Module, Contribution, Reduction) of
        mismatch ->
            finish_transition(Phase, Runtime#runtime{
                postponed = Postponed#{MessageID => true}
            });
        {pending, NextReduction} ->
            Consumed = consume_message(Selection, Entry, Runtime),
            finish_transition(Phase, Consumed#runtime{
                reduction = NextReduction
            });
        {complete, Completion} ->
            Consumed = consume_message(Selection, Entry, Runtime),
            process_internal(
                Completion,
                Consumed#runtime{reduction = none}
            );
        {error, Reason} ->
            {stop,
                {hls_statem_reduction_failure, Reason, Message},
                Runtime}
    end;
process_contribution(
    _Contribution,
    _Selection,
    _Entry,
    _Phase,
    _Data,
    #runtime{phase = NextPhase, data = NextData}
) ->
    error({bad_hls_statem_contribution_state, NextPhase, NextData}).

apply_contribution(_Module, _Contribution, none) ->
    mismatch;
apply_contribution(
    Module,
    {contribute, Name, Key, Value},
    Reduction
) ->
    hls_reduction:contribute(Module, Name, Key, Value, Reduction);
apply_contribution(
    Module,
    {contribute, Name, Key, Member, Value},
    Reduction
) ->
    hls_reduction:contribute(
        Module,
        Name,
        Key,
        Member,
        Value,
        Reduction
    ).

consume_message(Selection, Entry = {MessageID, _Message}, Runtime = #runtime{
    mailbox = Mailbox,
    postponed = Postponed
}) ->
    {ok, Entry, NextMailbox} = hls_mailbox:consume(Selection, Mailbox),
    Runtime#runtime{
        mailbox = NextMailbox,
        postponed = maps:remove(MessageID, Postponed)
    }.

state_result({repeat_phase, NextData, consume}, Phase, _Data) ->
    {Phase, NextData, consume, true};
state_result({repeat_phase, _NextData, Directive}, _Phase, _Data) ->
    error({bad_hls_statem_conclusion, repeat_phase, Directive});
state_result({NextPhase, NextData, Directive}, _Phase, _Data) ->
    ok = validate_conclusion(NextPhase, Directive),
    {NextPhase, NextData, Directive, false};
state_result(Result, _Phase, _Data) ->
    error({bad_hls_statem_result, Result}).

internal_state_result({repeat_phase, NextData, consume}, Phase) ->
    {Phase, NextData, consume, true};
internal_state_result({repeat_phase, _NextData, Directive}, _Phase) ->
    error({bad_hls_statem_internal_conclusion, repeat_phase, Directive});
internal_state_result({NextPhase, NextData, Directive}, _Phase) ->
    ok = validate_internal_conclusion(NextPhase, Directive),
    {NextPhase, NextData, Directive, false};
internal_state_result(Result, _Phase) ->
    error({bad_hls_statem_internal_result, Result}).

finish_transition(PreviousPhase, Runtime0 = #runtime{phase = Phase}) ->
    Runtime1 = case Phase =/= PreviousPhase of
        true ->
            ok = require_idle_reduction(Runtime0),
            Entered = enter_phase(PreviousPhase, Runtime0),
            Entered#runtime{postponed = #{}};
        false ->
            Runtime0
    end,
    process_messages(Runtime1).

finish_repeat(Phase, Runtime0) ->
    ok = require_idle_reduction(Runtime0),
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
    outputs = Outputs,
    reduction = Reduction
}) ->
    Result = Module:Phase(enter, OldPhase, Data),
    {NextData, Actions} = enter_result(Result),
    {NextReduction, Casts} = prepare_entry_actions(
        Module,
        Actions,
        Outputs,
        Reduction
    ),
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
    Runtime#runtime{data = NextData, reduction = NextReduction}.

enter_result({NextData, Casts}) -> {NextData, Casts};
enter_result(Result) -> error({bad_hls_statem_enter_result, Result}).

validate_conclusion(NextPhase, Directive)
        when is_atom(NextPhase), NextPhase =/= repeat_phase,
             NextPhase =/= reduce, NextPhase =/= terminate,
             (Directive =:= consume orelse
              Directive =:= postpone orelse
              Directive =:= fail) ->
    ok;
validate_conclusion(NextPhase, {contribute, Name, _Key, _Value})
        when is_atom(NextPhase), NextPhase =/= repeat_phase,
             NextPhase =/= reduce, NextPhase =/= terminate, is_atom(Name) ->
    ok;
validate_conclusion(
    NextPhase,
    {contribute, Name, _Key, _Member, _Value}
)
        when is_atom(NextPhase), NextPhase =/= repeat_phase,
             NextPhase =/= reduce, NextPhase =/= terminate, is_atom(Name) ->
    ok;
validate_conclusion(NextPhase, Directive) ->
    error({bad_hls_statem_conclusion, NextPhase, Directive}).

validate_internal_conclusion(NextPhase, Directive)
        when is_atom(NextPhase), NextPhase =/= repeat_phase,
             NextPhase =/= reduce, NextPhase =/= terminate,
             (Directive =:= consume orelse Directive =:= fail) ->
    ok;
validate_internal_conclusion(NextPhase, Directive) ->
    error({bad_hls_statem_internal_conclusion, NextPhase, Directive}).

validate_phase(Phase)
        when is_atom(Phase), Phase =/= repeat_phase, Phase =/= reduce,
             Phase =/= terminate ->
    ok;
validate_phase(Phase) ->
    error({bad_hls_statem_phase, Phase}).

prepare_entry_actions(Module, Actions, Outputs, Reduction)
        when is_list(Actions) ->
    {NextReduction, Casts} = case Actions of
        [{open_reduction, Name, Key, Population, Operator} | Rest] ->
            case Reduction of
                none -> ok;
                _ -> error({hls_statem_reduction_already_active,
                    reduction_status(Reduction)})
            end,
            case erlang:function_exported(Module, reduce, 3) of
                true -> ok;
                false -> error({missing_hls_statem_callback, reduce, 3})
            end,
            case hls_reduction:open(
                Name,
                Key,
                Population,
                Operator
            ) of
                {ok, Opened} -> {Opened, Rest};
                {error, Reason} ->
                    error({bad_hls_statem_open_reduction, Reason})
            end;
        _ ->
            {Reduction, Actions}
    end,
    case lists:any(
        fun
            ({open_reduction, _, _, _, _}) -> true;
            (_) -> false
        end,
        Casts
    ) of
        true -> error(hls_statem_open_reduction_must_be_first);
        false -> ok
    end,
    ok = validate_casts(Casts, Outputs),
    {NextReduction, Casts};
prepare_entry_actions(
    _Module,
    Actions,
    _Outputs,
    _Reduction
) ->
    error({bad_hls_statem_actions, Actions}).

validate_casts(Casts, Outputs) ->
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
    end.

require_idle_reduction(#runtime{reduction = none}) ->
    ok;
require_idle_reduction(#runtime{reduction = Reduction}) ->
    error({hls_statem_reduction_incomplete,
        reduction_status(Reduction)}).

reduction_status(none) ->
    idle;
reduction_status(Reduction) ->
    hls_reduction:info(Reduction).

%%%
%%% Options and diagnostics
%%%

format_info(#runtime{
    lifecycle = Lifecycle,
    phase = Phase,
    data = Data,
    outputs = Outputs,
    mailbox = Mailbox,
    postponed = Postponed,
    reduction = Reduction
}) ->
    #{
        lifecycle => Lifecycle,
        phase => Phase,
        data => Data,
        connected => Lifecycle =:= connected,
        outputs => output_names(Outputs),
        postponed => map_size(Postponed),
        mailbox => hls_mailbox:info(Mailbox),
        reduction => reduction_status(Reduction)
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
