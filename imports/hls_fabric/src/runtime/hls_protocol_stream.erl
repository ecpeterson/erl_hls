-module(hls_protocol_stream).
-moduledoc """
Application clients start this owner over independently compiled RTL roles and existing brokers. It combines retained application codecs with hls_protocol_relay_queue and owns all framed writes and event delivery.

One bounded framed owner for a fixed deployment of source-protocol RTL partitions. The sole application client submits ordered controls and consumes canonical external frames. Any participant failure retires all deployment routes; no write is retried. Transport closure and coordinated hardware reset remain caller obligations.
""".
-behaviour(gen_server).
%% Public deployment-session API.
-export([start_link/3, start_application/3, submit/2, next/2, info/1, stop/1]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% Deployment keys are caller-defined Erlang terms, independent of wire addresses.
-type role() :: term().
%% A participant progresses independently; aggregate start waits for all roles.
-type phase() :: pending | attaching | attached | starting | running.
%% One command retains the unissued suffix of its ordered device fanout.
-type command() :: {nonempty_list(role()), start | binary()}.
%% Events retain raw frames until the sole consumer's application codec runs.
-type event() :: {application, {started}} | {{role(), byte()}, non_neg_integer()}.
%% A waiter owns both the response alias and its cancellable timer.
-type waiter() :: none | {gen_server:from(), reference(), reference()}.
%% Broker receipt credit is independent of logical pair credit and source ACKs.
-type receipt() :: {reference(), hls_fabric:header(), binary()}.
%% The relay queue binds physical completion to a particular pair and sequence.
-type packet_token() :: hls_protocol_relay_queue:token().
%% Exactly one broker request may be outstanding across the deployment.
-type writer_tag() :: {role(), attach | control | {packet, packet_token()}}.
%% Scheduling reserves ownership before issue_write performs the broker effect.
-type write_request() :: #{tag := writer_tag(), frame := {hls_fabric:header(), binary()}}.
%% A blocked decision can retain changes already made by the current work pass.
-type write_decision() :: {wait, state()} | {send, write_request(), state()}.
%% This owner types its own lifecycle and retention; plans and relay queue stay
%% under their respective modules' contracts rather than duplicating their schema.
-type state() :: #{
    application := raw | map(),
    devices := #{role() => map()},
    roles := [role()],
    returns := #{{pos_integer(), pos_integer()} => role()},
    limits := #{commands := pos_integer(), events := pos_integer(), crossings := pos_integer()},
    record_limit := pos_integer(),
    brokers := #{role() => pid()},
    sessions := #{role() => pos_integer()},
    client := pid(),
    monitors := #{reference() => client | {device, role()}},
    identities := #{role() => binary()},
    queue := hls_protocol_relay_queue:state(),
    phases := #{role() => phase()},
    phase := phase(),
    starts := boolean(),
    commands := queue:queue(command()),
    events := queue:queue(event()),
    held := #{role() => receipt()},
    writer := none | writer_tag(),
    sends := gen_server:request_id_collection(),
    waiter := waiter(),
    retiring := none | gen_server:from(),
    received := non_neg_integer(),
    written := non_neg_integer()
}.

-doc "Attaches one fresh broker per deployment device using the descriptor's identity, host and service. Device keys must match brokers and distinct nonzero sessions. Return route pairs must be unique because broker deliveries contain a route but no broker identity. All participants share one reset/retirement domain; the caller exclusively owns commands/events and must retire old transports before reuse.".
-spec start_link(map(), map(), map()) -> gen_server:start_ret().
start_link(Plan, Brokers, Sessions) ->
    gen_server:start_link(?MODULE, {Plan, Brokers, Sessions, self(), raw}, []).

