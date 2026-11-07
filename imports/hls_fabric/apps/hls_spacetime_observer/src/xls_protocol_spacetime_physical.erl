-module(xls_protocol_spacetime_physical).
-moduledoc "Qualifies proposed RTL storage-bit associations against a complete native catalogue and independent finite replay evidence. Producer orchestration supplies the checked input identities and actual connected-parent-net names; this module checks their native output-pin membership before producing generic physical claims. Names and equal values alone never create associations or execution dependencies.".

%% Explicit candidate qualification and generic recording attachment claims.
-export([qualify/3, claims/2]).
-export_type([identity/0, candidates/0, witness/0, qualified/0]).

%% Build agreement covers the observation plan separately from the routed artifact.
-type build() :: #{source := binary(), rtl := binary(), observation := binary()}.
-doc "Exact input closure shared by the catalogue, proposed observations and finite comparison. probe identifies the checked candidate specification, not a simulator result.".
-type identity() :: #{
    build := build(), checkpoint := binary(), netlist := binary(), probe := binary()
}.
%% A caller proposes an explicit bit/output connection; native aliases are resolved independently.
-type candidate_bit() :: #{
    bit := non_neg_integer(),
    cell := binary(),
    pin := binary(),
    native_pin := binary(),
    primitive := binary(),
    parent_net := binary()
}.
%% Association to a semantic resource is explicit; generated paths are descriptive evidence only.
-type candidate() :: #{
    id := binary(),
    resource := binary(),
    generated := binary(),
    width := pos_integer(),
    bits := [candidate_bit()]
}.
-doc "Proposed encoded-register observations with exact connected-net identities from the bound functional netlist. The caller verifies that these records were extracted from that netlist and that the probe digest binds this specification; qualification does not discover source equivalence or parse HDL.".
-type candidates() :: #{identity := identity(), probes := [candidate()]}.
%% Independent replay comparison retains actual and expected populations, including constant-only bits.
-type comparison() :: #{
    id := binary(),
    width := pos_integer(),
    mask := non_neg_integer(),
    mismatch_samples := non_neg_integer(),
    unknown_samples := non_neg_integer(),
    mismatch_mask := non_neg_integer(),
    unknown_mask := non_neg_integer(),
    observed_ones := non_neg_integer(),
    observed_zeroes := non_neg_integer(),
    expected_ones := non_neg_integer(),
    expected_zeroes := non_neg_integer()
}.
%% Horizons exclude reset consistently with the finite comparison; an empty witness cannot qualify.
-type witness_case() :: #{
    id := binary(),
    cycles := pos_integer(),
    nonreset_cycles := pos_integer(),
    complete := boolean(),
    public_passed := boolean(),
    rows := [comparison()]
}.
-doc "Independent finite comparison results bound to the same input identities. Every case must compare every proposed bit over a nonempty nonreset horizon with no mismatches or unknowns; retained actual and expected bit populations must agree. The caller verifies the complete captured files and comparison before supplying this summary.".
-type witness() :: #{identity := identity(), cases := [witness_case()]}.
%% A checked bit retains native membership and whether both Boolean values were exercised.
-type qualified_bit() :: #{
    bit := non_neg_integer(),
    cell := binary(),
    pin := binary(),
    native_pin := binary(),
    parent_net := binary(),
    canonical_net := binary(),
    varied := boolean()
}.
%% Partial words keep their omitted bits explicit when rendered into generic claims.
-type qualified_probe() :: #{
    id := binary(),
    resource := binary(),
    generated := binary(),
    width := pos_integer(),
    bits := [qualified_bit()]
}.
-doc "Native membership plus finite stored-value correspondence, with exact input identities and case horizons. This is not all-input equivalence, a write-action proof, whole-actor mapping or dynamic gate causality.".
-type qualified() :: #{
    identity := identity(),
    cases := [
        #{
            id := binary(),
            cycles := pos_integer(),
            nonreset_cycles := pos_integer()
        }
    ],
    probes := [qualified_probe()]
}.
%% Catalogue records are already validated by the generic native importer; indexes preserve identities.
-type context() :: #{
    cells := #{binary() => map()},
    pins := #{binary() => map()},
    nets := #{binary() => true},
    aliases := #{binary() => binary()}
}.

