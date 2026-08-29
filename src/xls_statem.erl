-module(xls_statem).
-moduledoc """
A bounded CPU scheduler for an XLS-shaped state machine.

The scheduler borrows one semantic rule from `gen_statem`: a postponed input
is retried only after the outer phase atom changes. Updating the separate data
value, or returning the same phase again, does not make it eligible. It
does not otherwise reproduce the `gen_statem` callback API.

Every transition returns one fixed product:

```
{{Emit, Output}, {NextPhase, NextData}, Directive}
```

`Directive` is `consume`, `postpone`, or `fail`. `Emit` permits at most one
output per consumed input; a postponed or failing transition cannot emit.
This closed shape has a direct XLS representation and avoids both tagged-tuple
return unions and unbounded action lists. An XLS implementation represents a
suppressed output as a zero `axis::Frame`.

The callback receives one application message type, not OTP's disjoint union
of calls, casts, and info events. Missing clauses, callback exceptions, a
`fail` directive, and exhausting the bounded mailbox stop the CPU scheduler.
The generated fabric latches a failed machine inert and issues one slot credit
before its stream receiver can accept the first beat of a frame. It does not
provide OTP termination diagnostics.

Postponed inputs retain capacity. A protocol must therefore size the mailbox
so that an input capable of changing phase can still be admitted. Otherwise
the CPU model fails on overflow and a backpressured fabric can make no progress.

As with any host-side reference process, the ordinary BEAM mailbox precedes
this bounded queue. It is a semantic model, not a host admission guarantee.
""".

-behaviour(gen_server).

-export([start_link/3, stop/1, send/2, info/1]).
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).
-export_type([phase/0, directive/0, conclusion/0]).

-type phase() :: atom().
-type data() :: term().
-type directive() :: consume | postpone | fail.
-type conclusion() :: {
    {Emit :: boolean(), Output :: term()},
    {NextPhase :: phase(), NextData :: data()},
    directive()
}.
-type start_option() ::
    {mailbox_capacity, 1..255} |
    {output, pid()}.

-callback init(term()) -> {
    {Emit :: boolean(), Output :: term()},
    {InitialPhase :: phase(), InitialData :: data()}
}.
-callback transition(term(), {phase(), data()}) -> conclusion().
-callback terminate(term(), phase(), data()) -> term().

-optional_callbacks([terminate/3]).

-record(state, {
    module :: module(),
    phase :: phase(),
    data :: data(),
    output :: pid(),
    mailbox :: xls_mailbox:mailbox(),
    postponed = #{} :: #{non_neg_integer() => true},
    next_message_id = 0 :: non_neg_integer()
}).

-doc "Starts a machine with a required mailbox capacity in `1..255`.".
-spec start_link(module(), term(), [start_option()]) ->
    gen_server:start_ret().
start_link(Module, Arg, Options) ->
    Caller = self(),
    {Capacity, Output} = start_options(Options, Caller),
    gen_server:start_link(?MODULE, {Module, Arg, Capacity, Output}, []).

-spec stop(pid()) -> ok.
stop(PID) ->
    gen_server:stop(PID).

-doc "Asynchronously sends one application message to the CPU scheduler.".
-spec send(pid(), term()) -> ok.
send(PID, Message) ->
    gen_server:cast(PID, Message).

-doc "Returns the outer phase, callback data, and bounded queue counters.".
-spec info(pid()) -> map().
info(PID) ->
    state_info(sys:get_state(PID)).

init({Module, Arg, Capacity, Output}) ->
    {{Emit, InitialOutput}, {Phase, Data}} = Module:init(Arg),
    true = is_atom(Phase),
    true = is_boolean(Emit),
    State = #state{
        module = Module,
        phase = Phase,
        data = Data,
        output = Output,
        mailbox = xls_mailbox:new(Capacity)
    },
    maybe_emit(Emit, InitialOutput, State),
    {ok, State}.

handle_call(Request, _From, State) ->
    {stop, {unsupported_xls_statem_call, Request},
        {error, unsupported_call}, State}.

handle_cast(Message, State0) ->
    admit_and_process(Message, State0).

handle_info(Message, State0) ->
    admit_and_process(Message, State0).

