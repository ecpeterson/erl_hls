-module(hls_partition_schedule).
-moduledoc "Homogeneous device-local RAM groups with independent actor output reservations.".
-export([shared/2, shared_by_module/2, shared_by_module/3, local/2, topology/1, specs/1]).

-doc "Groups actors by device and module, balancing each bucket across the fewest executors with at most MaxActors members each. Family boundaries do not constrain sharing. Identities, routes and independent outboxes are preserved; the bound controls contention, not throughput or area. Module identity must denote one compiled actor implementation.".
-spec shared_by_module(map(), pos_integer()) -> map().
shared_by_module(Partition, MaxActors) when MaxActors > 0 ->
    shared_by_module(Partition, MaxActors, #{}).

-doc "Balances device-local groups with a default actor cap and per-module overrides. Overrides must name present modules and have positive caps; routes and actor identities are preserved.".
-spec shared_by_module(map(), pos_integer(), #{module() => pos_integer()}) -> map().
shared_by_module(Partition = #{actors := Actors}, MaxActors, Overrides) when MaxActors > 0 ->
    Modules = lists:usort([M || #{module := M} <- Actors]),
    case maps:keys(Overrides) -- Modules of
        [] -> ok;
        Unknown -> error({unknown_scheduler_modules, lists:sort(Unknown)})
    end,
    maps:foreach(fun(Module, Limit) ->
        case Limit > 0 of
            true -> ok;
            false -> error({invalid_scheduler_capacity, Module, Limit})
        end
    end, Overrides),
    Buckets = lists:foldl(fun(#{identity := Id, device := D, module := M}, Acc) ->
        maps:update_with({D, M}, fun(Ids) -> [Id | Ids] end, [Id], Acc)
    end, #{}, Actors),
    Members = maps:fold(fun(Key = {_, Module}, Ids, Acc) ->
        Limit = maps:get(Module, Overrides, MaxActors),
        Count = (length(Ids) + Limit - 1) div Limit,
        balanced_groups(Key, lists:sort(Ids), Count, Acc)
    end, #{}, Buckets),
    shared(Partition, Members).

%% Interleave canonical identities so executor occupancies differ by at most one.
-spec balanced_groups({term(), module()}, [term()], pos_integer(), map()) -> map().
balanced_groups({Device, Module}, Ids, Count, Groups) ->
    lists:foldl(fun({Index, Id}, Acc) ->
        Key = {Device, Module, Index rem Count},
        maps:update_with(Key, fun(Members) -> [Id | Members] end, [Id], Acc)
    end, Groups, lists:enumerate(0, Ids)).

-doc "Places every actor in one device-local RAM group. Members are deployment identities; groups may not span devices or actor modules.".
-spec shared(map(), #{term() => [term(), ...]}) -> map().
shared(Partition = #{actors := Actors}, Members) ->
    [ok = startup_capacity(A) || A <- Actors],
    Specs = maps:map(fun(_, Ids) -> group_spec(Ids) end, Members),
    #{groups := Groups, direct_members := Direct} = hls_scheduler_plan:normalize(topology(Actors), Specs,
        maps:get(frame_layout, Partition, hls_frame_layout:default())),
    case Direct of [] -> ok; _ -> error({partition_unscheduled, Direct}) end,
    Index = maps:from_list([{Id, A} || A = #{identity := Id} <- Actors]),
    Partition#{schedulers => [bind(Group, Index) || Group <- Groups]}.

%% Reuse public layout, storage widths and slot assignment for materialized identities.
-spec group_spec([term()]) -> map().
group_spec(Ids) -> #{members => [{actor, Id} || Id <- Ids],
    state_storage => block_ram, mailbox_storage => block_ram}.

%% A group has one physical owner and each member retains its logical identity.
-spec bind(map(), map()) -> map().
bind(Group = #{id := Id, members := Members, module := Module}, Index) ->
    Actors = [(maps:get(Actor, Index))#{slot => Slot}
        || #{id := Actor, base_slot := Slot} <- Members],
    Devices = lists:usort([D || #{device := D} <- Actors]),
    case Devices of
        [Device] -> Group#{device => Device, actors => Actors,
            module_name => atom_to_list(Module)};
        _ -> error({partition_scheduler_devices, Id, Devices})
    end.

-doc "Adds dense local scheduler indices without adding any inter-device permission lanes.".
-spec local(map(), map()) -> map().
local(#{schedulers := Groups}, Local = #{id := Device}) ->
    Selected = [G || G = #{device := D} <- Groups, D =:= Device],
    Local#{schedulers => [G#{index => I, stem => "scheduler_" ++ integer_to_list(I)}
        || {I, G} <- lists:enumerate(0, Selected)]};
local(_, Local) -> Local#{schedulers => []}.

-doc "Returns the materialized public scheduler-planning view of the selected actors.".
-spec topology([map()]) -> map().
topology(Actors) -> #{actors => [A#{id => Id} || A = #{identity := Id} <- Actors], families => []}.

-doc "Returns public group specifications preserving this device's group and slot order.".
-spec specs([map()]) -> map().
specs(Groups) -> maps:from_list([{Id, group_spec([Actor || #{identity := Actor} <- Actors])}
    || #{id := Id, actors := Actors} <- Groups]).

%% Preloading cannot retire a message to make room before every startup frame is stored.
-spec startup_capacity(map()) -> ok.
startup_capacity(#{identity := Id, startup := Frames, mailbox_capacity := Capacity}) ->
    case length(Frames) =< Capacity of
        true -> ok;
        false -> error({partition_startup_capacity, Id, length(Frames), Capacity})
    end.
