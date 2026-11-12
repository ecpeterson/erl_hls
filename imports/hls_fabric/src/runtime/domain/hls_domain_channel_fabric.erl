-module(hls_domain_channel_fabric).
-moduledoc """
Shared framed management adapter for fixed reset-domain mailbox channels.

Each channel has one local owner capability. The bounded shared queue carries only
inspect/bind/fence commands; application frames and credits never pass through this
process. A lost response retains an uncertain mutation and allows ordered status
queries to reconcile it without retransmission. Broker loss ends this adapter;
remote channel state is not reset and application work is never replayed. The
deployment must give this adapter exclusive access to its broker route and device
session; a local capability is not distributed hardware ownership arbitration.

Owner death revokes its capability, discards unsent requests and retains a fence
obligation. A transmitted bind must be observed before fencing its resulting
exact generation. New attachment waits until the channel is observed inactive.
This obligation survives the owner's death, but not loss of this adapter itself;
reattachment to a fresh transport must explicitly reconcile the surviving device.
""".
-behaviour(gen_server).

%% Deployment, exclusive per-channel authority and asynchronous request interface.
-export([start_link/3, attach/3, status/2, request/4, send_request/2, stop/1, info/1]).
-export_type([transport/0, options/0, request/0, info/0]).
%% OTP callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-doc "One existing broker with an externally established nonzero management session.".
-type transport() :: #{management := pid(), session := hls_nums:u64()}.
-doc "Finite control response deadline and optional ordinary local process name; expiration means uncertainty, not successful fencing.".
-type options() :: #{management_timeout_ms => pos_integer(), name => atom()}.
-doc "Messages accepted by the asynchronous API without changing the calling owner identity.".
-type request() ::
    {attach, hls_nums:u32(), pid()}
    | {status, hls_nums:u32()}
    | {request, reference(), hls_nums:u32(), hls_domain_channel_wire:command()}.
-doc "Bounded management metadata; absence of a pending exchange is not evidence of remote liveness.".
-type info() :: #{
    session := hls_nums:u64(),
    observed := #{hls_nums:u32() => hls_domain_channel_wire:snapshot()},
    retiring := #{hls_nums:u32() => inspect | {fence, hls_nums:u64()}},
    uncertain := #{hls_nums:u32() => hls_domain_channel_wire:command()},
    queued := non_neg_integer(),
    ignored := non_neg_integer()
}.
%% One owner may claim several channels, each with an independent revocable capability.
-type owner() :: #{pid := pid(), monitor := reference(), authority := reference()}.
%% A current exchange retains the exact command even if its submitting owner dies.
-type exchange() :: #{
    channel := hls_nums:u32(),
    command := hls_domain_channel_wire:command(),
    from := none | gen_server:from(),
    retirement := boolean(),
    sequence => hls_nums:u32(),
    timer => reference()
}.
%% Retirement commands have bounded storage in the declared channel map, outside the caller queue.
-record(backend, {
    broker :: pid(),
    broker_monitor :: reference(),
    route :: hls_fabric:route(),
    session :: hls_nums:u64(),
    interface :: hls_domain_channel_wire:interface(),
    owners = #{} :: #{hls_nums:u32() => owner()},
    retiring = #{} :: #{hls_nums:u32() => inspect | {fence, hls_nums:u64()}},
    uncertain = #{} :: #{hls_nums:u32() => hls_domain_channel_wire:command()},
    observed = #{} :: #{hls_nums:u32() => hls_domain_channel_wire:snapshot()},
    queue = queue:new() :: queue:queue(exchange()),
    exchange = none :: none | exchange(),
    sequence = 1 :: pos_integer(),
    writing = false :: boolean(),
    prefer_retirement = true :: boolean(),
    retirement_cursor = -1 :: integer(),
    sends = gen_server:reqids_new() :: gen_server:request_id_collection(),
    timeout_ms = 1000 :: pos_integer(),
    ignored = 0 :: non_neg_integer()
}).