terminate(Reason, #state{
    module = Module,
    phase = Phase,
    data = Data
}) ->
    %%%% This callback is host-side diagnostics and is not lowered into XLS.
    case erlang:function_exported(Module, terminate, 3) of
        true -> Module:terminate(Reason, Phase, Data);
        false -> ok
    end.

code_change(_OldVersion, _State, _Extra) ->
    {error, xls_statem_code_change_not_supported}.

admit_and_process(Message, State0) ->
    case enqueue(Message, State0) of
        {ok, State1} ->
            case process_messages(State1) of
                {ok, State2} -> {noreply, State2};
                {stop, Reason, State2} -> {stop, Reason, State2}
            end;
        {error, full} ->
            {stop, {mailbox_full, Message}, State0}
    end.

enqueue(Message, State = #state{
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
            {ok, State#state{
                mailbox = Mailbox2,
                next_message_id = MessageID + 1
            }}
    end.

process_messages(State = #state{
    mailbox = Mailbox,
    postponed = Postponed
}) ->
    Eligible = fun({MessageID, _Message}) ->
        not maps:is_key(MessageID, Postponed)
    end,
    case xls_mailbox:select([Eligible], Mailbox) of
        none ->
            {ok, State};
        {ok, Selection, 1, Entry} ->
            process_message(Selection, Entry, State)
    end.

process_message(
    Selection,
    {MessageID, Message},
    State = #state{
        module = Module,
        phase = Phase,
        data = Data,
        mailbox = Mailbox0,
        postponed = Postponed0
    }
) ->
    Conclusion = Module:transition(Message, {Phase, Data}),
    {{Emit, Output}, {NextPhase, NextData}, Directive} = Conclusion,
    ok = validate_conclusion(Emit, NextPhase, Directive),
    NextState0 = State#state{
        phase = NextPhase,
        data = NextData
    },
    case Directive of
        fail ->
            {stop, {xls_statem_failure, Message}, NextState0};
        postpone ->
            finish_transition(
                Phase,
                NextState0#state{
                    postponed = Postponed0#{MessageID => true}
                }
            );
        consume ->
            maybe_emit(Emit, Output, State),
            {ok, {MessageID, Message}, Mailbox1} =
                xls_mailbox:consume(Selection, Mailbox0),
            finish_transition(
                Phase,
                NextState0#state{
                    mailbox = Mailbox1,
                    postponed = maps:remove(MessageID, Postponed0)
                }
            )
    end.

finish_transition(PreviousPhase, State0) ->
    State1 = case State0#state.phase =/= PreviousPhase of
        true -> State0#state{postponed = #{}};
        false -> State0
    end,
    process_messages(State1).

validate_conclusion(Emit, NextPhase, consume)
        when is_boolean(Emit), is_atom(NextPhase) ->
    ok;
validate_conclusion(false, NextPhase, Directive)
        when is_atom(NextPhase),
             (Directive =:= postpone orelse Directive =:= fail) ->
    ok;
validate_conclusion(Emit, NextPhase, Directive) ->
    error({bad_xls_statem_conclusion, Emit, NextPhase, Directive}).

maybe_emit(false, _Output, _State) ->
    ok;
maybe_emit(true, Output, #state{output = Recipient}) ->
    Recipient ! {xls_statem, self(), Output},
    ok.

state_info(#state{
    phase = Phase,
    data = Data,
    mailbox = Mailbox,
    postponed = Postponed
}) ->
    #{
        phase => Phase,
        data => Data,
        postponed => map_size(Postponed),
        mailbox => xls_mailbox:info(Mailbox)
    }.

start_options(Options, DefaultOutput) ->
    Known = lists:all(
        fun
            ({mailbox_capacity, _Capacity}) -> true;
            ({output, _Output}) -> true;
            (_Option) -> false
        end,
        Options
    ),
    Capacity = proplists:get_value(mailbox_capacity, Options),
    Output = proplists:get_value(output, Options, DefaultOutput),
    case Known andalso
            is_integer(Capacity) andalso
            Capacity > 0 andalso Capacity =< 255 andalso
            is_pid(Output) of
        true -> {Capacity, Output};
        false -> error(badarg)
    end.
