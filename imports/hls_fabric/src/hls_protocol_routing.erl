-module(hls_protocol_routing).
-moduledoc "Static actor ownership and crossing routes for a source-protocol deployment. Session identities, credits and physical-write ownership belong to its runtime incarnation.".
-export([plan/1, roles/1, routes/1]).
-export_type([role/0, device/0, route/0, plan/0]).

-doc "A deployment device key, independent of its physical address or session.".
-type role() :: term().

%% A route addresses compact class slots; the codec module owns their payload interpretation.
-type class() :: #{slot := byte(), codec := map()}.
%% Both endpoints retain the same actor/class descriptor with opposite directions.
-type crossing() :: #{index := 0 .. ((1 bsl 16) - 1), direction := incoming | outgoing,
    source_index := non_neg_integer(), destination_index := non_neg_integer(), classes := nonempty_list(class())}.

-doc "The device ownership and crossing descriptors needed to check deployment routing.".
-type device() :: #{native_indices := [non_neg_integer()], links := [crossing()]}.

-doc "The checked source and destination devices with the unchanged outgoing crossing descriptor.".
-type route() :: #{from := role(), to := role(), link := crossing()}.

-doc "Checked complete ownership and paired crossing descriptors, without runtime state.".
-opaque plan() :: #{roles := [role()], routes := #{0 .. ((1 bsl 16) - 1) => route()}}.