-doc "Checks unique candidate bits, exact build/checkpoint/netlist/probe agreement, every nonreset finite comparison and actual native output-pin/parent-net membership. Requires a complete validated catalogue and at least one nonempty case. Rejects disagreement with {spacetime_physical, Reason}; does not invoke vendor tools or infer missing constants, aliases or causality.".
-spec qualify(hls_spacetime_physical:physical(), candidates(), witness()) -> qualified().
qualify(
    Catalogue = #{build := Build, checkpoint := Checkpoint},
    #{identity := Identity = #{build := Build, checkpoint := Checkpoint}, probes := Probes},
    #{identity := WitnessIdentity, cases := Cases}
) ->
    require(Identity =:= WitnessIdentity, identity_mismatch),
    identity(Identity),
    require(Probes =/= [], no_candidates),
    require(Cases =/= [], no_cases),
    _ = unique([{maps:get(id, C), true} || C <- Cases], duplicate_case),
    ProbeIndex = unique([{maps:get(id, P), P} || P <- Probes], duplicate_probe),
    _ = unique([{maps:get(resource, P), true} || P <- Probes], duplicate_resource),
    Rows = [witness_case(C, lists:sort(maps:keys(ProbeIndex))) || C <- Cases],
    Context = catalogue_index(Catalogue),
    Qualified = [qualify_probe(P, Rows, Context) || P <- Probes],
    #{
        identity => Identity,
        cases => [maps:with([id, cycles, nonreset_cycles], C) || C <- Cases],
        probes => Qualified
    };
qualify(_, _, _) ->
    error({spacetime_physical, catalogue_identity_mismatch}).

%% Opaque identity bytes must be nonempty; orchestration verifies their actual file hashes.
-spec identity(identity()) -> ok.
identity(#{
    build := #{source := Source, rtl := Rtl, observation := Observation},
    checkpoint := Checkpoint,
    netlist := Netlist,
    probe := Probe
}) ->
    lists:foreach(fun identifier/1, [Source, Rtl, Observation, Checkpoint, Netlist, Probe]).

%% Invalid external identities must not silently become shared empty keys.
-spec identifier(binary()) -> ok.
identifier(Value) ->
    require(is_binary(Value) andalso byte_size(Value) > 0, {invalid_identity, Value}).

%% Duplicates reject even when their values happen to agree.
-spec unique([{binary() | non_neg_integer(), term()}], atom()) -> map().
unique(Rows, Reason) ->
    lists:foldl(
        fun({Id, Value}, Acc) ->
            require(not maps:is_key(Id, Acc), {Reason, Id}),
            Acc#{Id => Value}
        end,
        #{},
        Rows
    ).

