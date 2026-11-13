-module(hls_protocol_inspection).
-moduledoc "Emits passive process metadata and DSLX inspection constants from a retained source transport. Network and boundary renderers add these artifacts to the existing endpoint-2 inspection service; this metadata does not define an independent execution path.".

%% Inspection selection.
-export([mode/1]).

%% Metadata and DSLX support emission.
-export([emit/1, write/2]).
-export_type([manifest/0]).

%% JSON normalization uses binary keys; the debug provider owns nested catalogue schemas.
-type json_value() ::
    null | boolean() | number() | binary() | [json_value()] | #{binary() => json_value()}.

-doc "The normalized JSON inspection catalogue passed unchanged to the debug service. Nested resources belong to the compiler's observation schema; composition consumers retain this object without interpreting it.".
-type manifest() :: #{binary() => json_value()}.

-doc "Accepts none or process; rejects unsupported inspection before source compilation.".
-spec mode(term()) -> none | process.
mode(none) -> none;
mode(process) -> process;
mode(Other) -> error({unsupported_protocol_inspection, Other}).

-doc "Writes passive DSLX observation functions, a fingerprinted JSON manifest and a trusted local catalog beside a fresh network. Reads committed machine metadata only, with no new actor state or application backpressure. Collection fields use the common 128-bit reply policy; payloads, mailbox occupancy and history are excluded. The caller must connect inspect_address/value to the unchanged topology debug service under the same reset.".
-spec write(hls_protocol_transport:descriptor() | xls_protocol_network:input(), file:filename()) ->
    manifest().
write(Plan, Directory) ->
    hls_generated_files:write_into(emit(Plan), Directory).

-doc "Returns passive observation DSLX, fingerprinted JSON and the trusted ETF catalog in memory. Requires finalized receiver manifests from the same transport emission so allocated failures match the emitted owners. A partition catalog contains only native receivers, retaining global actor IDs; nonlocal addresses have no resource. The result is the same bound manifest; no output files are created or read back.".
-spec emit(hls_protocol_transport:descriptor() | xls_protocol_network:input()) ->
    hls_generated_files:output(manifest()).
emit(#{bundle := #{topology := #{actors := Actors}, modules := Modules}, receivers := Receivers}) ->
    Rows = [
        begin
            #{id := Id, module := M} = lists:nth(I + 1, Actors),
            #{index => I, id => Id, module => M}
        end
     || #{index := I, module := M} <- Receivers
    ],
    ReceiverManifests = maps:from_list([
        {I, Manifest}
     || #{index := I, manifest := Manifest} <- Receivers
    ]),
    true = length(Rows) =:= map_size(ReceiverManifests),
    Resources = [
        resource(A, maps:get(M, Modules), maps:get(I, ReceiverManifests))
     || A = #{index := I, module := M} <- Rows
    ],
    Source = [observation(R, maps:get(M, Modules)) || R = #{module := M} <- Receivers],
    Manifest0 = json(#{
        schema => 5,
        resources => Resources,
        probes => [],
        catalogue_sha256 => digest(term_to_binary(Rows, [deterministic])),
        inspection => #{
            scope => process,
            coherence => one_process_pre_edge,
            history => unavailable,
            sampling => addressed_pre_edge,
            transport_stalls => excluded
        },
        source_identities => hls_protocol_identity:source_modules(Modules),
        dslx_sha256 => digest(iolist_to_binary(Source)),
        limits => [
            <<"Separate queries are not atomic together.">>,
            <<"No mailbox counts, payloads or continuous event history.">>
        ]
    }),
    Manifest = Manifest0#{<<"fingerprint">> => hls_topology_debug:manifest_fingerprint(Manifest0)},
    #{
        result => Manifest,
        files => #{
            "process_observation.x" => Source,
            "inspection.json" => json:encode(Manifest),
            "inspection.etf" => term_to_binary(#{actors => Rows, manifest => Manifest}, [
                deterministic
            ])
        }
    }.

%% Resource order follows normalized actors; each finalized receiver supplies the codebook actually emitted for its owner.
-spec resource(map(), map(), hls_local_actor:manifest()) -> map().
resource(#{index := I, id := Id, module := M}, #{program := Program}, #{
    failure_sites := FailureSites
}) ->
    Spec = xls_actor_program:spec(Program),
    Collection = xls_actor_observation:collection(Spec),
    Layout = xls_actor_observation:layout(Collection),
    Base = #{
        id => I,
        kind => actor,
        name => iolist_to_binary(["owner/", integer_to_list(I)]),
        owner_index => I,
        logical_key => hls_actor_identity:actor_key(Id),
        logical_name => iolist_to_binary(io_lib:format("~0tp", [Id])),
        role => M,
        phases => maps:get(phases, Spec),
        failures => xls_actor_debug:failures(FailureSites),
        width =>
            case Collection of
                none -> 26;
                _ -> 56 + maps:get(width, maps:get(reduction, Layout))
            end
    },
    case Collection of
        none ->
            Base;
        #{sites := Sites} ->
            Base#{
                reduction => (maps:get(reduction, Layout))#{
                    sites => [maps:with([id, phase, name, population, kind], S) || S <- Sites]
                }
            }
    end.

