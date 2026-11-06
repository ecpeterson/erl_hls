-module(hls_spacetime).
-moduledoc """
Cycle-native execution evidence shared by compiler/lowering observers and offline viewers. Producers supply identities and observations; this module checks consistency before serialization. Storage history and physical correspondence are checked by hls_spacetime_storage and hls_spacetime_physical. It neither observes hardware nor infers missing causality, and does not change the nanosecond timing-profile format.
""".
%% Producer-facing artifact validation and serialization; neither writes files.
-export([validate/1, encode/1]).
%% Shared observer and companion-validator vocabulary.
-export_type([id/0, build/0, event/0, version/0, resource/0, capture/0, bundle/0, summary/0]).

-doc "Nonempty textual identifier scoped to one artifact, independent of payload equality.".
-type id() :: binary().
-doc "Identities of the exact source bundle, compiled RTL and observation bindings; not application names.".
-type build() :: #{source := id(), rtl := id(), observation := id()}.
-doc "A semantic storage word or explicit transient value. Root versions disclose initial, carry-in or unknown ancestry.".
-type version() :: #{
    id := id(),
    incarnation := id(),
    producer := root | id(),
    origin := initial | carry_in | unknown | event,
    storage := null | #{resource := id(), address := non_neg_integer()},
    evidence := binary()
}.
-doc "Logical resource. Storage resources declare shape, ports, reset treatment and supported read collision semantics.".
-type resource() :: #{
    id := id(),
    kind := ff | bram | srl | register | logic | queue,
    evidence := binary(),
    width => pos_integer(),
    depth => pos_integer(),
    ports => #{id() => read | write | read_write},
    read_latency => non_neg_integer(),
    collision => read_first | write_first | forbidden,
    reset => reinitialize | retained | unknown
}.
%% Access-specific fields are checked against the storage resource and its current version.
-type access() :: #{
    kind := write | hold | read_request | read_result,
    resource := id(),
    address := non_neg_integer(),
    port := id(),
    before => id(),
    after_version => id(),
    mask => pos_integer(),
    version => id(),
    request => id()
}.
-doc "One observed semantic action at a clock edge. Sequence orders observer records only; inputs/outputs identify versions, not bit transitions. Optional resources associate the action with logical hardware; storage accesses also name their resource directly.".
-type event() :: #{
    id := id(),
    observer := id(),
    sequence := non_neg_integer(),
    cycle := non_neg_integer(),
    incarnation := id(),
    actor := id(),
    task := id(),
    activation := id(),
    operation := binary(),
    inputs := [id()],
    outputs := [id()],
    evidence := binary(),
    resources => [id()],
    access => access()
}.
%% Half-open intervals partition the captured clock span into reset incarnations.
-type incarnation() :: #{id := id(), first_cycle := non_neg_integer(), end_cycle := pos_integer()}.
%% Explicit missing sequence ranges disclose loss without inventing placeholder events.
-type gap() :: #{
    first_sequence := non_neg_integer(), next_sequence := pos_integer(), reason := binary()
}.
%% Both counter endpoints are mandatory, even for an observer that emitted no records.
-type observer() :: #{
    id := id(),
    first_sequence := non_neg_integer(),
    next_sequence := non_neg_integer(),
    gaps := [gap()],
    scope := binary()
}.
-doc "Single-device, single-clock coverage. complete=false retains known gaps/truncation without permitting a complete-window claim.".
-type capture() :: #{
    device := id(),
    clock := id(),
    first_cycle := non_neg_integer(),
    end_cycle := pos_integer(),
    complete := boolean(),
    evidence := binary(),
    incarnations := [incarnation()],
    observers := [observer()]
}.
%% Additional required control and observed resource order stay separate from version ancestry.
-type relation() :: #{
    source := id(),
    target := id(),
    kind := required | resource_order,
    evidence := binary(),
    resource => id()
}.
%% Electrical activity cannot serve as an event or dependency endpoint.
-type activity() :: #{
    cycle := non_neg_integer(), incarnation := id(), resource := id(), evidence := binary()
}.
-doc "Versioned cycle companion; synthetic fixtures have separate build identities from real recordings. No clock period is implied.".
-type bundle() :: #{
    format := spacetime,
    schema := 1,
    unit := cycle,
    evidence := synthetic_fixture | simulation_witness,
    build := build(),
    capture := capture(),
    resources := [resource()],
    versions := [version()],
    events := [event()],
    relations := [relation()],
    activity := [activity()],
    physical := hls_spacetime_physical:physical()
}.
-doc "Derived recording size and mapping coverage; complete refers only to the observer's declared scope.".
-type summary() :: #{
    events := non_neg_integer(),
    versions := non_neg_integer(),
    resources := non_neg_integer(),
    complete := boolean(),
    required_version_edges := non_neg_integer(),
    mapping := hls_spacetime_physical:summary()
}.

