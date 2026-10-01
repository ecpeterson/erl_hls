%%%% hls_statem
%%%%
%% TODO: Evaluate bounded subsets of gen_statem timeouts.

-module(hls_statem).
-moduledoc """
A bounded CPU reference scheduler for HLS state machines.

Callbacks separate finite-control `Phase` from typed `Data`. `init/1` returns
`{ok, Phase, Data}`; each `Phase/3` handles entry, casts, declared calls and
private internal events. Translation requires one unguarded `init([])` clause
and one entry clause per phase.

`Phase(enter, OldPhase, Data)` returns `{NextData, Actions}`. Entry actions are
bounded casts, optionally preceded by one `open_reduction` or `open_gather` action. A complete
entry must succeed before any of its effects are emitted. See
`docs/entry-outcomes.md` and `docs/actor-reductions.md`.

`Phase(cast, Record, Data)` returns `{NextPhase, NextData, Directive}`.
`consume` removes the input; `postpone` retains it until a phase boundary;
`fail` stops the actor. Reduction contributions use a structured directive.
`{repeat_phase, NextData, consume}` explicitly reenters the current phase and
retries postponed inputs. Returning the current phase normally does neither.

With `-hls_continuations([Name, ...])`, a consuming cast or named internal
callback may append `[{next_event, internal, Name}]` as a fourth result field.
It invokes `Phase(internal, Name, Data)` before another mailbox selection.
Phase entry runs first if the preceding callback changed or repeated phase.
Only one named event may be pending; iteration arguments belong in `Data`.
Collection-completion callbacks may insert a named event but cannot reply.
Entry callbacks cannot insert events or reply.

`{open_gather, Name, Key, {members_mask, Capacity, Mask}, Padding}` captures
a bounded membership set. Casts return `{gather, Name, Key, Member, Value}`
without changing phase or data. Completion invokes `{gather_complete, Name,
Key, Mask, Values}` with a capacity-sized list ordered by member index; inactive
slots retain Padding. Empty membership completes after the whole entry commits.
Partial values remain private; `info` exposes membership progress. Only one
gather or reduction may be active, and mismatched contributions postpone.

Retained calls opt in with `-hls_pending_calls(N)`, `-hls_reply_port(Port)` and
`-hls_replies(...)`. `Phase({call, From}, Request, Data)` consumes the request
and may save `From` in typed state. Any ordinary or named internal callback
can complete it with `[{reply, From, Reply}]`, optionally followed by one
`next_event` action. Calls cannot postpone or contribute to a reduction.
Caller timeout abandons interest without freeing the retained slot. See
`docs/retained-replies.md` for capacity, ordering and failure semantics.

The oldest eligible mailbox input runs first. Initial entry and phase entry
precede private events, which precede postponed retries and external input.
Postponed inputs retain capacity; reserve room for a message which advances
the phase. An endless internal-event chain starves this actor's mailbox.

Passing `{outputs, Map}` to `start_link/3` connects and enters immediately.
Cyclic CPU topologies may start disconnected, then call `connect/2`. Inputs
received before connection occupy the bounded queue without running callbacks.
The ordinary BEAM mailbox precedes this queue, so it models scheduling rather
than host admission guarantees.

Callback exceptions, invalid results and overflow terminate the CPU adapter.
Hardware latches failure until coordinated reset. Retained-call hardware also
fails outstanding and subsequent calls. Timeouts and other OTP result forms
are outside this restricted `gen_statem` state-functions vocabulary.
""".

-behavior(gen_server).

-export([start_link/3, connect/2, stop/1, cast/2, call/2, call/3, info/1, info/2]).
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
    open_gather_action/0, gather_contribution/0, gather_complete/0,
    reduction_complete/0,
    reduction_population/0,
    reduction_operator/0,
    contribution/0,
    enter_result/0,
    enter_result/1,
    internal_result/0,
    internal_result/1,
    internal_result/2,
    next_event_action/0, reply_action/0, step_actions/0, call_result/1
]).

%%%
%%% Callback contract
%%%

