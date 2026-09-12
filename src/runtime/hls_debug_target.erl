-module(hls_debug_target).
-moduledoc "Scoped current-state inspection; event collection remains a separate operation.".
-export([info/3, collect/3, inspect_waits/2]).
-export_type([target/0]).

-type target() :: pid() | {hls_statem, pid()} |
    {resource, map(), non_neg_integer()} | {boundary, pid(), term()} |
    {actor, map(), none | {hls_statem, pid()} | {actor_snapshot, map(), non_neg_integer()}}.

%% A list requests one provider snapshot. Metadata-only requests do not contact
%% the target. CPU state and its front-end BEAM queue have separate observations.
-spec info(target(), atom() | [atom()], timeout()) -> term().
info(Target, Item, Timeout) when is_atom(Item) ->
    case info(Target, [Item], Timeout) of
        [Pair] -> Pair;
        Other -> Other
    end;
info(Target, Items, Timeout) when is_list(Items) ->
    {Metadata, Fields, Provider} = describe(Target),
    #{scope := Scope} = Metadata,
    Static = Metadata#{capabilities => #{info => lists:sort(maps:keys(Metadata) ++
        [capabilities | Fields]), counters => is_boundary(Target), trace => is_boundary(Target),
        inspect_waits => is_resource(Target)}},
    Unknown = lists:usort(Items) -- (maps:keys(Static) ++ Fields),
    case Unknown of
        [] ->
            Needed = lists:usort(Items -- maps:keys(Static)),
            case observe(Provider, Needed, Timeout) of
                {ok, Snapshot} ->
                    Values = maps:merge(Static, Snapshot),
                    [{Item, maps:get(Item, Values)} || Item <- Items];
                Error -> Error
            end;
        _ -> {error, {unsupported_items, Scope, Unknown}}
    end.

collect({boundary, Client, Id}, Operation, Timeout) ->
    Result = case Operation of
        get_counters -> hls_debug:get_counters(Client, Timeout);
        get_trace -> hls_debug:get_trace(Client, Timeout)
    end,
    case Result of
        {ok, Values} -> {ok, Values#{scope => #{kind => boundary, id => Id}}};
        Error -> Error
    end;
collect(Target, Operation, _Timeout) ->
    {Metadata, _, _} = describe(Target),
    {error, {unsupported_operation, maps:get(scope, Metadata), Operation}}.

inspect_waits({resource, Session, Id} = Target, Options) ->
    case is_resource(Target) of
        true -> hls_topology_debug:inspect_waits(Session, [Id], Options);
        false -> unsupported_wait(Target)
    end;
inspect_waits(Target, _Options) ->
    unsupported_wait(Target).

unsupported_wait(Target) ->
    {Metadata, _, _} = describe(Target),
    {error, {unsupported_operation, maps:get(scope, Metadata), inspect_waits}}.

describe(Pid) when is_pid(Pid) ->
    {#{scope => #{kind => beam_process, pid => Pid}},
        [message_queue_len, status, reductions, memory], {beam, Pid}};
describe({hls_statem, Pid}) ->
    {#{scope => #{kind => cpu_actor, pid => Pid}}, statem_fields(), {statem, Pid}};
describe({actor, Metadata, Provider}) ->
    {Fields, Source} = actor_provider(Provider),
    {Metadata, Fields, Source};
describe({boundary, _Client, Id}) ->
    {#{scope => #{kind => boundary, id => Id}}, [], none};
describe({resource, Session = #{resources := Resources, manifest := Manifest}, Id})
        when Id >= 0, Id < tuple_size(Resources) ->
    Resource = element(Id+1, Resources),
    #{<<"kind">> := Kind, <<"name">> := Name} = Resource,
    Fields = case Kind of
        <<"fifo">> -> [occupancy, free_slots];
        <<"channel">> -> [valid, ready];
        <<"actor">> -> actor_fields()
    end,
    Metadata = #{scope => #{kind => topology_resource,
        fingerprint => maps:get(<<"fingerprint">>, Manifest), id => Id},
        resource_kind => Kind, name => Name},
    WithCapacity = case Resource of
        #{<<"capacity">> := Capacity} -> Metadata#{capacity => Capacity};
        _ -> Metadata
    end,
    {WithCapacity, [cycle, value | Fields], {resource, Session, Id}}.

statem_fields() ->
    [message_queue_len, mailbox_capacity, free_slots, reserved, postponed,
        phase, lifecycle, beam_message_queue_len].

actor_fields() -> [initialized, phase, enter_pending, failed, failure].

actor_provider(none) -> {[], none};
actor_provider({hls_statem, Pid}) -> {statem_fields(), {statem, Pid}};
actor_provider({actor_snapshot, _, _} = Provider) -> {[cycle | actor_fields()], Provider}.

observe(_Provider, [], _Timeout) -> {ok, #{}};
observe({actor_snapshot, Session, Id}, Fields, Timeout) ->
    case observe({resource, Session, Id}, Fields, Timeout) of
        {ok, Snapshot = #{phase := Phase}} when is_binary(Phase) ->
            %% Catalog binding already checked the codebook against loaded actors.
            {ok, Snapshot#{phase := binary_to_existing_atom(Phase),
                failure := actor_failure(maps:get(failure, Snapshot))}};
        Other -> Other
    end;
observe({beam, Pid}, Fields, _Timeout) ->
    case erlang:process_info(Pid, Fields) of
        undefined -> undefined;
        Values -> {ok, maps:from_list(Values)}
    end;
observe({resource, Session, Id}, _Fields, Timeout) ->
    try hls_topology_debug:query(Session, Id, Timeout)
    catch
        exit:{noproc, _} -> undefined;
        exit:{timeout, _} -> {error, timeout}
    end;
observe({statem, Pid}, Fields, Timeout) ->
    %% A BEAM-only query must not wait for an application callback to finish.
    StateFields = Fields -- [beam_message_queue_len],
    try
        State = case StateFields of
            [] -> #{};
            _ ->
                #{mailbox := #{committed := Count, capacity := Capacity,
                    available := Free, reserved := Reserved}, postponed := Postponed,
                    phase := Phase, lifecycle := Lifecycle} = hls_statem:info(Pid, Timeout),
                #{message_queue_len => Count, mailbox_capacity => Capacity,
                    free_slots => Free, reserved => Reserved, postponed => Postponed,
                    phase => Phase, lifecycle => Lifecycle}
        end,
        case lists:member(beam_message_queue_len, Fields) of
            false -> {ok, State};
            true ->
                case erlang:process_info(Pid, message_queue_len) of
                    undefined -> undefined;
                    {message_queue_len, Count0} -> {ok, State#{beam_message_queue_len => Count0}}
                end
        end
    catch
        exit:{noproc, _} -> undefined;
        exit:{timeout, _} -> {error, timeout}
    end.

is_boundary({boundary, _, _}) -> true;
is_boundary(_) -> false.
is_resource({resource, #{resources := Resources}, Id}) ->
    maps:get(<<"kind">>, element(Id+1, Resources)) =/= <<"actor">>;
is_resource(_) -> false.

actor_failure(Failure = #{kind := Kind}) -> Failure#{kind := binary_to_existing_atom(Kind)};
actor_failure(none) -> none.
