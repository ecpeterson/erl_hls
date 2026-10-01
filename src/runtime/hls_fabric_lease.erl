-module(hls_fabric_lease).
-moduledoc false.
-behavior(gen_server).

%% Reservations outlive brokers and are released only by explicit raw-FD
%% closure. Keep a fail-closed copy across an unexpected registry crash.
-include_lib("kernel/include/file.hrl").
-export([open/3, closed/2, await/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

open(WritePath, ReadPath, Broker) ->
    ensure_started(),
    gen_server:call(?MODULE, {open, WritePath, ReadPath, Broker}).

closed(Lease, Result) -> gen_server:cast(?MODULE, {closed, Lease, self(), Result}).

await(Lease, Timeout) ->
    ensure_started(),
    gen_server:call(?MODULE, {await, Lease, Timeout}, infinity).

ensure_started() ->
    case gen_server:start({local, ?MODULE}, ?MODULE, [], []) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end.

init([]) ->
    Leases = maps:map(fun(_ID, Entry) -> Entry#{status => registry_restarted} end,
        persistent_term:get(?MODULE, #{})),
    {ok, #{leases => Leases, waiters => #{}}}.

handle_call({open, WritePath, ReadPath, Broker}, _From, State) ->
    case {path_keys(WritePath), path_keys(ReadPath)} of
        {{ok, Write, WriteKeys}, {ok, Read, ReadKeys}} ->
            reserve(Write, Read, Broker, lists:usort(WriteKeys ++ ReadKeys), State);
        {{error, _} = Error, _} -> {reply, Error, State};
        {_, Error} -> {reply, Error, State}
    end;
handle_call({await, Lease, Timeout}, From = {Caller, _}, State = #{leases := Leases, waiters := Waiters}) ->
    case Leases of
        #{Lease := #{status := Status}} when Status =/= open, Status =/= closing ->
            {reply, {error, {release_unconfirmed, Status}}, State};
        #{Lease := _} ->
            ID = make_ref(),
            Timer = case Timeout of
                infinity -> none;
                _ -> erlang:start_timer(Timeout, self(), ID)
            end,
            Waiter = {Lease, From, Timer, monitor(process, Caller)},
            {noreply, State#{waiters := Waiters#{ID => Waiter}}};
        _ -> {reply, ok, State}
    end.

handle_cast({closed, Lease, Worker, Result}, State = #{leases := Leases}) ->
    case Leases of
        #{Lease := #{workers := Workers} = Entry} when is_map_key(Worker, Workers) ->
            case Result of
                ok ->
                    Remaining = maps:remove(Worker, Workers),
                    case map_size(Remaining) of
                        0 ->
                            demonitor(maps:get(monitor, Entry), [flush]),
                            {noreply, notify(Lease, ok, save(State#{leases := maps:remove(Lease, Leases)}))};
                        _ -> {noreply, save(State#{leases := Leases#{Lease := Entry#{workers := Remaining}}})}
                    end;
                Error -> {noreply, quarantine(Lease, {close_failed, Worker, Error}, State)}
            end;
        _ -> {noreply, State}
    end.

handle_info({'DOWN', Monitor, process, Pid, Reason}, State = #{leases := Leases}) ->
    Next = maps:fold(fun(Lease, #{monitor := Ref, workers := Workers} = Entry, Acc) ->
        case {Ref =:= Monitor, is_map_key(Pid, Workers)} of
            {true, _} ->
                [Worker ! stop || Worker <- maps:keys(Workers)],
                #{leases := Current} = Acc,
                Status = case maps:get(status, Entry) of open -> closing; Other -> Other end,
                save(Acc#{leases := Current#{Lease := Entry#{status := Status}}});
            {_, true} -> quarantine(Lease, {worker_down, Pid, Reason}, Acc);
            _ -> Acc
        end
    end, State, Leases),
    #{waiters := Waiters} = Next,
    Live = maps:filter(fun(_ID, {_Lease, _From, Timer, Ref}) ->
        case Ref =:= Monitor of
            true -> cancel_timer(Timer), false;
            false -> true
        end
    end, Waiters),
    {noreply, Next#{waiters := Live}};
handle_info({timeout, Timer, ID}, State = #{waiters := Waiters}) ->
    case maps:take(ID, Waiters) of
        {{_Lease, _From, Timer, _Monitor} = Waiter, Rest} ->
            finish_waiter(Waiter, {error, timeout}),
            {noreply, State#{waiters := Rest}};
        error -> {noreply, State}
    end.

reserve(WritePath, ReadPath, Broker, Keys, State = #{leases := Leases}) ->
    Conflicts = [Entry || #{keys := Existing} = Entry <- maps:values(Leases),
        lists:any(fun(Key) -> lists:member(Key, Existing) end, Keys)],
    case Conflicts of
        [#{owner := Owner, status := Status} | _] ->
            {reply, {error, {device_owned, Owner, Status}}, State};
        [] ->
            Lease = make_ref(),
            %% Workers cannot open anything before the reservation is stored.
            Writer = worker(writer, WritePath, Broker, Lease),
            Reader = worker(reader, ReadPath, Broker, Lease),
            Monitor = monitor(process, Broker),
            Entry = #{owner => Broker, monitor => Monitor, keys => Keys,
                workers => #{Writer => pending, Reader => pending}, status => open},
            Next = save(State#{leases := Leases#{Lease => Entry}}),
            Writer ! open, Reader ! open,
            {reply, {ok, Lease, Writer, Reader}, Next}
    end.

worker(Direction, Path, Broker, Lease) ->
    {Pid, _Monitor} = spawn_monitor(fun() ->
        process_flag(trap_exit, true),
        link(Broker),
        receive
            open -> hls_fabric_io:run(Direction, Path, Broker, Lease);
            stop -> closed(Lease, ok);
            {'EXIT', Broker, _} -> closed(Lease, ok)
        end
    end),
    Pid.

save(State = #{leases := Leases}) -> persistent_term:put(?MODULE, Leases), State.

quarantine(Lease, Reason, State = #{leases := Leases}) ->
    Entry = maps:get(Lease, Leases),
    notify(Lease, {error, {release_unconfirmed, Reason}},
        save(State#{leases := Leases#{Lease := Entry#{status := Reason}}})).

notify(Lease, Result, State = #{waiters := Waiters}) ->
    Remaining = maps:filter(fun(_ID, {ID, _From, _Timer, _Monitor} = Waiter) ->
        case ID =:= Lease of
            true -> finish_waiter(Waiter, Result), false;
            false -> true
        end
    end, Waiters),
    State#{waiters := Remaining}.

finish_waiter({_Lease, From, Timer, Monitor}, Result) ->
    cancel_timer(Timer),
    demonitor(Monitor, [flush]),
    gen_server:reply(From, Result).

cancel_timer(none) -> ok;
cancel_timer(Timer) -> erlang:cancel_timer(Timer), ok.

path_keys(Path) ->
    %% Cover alternate spellings and existing symlink/hard-link aliases. A
    %% caller must not replace pathnames while a transport owns them.
    Absolute = filename:absname(Path),
    Name = filename:join(normalize(filename:split(Absolute), [])),
    %% Stat the actual spelling: resolving ".." lexically across a directory
    %% symlink can name a different file than the OS will open.
    case file:read_file_info(Absolute) of
        {ok, #file_info{major_device = Major, minor_device = Minor, inode = Inode}} ->
            {ok, Absolute, [{path, Name}, {inode, Major, Minor, Inode}]};
        {error, Reason} -> {error, {endpoint, Absolute, Reason}}
    end.

normalize([], Acc) -> lists:reverse(Acc);
normalize(["." | Rest], Acc) -> normalize(Rest, Acc);
normalize([".." | Rest], [_Last | Acc]) when Acc =/= [] -> normalize(Rest, Acc);
normalize([Part | Rest], Acc) -> normalize(Rest, [Part | Acc]).