-doc "Attaches a fresh deployment emitted by hls_protocol_deployment with source-checked application codecs. submit accepts typed rectangle commands and next returns {ok,Device,External,Record}; aggregate start uses Device=application. The same bounded owner, crossing queue and collective retirement rules apply; descriptors must be trusted local build outputs.".
-spec start_application(map(), map(), map()) -> gen_server:start_ret().
start_application(Plan = #{application := Application}, Brokers, Sessions) ->
    gen_server:start_link(?MODULE, {Plan, Brokers, Sessions, self(), Application}, []).
-doc "Admits raw control bytes (start_link) or a source-checked typed rectangle (start_application), or one-shot start within the deployment command limit. A command reaches all participants before the next command is issued; recipients are not atomically updated. Failure after partial delivery is terminal and must never trigger replay.".
-spec submit(pid(), hls_partition_wire:command() | {control, binary()}) -> {ok, 1} | {error, busy}.
submit(Pid, Command) -> gen_server:call(Pid, {submit, Command}, infinity).
-doc "Returns a canonical external frame in raw mode or a decoded {ok,Device,External,Record} in application mode, or timeout after cancelling the sole waiter. The single started event precedes application output and means all participants acknowledged start; this is not a simultaneous clock-edge guarantee.".
-spec next(pid(), pos_integer()) ->
    {ok, application | {term(), byte()}, term()} | {ok, term(), term(), tuple()} | timeout.
next(Pid, Timeout) -> gen_server:call(Pid, {next, Timeout}, infinity).
-doc "Reports bounded categories and packet counters without private actor state. ERTS client mailboxes and OS transport buffers are outside the record count.".
-spec info(pid()) -> map().
info(Pid) -> gen_server:call(Pid, info).
-doc "Stops new work and waits for the current physical write, then retires all registered routes by ending their owner. Caller must close all transports and await descriptor release before resetting any participant.".
-spec stop(pid()) -> ok.
stop(Pid) -> gen_server:call(Pid, retire, infinity).

-doc "Checks static deployment routing and fresh sessions before reserving distinct return routes and starting serialized attachment. Each broker may hold one credited frame for this owner.".
-spec init({map(), map(), map(), pid(), raw | map()}) -> {ok, state()}.
init({
    Plan = #{
        devices := Devices,
        limits := Limits = #{commands := Commands, events := Events, crossings := Crossings}
    },
    Brokers,
    Sessions,
    Client,
    Application
}) when
    is_integer(Commands), Commands > 0, is_integer(Events), Events >= 2