%% Projection reads declared raw-machine offsets, never private action or collection payload data.
-spec observation(map(), map()) -> iodata().
observation(#{index := I, manifest := #{machine_layout := ML, machine_bits := Width}}, #{
    program := Program
}) ->
    Spec = xls_actor_program:spec(Program),
    Layout = xls_actor_observation:layout(xls_actor_observation:collection(Spec)),
    Fields = maps:get(fields, maps:get(reduction, Layout, #{fields => #{}})),
    Pieces =
        [
            "(bits[128]:1 << u32:25)",
            shift(slice(maps:get(phase, ML)), 0),
            shift(slice(maps:get(enter_pending, ML)), 8),
            shift(slice(maps:get(failure, ML)), 9)
        ] ++
            [
                shift(progress(Name, Bits, Spec, ML), At)
             || {Name, #{observation_offset := At, width := Bits}} <- lists:sort(
                    maps:to_list(Fields)
                ),
                Bits > 0
            ],
    [
        "// One coherent committed process observation; initialization/reset mask all metadata.\n",
        "pub fn observe_",
        n(I),
        "(raw: bits[",
        n(Width),
        "], initialized: bool, reset: bool) -> bits[128] {\n",
        "if reset || !initialized { bits[128]:0 } else { ",
        lists:join(" | ", Pieces),
        " } }\n"
    ].

%% Gather metadata supersedes scalar metadata only while its source status is active.
-spec progress(atom(), pos_integer(), map(), map()) -> iodata().
progress(Name, Width, #{reductions := Reduction, gathers := Gather}, Machine) ->
    Scalar =
        case Reduction of
            none ->
                ["bits[", n(Width), "]:0"];
            _ ->
                field(
                    Name,
                    Width,
                    reduction,
                    xls_statem_reduction_ir:packed_layout(Reduction),
                    Machine
                )
        end,
    case Gather of
        none ->
            Scalar;
        _ ->
            #{fields := Fields} = xls_statem_gather_layout:progress(Gather),
            Value = field(Name, Width, gather, Fields, Machine),
            SiteCount =
                case Reduction of
                    none -> 0;
                    #{sites := Sites} -> length(Sites)
                end,
            Indexed =
                case Name of
                    site -> ["(", Value, " + bits[", n(Width), "]:", n(SiteCount), ")"];
                    _ -> Value
                end,
            [
                "(if ",
                field(status, 2, gather, Fields, Machine),
                " != u2:0 { ",
                Indexed,
                " } else { ",
                Scalar,
                " })"
            ]
    end.

%% Absent membership fields are zero; widths follow the common bounded observation ABI.
-spec field(atom(), pos_integer(), atom(), map(), map()) -> iodata().
field(Name, Width, Kind, Layout, ML) ->
    case maps:find(Name, Layout) of
        error ->
            ["bits[", n(Width), "]:0"];
        {ok, #{width := 0}} ->
            ["bits[", n(Width), "]:0"];
        {ok, #{offset := At, width := Bits}} ->
            #{offset := Base} = maps:get(Kind, ML),
            ["(", slice(#{offset => Base + At, width => Bits}), " as bits[", n(Width), "])"]
    end.

%% Slices are compiler-owned dimensions; no source text is interpreted as a wire expression.
-spec slice(map()) -> iodata().
slice(#{offset := At, width := Bits}) -> ["raw[", n(At), "+:bits[", n(Bits), "]]"].
%% Cast before shifting so narrow metadata is never truncated at its destination offset.
-spec shift(iodata(), non_neg_integer()) -> iodata().
shift(Value, At) -> ["((", Value, " as bits[128]) << u32:", n(At), ")"].
%% Normalize JSON before computing the shared canonical fingerprint.
-spec json(map()) -> manifest().
json(Value) -> json:decode(iolist_to_binary(json:encode(Value))).
%% Stable byte identities bind metadata and its trusted local catalog.
-spec digest(binary()) -> binary().
digest(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
%% Only validated static widths/indices enter generated DSLX.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