-doc "Registers one management route without resetting channels or acquiring per-channel authority. Optional name uses ordinary local OTP registration for stable supervisor child specifications.".
-spec start_link(
    transport(), hls_domain_channel_wire:interface() | map() | file:filename(), options()
) -> gen_server:start_ret().
start_link(Transport, Interface, Options) ->
    Args = {Transport, Interface, Options},
    case maps:find(name, Options) of
        error -> gen_server:start_link(?MODULE, Args, []);
        {ok, Name} when is_atom(Name) -> gen_server:start_link({local, Name}, ?MODULE, Args, [])
    end.
-doc "Claims one channel for the actual local caller; old-owner retirement must complete first.".
-spec attach(pid(), hls_nums:u32(), pid()) -> {ok, reference()} | {error, atom()}.
attach(Backend, Channel, Owner) -> gen_server:call(Backend, {attach, Channel, Owner}).
-doc "Obtains ordered device evidence; a status response can resolve a previously lost mutation reply.".
-spec status(pid(), hls_nums:u32()) -> {ok, hls_domain_channel_wire:snapshot()} | {error, term()}.
status(Backend, Channel) -> gen_server:call(Backend, {status, Channel}, infinity).
-doc "Submits one capability-authorized command. An outcome_unknown error retains its exact identity; inspect before making another decision.".
-spec request(pid(), reference(), hls_nums:u32(), hls_domain_channel_wire:command()) ->
    {ok, hls_domain_channel_wire:snapshot()} | {error, term()}.
request(Backend, Authority, Channel, Command) ->
    gen_server:call(Backend, {request, Authority, Channel, Command}, infinity).
-doc "Starts a correlated request from the same owner process; no temporary worker gains mutation authority.".
-spec send_request(pid(), request()) -> gen_server:request_id().
send_request(Backend, Request) -> gen_server:send_request(Backend, Request).
-doc "Stops this local adapter without resetting the device or closing deployment-owned brokers.".
-spec stop(pid()) -> ok.
stop(Backend) -> gen_server:stop(Backend).
-doc "Returns bounded control metadata; no application payload or completed-work history is stored.".
-spec info(pid()) -> info().
info(Backend) -> gen_server:call(Backend, info).

