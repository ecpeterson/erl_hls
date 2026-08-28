-module(xls_statem).
-moduledoc """
A bounded CPU reference runtime for a small, explicit subset of `gen_statem`.

The callback has an outer state name and a separate data value.  Returning
`postpone` keeps the current event resident in an `xls_mailbox`.  Postponed
events are excluded while the outer state name is unchanged, even when the
data value changes.  Only a transition for which `NextState =/= State` makes
all postponed events eligible again, in their original arrival order.  This is
the same retry boundary used by `gen_statem`.

The callback surface follows `gen_statem`'s `handle_event_function` mode, with
deliberately narrower types: state names are atoms, `init/1` returns only
`{ok, StateName, Data}`, and event callbacks return `keep_state_and_data`,
`keep_state`, or `next_state`, optionally followed by `postpone` and reply
actions.  An optional `terminate/3` callback is honored.  Init actions,
timeouts, state-enter calls, `next_event`, hibernation, hot code upgrades, and
fabric proxying are not implemented.

An event is postponed only when its matching callback explicitly returns a
postpone action.  A missing `handle_event/4` clause or a callback exception
crashes the runtime, as it does in `gen_statem`; it is not treated as a
selective-receive miss.

The bounded mailbox begins after the outer BEAM mailbox: callers of this CPU
model can still enqueue unbounded raw process messages before this runtime
admits them.  A fabric implementation must reserve capacity before accepting a
frame rather than relying on this host-side boundary.

If this host-side boundary fills, a call receives `{error, mailbox_full}`;
casts and ordinary process messages stop the runtime because they provide no
admission response channel.
""".

-behaviour(gen_server).

-export([
    start_link/3,
    stop/1,
    call/2,
    cast/2,
    send_request/2,
    receive_response/2,
    info/1
]).
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-type state_name() :: atom().
-type data() :: term().
-type event_type() :: {call, gen_server:from()} | cast | info.
-type start_option() :: {mailbox_capacity, pos_integer()}.
-type response_timeout() :: timeout() | {abs, integer()}.
-type reply_action() :: {reply, gen_server:from(), term()}.
-type action() :: postpone | {postpone, boolean()} | reply_action().
-type actions() :: action() | [action()].
-type callback_result() ::
    keep_state_and_data |
    {keep_state_and_data, actions()} |
    {keep_state, data()} |
    {keep_state, data(), actions()} |
    {next_state, state_name(), data()} |
    {next_state, state_name(), data(), actions()}.

-callback callback_mode() -> handle_event_function.
-callback init(term()) -> {ok, state_name(), data()}.
-callback handle_event(event_type(), term(), state_name(), data()) ->
    callback_result().
-callback terminate(term(), state_name(), data()) -> term().

-optional_callbacks([terminate/3]).

-record(state, {
    module :: module(),
    state_name :: state_name(),
    data :: data(),
    mailbox :: xls_mailbox:mailbox(),
    postponed = #{} :: #{non_neg_integer() => true},
    next_event_id = 0 :: non_neg_integer()
}).

-doc "Starts a state machine with one required `{mailbox_capacity, N}` option.".
-spec start_link(module(), term(), [start_option()]) ->
    gen_server:start_ret().
start_link(Module, Arg, Options) when is_atom(Module), is_list(Options) ->
    Capacity = mailbox_capacity(Options),
    gen_server:start_link(?MODULE, {Module, Arg, Capacity}, []);
start_link(_Module, _Arg, _Options) ->
    error(badarg).

-spec stop(pid()) -> ok.
stop(PID) ->
    gen_server:stop(PID).

-spec call(pid(), term()) -> term().
call(PID, Request) ->
    gen_server:call(PID, Request).

-spec cast(pid(), term()) -> ok.
cast(PID, Event) ->
    gen_server:cast(PID, Event).

-doc "Starts an asynchronous call compatible with `receive_response/2`.".
-spec send_request(pid(), term()) -> gen_server:request_id().
send_request(PID, Request) ->
    gen_server:send_request(PID, Request).

-spec receive_response(gen_server:request_id(), response_timeout()) ->
    {reply, term()} | {error, term()} | timeout.
receive_response(RequestID, Timeout) ->
    gen_server:receive_response(RequestID, Timeout).

-doc "Returns the outer state, callback data, and bounded queue counters.".
-spec info(pid()) -> map().
info(PID) ->
    state_info(sys:get_state(PID)).

init({Module, Arg, Capacity}) ->
    handle_event_function = Module:callback_mode(),
    case Module:init(Arg) of
        {ok, InitialState, Data} when is_atom(InitialState) ->
            {ok, #state{
                module = Module,
                state_name = InitialState,
                data = Data,
                mailbox = xls_mailbox:new(Capacity)
            }};
        Result ->
            {stop, {bad_xls_statem_init, Result}}
    end.

handle_call(Event, From, State0) ->
    case enqueue({call, From}, Event, State0) of
        {ok, State1} ->
            {noreply, process_events(State1)};
        {error, full} ->
            {reply, {error, mailbox_full}, State0}
    end.