-type phase() :: atom().
-type lifecycle() :: disconnected | connected.
-type output_port() :: atom().
-type data() :: term().
-doc "The callback event discriminator; From is an activation-local retained-call handle.".
-type event_type() :: enter | cast | internal | {call, hls_gs:from()}.
-type cast_action() :: {cast, output_port(), term()}.
-doc "A nonempty contributor count, explicit member set, or bounded runtime numeric-member mask.".
-type reduction_population() :: hls_reduction:population().
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
-doc "Opens one indexed collection; zero membership completes after entry commits.".
-type open_gather_action() :: {open_gather, atom(), term(),
    {members_mask, 1..255, non_neg_integer()}, term()}.
-doc "Supplies one selected numeric member without mutating callback data or phase.".
-type gather_contribution() :: {gather, atom(), term(), non_neg_integer(), term()}.
-doc "A complete fixed-capacity member-indexed view; the mask identifies active values.".
-type gather_complete() :: hls_indexed_gather:completion(term()).
-doc "Entry effects, optionally preceded by one collection opening.".
-type entry_action() :: cast_action() | open_reduction_action() | open_gather_action().
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
%% Collection directives retain actor state until their private completion.
-type cast_directive() :: consume | postpone | fail | contribution() | gather_contribution().
-type cast_result() :: cast_result(phase(), data()).
-type cast_result(DataType) :: cast_result(phase(), DataType).
-doc "One named internal step, inserted ahead of postponed and external messages.".
-type next_event_action() :: {next_event, internal, atom()}.
-doc "Completes an activation-local retained caller with one declared reply record.".
-type reply_action() :: {reply, hls_gs:from(), term()}.
-doc "At most one reply, followed by at most one named internal event.".
-type step_actions() :: [reply_action() | next_event_action()].
-doc "A call consumes its input; a saved From may be completed by a later callback.".
-type call_result(DataType) :: internal_result(DataType).
-doc "A cast conclusion, optionally scheduling one internal step after phase entry.".
-type cast_result(PhaseType, DataType) ::
    {
        NextPhase :: PhaseType,
        NextData :: DataType,
        Directive :: cast_directive()
    } |
    {repeat_phase, NextData :: DataType, consume} |
    {PhaseType | repeat_phase, DataType, consume, step_actions()}.
-type enter_result() :: enter_result(data()).
-type enter_result(DataType) :: {
    NextData :: DataType,
    Actions :: [entry_action()]
}.
-type internal_result() :: internal_result(phase(), data()).
-type internal_result(DataType) :: internal_result(phase(), DataType).
-doc "An internal conclusion; it cannot postpone itself or consume mailbox capacity.".
-type internal_result(PhaseType, DataType) ::
    {
        NextPhase :: PhaseType,
        NextData :: DataType,
        Directive :: consume | fail
    } |
    {repeat_phase, NextData :: DataType, consume} |
    {PhaseType | repeat_phase, DataType, consume, step_actions()}.
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
-doc "Handles entry, cast, declared call, or private internal events for one phase.".
-callback 'StateName'(
    enter,
    OldPhase :: phase(),
    Data :: DataType
) -> enter_result(DataType);
    (cast, Message :: term(), Data :: DataType) -> cast_result(DataType);
    ({call, hls_gs:from()}, Message :: term(), Data :: DataType) -> call_result(DataType);
    (internal, reduction_complete() | gather_complete() | atom(), Data :: DataType) ->
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
    reduction = none :: none | hls_reduction:reduction(),
    gather = none :: none | hls_indexed_gather:gather(term()),
    gather_completion = none :: none | gather_complete(),
    continuation = none :: none | atom(),
    continuation_names = [] :: [atom()],
    calls = #{} :: #{atom() => [atom()]},
    reply_book = none :: none | hls_reply_book:book(),
    call_messages = #{} :: #{non_neg_integer() => gen_server:from()}
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

-doc "Calls a state machine with the ordinary five-second ERTS timeout.".
-spec call(pid(), term()) -> term().
call(Pid, Message) -> call(Pid, Message, 5000).

-doc "Waits for a declared call's reply; timeout abandons caller interest, not retained service ownership.".
-spec call(pid(), term(), timeout()) -> term().
call(Pid, Message, Timeout) -> gen_server:call(Pid, Message, Timeout).