->
    case Application of
        raw -> ok;
        _ -> ok = hls_partition_wire:check(Application)
    end,
    Routing = hls_protocol_routing:plan(Plan),
    Roles = hls_protocol_routing:roles(Routing),
    Roles = lists:sort(maps:keys(Brokers)),
    true = length(Roles) =:= length(lists:usort(maps:values(Brokers))),
    Queue = hls_protocol_relay_queue:new(Routing, Sessions),
    Bindings = [
        begin
            true = is_integer(Host) andalso Host > 0 andalso Host < 65536,
            true =
                is_integer(Service) andalso Service > 0 andalso Service < 65536 andalso
                    Service =/= Host,
            true = is_binary(Identity) andalso byte_size(Identity) =:= 32,
            {{Service, Host}, Role}
        end
     || {Role, #{host := Host, service := Service, identity := Identity}} <- maps:to_list(Devices)
    ],
    Returns = maps:from_list(Bindings),
    true = map_size(Returns) =:= length(Roles),
    [
        ok = hls_fabric:register_route(maps:get(Role, Brokers), Route, self())
     || {Route, Role} <- Bindings
    ],
    Monitors = maps:from_list([
        {monitor(process, Pid), {device, Role}}
     || {Role, Pid} <- maps:to_list(Brokers)
    ]),
    State = #{
        application => Application,
        devices => Devices,
        roles => Roles,
        returns => Returns,
        limits => Limits,
        record_limit => Commands + Events + Crossings + length(Roles) + 1,
        brokers => Brokers,
        sessions => Sessions,
        client => Client,
        monitors => Monitors#{monitor(process, Client) => client},
        identities => maps:map(fun(_, #{identity := Identity}) -> Identity end, Devices),
        queue => Queue,
        phases => maps:from_keys(Roles, pending),
        phase => attaching,
        starts => false,
        commands => queue:new(),
        events => queue:new(),
        held => #{},
        writer => none,
        sends => gen_server:reqids_new(),
        waiter => none,
        retiring => none,
        received => 0,
        written => 0
    },
    {ok, work(State)}.

-doc "Serializes control admission, one bounded read and graceful retirement for the sole client.".
-spec handle_call(term(), gen_server:from(), state()) ->
    {reply, term(), state()} | {noreply, state()} | {stop, normal, ok, state()}.
%% Retire only after the outstanding write is definite; issue no further packets.
handle_call(
    retire, From = {Client, _}, S = #{client := Client, retiring := none, writer := Writer}
) ->
    case Writer of
        none -> {stop, normal, ok, S};
        _ -> {noreply, S#{retiring := From}}
    end;
%% One command carries a fanout cursor, without duplicate per-device queues.
handle_call(
    {submit, Command},
    {Client, _},
    S = #{
        client := Client,
        commands := Commands,
        starts := Started,
        roles := Roles,
        application := Application,
        limits := #{commands := Limit}
    }
) ->
    case queue:len(Commands) < Limit of
        false ->
            {reply, {error, busy}, S};
        true ->
            Bytes =
                case Command of
                    start ->
                        false = Started,
                        start;
                    _ ->
                        control(Application, Command)
                end,
            Next = S#{
                commands := queue:in({Roles, Bytes}, Commands),
                starts := Started orelse Command =:= start
            },
            {reply, {ok, 1}, work(Next)}
    end;
%% Cancel the timer before replying, avoiding an abandoned late event.
handle_call({next, Timeout}, From = {Client, _}, S = #{client := Client, waiter := none}) when
    Timeout > 0
->
    Token = make_ref(),
    Timer = erlang:send_after(Timeout, self(), {next_timeout, Token}),
    {noreply, work(S#{waiter := {From, Token, Timer}})};
%% Count retained records conservatively, including the writer's descriptor.
handle_call(
    info,
    _,
    S = #{
        queue := Queue,
        commands := Commands,
        events := Events,
        held := Held,
        writer := Writer,
        record_limit := Limit
    }
) ->
    QueueInfo = hls_protocol_relay_queue:info(Queue),
    Counts = #{
        crossings => maps:get(records, QueueInfo),
        commands => queue:len(Commands),
        events => queue:len(Events),
        held => map_size(Held),
        writer => occupied(Writer)
    },
    true = lists:sum(maps:values(Counts)) =< Limit,
    Info = (maps:with([phase, phases, received, written], S))#{
        counts => Counts,
        record_limit => Limit,
        packets => QueueInfo
    },
    {reply, Info, S}.

-doc "Accepts one credited broker frame per role. Distinct return routes bind the sender before packet validation.".
-spec handle_cast(term(), state()) -> {noreply, state()}.
%% Broker receipt credit is separate from destination capacity and source delivery ACK.
handle_cast(
    {'$hls_fabric_frame', Receipt, Route, Header, Payload}, S = #{held := Held, returns := Returns}
) ->
    Role = maps:get(Route, Returns),
    false = maps:is_key(Role, Held),
    {noreply, work(S#{held := Held#{Role => {Receipt, Header, Payload}}})}.

-doc "Commits definite physical completion, cancels timed-out reads and stops globally on participant failure. Every write error is terminal, including definitely-unsent writes.".
-spec handle_info(term(), state()) -> {noreply, state()} | {stop, term(), state()}.
%% Any transport or client death invalidates all credits and attachments.
handle_info({'DOWN', Ref, process, _, Reason}, S = #{monitors := Monitors}) ->
    {stop, {shutdown, {maps:get(Ref, Monitors), Reason}}, S};
%% Remove the sole waiter before returning timeout.
handle_info({next_timeout, Token}, S = #{waiter := {From, Token, _}}) ->
    gen_server:reply(From, timeout),
    {noreply, S#{waiter := none}};
%% A cancelled timer may already have delivered its message.
handle_info({next_timeout, _}, S) ->
    {noreply, S};
%% Only physical completion makes a peer-delivery ACK eligible; retirement issues nothing further.
handle_info(
    Message, S = #{sends := Sends, writer := Writer, written := Count, retiring := Retiring}
) ->
    case gen_server:check_response(Message, Sends, true) of
        {{reply, ok}, Writer, Rest} ->
            Next = completed(Writer, S#{writer := none, sends := Rest, written := Count + 1}),
            case Retiring of
                none ->
                    {noreply, work(Next)};
                From ->
                    gen_server:reply(From, ok),
                    {stop, normal, Next}
            end;
        {{reply, Error}, _, _} ->
            {stop, {shutdown, {write_failed, Error}}, S};
        {{error, Error}, _, _} ->
            {stop, {shutdown, {writer_failed, Error}}, S};
        _ ->
            {noreply, S}
    end.

-doc "Cancels a pending read timer. Owner death retires all monitored broker routes; callers must still await transport closure and reset before replacement.".
-spec terminate(term(), state()) -> ok.
terminate(_, #{waiter := Waiter}) ->
    case Waiter of
        none ->
            ok;
        {_, _, Timer} ->
            erlang:cancel_timer(Timer),
            ok
    end.

%% One pass preserves broker backpressure: notify, admit each role once, notify,
%% reserve one write. Retirement leaves receipts and commands untouched.
-spec work(state()) -> state().
work(S = #{retiring := From}) when From =/= none -> S;
work(S) ->
    Notified = notify(S),
    Received = receive_frames(Notified),
    Delivered = notify(Received),
    issue_write(prepare_write(Delivered)).

%% Hold application events until aggregate start has been queued in front of them.
-spec notify(state()) -> state().
notify(S = #{phase := Phase}) when Phase =/= running -> S;
notify(S = #{waiter := none}) ->
    S;
notify(S = #{waiter := {From, _, Timer}, events := Events, application := Application}) ->
    case queue:out(Events) of
        {empty, _} ->
            S;
        {{value, {Id, Record}}, Rest} ->
            erlang:cancel_timer(Timer),
            gen_server:reply(From, reply(Application, Id, Record)),
            S#{waiter := none, events := Rest}
    end.

%% One reserved start slot prevents early output from blocking the final start ACK.
-spec receive_frames(state()) -> state().
receive_frames(S = #{roles := Roles}) -> lists:foldl(fun receive_role/2, S, Roles).

%% Release broker credit only after application capacity and ACK completion permit admission.
-spec receive_role(role(), state()) -> state().
receive_role(
    Role, S = #{held := Held, sessions := Sessions, brokers := Brokers, received := Count}
) ->
    case maps:find(Role, Held) of
        error ->
            S;
        {ok, {Receipt, Header, Payload}} ->
            Event = hls_protocol_bridge_wire:event(maps:get(Role, Sessions), Header, Payload),
            case receive_blocked(Role, Event, S) of
                true ->
                    S;
                false ->
                    Next = event(Role, Event, S),
                    hls_fabric:ack(maps:get(Role, Brokers), Receipt),
                    Next#{held := maps:remove(Role, Held), received := Count + 1}
            end
    end.

%% A peer may consume its ACK before our write-completion message arrives. Keep
%% its next same-link data under broker credit until the old reservation retires.
-spec receive_blocked(role(), term(), state()) -> boolean().
receive_blocked(
    Role,
    {packet, #{kind := 1, link := Link}},
    #{writer := {Role, {packet, {ack, Link, _}}}}
) ->
    true;
receive_blocked(_, {external, _, _}, #{events := Events, limits := #{events := Limit}}) ->
    queue:len(Events) >= Limit - 1;
receive_blocked(_, _, _) ->
    false.

%% Participant responses advance local phases; only the final start opens output.
-spec event(role(), term(), state()) -> state().
event(Role, attached, S = #{phases := Phases}) ->
    attaching = maps:get(Role, Phases),
    NextPhases = Phases#{Role := attached},
    Phase =
        case lists:usort(maps:values(NextPhases)) of
            [attached] -> attached;
            _ -> attaching
        end,
    S#{phases := NextPhases, phase := Phase};
event(Role, started, S = #{phases := Phases, events := Events}) ->
    starting = maps:get(Role, Phases),
    NextPhases = Phases#{Role := running},
    case lists:usort(maps:values(NextPhases)) of
        [running] ->
            S#{
                phases := NextPhases,
                phase := running,
                events := queue:in_r({application, {started}}, Events)
            };
        _ ->
            S#{phases := NextPhases}
    end;
event(Role, {packet, Packet}, S = #{queue := Queue}) ->
    S#{queue := hls_protocol_relay_queue:event(Role, Packet, Queue)};
event(Role, {external, Index, Frame}, S = #{devices := Devices, events := Events}) ->
    #{externals := Externals} = maps:get(Role, Devices),
    true = Index < length(Externals),
    Words = Frame band 255,
    true = Words =< 3,
    0 = (Frame bsr 8) band 65535,
    true = (Frame bsr 32) < (1 bsl (Words * 32)),
    S#{events := queue:in({{Role, Index}, Frame}, Events)}.

%% Successful forwarding permits a source ACK; successful ACK releases that pair.
-spec completed(writer_tag(), state()) -> state().
completed({_, {packet, Token}}, S = #{queue := Queue}) ->
    S#{queue := hls_protocol_relay_queue:complete(Token, Queue)};
completed(_, S) ->
    S.

%% Write priority: existing writer, pending attaches, attachment barrier,
%% command fanout, then the relay queue's ACK/data scheduler. Selection is pure.
-spec prepare_write(state()) -> write_decision().
prepare_write(S = #{writer := Writer}) when Writer =/= none -> {wait, S};
prepare_write(S = #{phases := Phases, identities := Identities, sessions := Sessions}) ->
    Pending = [Role || {Role, pending} <- lists:sort(maps:to_list(Phases))],
    case Pending of
        [Role | _] ->
            Frame = hls_protocol_bridge_wire:attach(
                maps:get(Role, Identities), maps:get(Role, Sessions)
            ),
            {send, #{tag => {Role, attach}, frame => Frame}, S#{
                phases := Phases#{Role := attaching}
            }};
        [] ->
            case lists:member(attaching, maps:values(Phases)) of
                true -> {wait, S};
                false -> prepare_command(S)
            end
    end.

%% Reserve exactly one destination from the head command before any pair traffic.
-spec prepare_command(state()) -> write_decision().
prepare_command(S = #{commands := Commands, sessions := Sessions, phases := Phases}) ->
    case queue:out(Commands) of
        {empty, _} ->
            prepare_packet(S);
        {{value, {[Role | Roles], Bytes}}, Rest} ->
            Remaining =
                case Roles of
                    [] -> Rest;
                    _ -> queue:in_r({Roles, Bytes}, Rest)
                end,
            Next =
                case Bytes of
                    start ->
                        attached = maps:get(Role, Phases),
                        S#{phases := Phases#{Role := starting}, phase := starting};
                    _ ->
                        S
                end,
            Frame = hls_protocol_bridge_wire:command(maps:get(Role, Sessions), Bytes),
            {send, #{tag => {Role, control}, frame => Frame}, Next#{commands := Remaining}}
    end.

%% The queue reserves capacity and retains source identity through ACK completion.
-spec prepare_packet(state()) -> write_decision().
prepare_packet(S = #{queue := Queue}) ->
    case hls_protocol_relay_queue:next(Queue) of
        none ->
            {wait, S};
        {Role, Packet, Token, Next} ->
            Request = #{
                tag => {Role, {packet, Token}}, frame => hls_protocol_bridge_wire:packet(Packet)
            },
            {send, Request, S#{queue := Next}}
    end.

%% Issue one reserved request; the response alias carries its role and completion token.
-spec issue_write(write_decision()) -> state().
issue_write({wait, S}) ->
    S;
issue_write(
    {send, #{tag := Tag = {Role, _}, frame := {Header, Payload}},
        S = #{brokers := Brokers, devices := Devices, writer := none, sends := Sends}}
) ->
    #{host := Host, service := Service} = maps:get(Role, Devices),
    Ref = hls_fabric:send_request(
        maps:get(Role, Brokers), {Host, Service}, Header, Payload, infinity
    ),
    S#{writer := Tag, sends := gen_server:reqids_add(Ref, Tag, Sends)}.

%% Count an occupied descriptor without exposing application data.
-spec occupied(term()) -> 0 | 1.
occupied(none) -> 0;
occupied(_) -> 1.

%% Raw and typed modes have distinct command boundaries; neither silently accepts the other's data.
-spec control(raw | map(), term()) -> binary().
control(raw, {control, Payload}) ->
    _ = hls_protocol_bridge_wire:command(1, Payload),
    Payload;
control(Application, Command) when is_map(Application) ->
    hls_protocol_application_codec:control(Application, Command).

%% Decode before returning to the sole caller; no additional event buffering is introduced.
-spec reply(raw | map(), term(), term()) -> tuple().
reply(raw, Id, Record) ->
    {ok, Id, Record};
reply(_, application, {started}) ->
    {ok, application, application, {started}};
reply(Application, {Device, Index}, Frame) ->
    {External, Record} = hls_protocol_application_codec:event(Application, Device, Index, Frame),
    {ok, Device, External, Record}.