%% Canonical pin membership is independent of descriptive generated names.
-spec catalogue_index(hls_spacetime_physical:physical()) -> context().
catalogue_index(#{cells := Cells, nets := Nets} = Catalogue) ->
    Aliases = maps:get(aliases, maps:get(native, Catalogue, #{}), []),
    #{
        cells => unique([{maps:get(id, C), C} || C <- Cells], duplicate_cell),
        nets => unique([{maps:get(id, N), true} || N <- Nets], duplicate_net),
        pins => unique(
            [
                {maps:get(native, P), P#{net => Net}}
             || #{id := Net, pins := Pins} <- Nets,
                P <- Pins
            ],
            duplicate_pin
        ),
        aliases => unique([{maps:get(id, A), maps:get(net, A)} || A <- Aliases], duplicate_alias)
    }.

%% Every case must cover the same observations and a real nonreset horizon.
-spec witness_case(witness_case(), [binary()]) -> #{binary() => comparison()}.
witness_case(
    #{
        id := Id,
        cycles := Cycles,
        nonreset_cycles := Nonreset,
        complete := Complete,
        public_passed := Public,
        rows := Rows
    },
    ProbeIds
) ->
    identifier(Id),
    require(Complete =:= true andalso Public =:= true, {incomplete_witness, Id}),
    require(
        is_integer(Cycles) andalso is_integer(Nonreset) andalso
            Nonreset > 0 andalso Nonreset =< Cycles,
        {invalid_horizon, Id}
    ),
    Index = unique([{maps:get(id, R), R} || R <- Rows], duplicate_comparison),
    require(lists:sort(maps:keys(Index)) =:= ProbeIds, {comparison_population, Id}),
    Index.

%% A candidate mask is derived from unique in-range bit rows, never trusted as a cache.
-spec qualify_probe(candidate(), [#{binary() => comparison()}], context()) -> qualified_probe().
qualify_probe(
    #{
        id := Id,
        resource := Resource,
        generated := Generated,
        width := Width,
        bits := Bits
    },
    Cases,
    Context
) ->
    lists:foreach(fun identifier/1, [Id, Resource, Generated]),
    require(is_integer(Width) andalso Width > 0, {invalid_width, Id}),
    require(Bits =/= [], {empty_candidate, Id}),
    Index = unique([{maps:get(bit, B), B} || B <- Bits], duplicate_bit),
    Indices = maps:keys(Index),
    require(
        lists:all(fun(I) -> is_integer(I) andalso I >= 0 andalso I < Width end, Indices),
        {bit_out_of_range, Id}
    ),
    Mask = lists:foldl(fun(I, M) -> M bor (1 bsl I) end, 0, Indices),
    Populations = [comparison(maps:get(Id, C), Width, Mask) || C <- Cases],
    {Ones, Zeroes} = lists:foldl(
        fun({O, Z}, {Os, Zs}) -> {O bor Os, Z bor Zs} end,
        {0, 0},
        Populations
    ),
    Varied = Ones band Zeroes,
    #{
        id => Id,
        resource => Resource,
        generated => Generated,
        width => Width,
        bits => [native_bit(maps:get(I, Index), Varied, Context) || I <- lists:sort(Indices)]
    }.

%% A zero mismatch count alone is insufficient: every selected bit must have been observed.
-spec comparison(comparison(), pos_integer(), non_neg_integer()) ->
    {non_neg_integer(), non_neg_integer()}.
comparison(
    #{
        id := Id,
        width := Width,
        mask := Mask,
        mismatch_samples := Mismatches,
        unknown_samples := Unknowns,
        mismatch_mask := MismatchMask,
        unknown_mask := UnknownMask,
        observed_ones := Ones,
        observed_zeroes := Zeroes,
        expected_ones := ExpectedOnes,
        expected_zeroes := ExpectedZeroes
    },
    Width,
    Mask
) ->
    require(
        Mismatches =:= 0 andalso Unknowns =:= 0 andalso
            MismatchMask =:= 0 andalso UnknownMask =:= 0,
        {failed_comparison, Id}
    ),
    require(
        is_integer(Ones) andalso Ones >= 0 andalso is_integer(Zeroes) andalso Zeroes >= 0 andalso
            (Ones bor Zeroes) =:= Mask,
        {unobserved_bits, Id}
    ),
    require(Ones =:= ExpectedOnes andalso Zeroes =:= ExpectedZeroes, {population_mismatch, Id}),
    {Ones, Zeroes};
comparison(#{id := Id}, _, _) ->
    error({spacetime_physical, {comparison_shape, Id}}).

%% Source candidates require an actual native register output, not just a net with a similar name.
-spec native_bit(candidate_bit(), non_neg_integer(), context()) -> qualified_bit().
native_bit(
    #{
        bit := Bit,
        cell := Cell,
        pin := Pin,
        native_pin := NativePin,
        primitive := Primitive,
        parent_net := Parent
    },
    Varied,
    #{cells := Cells, pins := Pins} = Context
) ->
    require(
        lists:member(Primitive, [<<"FDRE">>, <<"FDSE">>, <<"FDCE">>, <<"FDPE">>]) andalso
            Pin =:= <<"Q">>,
        {unsupported_storage_output, Cell, Primitive, Pin}
    ),
    require(maps:get(kind, maps:get(Cell, Cells)) =:= Primitive, {primitive_mismatch, Cell}),
    #{cell := PinCell, pin := PinName, direction := Direction, net := Net} = maps:get(
        NativePin, Pins
    ),
    require(
        PinCell =:= Cell andalso PinName =:= Pin andalso Direction =:= output,
        {output_pin_mismatch, NativePin}
    ),
    require(canonical(Parent, Context) =:= Net, {parent_net_mismatch, NativePin, Parent}),
    #{
        bit => Bit,
        cell => Cell,
        pin => Pin,
        native_pin => NativePin,
        parent_net => Parent,
        canonical_net => Net,
        varied => (Varied band (1 bsl Bit)) =/= 0
    }.

