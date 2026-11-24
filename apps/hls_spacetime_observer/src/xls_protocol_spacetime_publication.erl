-module(xls_protocol_spacetime_publication).
-moduledoc "Joins source publication occurrences to capture arrivals and endpoint transfers using checked transport ownership. The tap planner supplies exact register identities; this adapter qualifies pending-bit retirement, capture leases and endpoint arbitration before refining existing unknown graph inputs. Narrowed payload bits remain encoded, not decoded using source offsets.".

%% Static source/register binding and recorded graph refinement.
-export([plan/2, attach/3]).
-export_type([plan/0, observation/0, result/0]).

%% All register inputs are existing checked trace IDs, including emitted D and enable expressions.
-type register() :: #{
    q := binary(), d := binary(), enable := binary(), resource := binary(), width := pos_integer()
}.
%% One publisher holds one immutable occurrence; pending groups are per output then source sequence.
-type source() :: #{
    index := non_neg_integer(),
    slots := pos_integer(),
    outputs := pos_integer(),
    masks := [non_neg_integer()],
    pending := register() | none,
    busy := register() | none,
    accept := binary()
}.
%% The concrete capture tuple owns both the credit code and its encoded payload register.
-type slot() :: #{
    link := non_neg_integer(),
    slot := non_neg_integer(),
    source := non_neg_integer(),
    output := non_neg_integer(),
    sequences := [non_neg_integer()],
    owner := register() | none,
    payload := register() | none
}.
%% Singleton endpoints have no arbitration state; multiple producers preserve declared order.
-type endpoint() :: #{
    index := non_neg_integer(),
    route := non_neg_integer(),
    members := [#{source := non_neg_integer(), output := non_neg_integer()}],
    valid := binary(),
    ready := binary(),
    cursor := register() | none,
    held := register() | none,
    owner := register() | none
}.
-doc "Source-bound transport ownership and the exact retained controls needed to interpret it. signals is empty because required Q/D/enable taps already belong to the register observer. Unsupported control encodings leave the graph unchanged rather than guessing a route or owner.".
-type plan() :: #{
    schema := 1,
    sources := [source()],
    slots := [slot()],
    endpoints := [endpoint()],
    advance := binary(),
    signals := [],
    unsupported := [map()],
    source_files := #{binary() => binary()}
}.
%% An explicit refinement preserves the consumer's input identity and all existing timing/storage records.
-type refinement() :: #{
    version := binary(),
    producer := binary(),
    consumer := binary(),
    kind := arrival | boundary | capture_write,
    incarnation := binary(),
    cycle := non_neg_integer(),
    source := non_neg_integer(),
    output := non_neg_integer(),
    sequence := non_neg_integer(),
    link => non_neg_integer(),
    slot => non_neg_integer(),
    endpoint => non_neg_integer()
}.
%% A current publication may be carry-in work whose admission was outside the observed scope.
-type current() :: #{
    source := non_neg_integer(),
    event := binary() | unknown,
    incarnation := binary(),
    cycle := non_neg_integer(),
    ordinal := non_neg_integer()
}.
-doc "Refinement inventory, observed publication identities and explicit unjoined work. Pending publications remain live at the finite capture boundary; reset retires them without joining later transfers. Evidence establishes control/ownership correspondence, not sensitized or decoded numerical ancestry.".
-type observation() :: #{
    schema := 1,
    refinements := [refinement()],
    publications := [current()],
    pending := [current()],
    retired := [#{cycle := non_neg_integer(), publications := [current()]}],
    unresolved := [map()],
    unsupported := [map()],
    source_files := #{binary() => binary()},
    evidence := binary()
}.
-doc "Generic graph plus a separate publication-attribution sidecar; no backend fields enter graph records.".
-type result() :: #{bundle := hls_spacetime:bundle(), publication := observation()}.

