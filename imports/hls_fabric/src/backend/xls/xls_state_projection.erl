-module(xls_state_projection).
-moduledoc "Validates topology-established state constants and renders codecs for the remaining mutable fields. Activation and scheduler machine codegen use those codecs; layout and debug planning read the same physical width and retained projection metadata.".

%% Projection validation and physical dimensions.
-export([validate/3, width/1]).

%% Mutable-state codecs and function interface.
-export([functions/1, decode/4, encode/2, parameter/1, argument/1]).

%% Inspection metadata for retained constants.
-export([manifest/1]).

-doc "Returns the physical callback-data width, retaining ordinary storage when unspecialized.".
-spec width(map()) -> non_neg_integer().
width(#{state_projection := #{physical_width := W}}) -> W;
width(#{data_width := W}) -> W.

-doc "Rejects a projection derived from different actor source or a different record width.".
-spec validate(map(), map(), [hls_source:form()]) -> ok.
validate(Spec, Projection, Forms) ->
    %% Completion callbacks are analyzed with unconstrained internal events.
    %% Private reduction state is packed separately and is never projected.
    case maps:get(retained_calls, Spec, none) of
        none -> ok;
        _ -> error(state_projection_protocol)
    end,
    Hash = binary:encode_hex(crypto:hash(sha256, term_to_binary(hls_records:resolve(Forms)))),
    #{
        logical_width := Logical,
        physical_width := Physical,
        fields := Fields,
        constants := Constants,
        rows := Rows
    } = Projection,
    Logical = maps:get(data_width, Spec),
    Logical = lists:sum([hls_type:width(maps:get(type, F)) || F <- Fields]),
    Physical = lists:sum([
        hls_type:width(maps:get(type, F))
     || F <- Fields,
        not lists:member(maps:get(name, F), Constants)
    ]),
    case Rows =/= [] andalso lists:all(fun(#{source_hash := H}) -> H =:= Hash end, Rows) of
        true -> ok;
        false -> error(state_projection_source_mismatch)
    end.

-doc "Adds a compile-time instance identity only for specialized codecs.".
-spec parameter(map()) -> iodata().
parameter(#{state_projection := _}) -> "<INSTANCE_ID: u32>";
parameter(_) -> "".

-doc "Passes the enclosing service identity to a specialized codec/executor.".
-spec argument(map()) -> iodata().
argument(#{state_projection := _}) -> "<INSTANCE_ID>";
argument(_) -> "".

-doc "Renders physical data decoding, including slot/phase reconstruction when selected.".
-spec decode(map(), iodata(), iodata(), iodata()) -> iodata().
decode(#{state_projection := _}, Raw, Slot, Phase) ->
    ["shared_data_from_bits<INSTANCE_ID>(", Raw, ", ", Slot, ", ", Phase, ")"];
decode(#{data_name := Name}, Raw, _Slot, _Phase) ->
    [xls_names:record_codec(Name), "_from_bits(", Raw, ")"].

-doc "Renders the compact physical data encoding without circulating inferred constants.".
-spec encode(map(), iodata()) -> iodata().
encode(#{state_projection := _}, Data) -> ["shared_bits_from_data(", Data, ")"];
encode(#{data_name := Name}, Data) -> ["bits_from_", xls_names:record_codec(Name), "(", Data, ")"].

-doc "Emits constant reconstruction and inverse mutable-field codecs; does not alter callback code.".
-spec functions(map()) -> iodata().
functions(#{state_projection := P, data_name := Name}) ->
    #{
        physical_width := Width,
        logical_width := Logical,
        fields := Fields,
        constants := Constants,
        rows := Rows
    } = P,
    ConstantWidth = Logical - Width,
    DynamicLayout = layout([F || F <- Fields, not lists:member(maps:get(name, F), Constants)]),
    ConstantLayout = layout([F || F <- Fields, lists:member(maps:get(name, F), Constants)]),
    [
        "// Constants follow fixed startup and closed routing; mutable fields retain their types.\n",
        "fn shared_configuration<INSTANCE_ID: u32>(slot: u32, phase: Phase) -> bits[",
        n(ConstantWidth),
        "] {\n",
        "  match INSTANCE_ID {\n",
        [
            [
                "    u32:",
                n(I),
                " => match slot {\n",
                [
                    [
                        "      u32:",
                        n(S),
                        " => match phase {\n",
                        [
                            [
                                "        Phase::",
                                xls_names:enum_member(Phase),
                                " => ",
                                constants_value(Values),
                                ",\n"
                            ]
                         || #{phase := Phase, values := Values} <- Phases
                        ],
                        "        _ => zero!<bits[",
                        n(ConstantWidth),
                        "]>(),\n      },\n"
                    ]
                 || #{instance := J, slot := S, phases := Phases} <- Rows, I =:= J
                ],
                "      _ => zero!<bits[",
                n(ConstantWidth),
                "]>(),\n    },\n"
            ]
         || I <- lists:usort([maps:get(instance, R) || R <- Rows])
        ],
        "    _ => zero!<bits[",
        n(ConstantWidth),
        "]>(),\n  }\n}\n\n",
        "fn shared_data_from_bits<INSTANCE_ID: u32>(raw: bits[",
        n(Width),
        "], slot: u32, phase: Phase) -> ",
        xls_names:record_type(Name),
        " {\n",
        "  let constants = shared_configuration<INSTANCE_ID>(slot, phase);\n",
        "  ",
        xls_names:record_type(Name),
        " {\n",
        [
            [
                "    ",
                atom_to_list(F),
                ": ",
                case maps:find(F, DynamicLayout) of
                    {ok, Slice} ->
                        hls_type:dslx_from_bits(Type, slice("raw", Slice));
                    error ->
                        hls_type:dslx_from_bits(Type, [
                            "hls_bits::from_stream(",
                            slice("constants", maps:get(F, ConstantLayout)),
                            ")"
                        ])
                end,
                ",\n"
            ]
         || #{name := F, type := Type} <- Fields
        ],
        "  }\n}\n\n",
        "fn shared_bits_from_data(data: ",
        xls_names:record_type(Name),
        ") -> bits[",
        n(Width),
        "] {\n  ",
        lists:join(
            " ++ ",
            [
                hls_type:dslx_to_bits(Type, ["data.", atom_to_list(F)])
             || #{name := F, type := Type} <- Fields, maps:is_key(F, DynamicLayout)
            ] ++ ["zero!<bits[0]>()"]
        ),
        "\n}\n\n"
    ];
functions(_) ->
    [].

%% Physical fields are concatenated in declaration order, most significant first.
-spec layout([map()]) -> map().
layout(Fields) ->
    {_, Result} = lists:foldr(
        fun(#{name := Name, type := Type}, {Offset, Acc}) ->
            Width = hls_type:width(Type),
            {Offset + Width, Acc#{Name => #{offset => Offset, width => Width}}}
        end,
        {0, #{}},
        Fields
    ),
    Result.

%% Encoded constants retain the host field-stream bit ordering until reconstruction.
-spec constants_value([map()]) -> iodata().
constants_value(Values) ->
    lists:join(" ++ ", [
        ["bits[", n(W), "]:", n(V)]
     || #{width := W, value := V} <- Values
    ]).

%% Static-width slices do not infer shifting or per-bit storage selectors.
-spec slice(iodata(), map()) -> iodata().
slice(Raw, #{offset := O, width := W}) -> [Raw, "[", n(O), "+:bits[", n(W), "]]"].

-doc "Describes logical fields, physical offsets and constant tables for source-level reconstruction.".
-spec manifest(map()) -> map().
manifest(P = #{fields := Fields, constants := Constants}) ->
    Dynamic = layout([F || F <- Fields, not lists:member(maps:get(name, F), Constants)]),
    (maps:without([fields], P))#{
        encoding => native_field_concatenation,
        constant_encoding => field_stream,
        fields => [
            #{
                name => F,
                width => hls_type:width(Type),
                storage => maps:get(F, Dynamic, constant),
                type => iolist_to_binary(hls_type:print_type(Type))
            }
         || #{name := F, type := Type} <- Fields
        ]
    }.

%% Numeric literals never use host locale or exponent formatting.
-spec n(integer()) -> string().
n(N) -> integer_to_list(N).
