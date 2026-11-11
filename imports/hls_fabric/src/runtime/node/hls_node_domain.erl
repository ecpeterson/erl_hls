-module(hls_node_domain).
-moduledoc """
Managed-domain bindings for hls_node. The node manager reads ready endpoints from
hls_domain and allocates external PIDs; it never starts actors or changes lifecycle
state. A binding names one fixed local deployment owner and domain.
""".

%% Internal node-manager binding and publication validation.
-export([snapshot/1, allocate/5, replacement/3]).

-doc "Reads one declared domain's ready local endpoints. Owner loss and non-ready state remain errors, never replacement permission.".
-spec snapshot(hls_node:service()) -> {ok, hls_domain:snapshot()} | {error, term()}.
snapshot(#{domain := #{owner := Owner, id := Domain}}) ->
    try hls_domain:status(Owner, Domain) of
        {ok, Snapshot = #{phase := ready, handle := {Domain, Incarnation}, actors := Actors}} when
            is_integer(Incarnation),
            Incarnation > 0,
            Incarnation < (1 bsl 64),
            is_map(Actors),
            map_size(Actors) > 0,
            map_size(Actors) =< 65535
        ->
            case
                lists:all(
                    fun(P) -> is_pid(P) andalso node(P) =:= node() andalso is_process_alive(P) end,
                    maps:values(Actors)
                ) andalso map_size(Actors) =:= length(lists:usort(maps:values(Actors)))
            of
                true -> {ok, Snapshot};
                false -> {error, invalid_domain_endpoints}
            end;
        {ok, _} ->
            {error, not_ready};
        {error, _} = Error ->
            Error
    catch
        exit:Reason -> {error, {domain_owner_unavailable, Reason}}
    end.

-doc "Allocates never-reused virtual PIDs for a ready snapshot, returning its public handle and next ID. Exhaustion rejects instead of wrapping.".
-spec allocate(node(), non_neg_integer(), atom(), hls_domain:snapshot(), non_neg_integer()) ->
    {[map()], map(), non_neg_integer()}.
allocate(Node, Creation, Name, #{handle := Handle, actors := Actors}, Next) ->
    true = Next + map_size(Actors) =< (1 bsl 32),
    Targets = [
        #{
            kind => domain,
            service => Name,
            identity => Id,
            endpoint => Endpoint,
            incarnation => Handle,
            pid => hls_node_wire:pid(Node, Creation, Next + Offset)
        }
     || {Offset, {Id, Endpoint}} <- lists:enumerate(0, lists:sort(maps:to_list(Actors)))
    ],
    Public = #{
        domain => Handle,
        actors => maps:from_list([{Id, Pid} || #{identity := Id, pid := Pid} <- Targets])
    },
    {Targets, Public, Next + length(Targets)}.

-doc "Accepts a newer ready incarnation only after every old local endpoint is dead and the actor set is unchanged. Exact duplicate publication preserves its PIDs.".
-spec replacement(hls_node:service(), [map()], map()) ->
    unchanged | {ok, hls_domain:snapshot()} | {error, term()}.
replacement(Service, Old, #{domain := {Domain, Previous}}) ->
    case snapshot(Service) of
        {ok, Snapshot = #{handle := {Domain, Incarnation}, actors := Actors}} ->
            Existing = maps:from_list([
                {Id, Endpoint}
             || #{identity := Id, endpoint := Endpoint} <- Old
            ]),
            case {Incarnation, Actors} of
                {Previous, Existing} ->
                    unchanged;
                {Previous, _} ->
                    {error, changed_incarnation_endpoints};
                _ when Incarnation < Previous -> {error, stale_incarnation};
                _ ->
                    case lists:sort(maps:keys(Existing)) =:= lists:sort(maps:keys(Actors)) of
                        false ->
                            {error, changed_domain_actors};
                        true ->
                            case lists:any(fun is_process_alive/1, maps:values(Existing)) of
                                true -> {error, old_endpoints_alive};
                                false -> {ok, Snapshot}
                            end
                    end
            end;
        Error ->
            Error
    end.