%% Current publication identities and graph updates are independent of payload equality.
-record(capture, {
    plan :: plan(),
    current = #{} :: #{non_neg_integer() => current()},
    ordinals = #{} :: map(),
    incarnation = 0 :: non_neg_integer(),
    reset = false :: boolean(),
    warm = false :: boolean(),
    events = #{} :: map(),
    versions = #{} :: map(),
    index = #{} :: map(),
    writes = #{} :: map(),
    refinements = [] :: [refinement()],
    publications = [] :: [current()],
    retired = [] :: [map()],
    unresolved = [] :: [map()]
}).

-doc "Binds already hash-verified source-build bytes and an existing register/stream tap plan. Regenerates only in-memory transport/network/boundary source from retained trusted descriptors and requires byte equality, including shared ownership/arbitration libraries. No source compilation, files, RTL or taps are created. Supports a whole single-stage network without crossing links or inspection; unsupported exact-width ownership controls are reported and disable refinement.".
-spec plan(#{binary() => binary()}, xls_protocol_spacetime:plan()) -> plan().
plan(
    Files,
    Existing = #{state := Leaves, registers := Registers, signals := Signals, stream := Stream}
) ->
    #{fabric := Fabric = #{sources := Sources, links := Links}, receivers := Receivers} =
        Transport = binary_to_term(maps:get(<<"transport.etf">>, Files)),
    #{source_boundary := #{activation := Activation, inspection := none, externals := Groups}} =
        binary_to_term(maps:get(<<"deployment.etf">>, Files)),
    require(maps:get(crossings, Fabric, []) =:= [], crossing_links),
    require(maps:get(arithmetic, Transport) =:= [], shared_arithmetic),
    #{files := GeneratedTransport} = xls_protocol_transport:emit(
        xls_protocol_transport:plan(Fabric)
    ),
    ok = same(<<"dslx/transport.x">>, maps:get("transport.x", GeneratedTransport), Files),
    NetworkPlan = xls_protocol_network:plan(Transport#{activation => Activation, inspection => none}),
    Network = xls_protocol_network:descriptor(NetworkPlan),
    %% The original network boundary consumes transport and receiver components;
    %% ingress and network files are generated by emit/3, never supplied twice.
    UpstreamNames = [<<"dslx/transport.x">> | [File || #{file := File} <- Receivers]],
    SourceFiles = maps:from_list([{binary_to_list(N), maps:get(N, Files)} || N <- UpstreamNames]),
    #{files := GeneratedNetwork} = xls_protocol_network:emit(NetworkPlan, Receivers, SourceFiles),
    ok = same(<<"network/network.x">>, maps:get("network/network.x", GeneratedNetwork), Files),
    BoundaryPlan = xls_protocol_boundary:plan(#{network => Network, externals => Groups}),
    #{files := GeneratedBoundary} = xls_protocol_boundary:emit(BoundaryPlan, none),
    lists:foreach(
        fun(Name) -> ok = same(list_to_binary(Name), maps:get(Name, GeneratedBoundary), Files) end,
        ["boundary/boundary.x", "boundary/protocol_boundary.sv"]
    ),
    Libraries = [
        {hls_target, <<"support/target/">>, "xls/lib/protocol_transport.x"},
        {hls_target, <<"support/target/">>, "xls/lib/protocol_egress.x"},
        {hls_compile, <<"support/compiler/">>, "xls/lib/arbitration.x"}
    ],
    lists:foreach(
        fun({App, Prefix, Name}) ->
            {ok, Bytes} = file:read_file(filename:join(code:priv_dir(App), Name)),
            ok = same(iolist_to_binary([Prefix, Name]), Bytes, Files)
        end,
        Libraries
    ),
    %% Native tuple positions follow emitted declaration order, not sorted identities.
    Indices = [I || #{index := I} <- Sources],
    Count = length(Sources),
    require(Indices =:= lists:seq(0, Count - 1), source_indices),
    require([I || #{index := I} <- Links] =:= lists:seq(0, length(Links) - 1), link_indices),
    require(
        Indices =:= lists:sort([I || #{actor := I} <- maps:get(actors, Existing)]), actor_indices
    ),
    Context = #{
        leaves => maps:from_list([{maps:get(tuple_path, L), L} || L <- Leaves]),
        registers => maps:from_list([{maps:get(name, R), R} || R <- Registers]),
        signals => maps:from_list([{maps:get(name, S), maps:get(id, S)} || S <- Signals])
    },
    BoundSources = [source(S, Context) || S <- Sources],
    Slots = lists:append([slots(L, Count, Context) || L <- Links]),
    Multiple = [I || #{index := I, members := M} <- Groups, length(M) > 1],
    StatePositions = maps:from_list(lists:zip(Multiple, lists:seq(1, length(Multiple)))),
    Endpoints = [endpoint(G, maps:get(endpoints, Stream), StatePositions, Context) || G <- Groups],
    SignalIds = maps:from_list([{maps:get(id, S), true} || S <- Signals]),
    Missing =
        [
            #{kind => publication_control, source => I}
         || #{index := I, accept := A} <- BoundSources,
            not maps:is_key(A, SignalIds)
        ] ++
            [
                #{kind => publisher, source => I}
             || #{index := I, pending := P, busy := B} <- BoundSources,
                P =:= none orelse B =:= none
            ] ++
            [
                #{kind => capture_owner, link => L, slot => S}
             || #{link := L, slot := S, owner := none} <- Slots
            ] ++
            [
                #{kind => endpoint_owner, endpoint => I}
             || #{index := I, members := M, cursor := C, held := H, owner := O} <- Endpoints,
                length(M) > 1,
                C =:= none orelse H =:= none orelse O =:= none
            ],
    Names =
        [
            <<"transport.etf">>,
            <<"deployment.etf">>,
            <<"dslx/transport.x">>,
            <<"network/network.x">>,
            <<"boundary/boundary.x">>,
            <<"boundary/protocol_boundary.sv">>
        ] ++
            [iolist_to_binary([P, N]) || {_, P, N} <- Libraries],
    #{
        schema => 1,
        sources => BoundSources,
        slots => Slots,
        endpoints => Endpoints,
        advance => maps:get(<<"p0_stage_done">>, maps:get(signals, Context)),
        signals => [],
        unsupported => Missing,
        source_files => maps:from_list([{N, hash(maps:get(N, Files))} || N <- Names])
    }.

%% Pending-mask and busy fields retain their full native source widths in this interpretation.
-spec source(map(), map()) -> source().
source(#{index := I, sequence_slots := S, destinations := D, masks := Masks}, Context) ->
    #{
        index => I,
        slots => S,
        outputs => D,
        masks => lists:usort([M || #{mask := M} <- Masks]),
        pending => register([0, 0, I, 0, 1], D * S, true, Context),
        busy => register([0, 0, I, 0, 2], 1, true, Context),
        accept => <<"actor/", (integer_to_binary(I))/binary, "/publication_accept">>
    }.

%% Capture identity follows the checked link output and concrete payload tuple, never payload equality.
-spec slots(map(), non_neg_integer(), map()) -> [slot()].
slots(
    #{
        index := L,
        source_index := I,
        output_index := O,
        widths := Widths,
        output := #{rows := Rows}
    },
    Count,
    Context
) ->
    [
        #{
            link => L,
            slot => Slot,
            source => I,
            output => O,
            sequences => lists:usort([
                Seq
             || #{capture_slot := S, sequence := Seq} <- Rows, S =:= Slot
            ]),
            owner => register([0, 0, Count + L, Slot, 0], 2, true, Context),
            payload => register([0, 0, Count + L, Slot, 1], W, false, Context)
        }
     || {Slot, W} <- lists:enumerate(0, Widths)
    ].

%% State tuple positions count only multiple-producer endpoint arbiters, after the network state.
-spec endpoint(map(), [map()], map(), map()) -> endpoint().
endpoint(#{index := I, members := Members, index_bits := Bits}, Streams, Positions, Context) ->
    [#{route := Route, valid := Valid, ready := Ready}] = [
        S
     || S = #{index := J} <- Streams, I =:= J
    ],
    {Cursor, Held, Owner} =
        case maps:find(I, Positions) of
            error ->
                {none, none, none};
            {ok, Position} ->
                {
                    register([Position, 0], Bits, true, Context),
                    register([Position, 1], 1, true, Context),
                    register([Position, 2], Bits, true, Context)
                }
        end,
    #{
        index => I,
        route => Route,
        members => [
            #{source => S, output => O}
         || #{source_index := S, output_index := O} <- Members
        ],
        valid => Valid,
        ready => Ready,
        cursor => Cursor,
        held => Held,
        owner => Owner
    }.

%% Narrowing is permitted only for payload identity; it never supplies semantic bit offsets.
-spec register([non_neg_integer()], non_neg_integer(), boolean(), map()) -> register() | none.
register(Path, Width, Exact, #{leaves := Leaves, registers := Registers, signals := Signals}) ->
    case maps:find(Path, Leaves) of
        {ok, #{signal := Name, source_width := Width, physical_width := Physical}} when
            Name =/= null, Physical > 0, (not Exact orelse Physical =:= Width)
        ->
            #{width := Physical, data := D, enable := E, rule := enabled_same_edge_register_write} = maps:get(
                Name, Registers
            ),
            #{
                q => maps:get(Name, Signals),
                d => maps:get(D, Signals),
                enable => maps:get(E, Signals),
                width => Physical,
                resource => <<"register/", Name/binary>>
            };
        _ ->
            none
    end.

%% Source equality checks the complete generated composition rather than guessed names alone.
-spec same(binary(), iodata(), map()) -> ok.
same(Name, Expected, Files) ->
    require(maps:get(Name, Files) =:= iolist_to_binary(Expected), {source_binding, Name}).

%% Retained source hashes expose exactly which semantic support was checked.
-spec hash(binary()) -> binary().
hash(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).

-doc "Refines only existing unknown, nonstorage root versions after checking recorded publication ownership, lowest-pending-bit retirement, concrete capture transitions and held endpoint arbitration. Keeps graph IDs, cycles, sequences and storage access records. Unsupported bindings or carry-in admissions remain unknown; reset retires current identities. Encoded payload projection is not reconstructed and byte equality never chooses a producer. Input must be the validated register/stream graph before this refinement.".
-spec attach(plan(), hls_spacetime_trace:trace(), hls_spacetime:bundle()) -> result().
attach(
    Plan = #{unsupported := Unsupported, source_files := Files},
    Trace,
    Bundle = #{events := Events, versions := Versions}
) ->
    Initial = #capture{
        plan = Plan,
        events = index(Events),
        versions = index(Versions),
        index = event_index(Events),
        writes = write_index(Events)
    },
    Final =
        case Unsupported of
            [] -> hls_spacetime_trace:fold(fun sample/3, Initial, Trace);
            _ -> Initial
        end,
    Joined = Bundle#{
        events := [maps:get(maps:get(id, E), Final#capture.events) || E <- Events],
        versions := [maps:get(maps:get(id, V), Final#capture.versions) || V <- Versions]
    },
    _ = hls_spacetime:validate(Joined),
    #{
        bundle => Joined,
        publication => #{
            schema => 1,
            source_files => Files,
            refinements => lists:reverse(Final#capture.refinements),
            publications => lists:reverse(Final#capture.publications),
            pending => [V || {_, V} <- lists:sort(maps:to_list(Final#capture.current))],
            retired => lists:reverse(Final#capture.retired),
            unresolved => lists:reverse(Final#capture.unresolved),
            unsupported => Unsupported,
            evidence =>
                <<"Checked source-bound control and ownership correspondence; encoded payloads are not decoded, sensitized paths are not established, and finite tails need not be drained">>
        }
    }.

%% Sequence counters and sampled reset edges agree with the original graph observers.
-spec sample(non_neg_integer(), map(), #capture{}) -> #capture{}.
sample(Cycle, Values, S = #capture{reset = Previous, incarnation = Inc}) ->
    Reset = maps:get(<<"reset">>, Values) =/= 0,
    case {Reset, Previous, Cycle} of
        {true, false, C} when C > 0 ->
            Retired = #{cycle => C, publications => maps:values(S#capture.current)},
            S#capture{
                reset = true,
                warm = false,
                incarnation = Inc + 1,
                current = #{},
                ordinals = #{},
                retired = [Retired | S#capture.retired]
            };
        {true, _, _} ->
            S#capture{reset = true, warm = false};
        {false, _, _} ->
            Advance = maps:get(maps:get(advance, S#capture.plan), Values) =/= 0,
            case Advance andalso S#capture.warm of
                true -> tick(Cycle, Values, S#capture{reset = false});
                false -> S#capture{reset = false, warm = S#capture.warm orelse Advance}
            end
    end.

%% Every retired source-output occurrence must have exactly one checked capture or endpoint acceptance.
-spec tick(non_neg_integer(), map(), #capture{}) -> #capture{}.
tick(
    Cycle,
    Values,
    S0 = #capture{plan = #{sources := Sources, slots := Slots, endpoints := Endpoints}}
) ->
    Views = maps:from_list([
        {maps:get(index, Source), source_view(Source, Values)}
     || Source <- Sources
    ]),
    {Retiring, S1} = lists:foldl(
        fun(Source, Acc) ->
            retire(Cycle, Source, maps:get(maps:get(index, Source), Views), Acc)
        end,
        {#{}, S0},
        Sources
    ),
    {Rest1, S2} = lists:foldl(
        fun(Slot, Acc) -> arrival(Cycle, Values, Slot, Acc) end, {Retiring, S1}, Slots
    ),
    {Rest2, S3} = lists:foldl(
        fun(Endpoint, Acc) -> boundary(Cycle, Values, Endpoint, Views, Acc) end,
        {Rest1, S2},
        Endpoints
    ),
    require(map_size(Rest2) =:= 0, {unmatched_retirement, Cycle, maps:keys(Rest2)}),
    lists:foldl(
        fun(Source, S) ->
            admit(Cycle, Values, Source, maps:get(maps:get(index, Source), Views), S)
        end,
        S3,
        Sources
    ).

%% The current/next pending masks encode recipient retirement independently of frame contents.
-spec source_view(source(), map()) -> map().
source_view(#{pending := Pending, busy := Busy}, Values) ->
    {Old, New} = values(Pending, Values),
    {WasBusy, WillBusy} = values(Busy, Values),
    require(WasBusy =:= bool(Old =/= 0) andalso WillBusy =:= bool(New =/= 0), publication_busy),
    #{old => Old, new => New, busy => WasBusy}.

%% A busy source can clear only the earliest pending sequence for each recipient.
-spec retire(non_neg_integer(), source(), map(), {map(), #capture{}}) -> {map(), #capture{}}.
retire(
    Cycle,
    #{index := I, slots := Slots, outputs := Outputs},
    #{old := Old, new := New, busy := Busy},
    {All, S0}
) ->
    case Busy of
        0 ->
            {All, S0};
        1 ->
            require((New band Old) =:= New, {publication_added_pending, I, Cycle}),
            Current = maps:get(I, S0#capture.current, #{
                source => I,
                event => unknown,
                incarnation => incarnation(S0#capture.incarnation),
                cycle => Cycle,
                ordinal => 0
            }),
            S = S0#capture{current = (S0#capture.current)#{I => Current}},
            Retired = Old bxor New,
            Deliveries = [
                begin
                    Group = (Old bsr (O * Slots)) band ((1 bsl Slots) - 1),
                    Lost = (Retired bsr (O * Slots)) band ((1 bsl Slots) - 1),
                    require(Lost =:= (Group band -Group), {publication_order, I, O, Cycle}),
                    {{I, O}, Current#{output => O, sequence => first_bit(Lost, 0)}}
                end
             || O <- lists:seq(0, Outputs - 1),
                ((Retired bsr (O * Slots)) band ((1 bsl Slots) - 1)) =/= 0
            ],
            {maps:merge(All, maps:from_list(Deliveries)), S}
    end.

%% Admission occurs only while idle; the last retirement cannot create same-edge admission credit.
-spec admit(non_neg_integer(), map(), source(), map(), #capture{}) -> #capture{}.
admit(
    Cycle,
    Values,
    #{index := I, accept := Accept, masks := Masks},
    #{old := Old, new := New, busy := Busy},
    S
) ->
    case maps:get(Accept, Values) of
        0 ->
            require(Busy =:= 1 orelse New =:= Old, {unobserved_publication, I, Cycle}),
            case New of
                0 -> S#capture{current = maps:remove(I, S#capture.current)};
                _ -> S
            end;
        1 ->
            require(Busy =:= 0 andalso lists:member(New, Masks), {publication_admission, I, Cycle}),
            Event = find_event(Cycle, actor(I), <<"publication_accept">>, S),
            Ordinal = maps:get(I, S#capture.ordinals, 0),
            Current = #{
                source => I,
                event => Event,
                incarnation => incarnation(S#capture.incarnation),
                cycle => Cycle,
                ordinal => Ordinal
            },
            S#capture{
                ordinals = (S#capture.ordinals)#{I => Ordinal + 1},
                publications = [Current | S#capture.publications],
                current =
                    case New of
                        0 -> maps:remove(I, S#capture.current);
                        _ -> (S#capture.current)#{I => Current}
                    end
            }
    end.

%% Capture arrivals identify an exact lease and receive one source-output retirement.
-spec arrival(non_neg_integer(), map(), slot(), {map(), #capture{}}) -> {map(), #capture{}}.
arrival(
    Cycle,
    Values,
    Slot = #{
        link := L, slot := Number, source := I, output := O, owner := Owner, sequences := Allowed
    },
    {Retiring, S}
) ->
    {Old, New} = values(Owner, Values),
    case {Old, New} of
        {0, 1} ->
            {Delivery = #{sequence := Sequence}, Rest} = maps:take({I, O}, Retiring),
            require(lists:member(Sequence, Allowed), {capture_sequence, L, Number, Sequence}),
            Arrival = find_event(Cycle, slot_actor(L, Number), <<"arrival">>, S),
            Context = (maps:with([source, output, sequence], Delivery))#{link => L, slot => Number},
            Joined = resolve(Arrival, maps:get(event, Delivery), arrival, Context, S),
            {Rest, capture_write(Cycle, Values, Slot, Arrival, Context, Joined)};
        {X, X} ->
            {Retiring, S};
        {1, 2} ->
            {Retiring, S};
        {2, 0} ->
            {Retiring, S};
        _ ->
            error({spacetime_publication, {capture_transition, L, Number, Old, New}})
    end.

%% Only the actual payload write at this arrival may acquire the arriving value's provenance.
-spec capture_write(non_neg_integer(), map(), slot(), binary(), map(), #capture{}) -> #capture{}.
capture_write(Cycle, Values, #{payload := Payload}, Arrival, Context, S) ->
    case Payload of
        #{width := Width, enable := Enable, resource := Resource} when Width >= 16 ->
            case maps:get(Enable, Values) of
                0 ->
                    unresolved(capture_payload_not_written, Arrival, Context, S);
                _ ->
                    Key = {incarnation(S#capture.incarnation), Cycle, Resource},
                    Write = maps:get(Key, S#capture.writes),
                    resolve(Write, Arrival, capture_write, Context, S)
            end;
        _ ->
            unresolved(capture_payload_unobserved, Arrival, Context, S)
    end.

%% Endpoint arbitration is replayed from exact owner/cursor bits; actual ready/valid qualifies transfer.
-spec boundary(non_neg_integer(), map(), endpoint(), map(), {map(), #capture{}}) ->
    {map(), #capture{}}.
boundary(
    Cycle,
    Values,
    E = #{index := I, route := Route, members := Members, valid := Valid, ready := Ready},
    Views,
    {Retiring, S}
) ->
    Candidates = [valid(M, Views, S#capture.plan) || M <- Members],
    {Selected, Active} = select(E, Candidates, Values),
    require(maps:get(Valid, Values) =:= bool(Active), {endpoint_valid, I, Cycle}),
    Accepted = Active andalso maps:get(Ready, Values) =/= 0,
    ok = check_arbiter(E, Selected, Active, Accepted, Values),
    case Accepted of
        false ->
            {Retiring, S};
        true ->
            #{source := Source, output := Output} = lists:nth(Selected + 1, Members),
            {Delivery, Rest} = maps:take({Source, Output}, Retiring),
            Transfer = find_event(
                Cycle,
                <<"stream/route/", (integer_to_binary(Route))/binary>>,
                <<"boundary_transfer">>,
                S
            ),
            Context = (maps:with([source, output, sequence], Delivery))#{endpoint => I},
            {Rest, resolve(Transfer, maps:get(event, Delivery), boundary, Context, S)}
    end.

%% Each output is offered while at least one sequence bit remains in its old-state group.
-spec valid(map(), map(), plan()) -> boolean().
valid(#{source := I, output := O}, Views, #{sources := Sources}) ->
    [#{slots := Slots}] = [Source || Source = #{index := J} <- Sources, J =:= I],
    #{old := Old, busy := Busy} = maps:get(I, Views),
    Busy =:= 1 andalso ((Old bsr (O * Slots)) band ((1 bsl Slots) - 1)) =/= 0.

%% Held selection wins over later arrivals; otherwise the first valid index at/after cursor wins.
-spec select(endpoint(), [boolean()], map()) -> {non_neg_integer(), boolean()}.
select(#{members := []}, [], _) ->
    {0, false};
select(#{cursor := none}, [Only], _) ->
    {0, Only};
select(#{cursor := Cursor, held := Held, owner := Owner}, Candidates, Values) ->
    {C, _} = values(Cursor, Values),
    {H, _} = values(Held, Values),
    {O, _} = values(Owner, Values),
    N = length(Candidates),
    require(C < N andalso O < N, endpoint_owner_domain),
    case H of
        1 ->
            {O, lists:nth(O + 1, Candidates)};
        0 ->
            Ordered = lists:seq(C, N - 1) ++ lists:seq(0, C - 1),
            case [J || J <- Ordered, lists:nth(J + 1, Candidates)] of
                [] -> {0, false};
                [J | _] -> {J, true}
            end
    end.

%% Native next-state bits must match the checked arbitration rule, including independently stalled endpoints.
-spec check_arbiter(endpoint(), non_neg_integer(), boolean(), boolean(), map()) -> ok.
check_arbiter(#{cursor := none}, _, _, _, _) ->
    ok;
check_arbiter(
    #{cursor := Cursor, held := Held, owner := Owner, members := Members},
    Selected,
    Active,
    Accepted,
    Values
) ->
    {C, NC} = values(Cursor, Values),
    {H, NH} = values(Held, Values),
    {O, NO} = values(Owner, Values),
    Expected =
        case {Accepted, Active} of
            {true, _} -> {(Selected + 1) rem length(Members), 0, 0};
            {false, true} -> {C, 1, Selected};
            {false, false} -> {C, H, O}
        end,
    require({NC, NH, NO} =:= Expected, {endpoint_transition, {NC, NH, NO}, Expected}).

%% Resolve an unknown root only after its producer occurrence has been established by control history.
-spec resolve(binary(), binary() | unknown, arrival | boundary | capture_write, map(), #capture{}) ->
    #capture{}.
resolve(Consumer, unknown, _, Context, S) ->
    unresolved(publication_carry_in, Consumer, Context, S);
resolve(Consumer, Producer, Kind, Context, S = #capture{events = Events, versions = Versions}) ->
    C = #{inputs := [Root], incarnation := Inc, cycle := Cycle} = maps:get(Consumer, Events),
    P = #{outputs := Outputs, incarnation := Inc, cycle := Before} = maps:get(Producer, Events),
    require(Before =< Cycle andalso Producer =/= Consumer, {producer_time, Producer, Consumer}),
    V =
        #{producer := root, origin := unknown, storage := null, incarnation := Inc} = maps:get(
            Root, Versions
        ),
    require(not lists:member(Root, Outputs), {duplicate_output, Root}),
    Evidence =
        <<"Checked source-bound publication/lease occurrence; encoded payload ancestry, without source-bit decoding or sensitization">>,
    Refinement = Context#{
        version => Root,
        producer => Producer,
        consumer => Consumer,
        kind => Kind,
        incarnation => Inc,
        cycle => Cycle
    },
    S#capture{
        events = Events#{
            Consumer => C#{evidence := Evidence}, Producer => P#{outputs := Outputs ++ [Root]}
        },
        versions = Versions#{
            Root => V#{producer := Producer, origin := event, evidence := Evidence}
        },
        refinements = [Refinement | S#capture.refinements]
    }.

%% Unobserved carry-in and payload encodings remain visible without fabricated graph edges.
-spec unresolved(atom(), binary(), map(), #capture{}) -> #capture{}.
unresolved(Reason, Consumer, Context, S) ->
    S#capture{
        unresolved = [Context#{reason => Reason, consumer => Consumer} | S#capture.unresolved]
    }.

%% Effective D uses the sampled native enable; a disabled update retains Q.
-spec values(register(), map()) -> {non_neg_integer(), non_neg_integer()}.
values(#{q := Q, d := D, enable := E}, Sample) ->
    Old = maps:get(Q, Sample),
    {Old,
        case maps:get(E, Sample) of
            0 -> Old;
            _ -> maps:get(D, Sample)
        end}.

%% Only observed operation occurrences enter this index; unrelated same-cycle events cannot match.
-spec event_index([hls_spacetime:event()]) -> map().
event_index(Events) ->
    Rows = [
        {{Inc, C, A, Op}, Id}
     || #{id := Id, incarnation := Inc, cycle := C, actor := A, operation := Op} <- Events,
        lists:member(Op, [<<"publication_accept">>, <<"arrival">>, <<"boundary_transfer">>])
    ],
    require(length(Rows) =:= map_size(maps:from_list(Rows)), duplicate_occurrence),
    maps:from_list(Rows).

%% Storage write identity includes the exact resource and incarnation, not value change.
-spec write_index([hls_spacetime:event()]) -> map().
write_index(Events) ->
    Rows = [
        {{Inc, C, R}, Id}
     || #{
            id := Id,
            incarnation := Inc,
            cycle := C,
            access := #{kind := write, resource := R}
        } <- Events
    ],
    require(length(Rows) =:= map_size(maps:from_list(Rows)), duplicate_write),
    maps:from_list(Rows).

%% Match the actual control-qualified event within the current reset incarnation.
-spec find_event(non_neg_integer(), binary(), binary(), #capture{}) -> binary().
find_event(Cycle, Actor, Operation, #capture{incarnation = Inc, index = Index}) ->
    maps:get({incarnation(Inc), Cycle, Actor, Operation}, Index).

%% Checked generic graph identity is retained as the sole authority for existing records.
-spec index([map()]) -> map().
index(Records) -> maps:from_list([{maps:get(id, R), R} || R <- Records]).

%% Pending retirement masks are nonzero one-hot values by construction.
-spec first_bit(pos_integer(), non_neg_integer()) -> non_neg_integer().
first_bit(Value, Index) when Value band 1 =:= 1 -> Index;
first_bit(Value, Index) -> first_bit(Value bsr 1, Index + 1).

%% Boolean state bits are compared as their sampled numeric representation.
-spec bool(boolean()) -> 0 | 1.
bool(false) -> 0;
bool(true) -> 1.

%% Graph actor names are the existing observer's explicit identities.
-spec actor(non_neg_integer()) -> binary().
actor(I) -> <<"actor/", (integer_to_binary(I))/binary>>.

%% Existing capture events already identify concrete slots rather than aggregate links.
-spec slot_actor(non_neg_integer(), non_neg_integer()) -> binary().
slot_actor(L, S) -> iolist_to_binary(["link/", integer_to_binary(L), "/", integer_to_binary(S)]).

%% Reset identities use the same convention as the register and stream observers.
-spec incarnation(non_neg_integer()) -> binary().
incarnation(I) -> <<"reset/", (integer_to_binary(I))/binary>>.

%% Contradictory observations reject rather than become missing or invented ancestry.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> error({spacetime_publication, Reason}).