handle_cast(Event, State0) ->
    case enqueue(cast, Event, State0) of
        {ok, State1} ->
            {noreply, process_events(State1)};
        {error, full} ->
            {stop, {mailbox_full, Event}, State0}
    end.

handle_info(Event, State0) ->
    case enqueue(info, Event, State0) of
        {ok, State1} ->
            {noreply, process_events(State1)};
        {error, full} ->
            {stop, {mailbox_full, Event}, State0}
    end.

terminate(Reason, #state{
    module = Module,
    state_name = StateName,
    data = Data
}) ->
    case erlang:function_exported(Module, terminate, 3) of
        true -> Module:terminate(Reason, StateName, Data);
        false -> ok
    end.

code_change(_OldVersion, _State, _Extra) ->
    {error, xls_statem_code_change_not_supported}.

enqueue(Type, Content, State = #state{
    mailbox = Mailbox0,
    next_event_id = EventID
}) ->
    Generation = maps:get(generation, xls_mailbox:info(Mailbox0)),
    case xls_mailbox:reserve(Generation, self(), Mailbox0) of
        {error, full, _Mailbox} ->
            {error, full};
        {ok, Reservation, Mailbox1} ->
            Event = {EventID, Type, Content},
            {ok, Mailbox2} = xls_mailbox:commit(
                Reservation,
                Event,
                Mailbox1
            ),
            {ok, State#state{
                mailbox = Mailbox2,
                next_event_id = EventID + 1
            }}
    end.

process_events(State = #state{
    mailbox = Mailbox,
    postponed = Postponed
}) ->
    NotPostponed = fun({EventID, _Type, _Content}) ->
        not maps:is_key(EventID, Postponed)
    end,
    case xls_mailbox:select([NotPostponed], Mailbox) of
        none ->
            State;
        {ok, Selection, 1, Event} ->
            process_event(Selection, Event, State)
    end.

process_event(
    Selection,
    {EventID, Type, Content},
    State = #state{
        module = Module,
        state_name = StateName,
        data = Data,
        mailbox = Mailbox0,
        postponed = Postponed0
    }
) ->
    Result = Module:handle_event(Type, Content, StateName, Data),
    {NextStateName, NextData, Actions} = normalize_result(
        Result,
        StateName,
        Data
    ),
    Postpone = postpone_action(Actions),
    ok = perform_actions(Actions),
    {Mailbox1, Postponed1} = case Postpone of
        true ->
            {Mailbox0, Postponed0#{EventID => true}};
        false ->
            {ok, {EventID, Type, Content}, ConsumedMailbox} =
                xls_mailbox:consume(Selection, Mailbox0),
            {ConsumedMailbox, maps:remove(EventID, Postponed0)}
    end,
    StateChanged = NextStateName =/= StateName,
    NextPostponed = case StateChanged of
        true -> #{};
        false -> Postponed1
    end,
    process_events(State#state{
        state_name = NextStateName,
        data = NextData,
        mailbox = Mailbox1,
        postponed = NextPostponed
    }).

normalize_result(keep_state_and_data, StateName, Data) ->
    {StateName, Data, []};
normalize_result({keep_state_and_data, Actions}, StateName, Data) ->
    {StateName, Data, listify(Actions)};
normalize_result({keep_state, NewData}, StateName, _Data) ->
    {StateName, NewData, []};
normalize_result({keep_state, NewData, Actions}, StateName, _Data) ->
    {StateName, NewData, listify(Actions)};
normalize_result({next_state, NextState, NewData}, _StateName, _Data)
        when is_atom(NextState) ->
    {NextState, NewData, []};
normalize_result(
    {next_state, NextState, NewData, Actions},
    _StateName,
    _Data
) when is_atom(NextState) ->
    {NextState, NewData, listify(Actions)};
normalize_result(Result, _StateName, _Data) ->
    error({bad_xls_statem_result, Result}).

listify(Actions) when is_list(Actions) ->
    Actions;
listify(Action) ->
    [Action].

postpone_action(Actions) ->
    lists:foldl(
        fun
            (postpone, _Postpone) -> true;
            ({postpone, Value}, _Postpone) when is_boolean(Value) -> Value;
            ({reply, _From, _Reply}, Postpone) -> Postpone;
            (Action, _Postpone) -> error({bad_xls_statem_action, Action})
        end,
        false,
        Actions
    ).

perform_actions(Actions) ->
    lists:foreach(
        fun
            ({reply, From, Reply}) -> gen_server:reply(From, Reply);
            (postpone) -> ok;
            ({postpone, Value}) when is_boolean(Value) -> ok;
            (Action) -> error({bad_xls_statem_action, Action})
        end,
        Actions
    ).

state_info(#state{
    state_name = StateName,
    data = Data,
    mailbox = Mailbox,
    postponed = Postponed
}) ->
    #{
        state_name => StateName,
        data => Data,
        postponed => map_size(Postponed),
        mailbox => xls_mailbox:info(Mailbox)
    }.

mailbox_capacity(Options) ->
    case Options of
        [{mailbox_capacity, Capacity}]
                when is_integer(Capacity), Capacity > 0 ->
            Capacity;
        _ ->
            error(badarg)
    end.