-doc "Returns the lifecycle, phase, callback data, and queue counters.".
-spec info(pid()) -> map().
info(PID) -> info(PID, 5000).

-spec info(pid(), timeout()) -> map().
info(PID, Timeout) ->
    format_info(sys:get_state(PID, Timeout)).

%%%
%%% gen_server callbacks
%%%

-doc "Initializes a CPU state machine and enters its initial phase when connected.".
%% Initialize callback data and enter only when outputs are connected.
-spec init({module(), term(), pos_integer(), undefined | map()}) ->
    {ok, #runtime{}} | {stop, term()}.
init({Module, Arg, Capacity, Outputs}) ->
    {ok, Phase, Data} = Module:init(Arg),
    ok = validate_phase(Phase),
    {Lifecycle, OutputMap} = case Outputs of
        undefined -> {disconnected, #{}};
        _ -> {connected, Outputs}
    end,
    {Calls, Book} = case hls_service_contract:from_module(Module) of
        {ok, #{calls := C, pending_calls := N}} -> {C, hls_reply_book:new(N)};
        _ -> {#{}, none}
    end,
    Runtime0 = #runtime{
        module = Module,
        lifecycle = Lifecycle,
        phase = Phase,
        data = Data,
        outputs = OutputMap,
        mailbox = hls_mailbox:new(Capacity),
        continuation_names = hls_continuation:names(Module),
        calls = Calls, reply_book = Book
    },
    case Lifecycle of
        disconnected -> {ok, Runtime0};
        connected ->
            case process_messages(enter_phase(Phase, Runtime0)) of
                {ok, Started} -> {ok, Started};
                {stop, Reason, _Stopped} -> {stop, Reason}
            end
    end.

-doc "Connects outputs or queues a declared call for phase-sensitive dispatch.".
-spec handle_call(term(), gen_server:from(), #runtime{}) -> term().
%% Deferred connections enter before dispatching any queued application input.
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
%% A second connection cannot replace a live output map.
handle_call({connect, _Outputs}, _From, Runtime) ->
    {reply, {error, already_connected}, Runtime};
%% Actors without a call declaration retain their existing unsupported-call failure.
handle_call(Request, _From, Runtime = #runtime{reply_book = none}) ->
    {stop, {unsupported_hls_statem_call, Request}, {error, unsupported_call}, Runtime};
%% Calls occupy the same ordered input queue as casts; caller ownership begins at dispatch.
handle_call(Request, From, Runtime = #runtime{calls = Calls, next_message_id = Id, call_messages = Messages}) ->
    case is_tuple(Request) andalso tuple_size(Request) > 0 andalso maps:is_key(element(1, Request), Calls) of
        true -> admit_and_process(Request, Runtime#runtime{call_messages = Messages#{Id => From}});
        false -> {reply, {error, unsupported_call}, Runtime}
    end.

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

%% Internal steps have priority without creating a phase or mailbox boundary.
-spec process_messages(#runtime{}) -> {ok, #runtime{}} | {stop, term(), #runtime{}}.
process_messages(Runtime = #runtime{gather_completion = Completion}) when Completion =/= none ->
    process_internal(Completion, Runtime#runtime{gather_completion = none});
process_messages(Runtime = #runtime{continuation = Name}) when Name =/= none ->
    process_internal(Name, Runtime#runtime{continuation = none});
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

%% Dispatch a selected mailbox input before committing its conclusion.
-spec process_message(term(), {non_neg_integer(), term()}, #runtime{}) ->
    {ok, #runtime{}} | {stop, term(), #runtime{}}.
process_message(
    Selection,
    {MessageID, Message},
    Runtime = #runtime{
        phase = Phase,
        data = Data,
        postponed = Postponed0
    }
) ->
    {RawResult, Book, IsCall} = invoke_message(MessageID, Message, Runtime),
    {Result, Continue, Reply} = event_result(RawResult, Runtime#runtime.continuation_names),
    {NextPhase, NextData, Directive, Repeat} =
        state_result(Result, Phase, Data),
    NextRuntime = Runtime#runtime{
        phase = NextPhase,
        data = NextData,
        continuation = Continue,
        reply_book = Book
    },
    BoundaryStatus = collection_boundary_status(
        Directive, Repeat, Phase, NextPhase, Runtime
    ),
    ok = case IsCall andalso Directive =/= consume andalso Directive =/= fail of
        true -> error({unsupported_hls_statem_call_directive, Directive}); false -> ok
    end,
    Replied = case BoundaryStatus =:= ok andalso Directive =/= fail of
        true -> complete_reply(Reply, NextRuntime);
        false -> NextRuntime
    end,
    case {BoundaryStatus, Directive} of
        {{error, Reason, Status}, _} ->
            {stop,
                {Reason, Status, Message},
                Runtime};
        {ok, fail} ->
            {stop, {hls_statem_failure, Message}, Replied};
        {ok, postpone} ->
            finish_transition(Phase, Replied#runtime{
                postponed = Postponed0#{MessageID => true}
            });
        {ok, {contribute, _Name, _Key, _Value} = Contribution} ->
            process_contribution(
                Contribution,
                Selection,
                {MessageID, Message},
                Phase,
                Data,
                Replied
            );
        {ok, {contribute, _Name, _Key, _Member, _Value} = Contribution} ->
            process_contribution(
                Contribution,
                Selection,
                {MessageID, Message},
                Phase,
                Data,
                Replied
            );
        {ok, {gather, _Name, _Key, _Member, _Value} = Contribution} ->
            process_contribution(Contribution, Selection, {MessageID, Message}, Phase, Data, Replied);
        {ok, consume} ->
            Consumed = consume_message(
                Selection,
                {MessageID, Message},
                Replied
            ),
            case Repeat of
                true -> finish_repeat(Phase, Consumed);
                false -> finish_transition(Phase, Consumed)
            end
    end.

%% An unfinished collection may accept unrelated work but cannot cross a phase boundary.
-spec collection_boundary_status(cast_directive(), boolean(), phase(), phase(), #runtime{}) ->
    ok | {error, atom(), map()}.
collection_boundary_status(fail, _Repeat, _Phase, _NextPhase, _Runtime) -> ok;
collection_boundary_status({contribute, _, _, _}, _, _, _, _) -> ok;
collection_boundary_status({contribute, _, _, _, _}, _, _, _, _) -> ok;
collection_boundary_status({gather, _, _, _, _}, _, _, _, _) -> ok;
collection_boundary_status(_Directive, Repeat, Phase, NextPhase, Runtime) ->
    case Repeat orelse NextPhase =/= Phase of
        true -> active_collection_error(Runtime);
        false -> ok
    end.

%% Preserve scalar reduction diagnostics and distinguish indexed collection progress.
-spec active_collection_error(#runtime{}) -> ok | {error, atom(), map()}.
active_collection_error(#runtime{reduction = Reduction}) when Reduction =/= none ->
    {error, hls_statem_reduction_incomplete, hls_reduction:info(Reduction)};
active_collection_error(#runtime{gather = Gather}) when Gather =/= none ->
    {error, hls_statem_gather_incomplete, hls_indexed_gather:info(Gather)};
active_collection_error(_Runtime) -> ok.

%% Run a private event without removing any mailbox entry.
-spec process_internal(term(), #runtime{}) ->
    {ok, #runtime{}} | {stop, term(), #runtime{}}.
process_internal(Event, Runtime = #runtime{
    module = Module,
    phase = Phase,
    data = Data
}) ->
    RawResult = Module:Phase(internal, Event, Data),
    {Result, Continue, Reply} = event_result(RawResult, Runtime#runtime.continuation_names),
    ok = validate_completion_reply(Event, Reply),
    {NextPhase, NextData, Directive, Repeat} =
        internal_state_result(Result, Phase),
    NextRuntime = Runtime#runtime{phase = NextPhase, data = NextData,
        continuation = pending_continuation(Continue, Runtime#runtime.continuation)},
    case collection_boundary_status(Directive, Repeat, Phase, NextPhase, Runtime) of
        ok -> ok;
        {error, Reason, Status} -> error({Reason, Status, Event})
    end,
    case Directive of
        fail ->
            {stop, {hls_statem_failure, Event}, NextRuntime};
        consume when Repeat ->
            finish_repeat(Phase, complete_reply(Reply, NextRuntime));
        consume ->
            finish_transition(Phase, complete_reply(Reply, NextRuntime))
    end.

%% Completion may request one continuation, while direct retained replies remain unsupported.
-spec validate_completion_reply(term(), none | tuple()) -> ok.
validate_completion_reply({reduction_complete, _, _, _}, Reply) when Reply =/= none ->
    error(hls_statem_reduction_actions_unsupported);
validate_completion_reply({gather_complete, _, _, _, _}, Reply) when Reply =/= none ->
    error(hls_statem_gather_actions_unsupported);
validate_completion_reply(_, _) -> ok.

%% Empty entry completions precede an already pending named event without discarding it.
-spec pending_continuation(none | atom(), none | atom()) -> none | atom().
pending_continuation(none, Existing) -> Existing;
pending_continuation(Continue, none) -> Continue;
pending_continuation(_Continue, _Existing) -> error(hls_statem_continuation_already_pending).

%% Collection directives leave actor data unchanged and consume only accepted members.
-spec process_contribution(contribution() | gather_contribution(), hls_mailbox:selection(),
    {non_neg_integer(), term()}, phase(), data(), #runtime{}) ->
    {ok, #runtime{}} | {stop, term(), #runtime{}}.
process_contribution(
    Contribution,
    Selection,
    Entry = {MessageID, Message},
    Phase,
    Data,
    Runtime = #runtime{
        phase = Phase,
        data = Data,
        postponed = Postponed
    }
) ->
    Kind = case element(1, Contribution) of contribute -> reduction; gather -> gather end,
    case offer_collection(Contribution, Runtime) of
        mismatch ->
            finish_transition(Phase, Runtime#runtime{
                postponed = Postponed#{MessageID => true}
            });
        {pending, NextCollection} ->
            Consumed = consume_message(Selection, Entry, Runtime),
            finish_transition(Phase, set_collection(Kind, NextCollection, Consumed));
        {complete, Completion} ->
            Consumed = consume_message(Selection, Entry, Runtime),
            process_internal(
                Completion,
                set_collection(Kind, none, Consumed)
            );
        {error, Reason} ->
            {stop,
                {collection_failure(Kind), Reason, Message},
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

%% Route indexed input without requiring or invoking a scalar reducer callback.
-spec offer_collection(contribution() | gather_contribution(), #runtime{}) ->
    mismatch | {pending, term()} | {complete, term()} | {error, term()}.
offer_collection({gather, _, _, _, _}, #runtime{gather = none}) -> mismatch;
offer_collection({gather, Name, Key, Member, Value}, #runtime{gather = Gather}) ->
    hls_indexed_gather:offer(Name, Key, Member, Value, Gather);
offer_collection(Contribution, #runtime{module = Module, reduction = Reduction}) ->
    apply_contribution(Module, Contribution, Reduction).

%% Keep the two collection representations exclusive without changing scalar poison handling.
-spec set_collection(reduction | gather, term(), #runtime{}) -> #runtime{}.
set_collection(reduction, Value, Runtime) -> Runtime#runtime{reduction = Value};
set_collection(gather, Value, Runtime) -> Runtime#runtime{gather = Value}.

%% Distinct failures retain the rejected message at the scheduler boundary.
-spec collection_failure(reduction | gather) -> atom().
collection_failure(reduction) -> hls_statem_reduction_failure;
collection_failure(gather) -> hls_statem_gather_failure.

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

%% Retire input ownership together with its mailbox and postponement entries.
-spec consume_message(hls_mailbox:selection(), {non_neg_integer(), term()}, #runtime{}) -> #runtime{}.
consume_message(Selection, Entry = {MessageID, _Message}, Runtime = #runtime{
    mailbox = Mailbox,
    postponed = Postponed
}) ->
    {ok, Entry, NextMailbox} = hls_mailbox:consume(Selection, Mailbox),
    Runtime#runtime{
        mailbox = NextMailbox,
        postponed = maps:remove(MessageID, Postponed),
        call_messages = maps:remove(MessageID, Runtime#runtime.call_messages)
    }.

%% A checked action list can complete one retained caller and insert one private event.
-spec event_result(term(), [atom()]) -> {term(), none | atom(), none | {reply, non_neg_integer(), term()}}.
event_result({Phase, Data, consume, Actions}, Names) ->
    {Reply, Continue} = hls_callback_actions:split(Actions, statem, Names),
    {{Phase, Data, consume}, Continue, Reply};
event_result({_Phase, _Data, _Directive, Actions}, _Names) ->
    error({invalid_hls_statem_event_actions, Actions});
event_result(Result, _Names) -> {Result, none, none}.

%% No reply book is allocated for actors which only consume casts.
-spec complete_reply(none | {reply, non_neg_integer(), term()}, #runtime{}) -> #runtime{}.
complete_reply(none, Runtime) -> Runtime;
complete_reply(Reply, Runtime = #runtime{reply_book = Book}) when Book =/= none ->
    Runtime#runtime{reply_book = hls_reply_book:complete(Reply, Book)};
complete_reply(_Reply, _Runtime) -> error(hls_statem_calls_not_declared).

%% Allocate only at dispatch so delayed connection and phase entry preserve arrival order.
-spec invoke_message(non_neg_integer(), term(), #runtime{}) -> {term(), none | hls_reply_book:book(), boolean()}.
invoke_message(Id, Message, #runtime{module = Module, phase = Phase, data = Data,
        calls = Calls, call_messages = Messages, reply_book = Book}) ->
    case maps:find(Id, Messages) of
        error -> {Module:Phase(cast, Message, Data), Book, false};
        {ok, From} ->
            Tag = element(1, Message),
            case hls_reply_book:admit(Module:pack_tag(Tag), From, maps:get(Tag, Calls), Book) of
                full -> {{Phase, Data, consume}, Book, true};
                {ok, Token, Next} -> {Module:Phase({call, Token}, Message, Data), Next, true}
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

internal_state_result({repeat_phase, NextData, consume}, Phase) ->
    {Phase, NextData, consume, true};
internal_state_result({repeat_phase, _NextData, Directive}, _Phase) ->
    error({bad_hls_statem_internal_conclusion, repeat_phase, Directive});
internal_state_result({NextPhase, NextData, Directive}, _Phase) ->
    ok = validate_internal_conclusion(NextPhase, Directive),
    {NextPhase, NextData, Directive, false};
internal_state_result(Result, _Phase) ->
    error({bad_hls_statem_internal_result, Result}).

%% A committed phase change enters atomically, then releases postponed inputs.
-spec finish_transition(phase(), #runtime{}) -> {ok, #runtime{}} | {stop, term(), #runtime{}}.
finish_transition(PreviousPhase, Runtime0 = #runtime{phase = Phase}) ->
    Runtime1 = case Phase =/= PreviousPhase of
        true ->
            ok = require_idle_collection(Runtime0),
            Entered = enter_phase(PreviousPhase, Runtime0),
            Entered#runtime{postponed = #{}};
        false ->
            Runtime0
    end,
    process_messages(Runtime1).

%% Explicit reentry repeats entry before retrying any previously postponed input.
-spec finish_repeat(phase(), #runtime{}) -> {ok, #runtime{}} | {stop, term(), #runtime{}}.
finish_repeat(Phase, Runtime0) ->
    ok = require_idle_collection(Runtime0),
    Entered = enter_phase(Phase, Runtime0),
    process_messages(Entered#runtime{postponed = #{}}).

%%%
%%% Phase entry and validation
%%%

%% Validate every entry action before publishing casts or scheduling an empty completion.
-spec enter_phase(phase(), #runtime{}) -> #runtime{}.
enter_phase(OldPhase, Runtime = #runtime{
    module = Module,
    lifecycle = connected,
    phase = Phase,
    data = Data,
    outputs = Outputs
}) ->
    Result = Module:Phase(enter, OldPhase, Data),
    {NextData, Actions} = enter_result(Result),
    {Prepared, Casts} = prepare_entry_actions(Module, Actions, Outputs, Runtime),
    lists:foreach(
        fun
            ({cast, Port, Message}) ->
                gen_server:cast(maps:get(Port, Outputs), Message)
        end,
        Casts
    ),
    Prepared#runtime{data = NextData}.

enter_result({NextData, Casts}) -> {NextData, Casts};
enter_result(Result) -> error({bad_hls_statem_enter_result, Result}).

%% Accept bounded state conclusions; indexed contributions use the same state-preserving rule.
-spec validate_conclusion(term(), term()) -> ok.
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
validate_conclusion(NextPhase, {gather, Name, _Key, _Member, _Value})
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

%% Open at most one collection before any cast, then validate the complete effect batch.
-spec prepare_entry_actions(module(), term(), map(), #runtime{}) -> {#runtime{}, list()}.
prepare_entry_actions(Module, Actions, Outputs, Runtime) when is_list(Actions) ->
    {Prepared, Casts} = case Actions of
        [{open_reduction, Name, Key, Population, Operator} | Rest] ->
            ok = require_idle_collection(Runtime),
            case erlang:function_exported(Module, reduce, 3) of
                true -> ok;
                false -> error({missing_hls_statem_callback, reduce, 3})
            end,
            case hls_reduction:open(Name, Key, Population, Operator) of
                {ok, Opened} -> {Runtime#runtime{reduction = Opened}, Rest};
                {error, Reason} -> error({bad_hls_statem_open_reduction, Reason})
            end;
        [{open_gather, Name, Key, Population, Padding} | Rest] ->
            ok = require_idle_collection(Runtime),
            {open_gather(Name, Key, Population, Padding, Runtime), Rest};
        _ -> {Runtime, Actions}
    end,
    lists:foreach(fun
        ({open_reduction, _, _, _, _}) -> error(hls_statem_open_reduction_must_be_first);
        ({open_gather, _, _, _, _}) -> error(hls_statem_open_gather_must_be_first);
        (_) -> ok
    end, Casts),
    ok = validate_casts(Casts, Outputs),
    {Prepared, Casts};
prepare_entry_actions(_Module, Actions, _Outputs, _Runtime) ->
    error({bad_hls_statem_actions, Actions}).

%% Empty views become private events only after all entry actions validate and commit.
-spec open_gather(atom(), term(), term(), term(), #runtime{}) -> #runtime{}.
open_gather(Name, Key, {members_mask, Capacity, Mask}, Padding, Runtime) ->
    case hls_indexed_gather:open(Name, Key, Capacity, Mask, Padding) of
        {pending, Gather} -> Runtime#runtime{gather = Gather};
        {complete, Completion} -> Runtime#runtime{gather_completion = Completion};
        {error, Reason} -> error({bad_hls_statem_open_gather, Reason})
    end;
open_gather(_Name, _Key, Population, _Padding, _Runtime) ->
    error({bad_hls_statem_open_gather, {invalid_population, Population}}).

validate_casts(Casts, Outputs) ->
    Ports = lists:map(
        fun
            ({cast, Port, _Message}) when is_atom(Port) ->
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

%% No phase boundary may discard an unfinished member obligation.
-spec require_idle_collection(#runtime{}) -> ok.
require_idle_collection(Runtime) ->
    case active_collection_error(Runtime) of
        ok -> ok;
        {error, Reason, Status} -> error({Reason, Status})
    end.

%% Queries reveal gather progress without exposing any accepted element values.
-spec gather_status(none | hls_indexed_gather:gather(term())) -> idle | map().
gather_status(none) -> idle;
gather_status(Gather) -> hls_indexed_gather:info(Gather).

reduction_status(none) ->
    idle;
reduction_status(Reduction) ->
    hls_reduction:info(Reduction).

%%%
%%% Options and diagnostics
%%%

%% Return committed actor data and private collection progress, never partial gather values.
-spec format_info(#runtime{}) -> map().
format_info(#runtime{
    lifecycle = Lifecycle,
    phase = Phase,
    data = Data,
    outputs = Outputs,
    mailbox = Mailbox,
    postponed = Postponed,
    reduction = Reduction,
    gather = Gather
}) ->
    #{
        lifecycle => Lifecycle,
        phase => Phase,
        data => Data,
        connected => Lifecycle =:= connected,
        outputs => output_names(Outputs),
        postponed => map_size(Postponed),
        mailbox => hls_mailbox:info(Mailbox),
        reduction => reduction_status(Reduction),
        gather => gather_status(Gather)
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