%% Only supplied native aliases establish the canonical connection; no hierarchy/name guessing.
-spec canonical(binary(), context()) -> binary().
canonical(Name, #{aliases := Aliases, nets := Nets}) ->
    Net = maps:get(Name, Aliases, Name),
    require(maps:is_key(Net, Nets), {unknown_parent_net, Name}),
    Net.

-doc "Builds generic claims for explicit register resource IDs of matching width and depth one. Unsupported encoded bits stay unknown; shared output cells remain shared rather than duplicated. Leaves unrelated resources to the importer's unmapped disposition. Consume only the result of qualify/3 from the same checked input closure.".
-spec claims([hls_spacetime:resource()], qualified()) -> hls_spacetime_import:claims().
claims(Resources, #{probes := Probes}) ->
    Index = unique([{maps:get(id, R), R} || R <- Resources], duplicate_resource),
    Bindings = [binding(P, Index) || P <- Probes],
    Generated = unique(
        [
            {maps:get(generated, P), #{
                id => maps:get(generated, P),
                source =>
                    <<"Explicit encoded RTL register association; finite stored-value correspondence">>
            }}
         || P <- Probes
        ],
        duplicate_generated
    ),
    #{
        generated => [maps:get(Id, Generated) || Id <- lists:sort(maps:keys(Generated))],
        bindings => Bindings
    }.

%% Whole-word status is complete only when every encoded bit has qualified output correspondence.
-spec binding(qualified_probe(), #{binary() => hls_spacetime:resource()}) ->
    hls_spacetime_physical:binding().
binding(#{resource := Resource, generated := Generated, width := Width, bits := Bits}, Resources) ->
    #{kind := register, width := Width, depth := 1} = maps:get(Resource, Resources),
    Index = unique([{maps:get(bit, B), B} || B <- Bits], duplicate_bit),
    Disposition =
        case map_size(Index) =:= Width of
            true -> distributed;
            false -> ambiguous
        end,
    #{
        resource => Resource,
        generated => [Generated],
        cells => lists:usort([maps:get(cell, B) || B <- Bits]),
        disposition => Disposition,
        evidence =>
            <<"Checked native output-pin/parent-net membership and finite nonreset value agreement; not write or causal proof">>,
        bits => [bit_claim(I, Index) || I <- lists:seq(0, Width - 1)]
    }.

%% A bit constant only in the observed schedules remains weaker than an exercised bit.
-spec bit_claim(non_neg_integer(), #{non_neg_integer() => qualified_bit()}) -> map().
bit_claim(I, Bits) ->
    case maps:find(I, Bits) of
        {ok, #{cell := Cell, pin := Pin, varied := Varied}} ->
            Evidence =
                case Varied of
                    true ->
                        <<"Native output/parent net checked; finite equality with both Boolean values observed">>;
                    false ->
                        <<"Native output/parent net checked; finite equality at one constant observed value only">>
                end,
            #{bit => I, status => supported, cell => Cell, pin => Pin, evidence => Evidence};
        error ->
            #{
                bit => I,
                status => unknown,
                evidence =>
                    <<"No qualified output correspondence; not inferred constant, aliased or eliminated">>
            }
    end.

%% Stable domain errors distinguish rejected evidence from successful finite qualification.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> error({spacetime_physical, Reason}).
