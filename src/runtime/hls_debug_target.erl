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

%% Reports target identity, supported observations and their sampling scope.
-spec describe(pid() | {'hls_statem',term()} | {'actor',term(),'none' | {'hls_statem',term()} | {'actor_snapshot',map(),non_neg_integer()}} | {'boundary',term(),term()} | {'resource',map(),non_neg_integer()}) -> {term(),[atom()],'none' | {'beam',pid()} | {'statem',term()} | {'actor_snapshot',map(),non_neg_integer()} | {'resource',map(),non_neg_integer()}}.
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
        <<"actor">> -> resource_actor_fields(Session, Resource)
    end,
    Metadata = #{scope => #{kind => topology_resource,
        fingerprint => maps:get(<<"fingerprint">>, Manifest), id => Id},
        resource_kind => Kind, name => Name},
    WithCapacity = case Resource of
        #{<<"capacity">> := Capacity} -> Metadata#{capacity => Capacity};
        #{<<"mailbox_capacity">> := Capacity} -> Metadata#{mailbox_capacity => Capacity};
        _ -> Metadata
    end,
    {WithCapacity, [cycle, value | Fields], {resource, Session, Id}}.

%% CPU actors expose collection progress without returning private element storage.
-spec statem_fields() -> [atom()].
statem_fields() ->
    [message_queue_len, mailbox_capacity, free_slots, reserved, postponed,
        phase, lifecycle, reduction, gather, beam_message_queue_len].

%% A trusted session decoder declares its supported items; wire metadata cannot select code.
-spec resource_actor_fields(map(), map()) -> [atom()].
resource_actor_fields(Session, Resource) ->
    Observer = maps:get(actor_observer, Session, hls_topology_debug),
    Observer:actor_fields(Resource).

%% Selects the explicitly configured local observation decoder for an actor target.
-spec actor_provider('none' | {'hls_statem',term()} | {'actor_snapshot',map(),non_neg_integer()}) -> {[atom()],'none' | {'statem',term()} | {'actor_snapshot',map(),non_neg_integer()}}.
actor_provider(none) -> {[], none};
actor_provider({hls_statem, Pid}) -> {statem_fields(), {statem, Pid}};
actor_provider({actor_snapshot, #{resources := Resources} = Session, Id} = Provider) ->
    {[cycle | resource_actor_fields(Session, element(Id+1, Resources))], Provider}.

%% Read one provider snapshot, keeping actor names in its validated codebook.
-spec observe(term(), [atom()], timeout()) -> {ok, map()} | {error, term()} | undefined.
observe(_Provider, [], _Timeout) -> {ok, #{}};
observe({actor_snapshot, Session, Id}, Fields, Timeout) ->
    case observe({resource, Session, Id}, Fields, Timeout) of
        {ok, Snapshot = #{phase := Phase}} when is_binary(Phase) ->
            %% Catalog binding already checked the codebook against loaded actors.
            {ok, Snapshot#{phase := binary_to_existing_atom(Phase),
                failure := actor_failure(maps:get(failure, Snapshot)),
                reduction := actor_reduction(maps:get(reduction, Snapshot)),
                gather => actor_reduction(maps:get(gather, Snapshot, idle))}};
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
                    phase := Phase, lifecycle := Lifecycle, reduction := Reduction, gather := Gather} = hls_statem:info(Pid, Timeout),
                #{message_queue_len => Count, mailbox_capacity => Capacity,
                    free_slots => Free, reserved => Reserved, postponed => Postponed,
                    phase => Phase, lifecycle => Lifecycle, reduction => cpu_reduction(Reduction, Phase),
                    gather => cpu_gather(Gather, Phase)}
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

actor_reduction(Reduction = #{name := Name, phase := Phase, failure := Failure}) ->
    Reduction#{name := binary_to_existing_atom(Name), phase := binary_to_existing_atom(Phase),
        failure := actor_failure(Failure)};
actor_reduction(Reduction) -> Reduction.

cpu_reduction(idle, _Phase) -> idle;
cpu_reduction(Reduction, Phase) -> Reduction#{status => open, phase => Phase}.

%% Indexed progress preserves captured membership while hiding every collected value.
-spec cpu_gather(idle | map(), atom()) -> idle | map().
cpu_gather(idle, _Phase) -> idle;
cpu_gather(Gather = #{capacity := Capacity, expected := Expected, seen := Seen}, Phase) ->
    Members = [I || I <- lists:seq(0, Capacity - 1), Expected band (1 bsl I) =/= 0],
    Missing = [I || I <- Members, Seen band (1 bsl I) =:= 0],
    Gather#{status => open, phase => Phase, failure => none,
        population => {members, Members}, received => length(Members) - length(Missing),
        missing_members => Missing}.
