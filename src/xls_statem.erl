%%%% xls_statem
%%%%
%% TODO: Add a fixed-shape synchronous call/reply contract once its response
%% path and bounded lifetime have a lowerable representation.
%% TODO: Evaluate the useful bounded subsets of gen_statem state-enter calls,
%% timeouts, and next_event actions instead of growing ad hoc alternatives.

-module(xls_statem).
-moduledoc """
A bounded CPU reference scheduler for XLS state machines.

An `xls_statem` callback separates its finite-control `Phase` atom from its
rich `Data` value. The CPU scheduler in this module provides reference
semantics for the ordering and postponement rules used by the generated
implementation.

## Callback contract

`init/1` returns an optional initial output and the initial machine value:

```
{{Emit, Output}, {Phase, Data}}
```

`transition/2` receives one application message and the current
`{Phase, Data}` pair. It always returns the fixed product:

```
{{Emit, Output}, {NextPhase, NextData}, Directive}
```

The directive determines what happens to the input:

  * `consume` removes it from the mailbox and may emit one output.
  * `postpone` retains it and cannot emit.
  * `fail` installs the returned phase and data for diagnostics, then stops the
    CPU process; it cannot emit.

Outputs are delivered to the PID in the required `{output, PID}` start option.
The message has the form `{xls_statem, MachinePID, Output}`.

The CPU scheduler admits asynchronous casts and ordinary process messages.
Synchronous calls are not yet part of the callback contract and stop it.

## Postponement

The scheduler tries the oldest eligible input. A postponed input becomes
eligible again only after the `Phase` atom changes; changing `Data`, or
returning the same phase, does not retry it. A postponed transition which does
change phase therefore makes that same input immediately eligible. This retry
boundary is borrowed from `gen_statem`, but this module is not a compatible
implementation of its callback API.

## Capacity and failure

Postponed inputs retain mailbox capacity. The configured capacity must leave
room for an input capable of advancing the phase, or the protocol can
deadlock under backpressure. On the CPU, an overflowing cast or ordinary
process message stops the scheduler. Missing callback clauses, callback
exceptions, invalid callback results, and `fail` directives also stop it.

The ordinary BEAM mailbox sits in front of this bounded queue, so this module
models scheduling semantics rather than host-side admission guarantees.
""".

-behavior(gen_server).

-export([start_link/3, stop/1, cast/2, info/1]).
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).
-export_type([phase/0, directive/0, conclusion/0]).

%%%
%%% Callback contract
%%%

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

-record(runtime, {
    module :: module(),
    phase :: phase(),
    data :: data(),
    output :: pid(),
    mailbox :: xls_mailbox:mailbox(),
    postponed = #{} :: #{non_neg_integer() => true},
    next_message_id = 0 :: non_neg_integer()
}).

%%%
%%% Client interface
%%%

-doc "Starts a machine with required mailbox-capacity and output options.".
-spec start_link(module(), term(), [start_option()]) ->
    gen_server:start_ret().
start_link(Module, Arg, Options) ->
    {Capacity, Output} = start_options(Options),
    gen_server:start_link(?MODULE, {Module, Arg, Capacity, Output}, []).

-spec stop(pid()) -> ok.
stop(PID) ->
    gen_server:stop(PID).

-doc "Asynchronously casts one application message to the CPU scheduler.".
-spec cast(pid(), term()) -> ok.
cast(PID, Message) ->
    gen_server:cast(PID, Message).

-doc "Returns the phase, callback data, and bounded queue counters.".
-spec info(pid()) -> map().
info(PID) ->
    format_info(sys:get_state(PID)).

%%%
%%% gen_server callbacks
%%%

init({Module, Arg, Capacity, Output}) ->
    {{Emit, InitialOutput}, {Phase, Data}} = Module:init(Arg),
    true = is_atom(Phase),
    true = is_boolean(Emit),
    Runtime = #runtime{
        module = Module,
        phase = Phase,
        data = Data,
        output = Output,
        mailbox = xls_mailbox:new(Capacity)
    },
    maybe_emit(Emit, InitialOutput, Runtime),
    {ok, Runtime}.

%% Synchronous calls deliberately fail instead of masquerading as casts.
%% The TODO at the top records the missing lowerable call/reply contract.
handle_call(Request, _From, Runtime) ->
    {stop, {unsupported_xls_statem_call, Request},
        {error, unsupported_call}, Runtime}.

handle_cast(Message, Runtime0) ->
    admit_and_process(Message, Runtime0).

handle_info(Message, Runtime0) ->
    admit_and_process(Message, Runtime0).

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

admit_and_process(Message, Runtime0) ->
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
    Conclusion = Module:transition(Message, {Phase, Data}),
    {{Emit, Output}, {NextPhase, NextData}, Directive} = Conclusion,
    ok = validate_conclusion(Emit, NextPhase, Directive),
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
            maybe_emit(Emit, Output, NextRuntime0),
            {ok, {MessageID, Message}, Mailbox1} =
                xls_mailbox:consume(Selection, Mailbox0),
            finish_transition(
                Phase,
                NextRuntime0#runtime{
                    mailbox = Mailbox1,
                    postponed = maps:remove(MessageID, Postponed0)
                }
            )
    end.

finish_transition(PreviousPhase, Runtime0) ->
    Runtime1 = case Runtime0#runtime.phase =/= PreviousPhase of
        true -> Runtime0#runtime{postponed = #{}};
        false -> Runtime0
    end,
    process_messages(Runtime1).

%%%
%%% Validation and diagnostics
%%%

validate_conclusion(Emit, NextPhase, consume)
        when is_boolean(Emit), is_atom(NextPhase) ->
    ok;
validate_conclusion(false, NextPhase, Directive)
        when is_atom(NextPhase),
             (Directive =:= postpone orelse Directive =:= fail) ->
    ok;
validate_conclusion(Emit, NextPhase, Directive) ->
    error({bad_xls_statem_conclusion, Emit, NextPhase, Directive}).

maybe_emit(false, _Output, _Runtime) ->
    ok;
maybe_emit(true, Output, #runtime{output = Recipient}) ->
    Recipient ! {xls_statem, self(), Output},
    ok.

format_info(#runtime{
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

start_options(Options) ->
    Known = lists:all(
        fun
            ({mailbox_capacity, _Capacity}) -> true;
            ({output, _Output}) -> true;
            (_Option) -> false
        end,
        Options
    ),
    Capacity = proplists:get_value(mailbox_capacity, Options),
    Output = proplists:get_value(output, Options),
    case Known andalso
            is_integer(Capacity) andalso
            Capacity > 0 andalso Capacity =< 255 andalso
            is_pid(Output) of
        true -> {Capacity, Output};
        false -> error(badarg)
    end.
