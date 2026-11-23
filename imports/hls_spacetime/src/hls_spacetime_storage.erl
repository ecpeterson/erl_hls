-module(hls_spacetime_storage).
-moduledoc """
Checks the storage histories in a validated spacetime capture. hls_spacetime checks common identities and dependencies first; this module checks word versions, accepted port operations and read responses. Writes sampled at cycle C become ordinary state at C+1. Same-cycle read/write forwarding follows the declared collision mode. SRLs require explicit address operations; no shift is inferred from a primitive name.
""".

%% Internal validation entry used by the capture contract.
-export([validate/3]).

%% Word histories are independent across resource, address and reset incarnation.
-type key() :: {hls_spacetime:id(), non_neg_integer(), hls_spacetime:id()}.
%% The current word version immediately before a sampled clock edge.
-type state() :: #{key() => binary()}.
%% Registered request events remain available until their response or capture end.
-type requests() :: #{binary() => hls_spacetime:event()}.

-doc "Checks storage accesses after common event/reference validation. Pending reads at the capture tail are allowed. Contradictions raise {spacetime, Reason}; ambiguous no-change collisions are unsupported.".
-spec validate(
    [hls_spacetime:event()],
    #{binary() => hls_spacetime:version()},
    #{binary() => hls_spacetime:resource()}
) -> ok.
validate(Events, Versions, Resources) ->
    lists:foreach(fun(E) -> validate_input_access(E, Versions) end, Events),
    Initial = maps:fold(fun initial_version/3, #{}, Versions),
    Accesses = [E || E <- Events, maps:is_key(access, E)],
    Groups = lists:foldl(
        fun(#{cycle := Cycle} = E, Acc) ->
            Acc#{Cycle => [E | maps:get(Cycle, Acc, [])]}
        end,
        #{},
        Accesses
    ),
    Writes = validate_cycles(
        lists:sort(maps:to_list(Groups)), Initial, #{}, #{}, #{}, Versions, Resources
    ),
    maps:foreach(
        fun
            (_, #{producer := root}) -> ok;
            (_, #{storage := null}) -> ok;
            (Id, _) -> require(maps:is_key(Id, Writes), {unrecorded_storage_write, Id})
        end,
        Versions
    ).

%% Consumers cannot bypass storage lifetime checks by naming an old word as an ordinary input.
-spec validate_input_access(hls_spacetime:event(), #{binary() => hls_spacetime:version()}) -> ok.
validate_input_access(#{id := Id, inputs := Inputs} = E, Versions) ->
    lists:foreach(
        fun(Version) ->
            case maps:get(Version, Versions) of
                #{storage := null} ->
                    ok;
                _ ->
                    case maps:get(access, E, none) of
                        #{kind := write, before := Version} ->
                            ok;
                        #{kind := Kind, version := Version} when
                            Kind =:= hold; Kind =:= read_request; Kind =:= read_result
                        ->
                            ok;
                        _ ->
                            fail({unobserved_storage_read, Id, Version})
                    end
            end
        end,
        Inputs
    ).

%% An accessed word must begin with one explicit initial, unknown or carry-in root.
-spec initial_version(binary(), hls_spacetime:version(), state()) -> state().
initial_version(
    Id,
    #{producer := root, incarnation := Inc, storage := #{resource := Resource, address := Address}},
    State
) ->
    Key = {Resource, Address, Inc},
    require(not maps:is_key(Key, State), {duplicate_storage_root, Key}),
    State#{Key => Id};
initial_version(_, _, State) ->
    State.

%% Process a whole edge together so collision semantics do not depend on list order.
-spec validate_cycles(
    [{non_neg_integer(), [hls_spacetime:event()]}],
    state(),
    requests(),
    #{binary() => true},
    #{binary() => true},
    #{binary() => hls_spacetime:version()},
    #{binary() => hls_spacetime:resource()}
) -> #{binary() => true}.
validate_cycles([], _, _, _, Writes, _, _) ->
    Writes;
validate_cycles([{_, Events} | Rest], State, Requests, Responses, Written, Versions, Resources) ->
    check_ports(Events, Resources),
    Writes = lists:foldl(
        fun
            (#{access := #{kind := write}} = E, Acc) ->
                Key = storage_key(E),
                require(not maps:is_key(Key, Acc), {concurrent_storage_write, Key}),
                validate_write(E, State, Versions, Resources),
                Acc#{Key => E};
            (_, Acc) ->
                Acc
        end,
        #{},
        Events
    ),
    NextRequests = lists:foldl(
        fun
            (#{id := Id, access := #{kind := read_request}} = E, Acc) ->
                validate_request(E, State, Writes, Resources),
                Acc#{Id => E};
            (#{access := #{kind := hold}} = E, Acc) ->
                validate_hold(E, State, Writes),
                Acc;
            (_, Acc) ->
                Acc
        end,
        Requests,
        Events
    ),
    NextResponses = lists:foldl(
        fun
            (#{access := #{kind := read_result}} = E, Acc) ->
                validate_result(E, NextRequests, Acc, Versions, Resources);
            (_, Acc) ->
                Acc
        end,
        Responses,
        Events
    ),
    NextState = maps:fold(
        fun(Key, #{access := #{after_version := After}}, Acc) -> Acc#{Key => After} end,
        State,
        Writes
    ),
    NextWritten = maps:fold(
        fun(_, #{access := #{after_version := After}}, Acc) -> Acc#{After => true} end,
        Written,
        Writes
    ),
    validate_cycles(Rest, NextState, NextRequests, NextResponses, NextWritten, Versions, Resources).

%% A port accepts one operation per edge; read responses use a separate return lane.
-spec check_ports([hls_spacetime:event()], #{binary() => hls_spacetime:resource()}) -> ok.
check_ports(Events, Resources) ->
    _ = lists:foldl(
        fun(#{id := Id, incarnation := Inc, access := Access}, Seen) ->
            case Access of
                #{kind := Kind, resource := Resource, address := Address, port := Port} when
                    Kind =:= write; Kind =:= hold; Kind =:= read_request; Kind =:= read_result
                ->
                    R =
                        case maps:find(Resource, Resources) of
                            {ok, Found} -> Found;
                            error -> fail({unknown_storage_resource, Id, Resource})
                        end,
                    #{kind := ResourceKind} = R,
                    require(
                        lists:member(ResourceKind, [ff, bram, srl, register]), {not_storage, Id}
                    ),
                    #{depth := Depth, ports := Ports} = R,
                    require(
                        is_integer(Address) andalso Address >= 0 andalso Address < Depth,
                        {storage_address, Id}
                    ),
                    ok = check_read_mask(Access, R, Id),
                    Direction = maps:get(Port, Ports, absent),
                    require(port_allows(Kind, Direction), {storage_port_access, Id}),
                    case Kind of
                        hold ->
                            Seen;
                        _ ->
                            Lane =
                                case Kind of
                                    read_result -> response;
                                    _ -> request
                                end,
                            Key = {Resource, Port, Inc, Lane},
                            require(not maps:is_key(Key, Seen), {storage_port_busy, Id}),
                            Seen#{Key => true}
                    end;
                _ ->
                    fail({storage_access, Id})
            end
        end,
        #{},
        Events
    ),
    ok.

%% A read subset is optional evidence; present masks must be nonempty and fit the word.
-spec check_read_mask(map(), hls_spacetime:resource(), binary()) -> ok.
check_read_mask(#{read_mask := Mask, kind := Kind}, #{width := Width}, Id) ->
    require(
        (Kind =:= read_request orelse Kind =:= read_result) andalso
            is_integer(Mask) andalso Mask > 0 andalso Mask < (1 bsl Width),
        {storage_read_mask, Id}
    );
check_read_mask(_, _, _) ->
    ok.

%% A hold observes a valid port; requests and writes obey its declared direction.
-spec port_allows(atom(), atom()) -> boolean().
port_allows(hold, Direction) -> lists:member(Direction, [read, write, read_write]);
port_allows(write, Direction) -> lists:member(Direction, [write, read_write]);
port_allows(_, Direction) -> lists:member(Direction, [read, read_write]).

%% Every write creates a fresh word version; only preserved bits require prior-word data ancestry.
-spec validate_write(hls_spacetime:event(), state(), #{binary() => hls_spacetime:version()}, #{
    binary() => hls_spacetime:resource()
}) -> ok.
validate_write(
    #{
        id := Id,
        incarnation := Inc,
        inputs := Inputs,
        outputs := Outputs,
        access := #{
            resource := Resource,
            address := Address,
            before := Before,
            after_version := After,
            mask := Mask
        }
    } = E,
    State,
    Versions,
    Resources
) ->
    require(current(E, State) =:= Before, {stale_storage_write, Id}),
    #{width := Width} = maps:get(Resource, Resources),
    require(is_integer(Mask) andalso Mask > 0 andalso Mask < (1 bsl Width), {storage_mask, Id}),
    require(After =/= Before andalso Outputs =:= [After], {storage_write_version, Id}),
    require(
        Mask =:= (1 bsl Width) - 1 orelse lists:member(Before, Inputs), {storage_write_ancestry, Id}
    ),
    case maps:get(After, Versions) of
        #{
            producer := Id,
            origin := event,
            incarnation := Inc,
            storage := #{resource := Resource, address := Address}
        } ->
            ok;
        _ ->
            fail({storage_write_version, Id})
    end;
validate_write(#{id := Id}, _, _, _) ->
    fail({storage_write, Id}).

%% Holds carry a word unchanged and cannot conceal a simultaneous update.
-spec validate_hold(hls_spacetime:event(), state(), #{key() => hls_spacetime:event()}) -> ok.
validate_hold(
    #{id := Id, inputs := Inputs, outputs := [], access := #{version := Version}} = E, State, Writes
) ->
    require(not maps:is_key(storage_key(E), Writes), {hold_during_write, Id}),
    require(
        current(E, State) =:= Version andalso lists:member(Version, Inputs),
        {storage_hold_version, Id}
    );
validate_hold(#{id := Id}, _, _) ->
    fail({storage_hold, Id}).

%% Same-address writes select either the old word or the explicitly forwarded new word.
-spec validate_request(hls_spacetime:event(), state(), #{key() => hls_spacetime:event()}, #{
    binary() => hls_spacetime:resource()
}) -> ok.
validate_request(
    #{
        id := Id,
        inputs := Inputs,
        outputs := [],
        access := #{resource := Resource, version := Version}
    } = E,
    State,
    Writes,
    Resources
) ->
    Old = current(E, State),
    Selected =
        case maps:find(storage_key(E), Writes) of
            error ->
                Old;
            {ok, #{access := #{after_version := After}}} ->
                case maps:get(collision, maps:get(Resource, Resources)) of
                    read_first -> Old;
                    write_first -> After;
                    forbidden -> fail({storage_read_write_collision, Id})
                end
        end,
    require(Version =:= Selected andalso lists:member(Version, Inputs), {storage_read_version, Id});
validate_request(#{id := Id}, _, _, _) ->
    fail({storage_read_request, Id}).

%% A response refers to its accepted request, even if a later write changed that address.
-spec validate_result(
    hls_spacetime:event(),
    requests(),
    #{binary() => true},
    #{binary() => hls_spacetime:version()},
    #{binary() => hls_spacetime:resource()}
) -> #{binary() => true}.
validate_result(
    #{
        id := Id,
        cycle := Cycle,
        incarnation := Inc,
        inputs := Inputs,
        outputs := [Output],
        access := #{
            resource := Resource,
            address := Address,
            port := Port,
            request := Request,
            version := Version
        } = Access
    },
    Requests,
    Responses,
    Versions,
    Resources
) ->
    require(not maps:is_key(Request, Responses), {duplicate_storage_response, Id}),
    case maps:find(Request, Requests) of
        {ok, #{
            cycle := Requested,
            incarnation := Inc,
            access := #{resource := Resource, address := Address, port := Port, version := Version} =
                RequestedAccess
        }} ->
            require(
                maps:find(read_mask, Access) =:= maps:find(read_mask, RequestedAccess),
                {storage_read_mask_mismatch, Id}
            ),
            #{read_latency := Latency} = maps:get(Resource, Resources),
            require(Cycle =:= Requested + Latency, {storage_read_latency, Id});
        _ ->
            fail({storage_read_request_mismatch, Id})
    end,
    require(lists:member(Version, Inputs), {storage_read_ancestry, Id}),
    case maps:get(Output, Versions) of
        #{producer := Id, origin := event, incarnation := Inc, storage := null} -> ok;
        _ -> fail({storage_read_output, Id})
    end,
    Responses#{Request => true};
validate_result(#{id := Id}, _, _, _, _) ->
    fail({storage_read_result, Id}).

%% A missing root is unknown evidence, not permission to guess a current word.
-spec current(hls_spacetime:event(), state()) -> binary().
current(#{id := Id} = E, State) ->
    case maps:find(storage_key(E), State) of
        {ok, Version} -> Version;
        error -> fail({missing_storage_root, Id})
    end.

%% Include reset incarnation in every mutable-word address.
-spec storage_key(hls_spacetime:event()) -> key().
storage_key(#{incarnation := Inc, access := #{resource := Resource, address := Address}}) ->
    {Resource, Address, Inc}.

%% Keep contract failures distinct from programmer failures in the validator.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> fail(Reason).

%% Public capture validation exposes one structured error family.
-spec fail(term()) -> no_return().
fail(Reason) -> error({spacetime, Reason}).
