-module(hls_protocol_inventory).
-moduledoc "Inventories complete source programs and exact communication bindings during transport preparation, before fixed-slot lowering. Optional application models consume this report; closed routes and value bounds alone do not establish ordering, lifetime or capacity.".

%% Source and topology inventory.
-export([inspect/2]).
-export_type([report/0]).

-doc "Inspectable source-bound report with public structural fields. An inventory does not discharge the listed temporal obligations or authorize lowering.".
-type report() :: #{
    version := 1,
    topology_hash := binary(),
    modules := map(),
    actors := [map()],
    channels := [map()],
    boundaries := map(),
    diagnostics := [map()],
    obligations := [map()],
    eligible := false
}.

-doc "Inspects a normalized exact topology and module artifacts containing a complete opaque compiler program. Retains every entry alternative and complete ordered callback family. Reports unknown producers, interfaces and temporal obligations without executing callbacks or trusting fixture traces. The caller must bind these trusted compiler artifacts to current source; this function is not a stale-artifact validator.".
-spec inspect(hls_logical_topology:materialized_plan(), #{module() => map()}) -> report().
inspect(Topology = #{actors := Actors, routes := Routes}, Artifacts) ->
    Modules = maps:map(fun module/2, Artifacts),
    ActorModules = maps:from_list([{Id, M} || #{id := Id, module := M} <- Actors]),
    Channels = lists:append([channels(R, ActorModules, Modules) || R <- Routes]),
    Diagnostics =
        topology_diagnostics(Topology, ActorModules, Modules) ++
            internal_calls(Channels, ActorModules, Modules) ++
            lists:append([maps:get(diagnostics, M) || M <- maps:values(Modules)]),
    Rows = [actor(A, Topology, Modules) || A <- Actors],
    #{
        version => 1,
        topology_hash => hash(Topology),
        modules => Modules,
        actors => Rows,
        channels => Channels,
        boundaries => maps:with([ingresses, externals, startup], Topology),
        diagnostics => Diagnostics,
        obligations => lists:append([obligations(A, Channels) || A <- Rows]),
        eligible => false
    }.

%% Ordinary internal casts have no host transaction owner and cannot create calls.
-spec internal_calls([map()], map(), map()) -> [map()].
internal_calls(Channels, Actors, Modules) ->
    [
        diagnostic(
            unsupported_internal_call,
            #{source => {Source, Port}, destination => {actor, Destination}, schema => Tag},
            <<"Retained calls require a host caller owner; internal protocol sends are casts.">>
        )
     || #{source := Source, port := Port, destination := {actor, Destination}, tag := Tag} <-
            Channels,
        {ok, Module} <- [maps:find(Destination, Actors)],
        #{retained_calls := #{calls := Calls}} <- [maps:get(Module, Modules, #{})],
        is_map_key(Tag, Calls)
    ].

%% Keep source identities and complete families, not just a successful receive arm.
-spec module(module(), map()) -> map().
module(_Name, #{program := Program}) ->
    Spec = xls_actor_program:spec(Program),
    Plan = xls_actor_program:plan(Program),
    Callbacks = xls_statem_plan:callbacks(Plan),
    Entries = [alternative(E) || E <- xls_actor_program:entry_effects(Program)],
    Families = [
        #{
            phase => Phase,
            kind => Kind,
            clauses => [
                callback(C)
             || C <- Callbacks,
                maps:get(phase, C) =:= Phase,
                maps:get(kind, C) =:= Kind
            ],
            source_family_hash => hash([
                C
             || C <- Callbacks,
                maps:get(phase, C) =:= Phase,
                maps:get(kind, C) =:= Kind
            ])
        }
     || {Phase, Kind} <- lists:usort([{maps:get(phase, C), maps:get(kind, C)} || C <- Callbacks])
    ],
    #{
        identity => xls_statem_plan:provenance(Plan),
        phases => maps:get(phases, Spec),
        outputs => maps:get(output_names, Spec),
        messages => maps:get(message_names, Spec),
        alternatives => Entries,
        entry_layouts => entry_layouts(maps:get(entries, Spec)),
        families => Families,
        collections => collections(Spec),
        failure_locations => maps:get(failure_locations, Spec),
        retained_calls => maps:get(retained_calls, Spec),
        diagnostics => []
    }.

%% The inventory is a display projection; storage consumers use the full compiler effects.
-spec alternative(map()) -> map().
alternative(Effect = #{fields := Fields}) ->
    (maps:with([phase, layout, order, port, tag], Effect))#{
        fields => [maps:with([name, type, constant, known, offset], F) || F <- Fields]
    }.

%% Empty source layouts still commit state and must release a zero-delivery transaction.
-spec entry_layouts([map()]) -> [map()].
entry_layouts(Entries) ->
    [maps:with([phase, layout], L) || #{layouts := Layouts} <- Entries, L <- Layouts].

%% Collection declarations describe slots and contributions, not commutativity of the full receive.
-spec collections(map()) -> [map()].
collections(Spec) ->
    lists:append([
        case maps:get(Kind, Spec) of
            none ->
                [];
            #{sites := Sites} ->
                [
                    #{
                        kind => Kind,
                        site => maps:with([id, name, phase, population, opens_conditionally], Site),
                        contributions => [
                            maps:with([tag, source_capture_total, source_transportable], C)
                         || C <- maps:get(contributions, Site, [])
                        ]
                    }
                 || Site <- Sites
                ]
        end
     || Kind <- [gathers, reductions]
    ]).

%% Variable equality in a head is a candidate key relation, not an invariant across actors.
-spec callback(map()) -> map().
callback(#{ordinal := Ordinal, clause := Clause = {clause, Anno, Args, Guards, Body}}) ->
    %% The compiler appends a caller pattern only for retained-call callbacks.
    [Message, _Phase, State | _Caller] = Args,
    MessageFields = pattern_fields(Message),
    StateFields = pattern_fields(State),
    Equalities = [
        #{message => MF, state => SF}
     || {MF, V} <- MessageFields,
        {SF, W} <- StateFields,
        V =:= W,
        V =/= '_'
    ],
    #{
        ordinal => Ordinal,
        location => location(Anno),
        message => record_name(Message),
        head_equalities => Equalities,
        guards_hash => hash(Guards),
        clause_hash => hash(Clause),
        actions => actions(Body),
        helper_calls => lists:usort(helpers(Body)),
        state_aliases => aliases(State)
    }.

%% Only explicit record fields bound to the same variable establish head equality.
-spec pattern_fields(term()) -> [{atom(), atom()}].
pattern_fields({match, _, A, B}) ->
    pattern_fields(A) ++ pattern_fields(B);
pattern_fields({record, _, _, Fields}) ->
    [{Name, V} || {record_field, _, {atom, _, Name}, {var, _, V}} <- Fields];
pattern_fields(_) ->
    [].

%% An aliased record pattern keeps its schema; catch-all receives stay visibly unknown.
-spec record_name(term()) -> atom() | unknown.
record_name({record, _, Name, _}) ->
    Name;
record_name({match, _, A, B}) ->
    case record_name(A) of
        unknown -> record_name(B);
        Name -> Name
    end;
record_name(_) ->
    unknown.

%% State aliases help later checking distinguish unchanged-state contributions from updates.
-spec aliases(term()) -> [atom()].
aliases({var, _, Name}) -> [Name];
aliases({match, _, A, B}) -> aliases(A) ++ aliases(B);
aliases(_) -> [].

%% Inventory explicit directives wherever they occur; reachability and priority are not inferred.
-spec actions(term()) -> [map()].
actions({atom, Anno, Name}) when Name =:= postpone; Name =:= consume; Name =:= fail ->
    [#{kind => Name, location => location(Anno)}];
actions({tuple, Anno, [{atom, _, Name} | Args]} = Node) when
    Name =:= gather;
    Name =:= contribute;
    Name =:= cast;
    Name =:= reply;
    Name =:= open_gather;
    Name =:= open_reduction;
    Name =:= next_event
->
    [#{kind => Name, location => location(Anno), arguments => Args, source_hash => hash(Node)}];
actions(Node) when is_tuple(Node) -> actions(tuple_to_list(Node));
actions(Nodes) when is_list(Nodes) -> lists:append([actions(N) || N <- Nodes]);
actions(_) ->
    [].

%% Helpers are kept as explicit obligations instead of treating their bodies as action-free.
-spec helpers(term()) -> [term()].
helpers({xls_helper_call, _, Name, Args}) -> [{Name, length(Args)} | helpers(Args)];
helpers(Node) when is_tuple(Node) -> helpers(tuple_to_list(Node));
helpers(Nodes) when is_list(Nodes) -> lists:append([helpers(N) || N <- Nodes]);
helpers(_) -> [].

%% Exact route identities create candidate slots; each phase alternative remains attached.
-spec channels(map(), map(), map()) -> [map()].
channels(#{source := {Id, Port}, recipients := Recipients, delivery := Delivery}, Actors, Modules) ->
    case maps:find(Id, Actors) of
        error ->
            [];
        {ok, M} ->
            case maps:find(M, Modules) of
                error ->
                    [];
                {ok, #{alternatives := Alternatives}} ->
                    Selected = [A || A = #{port := P} <- Alternatives, P =:= Port],
                    [
                        #{
                            source => Id,
                            port => Port,
                            destination => Recipient,
                            tag => Tag,
                            delivery => Delivery,
                            alternatives => [A || A = #{tag := T} <- Selected, T =:= Tag],
                            ownership => unique_route_endpoint,
                            lifetime => unestablished
                        }
                     || Recipient <- Recipients,
                        Tag <- lists:usort([T || #{tag := T} <- Selected])
                    ]
            end
    end.

%% An actor's startup and incoming producers must remain visible even when no entry emits.
-spec actor(map(), map(), map()) -> map().
actor(A = #{id := Id, module := M}, Topology, Modules) ->
    A#{
        source_identity =>
            case maps:find(M, Modules) of
                {ok, #{identity := Identity}} -> Identity;
                error -> missing
            end,
        startup => lists:append([
            Messages
         || #{target := Target, messages := Messages} <-
                maps:get(startup, Topology),
            Target =:= Id
        ])
    }.

%% Unknown topology shapes and incomplete boundaries fail closed before any lowering.
-spec topology_diagnostics(map(), map(), map()) -> [map()].
topology_diagnostics(T = #{actors := Actors, routes := Routes}, ActorModules, Modules) ->
    Missing = [
        diagnostic(
            missing_source_plan,
            #{actor => Id, module => M},
            <<"Compile and bind this actor's complete source plan.">>
        )
     || #{id := Id, module := M} <- Actors, not maps:is_key(M, Modules)
    ],
    Families = [
        diagnostic(
            unelaborated_topology,
            #{field => K},
            <<"Elaborate every actor, route and lane before deriving protocol ownership.">>
        )
     || K <- [families, route_relations, lane_relations], maps:get(K, T, []) =/= []
    ],
    UnknownSources = [
        diagnostic(
            unknown_producer,
            #{source => S},
            <<"Bind the producer to a source actor or declare a checked boundary adapter.">>
        )
     || #{source := S = {Id, _}} <- Routes, not maps:is_key(Id, ActorModules)
    ],
    Ports = lists:append([port_diagnostics(R, ActorModules, Modules) || R <- Routes]),
    Missing ++ Families ++ UnknownSources ++ Ports ++ route_coverage(Actors, Routes, Modules) ++
        destination_diagnostics(T, ActorModules).

%% A route may name only a port present in the complete ordinary source interface.
-spec port_diagnostics(map(), map(), map()) -> [map()].
port_diagnostics(#{source := {Id, Port}}, Actors, Modules) ->
    case maps:find(Id, Actors) of
        error ->
            [];
        {ok, M} ->
            case maps:find(M, Modules) of
                error ->
                    [];
                {ok, #{outputs := Outputs}} ->
                    case lists:member(Port, Outputs) of
                        true ->
                            [];
                        false ->
                            [
                                diagnostic(
                                    undeclared_port,
                                    #{actor => Id, port => Port},
                                    <<"Use a source-declared output port.">>
                                )
                            ]
                    end
            end
    end.

%% Count route records as well as recipients so duplicate bindings cannot hide ownership conflicts.
-spec route_coverage([map()], [map()], map()) -> [map()].
route_coverage(Actors, Routes, Modules) ->
    lists:append([
        case maps:find(M, Modules) of
            error ->
                [];
            {ok, #{outputs := Outputs}} ->
                [
                    diagnostic(
                        route_coverage,
                        #{actor => Id, port => Port, routes => Count},
                        <<"Bind each declared output to exactly one complete route.">>
                    )
                 || Port <- Outputs,
                    Count <- [length([R || R = #{source := S} <- Routes, S =:= {Id, Port}])],
                    Count =/= 1
                ]
        end
     || #{id := Id, module := M} <- Actors
    ]).

%% Normalization usually catches these; retaining checks protects direct compiler API callers.
-spec destination_diagnostics(map(), map()) -> [map()].
destination_diagnostics(#{routes := Routes, externals := Externals}, Actors) ->
    ExternalIds = [Id || #{id := Id} <- Externals],
    lists:append(
        lists:append([
            [
                case Recipient of
                    {actor, Id} ->
                        case maps:is_key(Id, Actors) of
                            true ->
                                [];
                            false ->
                                [
                                    diagnostic(
                                        unknown_consumer,
                                        #{destination => Recipient},
                                        <<"Bind this destination to a declared source actor.">>
                                    )
                                ]
                        end;
                    {external, Id} ->
                        case lists:member(Id, ExternalIds) of
                            true ->
                                [];
                            false ->
                                [
                                    diagnostic(
                                        undeclared_boundary,
                                        #{destination => Recipient},
                                        <<"Declare the boundary and its accepted schemas and stall contract.">>
                                    )
                                ]
                        end
                end
             || Recipient <- Recipients
            ]
         || #{recipients := Recipients} <- Routes
        ])
    ).

%% No successful fixture, finite field or closed topology discharges a temporal obligation.
-spec obligations(map(), [map()]) -> [map()].
obligations(#{id := Id}, Channels) ->
    Incoming = [
        maps:with([source, port, tag], C)
     || C = #{destination := {actor, Target}} <- Channels,
        Target =:= Id
    ],
    [
        diagnostic(Code, #{actor => Id, producers => Incoming}, Message)
     || {Code, Message} <- [
            {generation_ownership,
                <<"Establish each collection's generation and member identity from source and startup facts.">>},
            {per_sender_order,
                <<"Preserve delivery order for each logical sender/destination pair across ports and generations, and retain selective receive/postponement. Distinct senders need no shared arrival order.">>},
            {capture_before_overwrite,
                <<"Establish snapshot lifetime through the last consumer, including overlapping generations.">>},
            {bounded_reservation,
                <<"Derive enough input/output reservations for every phase path and prove that acquisition cannot deadlock.">>},
            {boundary_contract,
                <<"Check reset, stalls and malformed external input behavior; undeclared interactions are unsupported.">>}
        ]
    ].

%% Diagnostics identify the missing fact rather than proposing implicit generic fallback.
-spec diagnostic(atom(), map(), binary()) -> map().
diagnostic(Code, Context, Message) -> #{code => Code, context => Context, message => Message}.

%% Preserve source files carried by prepared AST annotations.
-spec location(erl_anno:anno()) -> map().
location(Anno) -> #{file => erl_anno:file(Anno), line => erl_anno:line(Anno)}.

%% Deterministic identities bind full terms, including omitted-from-display source clauses.
-spec hash(term()) -> binary().
hash(Term) ->
    binary:encode_hex(crypto:hash(sha256, term_to_binary(Term, [deterministic])), lowercase).
