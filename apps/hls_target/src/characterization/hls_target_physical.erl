-module(hls_target_physical).
-moduledoc """
Physical companion validation for hls_spacetime recordings. Checks build identities, resource bindings and catalogue references before consumers join execution events to placed cells. Coverage describes declared associations; neither names nor a native_measurement label establish their authenticity or exact execution causality.
""".
%% Companion validation used by the execution contract and recording consumers.
-export([validate/3]).
%% Shared artifact and derived coverage contracts.
-export_type([physical/0, summary/0, generated/0, binding/0]).

%% Opaque nonempty identities are shared with the execution recording.
-type id() :: binary().
%% Exact source, generated RTL and observation identities bind both companions.
-type build() :: hls_observation_build:build().
%% Primitive placement uses one common tile grid; properties retain native strings.
-type cell() :: #{
    id := id(),
    kind := binary(),
    site := binary() | null,
    bel := binary() | null,
    x := non_neg_integer() | null,
    y := non_neg_integer() | null,
    placement => placed | unplaced,
    tile => binary(),
    clock_region => binary(),
    properties := #{binary() => binary()}
}.
-doc "Generated names retain their source association without asserting one-to-one lowering or equivalence to native cells.".
-type generated() :: #{id := id(), source := binary()}.
%% Mapping dispositions retain uncertainty and optimization separately from known associations.
-type disposition() ::
    direct | distributed | merged | replicated | folded | optimized_away | ambiguous | unmapped.
%% Encoded-word bits retain qualified output-pin correspondence or explicit unknown status.
-type bit_binding() :: #{
    bit := non_neg_integer(),
    status := supported | unknown,
    evidence := binary(),
    cell => id(),
    pin => binary()
}.
-doc "One semantic resource's reviewed physical association. Distributed words require a supported output-pin correspondence for every encoded bit; ambiguous candidates remain uncounted as mapped. Evidence identifies the independent qualification supporting the association.".
-type binding() :: #{
    resource := id(),
    generated := [id()],
    cells := [id()],
    disposition := disposition(),
    evidence := binary(),
    bits => [bit_binding()]
}.
%% Pins refer to catalogue cells; native retains an optional full native pin identity.
-type pin() :: #{
    cell := id(),
    pin := binary(),
    direction := input | output | inout,
    native => binary()
}.
%% Each canonical net retains its observed primitive connections.
-type net() :: #{id := id(), pins := [pin()]}.

-doc "A build-bound physical catalogue or null when no measurement is supplied. Tile coordinates are not distances in micrometres. Synthetic fixtures must be labelled explicitly; primitive properties may be empty when not yet exported.".
-type physical() ::
    null
    | #{
        build := build(),
        checkpoint := id(),
        evidence := synthetic_fixture | native_measurement,
        coordinate_unit := tile_grid,
        cells := [cell()],
        generated := [generated()],
        bindings := [binding()],
        nets := [net()],
        native => hls_target_native:native()
    }.

-doc "Coverage derived from one binding per semantic resource. Ambiguous candidates do not count as mapped. physical_cells counts unique supplied catalogue cells; zero for a null catalogue means unmeasured, not zero installed area.".
-type summary() :: #{
    catalogue_supplied := boolean(),
    mapped := non_neg_integer(),
    ambiguous := non_neg_integer(),
    unmapped := non_neg_integer(),
    optimized_away := non_neg_integer(),
    physical_cells := non_neg_integer()
}.