-doc "Checks the retained interface and establishes exclusive broker-route delivery.".
-spec init({transport(), hls_domain_channel_wire:interface() | map() | file:filename(), options()}) ->
    {ok, #backend{}}.
init({#{management := Broker, session := Session}, Interface0, Options}) ->
    true = is_integer(Session) andalso Session > 0 andalso Session < (1 bsl 64),
    [] = maps:keys(Options) -- [management_timeout_ms, name],
    Timeout = maps:get(management_timeout_ms, Options, 1000),
    true = is_integer(Timeout) andalso Timeout > 0,
    Interface = #{management_route := Route} = hls_domain_channel_wire:load(Interface0),
    ok = hls_fabric:register_route(Broker, Route, self()),
    {ok, #backend{
        broker = Broker,
        broker_monitor = monitor(process, Broker),
        route = Route,
        session = Session,
        interface = Interface,
        timeout_ms = Timeout
    }}.

-doc "Orders management while keeping authority and retirement separate per declared channel.".
-spec handle_call(term(), gen_server:from(), #backend{}) ->
    {reply, term(), #backend{}} | {noreply, #backend{}}.
%% Only the requesting local owner may acquire or repeat its channel capability.
handle_call({attach, Channel, Owner}, {Owner, _}, State) when node(Owner) =:= node() ->
    attach_channel(Channel, Owner, State);
%% Inspection is read-only and always gets fresh framed evidence.
handle_call({status, Channel}, From, State) ->
    enqueue(Channel, inspect, From, State);
%% Capability possession and actual caller identity are both required for mutation.
handle_call(
    {request, Authority, Channel, Command},
    {Owner, _} = From,
    State = #backend{owners = Owners, uncertain = Uncertain}
) ->
    case maps:find(Channel, Owners) of
        {ok, #{pid := Owner, authority := Authority}} when is_reference(Authority) ->
            case maps:find(Channel, Uncertain) of
                {ok, Pending} when Command =/= inspect ->
                    {reply, {error, {outcome_unknown, Pending}}, State};
                _ ->
                    enqueue(Channel, Command, From, State)
            end;
        _ ->
            {reply, {error, unauthorized}, State}
    end;
%% Diagnostics expose only bounded retained authority and command state.
handle_call(info, _From, State) ->
    {reply,
        #{
            session => State#backend.session,
            observed => State#backend.observed,
            retiring => State#backend.retiring,
            uncertain => State#backend.uncertain,
            queued => queue:len(State#backend.queue),
            ignored => State#backend.ignored
        },
        State};
%% Unsupported calls cannot become hardware controls.
handle_call(_, _, State) ->
    {reply, {error, unauthorized}, State}.

-doc "Consumes complete canonical replies and always releases their broker delivery receipt.".
-spec handle_cast(term(), #backend{}) -> {noreply, #backend{}} | {stop, term(), #backend{}}.
%% Only this adapter's registered management route may complete a control exchange.
handle_cast(
    {'$hls_fabric_frame', Receipt, Route, Header, Payload},
    State = #backend{broker = Broker, route = Route}
) ->
    try
        {Tag, 0, 0} = Header,
        frame(Tag, Payload, State)
    of
        Next ->
            hls_fabric:ack(Broker, Receipt),
            {noreply, pump(Next)}
    catch
        Class:Reason ->
            hls_fabric:ack(Broker, Receipt),
            {stop, {invalid_channel_frame, Class, Reason}, State}
    end;
%% There is no application-forwarding cast path through the management adapter.
handle_cast(_, State) ->
    {noreply, State}.

-doc "Retains uncertain mutations and owner-loss fencing without replaying transmitted commands.".
-spec handle_info(term(), #backend{}) -> {noreply, #backend{}} | {stop, term(), #backend{}}.
%% Broker loss is transport uncertainty, not evidence that channels or actors stopped.
handle_info({'DOWN', Ref, process, _Broker, Reason}, State = #backend{broker_monitor = Ref}) ->
    {stop, {transport_down, Reason}, State};
%% A dead owner cannot leave queued binds behind a successor's fence.
handle_info({'DOWN', Ref, process, _Owner, _Reason}, State) ->
    Channels = [
        Channel
     || {Channel, #{monitor := Monitor}} <- maps:to_list(State#backend.owners), Monitor =:= Ref
    ],
    {noreply, pump(lists:foldl(fun retire_owner/2, State, Channels))};
%% A missing reply permits ordered inspection, never retransmission or guessed success.
handle_info(
    {management_timeout, Sequence}, State = #backend{exchange = #{sequence := Sequence} = Entry}
) ->
    #{channel := Channel, command := Command, from := From} = Entry,
    Unknown =
        case Command of
            inspect -> State#backend.uncertain;
            _ -> (State#backend.uncertain)#{Channel => Command}
        end,
    answer(
        From,
        case Command of
            inspect -> {error, noconnection};
            _ -> {error, {outcome_unknown, Command}}
        end
    ),
    Retiring =
        case maps:get(retirement, Entry) of
            true -> (State#backend.retiring)#{Channel => inspect};
            false -> State#backend.retiring
        end,
    Next = State#backend{exchange = none, uncertain = Unknown, retiring = Retiring},
    {noreply, pump(Next)};
%% Physical write completion is independent of a management response and bounds outstanding writes.
handle_info(Message, State = #backend{sends = Sends}) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, ok}, _Label, Rest} ->
            {noreply, pump(State#backend{sends = Rest, writing = false})};
        {{reply, Failure}, _Label, Rest} ->
            {stop, {write_failed, Failure}, State#backend{sends = Rest}};
        {{error, Failure}, _Label, Rest} ->
            {stop, {write_failed, Failure}, State#backend{sends = Rest}};
        _ ->
            {noreply, State}
    end.

-doc "Returns uncertainty to retained callers; adapter teardown neither fences nor replays device commands.".
-spec terminate(term(), #backend{}) -> ok.
terminate(_Reason, State) ->
    case State#backend.exchange of
        none -> ok;
        #{from := From} -> answer(From, {error, noconnection})
    end,
    [
        answer(maps:get(from, Entry), {error, noconnection})
     || Entry <- queue:to_list(State#backend.queue)
    ],
    ok.

%% Attachment cannot bypass an unfinished fence for the previous local owner.
-spec attach_channel(hls_nums:u32(), pid(), #backend{}) -> {reply, term(), #backend{}}.
attach_channel(
    Channel,
    Owner,
    State = #backend{interface = #{channels := Channels}, owners = Owners, retiring = Retiring}
) ->
    case lists:member(Channel, Channels) of
        false ->
            {reply, {error, unknown_channel}, State};
        true ->
            case maps:is_key(Channel, Retiring) of
                true ->
                    {reply, {error, retiring}, State};
                false ->
                    case maps:find(Channel, Owners) of
                        {ok, #{pid := Owner, authority := Authority}} ->
                            {reply, {ok, Authority}, State};
                        {ok, _} ->
                            {reply, {error, owned}, State};
                        error ->
                            Authority = make_ref(),
                            Entry = #{
                                pid => Owner,
                                authority => Authority,
                                monitor => monitor(process, Owner)
                            },
                            {reply, {ok, Authority}, State#backend{
                                owners = Owners#{Channel => Entry}
                            }}
                    end
            end
    end.

%% One active and at most eight waiting caller requests bound shared control storage.
-spec enqueue(hls_nums:u32(), hls_domain_channel_wire:command(), gen_server:from(), #backend{}) ->
    {reply, term(), #backend{}} | {noreply, #backend{}}.
enqueue(
    Channel, Command, From, State = #backend{interface = #{channels := Channels}, queue = Queue}
) ->
    case lists:member(Channel, Channels) of
        false ->
            {reply, {error, unknown_channel}, State};
        true ->
            case {valid_command(Command), queue:len(Queue) < 8} of
                {false, _} ->
                    {reply, {error, invalid}, State};
                {true, false} ->
                    {reply, {error, busy}, State};
                {true, true} ->
                    Entry = #{
                        channel => Channel, command => Command, from => From, retirement => false
                    },
                    {noreply, pump(State#backend{queue = queue:in(Entry, Queue)})}
            end
    end.

%% Alternate caller work and retirement; round robin prevents one lost channel monopolizing the lane.
-spec pump(#backend{}) -> #backend{}.
pump(
    State = #backend{
        exchange = none,
        writing = false,
        retiring = Retiring,
        queue = Queue,
        prefer_retirement = Prefer
    }
) ->
    case map_size(Retiring) > 0 andalso (Prefer orelse queue:is_empty(Queue)) of
        true ->
            Channels = lists:sort(maps:keys(Retiring)),
            Later = [C || C <- Channels, C > State#backend.retirement_cursor],
            Channel = hd(
                case Later of
                    [] -> Channels;
                    _ -> Later
                end
            ),
            transmit(
                #{
                    channel => Channel,
                    command => maps:get(Channel, Retiring),
                    from => none,
                    retirement => true
                },
                State#backend{prefer_retirement = false, retirement_cursor = Channel}
            );
        false ->
            pump_caller(State)
    end;
pump(State) ->
    State.

%% An uncertain channel blocks only its own new mutations; ordered inspections remain available.
-spec pump_caller(#backend{}) -> #backend{}.
pump_caller(State = #backend{queue = Queue}) ->
    case queue:out(Queue) of
        {empty, _} ->
            State;
        {{value, Entry}, Rest} ->
            #{channel := Channel, command := Command, from := From} = Entry,
            Next = State#backend{queue = Rest, prefer_retirement = true},
            case maps:find(Channel, State#backend.uncertain) of
                {ok, Pending} when Command =/= inspect ->
                    answer(From, {error, {outcome_unknown, Pending}}),
                    pump(Next);
                _ ->
                    transmit(Entry, Next)
            end
    end.

%% Validate public mutation fields before they can reach the shared packet encoder.
-spec valid_command(term()) -> boolean().
valid_command(inspect) ->
    true;
valid_command({fence, Expected}) ->
    u64(Expected);
valid_command({bind, Expected, Source, Destination}) ->
    u64(Expected) andalso u64(Source) andalso Source > 0 andalso u64(Destination) andalso
        Destination > 0;
valid_command(_) ->
    false.

%% Untyped messages cannot silently truncate fixed-width generations or incarnations.
-spec u64(term()) -> boolean().
u64(Value) -> is_integer(Value) andalso Value >= 0 andalso Value < (1 bsl 64).

%% Only completed physical writes allow the next framed command to enter the ordered broker lane.
-spec transmit(exchange(), #backend{}) -> #backend{}.
transmit(Entry = #{channel := Channel, command := Command}, State) ->
    Sequence = State#backend.sequence,
    true = Sequence < (1 bsl 32),
    true = gen_server:reqids_size(State#backend.sends) =:= 0,
    {Tag, Payload} = hls_domain_channel_wire:command(
        State#backend.session, Sequence, Channel, Command, State#backend.interface
    ),
    Timer = erlang:send_after(State#backend.timeout_ms, self(), {management_timeout, Sequence}),
    Request = hls_fabric:send_request(
        State#backend.broker, State#backend.route, {Tag, 0, 0}, Payload, State#backend.timeout_ms
    ),
    State#backend{
        exchange = Entry#{sequence => Sequence, timer => Timer},
        sequence = Sequence + 1,
        writing = true,
        sends = gen_server:reqids_add(Request, management, State#backend.sends)
    }.

%% Old sessions are discardable even after a transport reconnect; malformed current evidence is not.
-spec frame(byte(), binary(), #backend{}) -> #backend{}.
frame(_Tag, <<Session:64/little, _/binary>>, State = #backend{session = Current}) when
    Session =/= Current
->
    State#backend{ignored = State#backend.ignored + 1};
frame(1, Payload, State) ->
    response(hls_domain_channel_wire:observation(Payload, State#backend.interface), State).

%% An ordered inspection resolves whether an earlier pulse reached this same transport session.
-spec response(hls_domain_channel_wire:observation(), #backend{}) -> #backend{}.
response(
    #{session := Session, request := Sequence, channel := Channel, snapshot := Snapshot},
    State = #backend{
        session = Session,
        exchange = #{
            sequence := Sequence,
            channel := Channel,
            timer := Timer,
            from := From,
            command := Command,
            retirement := Retirement
        }
    }
) ->
    erlang:cancel_timer(Timer),
    case maps:find(Channel, State#backend.observed) of
        {ok, #{generation := Previous}} -> true = maps:get(generation, Snapshot) >= Previous;
        error -> ok
    end,
    Unknown =
        case Command of
            inspect -> maps:remove(Channel, State#backend.uncertain);
            _ -> State#backend.uncertain
        end,
    Next = State#backend{
        exchange = none,
        observed = (State#backend.observed)#{Channel => Snapshot},
        uncertain = Unknown
    },
    answer(From, {ok, Snapshot}),
    case Retirement of
        true ->
            case Snapshot of
                #{active := false, fault := false} ->
                    Next#backend{retiring = maps:remove(Channel, Next#backend.retiring)};
                #{active := true, generation := Generation} ->
                    Next#backend{
                        retiring = (Next#backend.retiring)#{Channel => {fence, Generation}}
                    };
                _ ->
                    Next#backend{retiring = (Next#backend.retiring)#{Channel => inspect}}
            end;
        false ->
            Next
    end;
response(_Observation, State) ->
    State#backend{ignored = State#backend.ignored + 1}.

%% Keep submitted ownership, but discard every unsent command from a dead channel owner.
-spec retire_owner(hls_nums:u32(), #backend{}) -> #backend{}.
retire_owner(Channel, State) ->
    {Removed, Keep} = lists:partition(
        fun(#{channel := C}) -> C =:= Channel end, queue:to_list(State#backend.queue)
    ),
    [answer(maps:get(from, Entry), {error, owner_down}) || Entry <- Removed],
    State#backend{
        owners = maps:remove(Channel, State#backend.owners),
        retiring = (State#backend.retiring)#{Channel => inspect},
        queue = queue:from_list(Keep)
    }.

%% Internal retirement work has no caller, while ordinary aliases receive exactly one outcome.
-spec answer(none | gen_server:from(), term()) -> ok.
answer(none, _) -> ok;
answer(From, Reply) -> gen_server:reply(From, Reply).