-doc "Checks complete, unique ownership of actors 0..actors-1 and one incoming peer for every outgoing crossing. Each descriptor must belong to the appropriate actor's device, cross devices, use a 16-bit link index and have nonempty classes with unique byte slots and codec maps. Peer indices, actor indices and classes must agree exactly; other descriptor fields are preserved. Rejects malformed descriptors and a nonpositive or exceeded crossings limit. Codec meaning and source provenance remain the compiler/codec boundary's responsibility.".
-spec plan(map()) -> plan().
plan(#{devices := Devices, actors := Count, limits := #{crossings := Limit}})
        when is_map(Devices), map_size(Devices) > 0, is_integer(Count), Count > 0,
             is_integer(Limit), Limit > 0 ->
    Owners = maps:fold(fun ownership/3, #{}, Devices),
    Expected = lists:seq(0, Count - 1),
    case lists:sort(maps:keys(Owners)) of
        Expected -> ok;
        Actual -> error({invalid_actor_ownership, Expected, Actual})
    end,
    {Outgoing, Incoming} = maps:fold(fun(Role, #{links := Links}, Acc) ->
        lists:foldl(fun(Link, Routes) -> crossing(Role, Link, Owners, Routes) end, Acc, Links)
    end, {#{}, #{}}, Devices),
    Out = maps:keys(Outgoing),
    In = maps:keys(Incoming),
    case {Out -- In, In -- Out} of
        {[], []} -> ok;
        {MissingIncoming, MissingOutgoing} ->
            error({unpaired_routes, lists:sort(MissingIncoming), lists:sort(MissingOutgoing)})
    end,
    case map_size(Outgoing) of
        Size when Size > 0, Size =< Limit -> ok;
        Size -> error({invalid_crossing_count, Size, Limit})
    end,
    Routes = maps:map(fun(Index, Source) -> pair(Index, Source, maps:get(Index, Incoming)) end, Outgoing),
    #{roles => lists:sort(maps:keys(Devices)), routes => Routes};
plan(Other) -> error({invalid_routing_plan, Other}).

-doc "Returns device keys in deterministic Erlang term order.".
-spec roles(plan()) -> [role()].
roles(#{roles := Roles}) -> Roles.

-doc "Returns routes keyed by their globally unique wire link index.".
-spec routes(plan()) -> #{0 .. ((1 bsl 16) - 1) => route()}.
routes(#{routes := Routes}) -> Routes.

%% Every device and owned index is visited; malformed entries cannot disappear from a comprehension.
-spec ownership(role(), map(), #{non_neg_integer() => role()}) -> #{non_neg_integer() => role()}.
ownership(Role, #{native_indices := Indices, links := Links}, Owners) when is_list(Indices), is_list(Links) ->
    lists:foldl(fun(Index, Acc) -> own(Index, Role, Acc) end, Owners, Indices);
ownership(Role, Other, _) -> error({invalid_routing_device, Role, Other}).

%% Retain the first owner long enough to diagnose duplicates, including repeats within one device.
-spec own(term(), role(), #{non_neg_integer() => role()}) -> #{non_neg_integer() => role()}.
own(Index, Role, Owners) when is_integer(Index), Index >= 0 ->
    case maps:find(Index, Owners) of
        error -> Owners#{Index => Role};
        {ok, Previous} -> error({duplicate_actor_owner, Index, Previous, Role})
    end;
own(Index, Role, _) -> error({invalid_actor_index, Role, Index}).

%% Static pairing never allocates sessions or assumes that a transport is attached.
-spec crossing(role(), map(), #{non_neg_integer() => role()}, {map(), map()}) -> {map(), map()}.
crossing(Role, Link = #{index := Index, direction := Direction, source_index := Source,
        destination_index := Destination, classes := Classes}, Owners, {Outgoing, Incoming})
        when is_integer(Index), Index >= 0, Index < 65536,
             is_integer(Source), Source >= 0, is_integer(Destination), Destination >= 0,
             (Direction =:= outgoing orelse Direction =:= incoming) ->
    From = owner(Source, Index, Owners),
    To = owner(Destination, Index, Owners),
    case From =:= To of
        true -> error({local_crossing, Index, From});
        false -> ok
    end,
    Expected = case Direction of outgoing -> From; incoming -> To end,
    case Role =:= Expected of
        true -> ok;
        false -> error({wrong_route_owner, Index, Direction, Expected, Role})
    end,
    ok = classes(Index, Classes),
    case Direction of
        outgoing -> {insert(Index, Direction, {Role, Link}, Outgoing), Incoming};
        incoming -> {Outgoing, insert(Index, Direction, {Role, Link}, Incoming)}
    end;
crossing(Role, Other, _, _) -> error({invalid_crossing, Role, Other}).

%% Unknown route actors are diagnosed before looking for their peer descriptors.
-spec owner(non_neg_integer(), 0 .. ((1 bsl 16) - 1), #{non_neg_integer() => role()}) -> role().
owner(Actor, Index, Owners) ->
    case maps:find(Actor, Owners) of
        {ok, Role} -> Role;
        error -> error({unknown_route_actor, Index, Actor})
    end.

%% A duplicate cannot be silently replaced when descriptor lists become lookup maps.
-spec insert(0 .. ((1 bsl 16) - 1), incoming | outgoing, {role(), map()}, map()) -> map().
insert(Index, Direction, Entry, Routes) ->
    case maps:is_key(Index, Routes) of
        false -> Routes#{Index => Entry};
        true -> error({duplicate_route, Direction, Index})
    end.

%% Only class addressing belongs here; codec contents remain opaque to routing.
-spec classes(0 .. ((1 bsl 16) - 1), term()) -> ok.
classes(Index, Classes) when is_list(Classes), Classes =/= [] ->
    _ = lists:foldl(fun
        (#{slot := Slot, codec := Codec}, Seen) when is_integer(Slot), Slot >= 0, Slot < 256, is_map(Codec) ->
            case maps:is_key(Slot, Seen) of
                false -> Seen#{Slot => true};
                true -> error({duplicate_route_slot, Index, Slot})
            end;
        (Other, _) -> error({invalid_route_class, Index, Other})
    end, #{}, Classes),
    ok;
classes(Index, Other) -> error({invalid_route_classes, Index, Other}).

%% Direction is deliberately excluded: the two descriptors describe opposite ends of one crossing.
-spec pair(0 .. ((1 bsl 16) - 1), {role(), map()}, {role(), map()}) -> route().
pair(_, {From, Link = #{source_index := Source, destination_index := Destination, classes := Classes}},
        {To, #{source_index := Source, destination_index := Destination, classes := Classes}}) ->
    #{from => From, to => To, link => Link};
pair(Index, {_, Outgoing}, {_, Incoming}) -> error({mismatched_route, Index, Outgoing, Incoming}).