-doc "Checks a producer's complete artifact and returns derived counts/coverage. Raises {spacetime, Reason}; checks declared evidence consistency, not observer completeness or physical authenticity. Known gaps are accepted only when complete=false.".
-spec validate(bundle()) -> summary().
validate(Bundle) ->
    try
        validate_bundle(Bundle)
    catch
        error:{badkey, Key}:Stack -> erlang:raise(error, {spacetime, {missing_field, Key}}, Stack);
        error:{badmatch, _}:Stack -> erlang:raise(error, {spacetime, malformed_record}, Stack);
        error:function_clause:Stack -> erlang:raise(error, {spacetime, malformed_record}, Stack)
    end.

%% Structural patterns describe typed producer records; semantic checks report narrower failures.
-spec validate_bundle(bundle()) -> summary().
validate_bundle(#{
    format := spacetime,
    schema := 1,
    unit := cycle,
    evidence := Evidence,
    build := Build,
    capture := Capture,
    resources := Resources0,
    versions := Versions0,
    events := Events0,
    relations := Relations,
    activity := Activity,
    physical := Physical
}) ->
    member(Evidence, [synthetic_fixture, simulation_witness], evidence_kind),
    #{source := Source, rtl := Rtl, observation := Observation} = Build,
    lists:foreach(fun text/1, [Source, Rtl, Observation]),
    Resources = index(Resources0, resource),
    Versions = index(Versions0, version),
    Events = index(Events0, event),
    lists:foreach(fun resource/1, Resources0),
    Epochs = coverage(Capture, Events0),
    lists:foreach(fun(E) -> event(E, Versions, Epochs, Resources) end, Events0),
    activations(Events0),
    lists:foreach(fun(V) -> version(V, Events, Resources, Epochs) end, Versions0),
    DataEdges = lists:append([inputs(E, Versions, Events) || E <- Events0]),
    ReadEdges = reads(Events0, Events, Resources, Epochs, maps:get(complete, Capture)),
    OrderEdges = [relation(R, Events, Resources) || R <- Relations],
    acyclic(maps:keys(Events), lists:usort(DataEdges ++ ReadEdges ++ OrderEdges)),
    lists:foreach(fun(A) -> activity(A, Resources, Epochs) end, Activity),
    ok = hls_spacetime_storage:validate(Events0, Versions, Resources),
    case {Evidence, Physical} of
        {_, null} -> ok;
        {synthetic_fixture, #{evidence := synthetic_fixture}} -> ok;
        {simulation_witness, #{evidence := native_measurement}} -> ok;
        _ -> fail(mixed_evidence_kinds)
    end,
    Mapping = hls_spacetime_physical:validate(Build, Resources, Physical),
    #{
        events => map_size(Events),
        versions => map_size(Versions),
        resources => map_size(Resources),
        complete => maps:get(complete, Capture),
        required_version_edges => length(lists:usort(DataEdges)),
        mapping => Mapping
    };
validate_bundle(_) ->
    fail(format).

-doc "Validates then produces JSON iodata. Caller owns file creation/retention. Atom field/enum names become strings; write masks become hexadecimal strings to retain wide values in browser consumers. No term-to-atom decoder is involved.".
-spec encode(bundle()) -> iodata().
encode(Bundle = #{events := Events}) ->
    _ = validate(Bundle),
    json:encode(Bundle#{events := [wire_event(E) || E <- Events]}).

%% Hardware write masks routinely exceed the exact integer range of JSON browser numbers.
-spec wire_event(event()) -> map().
wire_event(#{access := #{kind := write, mask := Mask} = Access} = Event) ->
    Event#{access := Access#{mask := <<"0x", (integer_to_binary(Mask, 16))/binary>>}};
wire_event(Event) ->
    Event.

%% Unique IDs are required even for entries not referenced by a selected event.
-spec index([map()], atom()) -> map().
index(Items, Kind) ->
    lists:foldl(
        fun(#{id := Id} = Item, Acc) ->
            text(Id),
            require(not maps:is_key(Id, Acc), {duplicate, Kind, Id}),
            Acc#{Id => Item}
        end,
        #{},
        Items
    ).

%% Logical storage has explicit shape; physical cells are not counted here.
-spec resource(resource()) -> ok.
resource(#{id := Id, kind := Kind, evidence := Evidence} = R) ->
    member(Kind, [ff, bram, srl, register, logic, queue], {resource_kind, Id}),
    text(Evidence),
    case lists:member(Kind, [ff, bram, srl, register]) of
        false ->
            ok;
        true ->
            #{
                width := Width,
                depth := Depth,
                ports := Ports,
                read_latency := Latency,
                collision := Collision,
                reset := Reset
            } = R,
            require(is_integer(Width) andalso Width > 0, {width, Id}),
            require(is_integer(Depth) andalso Depth > 0, {depth, Id}),
            natural(Width),
            natural(Depth),
            require(
                not lists:member(Kind, [ff, register]) orelse Depth =:= 1, {register_depth, Id}
            ),
            natural(Latency),
            require(is_map(Ports) andalso map_size(Ports) > 0, {ports, Id}),
            maps:foreach(
                fun(P, Mode) ->
                    text(P),
                    member(Mode, [read, write, read_write], {port, Id, P})
                end,
                Ports
            ),
            member(Collision, [read_first, write_first, forbidden], {collision, Id}),
            member(Reset, [reinitialize, retained, unknown], {reset_policy, Id})
    end.

%% Coverage uses explicit observer counters, not an assumption that sparse events are exhaustive.
-spec coverage(capture(), [event()]) -> map().
coverage(
    #{
        device := Device,
        clock := Clock,
        first_cycle := First,
        end_cycle := End,
        complete := Complete,
        evidence := Evidence,
        incarnations := EpochList,
        observers := Observers
    },
    Events
) ->
    lists:foreach(fun text/1, [Device, Clock, Evidence]),
    interval(First, End),
    require(is_boolean(Complete), completeness),
    Epochs = index(EpochList, incarnation),
    Ranges = lists:sort([{maps:get(first_cycle, E), maps:get(end_cycle, E)} || E <- EpochList]),
    partition(First, End, Ranges, incarnation_coverage),
    ObserverMap = index(Observers, observer),
    lists:foreach(fun(#{observer := Id}) -> lookup(Id, ObserverMap, observer) end, Events),
    lists:foreach(fun(O) -> observer(O, Events, Complete) end, Observers),
    Epochs.

%% Every sequence is either present exactly once or explicitly missing; complete traces cannot have gaps.
-spec observer(observer(), [event()], boolean()) -> ok.
observer(
    #{id := Id, first_sequence := First, next_sequence := Next, gaps := Gaps, scope := Scope},
    Events,
    Complete
) ->
    text(Scope),
    natural(First),
    natural(Next),
    require(Next >= First, {observer_counters, Id}),
    Selected = [E || E = #{observer := O} <- Events, O =:= Id],
    Observed = [{maps:get(sequence, E), maps:get(sequence, E) + 1} || E <- Selected],
    Missing = [
        begin
            text(maps:get(reason, G)),
            {maps:get(first_sequence, G), maps:get(next_sequence, G)}
        end
     || G <- Gaps
    ],
    require(not Complete orelse Gaps =:= [], {complete_with_loss, Id}),
    partition(First, Next, lists:sort(Observed ++ Missing), {observer_sequence, Id}),
    Cycles = [
        maps:get(cycle, E)
     || {_, E} <- lists:sort([{maps:get(sequence, E), E} || E <- Selected])
    ],
    require(Cycles =:= lists:sort(Cycles), {observer_time, Id}).

%% A partition catches missing interiors, overlaps and truncated footers without allocating every clock/sequence.
-spec partition(non_neg_integer(), non_neg_integer(), [{non_neg_integer(), pos_integer()}], term()) ->
    ok.
partition(End, End, [], _) ->
    ok;
partition(First, End, [{First, Next} | Rest], Reason) when Next > First, Next =< End ->
    natural(First),
    natural(Next),
    partition(Next, End, Rest, Reason);
partition(_, _, _, Reason) ->
    fail(Reason).

%% Event ownership and version declarations are stable across all consumers of the recording.
-spec event(event(), map(), map(), map()) -> ok.
event(
    #{
        id := Id,
        observer := Observer,
        sequence := Seq,
        cycle := Cycle,
        incarnation := Epoch,
        actor := Actor,
        task := Task,
        activation := Activation,
        operation := Operation,
        inputs := Inputs,
        outputs := Outputs,
        evidence := Evidence
    } = Event,
    Versions,
    Epochs,
    Resources
) ->
    lists:foreach(fun text/1, [Observer, Actor, Task, Activation, Operation, Evidence]),
    natural(Seq),
    at(Cycle, Epoch, Epochs),
    unique(Inputs, {duplicate_inputs, Id}),
    unique(Outputs, {duplicate_outputs, Id}),
    Associated = maps:get(resources, Event, []),
    unique(Associated, {duplicate_event_resources, Id}),
    lists:foreach(fun(R) -> lookup(R, Resources, event_resource) end, Associated),
    lists:foreach(fun(V) -> lookup(V, Versions, version) end, Inputs),
    lists:foreach(
        fun(V) ->
            #{producer := Producer, incarnation := VEpoch} = lookup(V, Versions, version),
            require(Producer =:= Id andalso VEpoch =:= Epoch, {output_owner, Id, V})
        end,
        Outputs
    ).

%% Activation names cannot silently change owner, task or reset incarnation.
-spec activations([event()]) -> ok.
activations(Events) ->
    _ = lists:foldl(
        fun(#{activation := A, actor := Actor, task := Task, incarnation := Epoch}, Acc) ->
            Identity = {Actor, Task, Epoch},
            require(maps:get(A, Acc, Identity) =:= Identity, {activation_identity, A}),
            Acc#{A => Identity}
        end,
        #{},
        Events
    ),
    ok.

%% Root ancestry is explicit; resetting a RAM does not imply clearing its contents.
-spec version(version(), map(), map(), map()) -> ok.
version(
    #{
        id := Id,
        incarnation := Epoch,
        producer := Producer,
        origin := Origin,
        storage := Storage,
        evidence := Evidence
    },
    Events,
    Resources,
    Epochs
) ->
    text(Evidence),
    lookup(Epoch, Epochs, incarnation),
    case Producer of
        root ->
            member(Origin, [initial, carry_in, unknown], {root_origin, Id});
        _ ->
            #{incarnation := PEpoch, outputs := Outputs} = lookup(Producer, Events, producer),
            require(
                Origin =:= event andalso PEpoch =:= Epoch andalso lists:member(Id, Outputs),
                {producer, Id}
            )
    end,
    case Storage of
        null ->
            ok;
        #{resource := R, address := Address} ->
            #{kind := Kind, depth := Depth, reset := Reset} = lookup(R, Resources, storage),
            require(lists:member(Kind, [ff, bram, srl, register]), {not_storage, R}),
            natural(Address),
            require(Address < Depth, {address, Id}),
            case {Producer, Reset, Origin} of
                {root, unknown, initial} -> fail({unknown_reset_initial, Id});
                {root, retained, initial} -> fail({retained_reset_initial, Id});
                _ -> ok
            end
    end.

%% Version use creates required ancestry; temporal proximity and equal bits do not.
-spec inputs(event(), map(), map()) -> [{id(), id()}].
inputs(#{id := Id, cycle := Cycle, incarnation := Epoch, inputs := Inputs}, Versions, Events) ->
    lists:filtermap(
        fun(V) ->
            #{producer := P, incarnation := VEpoch} = maps:get(V, Versions),
            require(VEpoch =:= Epoch, {cross_reset_version, Id, V}),
            case P of
                root ->
                    false;
                _ ->
                    #{cycle := PCycle} = maps:get(P, Events),
                    require(PCycle =< Cycle, {future_version, Id, V}),
                    {true, {P, Id}}
            end
        end,
        Inputs
    ).

%% Completed captures may omit only responses due beyond an incarnation's retained interval.
-spec reads([event()], map(), map(), map(), boolean()) -> [{id(), id()}].
reads(Events, ById, Resources, Epochs, Complete) ->
    Results = [E || E = #{access := #{kind := read_result}} <- Events],
    Edges = [
        begin
            #{id := Id, access := #{request := Request}} = E,
            lookup(Request, ById, read_request),
            {Request, Id}
        end
     || E <- Results
    ],
    Responded = maps:from_list([{Request, true} || {Request, _} <- Edges]),
    lists:foreach(
        fun(
            #{
                id := Id,
                cycle := Cycle,
                incarnation := Epoch,
                access := #{resource := Resource}
            }
        ) ->
            #{read_latency := Latency} = maps:get(Resource, Resources),
            #{end_cycle := End} = maps:get(Epoch, Epochs),
            HasResult = maps:is_key(Id, Responded),
            require(
                not Complete orelse Cycle + Latency >= End orelse HasResult,
                {missing_read_result, Id}
            )
        end,
        [E || E = #{access := #{kind := read_request}} <- Events]
    ),
    Edges.

%% Resource ordering remains a separate relation, even though both kinds must form a consistent DAG.
-spec relation(relation(), map(), map()) -> {id(), id()}.
relation(
    #{source := Source, target := Target, kind := Kind, evidence := Evidence} = R, Events, Resources
) ->
    text(Evidence),
    member(Kind, [required, resource_order], relation_kind),
    #{cycle := A, incarnation := AEpoch} = lookup(Source, Events, relation_source),
    #{cycle := B, incarnation := BEpoch} = lookup(Target, Events, relation_target),
    require(A =< B, {relation_time, Source, Target}),
    require(AEpoch =:= BEpoch, {cross_reset_relation, Source, Target}),
    case Kind of
        required -> ok;
        resource_order -> lookup(maps:get(resource, R), Resources, resource)
    end,
    {Source, Target}.

%% The combined DAG catches zero-cycle loops without imposing a fabricated cross-observer total order.
-spec acyclic([id()], [{id(), id()}]) -> ok.
acyclic(Ids, Edges) ->
    Graph = digraph:new(),
    try
        [digraph:add_vertex(Graph, Id) || Id <- Ids],
        [digraph:add_edge(Graph, A, B) || {A, B} <- Edges],
        require(digraph_utils:is_acyclic(Graph), dependency_cycle)
    after
        digraph:delete(Graph)
    end.

%% Activity is a separate table and cannot masquerade as version ancestry.
-spec activity(activity(), map(), map()) -> ok.
activity(
    #{cycle := Cycle, incarnation := Epoch, resource := Resource, evidence := Evidence},
    Resources,
    Epochs
) ->
    at(Cycle, Epoch, Epochs),
    lookup(Resource, Resources, resource),
    text(Evidence).

%% Cycle intervals are half-open, including their first observation and excluding reset retirement.
-spec at(non_neg_integer(), id(), map()) -> ok.
at(Cycle, Epoch, Epochs) ->
    natural(Cycle),
    #{first_cycle := First, end_cycle := End} = lookup(Epoch, Epochs, incarnation),
    require(Cycle >= First andalso Cycle < End, {incarnation_cycle, Epoch, Cycle}).

%% Shared scalar checks run at the producer artifact boundary.
-spec interval(non_neg_integer(), pos_integer()) -> ok.
interval(First, End) ->
    natural(First),
    natural(End),
    require(End > First, interval).

%% Textual IDs/evidence must survive JSON encoding without allocating atoms.
-spec text(binary()) -> ok.
text(Text) ->
    require(
        is_binary(Text) andalso byte_size(Text) > 0 andalso
            unicode:characters_to_binary(Text) =:= Text,
        text
    ).

%% Negative or fractional cycle/sequence fields are not supported.
-spec natural(non_neg_integer()) -> ok.
natural(N) ->
    require(is_integer(N) andalso N >= 0 andalso N < (1 bsl 53), exact_nonnegative_integer).

%% Enum rejection is explicit so activity never becomes a required edge by spelling accident.
-spec member(term(), [term()], term()) -> ok.
member(Value, Allowed, Reason) -> require(lists:member(Value, Allowed), Reason).

%% Repeated references are ambiguous record ownership, not repeated work.
-spec unique([id()], term()) -> ok.
unique(Ids, Reason) -> require(length(Ids) =:= length(lists:usort(Ids)), Reason).

%% Resolve declared IDs without generating replacement roots for missing observations.
-spec lookup(id(), map(), atom()) -> map().
lookup(Id, Table, Kind) ->
    case maps:find(Id, Table) of
        {ok, Item} -> Item;
        error -> fail({unknown, Kind, Id})
    end.

%% Uniform semantic invariant errors remain usable from CLI or direct Erlang callers.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> fail(Reason).

%% One error namespace distinguishes evidence rejection from a valid incomplete recording.
-spec fail(term()) -> no_return().
fail(Reason) -> error({spacetime, Reason}).