-doc "Checks exact build agreement, complete unique resource bindings, disposition cardinalities and all catalogue references. Allows shared cells for merged/folded resources. Returns derived coverage, or raises {spacetime, Reason}; this is structural consistency validation, not physical equivalence or evidence authenticity verification.".
-spec validate(build(), #{id() => term()}, physical()) -> summary().
validate(Build, Resources, Physical) ->
    build(Build),
    require(is_map(Resources), invalid_semantic_resources),
    lists:foreach(fun identifier/1, maps:keys(Resources)),
    physical(Build, Resources, Physical).

%% A missing catalogue leaves every semantic resource explicitly unmapped.
-spec physical(build(), #{id() => term()}, physical()) -> summary().
physical(_Build, Resources, null) ->
    (empty_summary(0))#{unmapped := map_size(Resources), catalogue_supplied := false};
physical(
    Build,
    Resources,
    #{
        build := PhysicalBuild,
        checkpoint := Checkpoint,
        evidence := Evidence,
        coordinate_unit := Unit,
        cells := Cells,
        generated := Generated,
        bindings := Bindings,
        nets := Nets
    } = Physical
) ->
    build(PhysicalBuild),
    require(hls_observation_build:match(Build, PhysicalBuild) =:= ok, physical_build_mismatch),
    identifier(Checkpoint),
    require(
        lists:member(Evidence, [synthetic_fixture, native_measurement]),
        {invalid_physical_evidence, Evidence}
    ),
    require(Unit =:= tile_grid, {invalid_coordinate_unit, Unit}),
    CellIds = index(Cells, cell, fun cell/1),
    GeneratedIds = index(Generated, generated, fun generated/1),
    _ = index(Nets, net, fun(Net) -> net(Net, CellIds) end),
    Pins = pin_index(Nets),
    case maps:find(native, Physical) of
        error -> ok;
        {ok, Native} -> ok = hls_target_native:validate(Cells, Nets, Native)
    end,
    require(is_list(Bindings), invalid_physical_bindings),
    {Bound, Summary} = lists:foldl(
        fun(Binding, {Seen, Counts}) ->
            {Resource, Category} = binding(Binding, Resources, GeneratedIds, CellIds),
            ok = bit_bindings(Binding, maps:get(Resource, Resources), Pins),
            require(not maps:is_key(Resource, Seen), {duplicate_physical_binding, Resource}),
            {Seen#{Resource => true}, maps:update_with(Category, fun(N) -> N + 1 end, Counts)}
        end,
        {#{}, empty_summary(map_size(CellIds))},
        Bindings
    ),
    Missing = lists:sort([Id || Id <- maps:keys(Resources), not maps:is_key(Id, Bound)]),
    require(Missing =:= [], {missing_physical_bindings, Missing}),
    Summary;
physical(_Build, _Resources, _Physical) ->
    fail(invalid_physical_catalogue).

%% One primitive pin belongs to one canonical net, regardless of native-name aliases.
-spec pin_index([net()]) -> #{{id(), binary()} => input | output | inout}.
pin_index(Nets) ->
    lists:foldl(
        fun(#{pins := Pins}, Seen) ->
            lists:foldl(
                fun(#{cell := Cell, pin := Pin, direction := Direction}, Acc) ->
                    Key = {Cell, Pin},
                    require(not maps:is_key(Key, Acc), {duplicate_physical_pin, Cell, Pin}),
                    Acc#{Key => Direction}
                end,
                Seen,
                Pins
            )
        end,
        #{},
        Nets
    ).

%% The recording supplies each identity; consumers must not infer them from paths or names.
-spec build(term()) -> ok.
build(Build) ->
    case hls_observation_build:validate(Build) of
        ok ->
            #{source := Source, rtl := Rtl, observation := Observation} = Build,
            lists:foreach(fun identifier/1, [Source, Rtl, Observation]);
        {error, {invalid_component, _Name, Value}} ->
            identifier(Value);
        {error, invalid_shape} ->
            fail(invalid_physical_build)
    end.

%% Count installed catalogue cells once, regardless of repeated semantic or time-layer references.
-spec empty_summary(non_neg_integer()) -> summary().
empty_summary(Cells) ->
    #{
        catalogue_supplied => true,
        mapped => 0,
        ambiguous => 0,
        unmapped => 0,
        optimized_away => 0,
        physical_cells => Cells
    }.

%% Validate entries before indexing so duplicate identities cannot silently replace evidence.
-spec index([term()], atom(), fun((term()) -> id())) -> #{id() => true}.
index(Entries, Kind, Validate) ->
    require(is_list(Entries), {invalid_physical_entries, Kind}),
    lists:foldl(
        fun(Entry, Seen) ->
            Id = Validate(Entry),
            require(not maps:is_key(Id, Seen), {duplicate_physical_id, Kind, Id}),
            Seen#{Id => true}
        end,
        #{},
        Entries
    ).

%% Only common nonnegative tile coordinates are admitted; retain native property strings verbatim.
-spec cell(cell()) -> id().
cell(
    #{
        id := Id,
        kind := Kind,
        placement := unplaced,
        site := null,
        bel := null,
        x := null,
        y := null,
        properties := Properties
    } = Cell
) ->
    lists:foreach(fun identifier/1, [Id, Kind]),
    cell_properties(Id, Properties),
    cell_location(Cell),
    Id;
cell(
    #{id := Id, kind := Kind, site := Site, bel := Bel, x := X, y := Y, properties := Properties} =
        Cell
) ->
    require(maps:get(placement, Cell, placed) =:= placed, {invalid_cell_placement, Id}),
    lists:foreach(fun identifier/1, [Id, Kind, Site, Bel]),
    require(
        is_integer(X) andalso X >= 0 andalso X < (1 bsl 53) andalso
            is_integer(Y) andalso Y >= 0 andalso Y < (1 bsl 53),
        {invalid_cell_coordinates, Id}
    ),
    cell_properties(Id, Properties),
    cell_location(Cell),
    Id;
cell(_) ->
    fail(invalid_physical_cell).

%% Optional native location labels are separate from the primitive's lossless property map.
-spec cell_location(cell()) -> ok.
cell_location(Cell) ->
    lists:foreach(
        fun(Key) ->
            case maps:find(Key, Cell) of
                error -> ok;
                {ok, Value} -> require(utf8(Value), {invalid_cell_location, Key})
            end
        end,
        [tile, clock_region]
    ).

%% Placed and explicitly unplaced cells retain the same native property-text contract.
-spec cell_properties(id(), map()) -> ok.
cell_properties(Id, Properties) ->
    require(is_map(Properties), {invalid_cell_properties, Id}),
    maps:foreach(
        fun(Key, Value) ->
            require(utf8(Key) andalso utf8(Value), {invalid_cell_property, Id, Key})
        end,
        Properties
    ).

%% Source descriptions identify the generating declaration without claiming behavioral sensitization.
-spec generated(generated()) -> id().
generated(#{id := Id, source := Source}) ->
    lists:foreach(fun identifier/1, [Id, Source]),
    Id;
generated(_) ->
    fail(invalid_generated_object).

%% Every resource has one explicit disposition, including unknown and optimized-away cases.
-spec binding(binding(), #{id() => term()}, #{id() => true}, #{id() => true}) ->
    {id(), mapped | ambiguous | unmapped | optimized_away}.
binding(
    #{
        resource := Resource,
        generated := Generated,
        cells := Cells,
        disposition := Disposition,
        evidence := Evidence
    },
    Resources,
    GeneratedIds,
    CellIds
) ->
    reference(Resource, Resources, resource),
    identifier(Evidence),
    references(Generated, GeneratedIds, generated),
    references(Cells, CellIds, cell),
    {Resource, disposition(Disposition, length(Generated), length(Cells))};
binding(_, _Resources, _Generated, _Cells) ->
    fail(invalid_physical_binding).

%% Candidate cells are retained for ambiguous bindings without inflating known mapping coverage.
-spec disposition(disposition(), non_neg_integer(), non_neg_integer()) ->
    mapped | ambiguous | unmapped | optimized_away.
disposition(direct, Generated, 1) when Generated >= 1 -> mapped;
disposition(distributed, Generated, Cells) when Generated >= 1, Cells >= 2 -> mapped;
disposition(replicated, Generated, Cells) when Generated >= 1, Cells >= 2 -> mapped;
disposition(merged, Generated, Cells) when Generated >= 1, Cells >= 1 -> mapped;
disposition(folded, Generated, Cells) when Generated >= 1, Cells >= 1 -> mapped;
disposition(optimized_away, Generated, 0) when Generated >= 1 -> optimized_away;
disposition(ambiguous, Generated, Cells) when Generated >= 1, Cells >= 1 -> ambiguous;
disposition(unmapped, _Generated, 0) ->
    unmapped;
disposition(Disposition, Generated, Cells) ->
    fail({invalid_binding_cardinality, Disposition, Generated, Cells}).

%% Distributed words need complete per-bit evidence; partial observations remain uncertain.
-spec bit_bindings(map(), map(), map()) -> ok.
bit_bindings(#{disposition := distributed} = Binding, Resource, Pins) ->
    require(maps:is_key(bits, Binding), missing_distributed_bits),
    Bits = maps:get(bits, Binding),
    check_bits(Bits, Resource, Pins),
    require(
        lists:all(fun(#{status := Status}) -> Status =:= supported end, Bits),
        unsupported_distributed_bit
    ),
    require(
        lists:usort([maps:get(cell, B) || B <- Bits]) =:= lists:sort(maps:get(cells, Binding)),
        distributed_cell_coverage
    );
bit_bindings(#{bits := Bits, cells := Cells}, Resource, Pins) ->
    check_bits(Bits, Resource, Pins),
    require(
        lists:all(
            fun
                (#{status := supported, cell := Cell}) -> lists:member(Cell, Cells);
                (#{status := unknown}) -> true
            end,
            Bits
        ),
        bit_cell_coverage
    );
bit_bindings(_, _, _) ->
    ok.

%% A map covers every encoded bit once; a supported endpoint must be an actual catalogue output pin.
-spec check_bits([bit_binding()], map(), map()) -> ok.
check_bits(Bits, #{width := Width}, Pins) ->
    require(is_list(Bits), invalid_bit_bindings),
    require(
        is_integer(Width) andalso Width > 0 andalso length(Bits) =:= Width, bit_binding_coverage
    ),
    Indices = [maps:get(bit, B) || B <- Bits],
    require(lists:sort(Indices) =:= lists:seq(0, Width - 1), bit_binding_coverage),
    lists:foreach(
        fun
            (#{status := supported, cell := Cell, pin := Pin, evidence := Evidence}) ->
                identifier(Evidence),
                require(
                    maps:get({Cell, Pin}, Pins, missing) =:= output, {bit_output_pin, Cell, Pin}
                );
            (#{status := unknown, evidence := Evidence} = Bit) ->
                identifier(Evidence),
                require(
                    not maps:is_key(cell, Bit) andalso not maps:is_key(pin, Bit),
                    unknown_bit_endpoint
                );
            (_) ->
                fail(invalid_bit_binding)
        end,
        Bits
    );
check_bits(_, _, _) ->
    fail(bit_binding_without_width).

%% A net's repeated pin would falsely duplicate connectivity and is rejected.
-spec net(net(), #{id() => true}) -> id().
net(#{id := Id, pins := Pins}, Cells) ->
    identifier(Id),
    require(is_list(Pins), {invalid_net_pins, Id}),
    Connections = [pin(Pin, Cells) || Pin <- Pins],
    require(length(Connections) =:= length(lists:usort(Connections)), {duplicate_net_pin, Id}),
    Id;
net(_, _Cells) ->
    fail(invalid_physical_net).

%% The catalogue describes primitive pins, not undifferentiated source-level names.
-spec pin(pin(), #{id() => true}) -> {id(), binary()}.
pin(#{cell := Cell, pin := Pin, direction := Direction} = Entry, Cells) ->
    reference(Cell, Cells, cell),
    identifier(Pin),
    require(lists:member(Direction, [input, output, inout]), {invalid_pin_direction, Cell, Pin}),
    case maps:find(native, Entry) of
        error -> ok;
        {ok, Native} -> identifier(Native)
    end,
    {Cell, Pin};
pin(_, _Cells) ->
    fail(invalid_physical_pin).

%% Lists are sets of references within one binding; different bindings may share cells.
-spec references([id()], #{id() => term()}, atom()) -> ok.
references(Ids, Index, Kind) ->
    require(is_list(Ids), {invalid_physical_references, Kind}),
    lists:foreach(fun(Id) -> reference(Id, Index, Kind) end, Ids),
    require(length(Ids) =:= length(lists:usort(Ids)), {duplicate_physical_reference, Kind}).

%% Check nonempty identity before lookup so malformed records have a stable contract error.
-spec reference(id(), #{id() => term()}, atom()) -> ok.
reference(Id, Index, Kind) ->
    identifier(Id),
    require(maps:is_key(Id, Index), {unknown_physical_reference, Kind, Id}).

%% Artifact identity is opaque text, never an atom created from an external recording.
-spec identifier(id()) -> ok.
identifier(Id) ->
    require(utf8(Id) andalso byte_size(Id) > 0, {invalid_physical_identifier, Id}).

%% Native property strings may be empty but must survive JSON text encoding.
-spec utf8(binary()) -> boolean().
utf8(Text) -> is_binary(Text) andalso unicode:characters_to_binary(Text) =:= Text.

%% Keep contract failures distinct from unrelated exceptions raised by a caller.
-spec require(boolean(), term()) -> ok.
require(true, _Reason) -> ok;
require(false, Reason) -> fail(Reason).

%% One error family is shared by execution and physical companion validation.
-spec fail(term()) -> no_return().
fail(Reason) -> error({spacetime, Reason}).
