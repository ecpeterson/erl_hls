-module(hls_domain_endpoint_packets).
-moduledoc "Emits bounded packet selection and routing between independent mailbox endpoints and an atomic carrier. Source crossing codec plans supply class admission and canonical frame constants. Endpoint kernels retain ownership and sequence policy; the carrier retains complete packets. This router adds only a round-robin cursor and sticky fault, never payload history or peer lifecycle.".

%% Pure source generation; board composition and external compilation remain separate.
-export([emit/1]).
-export_type([config/0, result/0]).

%% Sampled pin order is shared by DSLX and the mechanical RTL adapter.
-type ports() :: [{string(), pos_integer()}].
%% Only trusted source-derived classes may authorize a DATA frame.
-type route() :: #{
    id := hls_nums:u32(),
    kind := tx | rx,
    slots := pos_integer(),
    classes := [#{slot := byte(), codec := hls_protocol_codec:plan()}, ...],
    common_mask := non_neg_integer(),
    common_value := non_neg_integer(),
    common_fixed_bits := non_neg_integer()
}.
-doc "Checked local role directions, complete source crossing descriptors and shared native endpoint codecs. At most four TX and four RX endpoints are admitted; each application frame has twenty payload words. Optional top_module names the adapter, core prefix and artifact directory and defaults to endpoint_packets. Direction comes from checked role composition, never a peer packet.".
-type config() :: #{
    endpoints := [hls_domain_endpoint_wire:endpoint(), ...],
    crossings := [hls_protocol_domains:crossing()],
    codecs := hls_domain_endpoint_wire:codecs(),
    top_module => string()
}.
-doc "Atomic carrier pins, raw endpoint packet pins, exact source classes and bounded storage. RX common constants restore only bits fixed identically by every source class after original-frame validation. No mapped area, arbitrary-history fairness or physical integrity claim is made.".
-type result() :: #{
    inputs := ports(),
    outputs := ports(),
    top_module := string(),
    core_module := string(),
    routes := [route()],
    codecs := hls_domain_endpoint_wire:codecs(),
    packet_format := map(),
    state_bit_budget := pos_integer(),
    cursor_bits := pos_integer(),
    payload_registers := 0,
    canonical_comparisons := #{tx := 1, rx := 1},
    unit := hls_artifact_bundle:unit()
}.

-doc "Returns one sampled packet router and its mechanical adapter without writing files or running tools. DATA has 32 words and ACK 11; all binding fields and sequence remain full-width. One cursor selects only valid-bit metadata before selecting and packing an offer. A stalled offer pins the cursor until atomic acceptance or endpoint cancellation; offered endpoint fields must remain stable until those events. Known canonical stale packets pass unchanged to native identity checks. Malformed traffic faults before RX handoff; a TX shape fault blocks that TX handoff and latches common fault for the next edge, permitting a valid RX transfer on the detection edge to avoid combinational ownership feedback. Only cold reset clears the router fault.".
-spec emit(config()) -> hls_generated_files:output(result()).
emit(#{endpoints := Endpoints, crossings := Crossings, codecs := Codecs} = Config) ->
    Top = maps:get(top_module, Config, "endpoint_packets"),
    ok = identifier(Top),
    Core = Top ++ "_core",
    SourcePath = Top ++ "/" ++ Top ++ ".x",
    AdapterPath = Top ++ "/packets.sv",
    #{codecs := Shared} = hls_domain_endpoint_wire:load(#{
        kind => domain_endpoint_management,
        management_route => {0, 2},
        endpoints => Endpoints,
        response_tag => 129,
        codecs => Codecs
    }),
    true = length(Endpoints) =< 8,
    true = length([E || E = #{kind := tx} <- Endpoints]) =< 4,
    true = length([E || E = #{kind := rx} <- Endpoints]) =< 4,
    Fields = binding_fields(maps:get(binding, Shared)),
    Routes = [route(E, Crossings) || E <- Endpoints],
    CursorBits = cursor_bits(length(Routes) - 1),
    {Inputs, Outputs} = ports(Routes, Fields),
    {ok, Template} = file:read_file(
        filename:join(code:priv_dir(hls_lowering), "xls/templates/domain_endpoint_packets.x.in")
    ),
    Text = xls_template:render(Template, [
        {<<"@@INPUTS@@">>, structure("Inputs", Inputs)},
        {<<"@@OUTPUTS@@">>, structure("Outputs", Outputs)},
        {<<"@@CURSOR_BITS@@">>, n(CursorBits)},
        {<<"@@COUNT@@">>, n(length(Routes))},
        {<<"@@BINDING_FIELDS@@">>, [[atom_to_list(F), ": u64, "] || F <- Fields]},
        {<<"@@DECODE_BINDING@@">>, [
            [atom_to_list(F), ": value[", n(I * 64), "+:u64],\n"]
         || {I, F} <- lists:enumerate(0, Fields)
        ]},
        {<<"@@PACK_BINDING@@">>,
            lists:join(" ++ ", [["value.", atom_to_list(F)] || F <- lists:reverse(Fields)])},
        {<<"@@VALID_OFFERS@@">>, valid_offers(Routes, CursorBits)},
        {<<"@@SELECT_OFFER@@">>, offers(Routes, Fields, CursorBits)},
        {<<"@@RX_ROUTE@@">>, receive_routes(Routes)},
        {<<"@@CLASSES@@">>, classes(Routes)},
        {<<"@@ENDPOINT_OUTPUTS@@">>, endpoint_outputs(Routes, Fields)}
    ]),
    #{imports := Support} = hls_build_support:layout([]),
    Profile = hls_build_profile:owner(hls_frame_layout:new(20)),
    #{
        files => #{
            SourcePath => Text, AdapterPath => sv_protocol_ports:emit(Inputs, Outputs, Top, Core)
        },
        result => #{
            inputs => Inputs,
            outputs => Outputs,
            top_module => Top,
            core_module => Core,
            routes => Routes,
            codecs => maps:with([operation, status, binding], Shared),
            packet_format => #{
                bits => 1024,
                data_words => 32,
                ack_words => 11,
                kind_bits => {0, 8},
                data_kind => 1,
                ack_kind => 2,
                slot_bits => {8, 8},
                reserved_zero_bits => {16, 16},
                channel_bits => {32, 32},
                binding_bits => {64, 256},
                sequence_bits => {320, 32},
                frame_bits => {352, 672},
                ack_slot => 0,
                ack_unused_frame => 0,
                word_order => little_endian
            },
            state_bit_budget => CursorBits + 1,
            cursor_bits => CursorBits,
            payload_registers => 0,
            canonical_comparisons => #{tx => 1, rx => 1},
            unit => #{
                role => <<".">>,
                directory => b(Top),
                source => b(SourcePath),
                top => <<"endpoint_packets_clock">>,
                module => b(Core),
                output => b(Top ++ "/core.v"),
                dslx_path => [b(P) || P <- [Top | Support]],
                rtl => [b(Top ++ "/core.v"), b(AdapterPath)],
                codegen_flags => hls_build_profile:flags(Profile, sampled_clock)
            }
        }
    }.

%% Generated module and directory identities cannot contain HDL fragments or path separators.
-spec identifier(string()) -> ok.
identifier(Name) ->
    match = re:run(Name, "^[a-zA-Z_][a-zA-Z0-9_]*$", [{capture, none}]),
    ok.

%% Source records fix the complete little-endian binding layout; no application schema is guessed here.
-spec binding_fields(hls_type:descriptor()) -> [atom()].
binding_fields({hls_type, hls_record, endpoint_binding, Fields}) ->
    Names = [F || {F, T} <- Fields, T =:= hls_nums:u64()],
    [namespace, generation, source_incarnation, destination_incarnation] = Names,
    4 = length(Fields),
    Names.

%% Membership in retained classes, rather than a slot range alone, authorizes one canonical source frame.
-spec route(hls_domain_endpoint_wire:endpoint(), [hls_protocol_domains:crossing()]) -> route().
route(#{id := Id, kind := Kind}, Crossings) ->
    [#{link := #{index := Id, slots := Slots, classes := Classes}}] =
        [C || C = #{index := Index} <- Crossings, Index =:= Id],
    true = Slots > 0 andalso Slots =< 256,
    true = Classes =/= [],
    ClassIds = [
        begin
            true = Slot >= 0 andalso Slot < Slots,
            672 = hls_frame_layout:frame_bits(Layout),
            true = Mask >= 0 andalso Mask < (1 bsl 672),
            true = Value >= 0 andalso Value < (1 bsl 672) andalso Value band Mask =:= Value,
            Slot
        end
     || #{slot := Slot, codec := #{frame_layout := Layout, mask := Mask, value := Value}} <- Classes
    ],
    true = length(ClassIds) =:= length(Classes),
    true = length(ClassIds) =:= length(lists:usort(ClassIds)),
    true = lists:sort(ClassIds) =:= lists:seq(0, Slots - 1),
    {CommonMask, CommonValue} = common(Classes),
    #{
        id => Id,
        kind => Kind,
        slots => Slots,
        classes => Classes,
        common_mask => CommonMask,
        common_value => CommonValue,
        common_fixed_bits => length([I || I <- lists:seq(0, 671), CommonMask band (1 bsl I) =/= 0])
    }.

%% A bit is restored only if every class fixes it and all those fixed values agree.
-spec common([#{codec := hls_protocol_codec:plan()}, ...]) ->
    {non_neg_integer(), non_neg_integer()}.
common([#{codec := #{mask := Mask, value := Value}} | Rest]) ->
    lists:foldl(
        fun(#{codec := #{mask := M, value := V}}, {CM, CV}) ->
            NextMask = CM band M band bnot (CV bxor V),
            {NextMask, CV band NextMask}
        end,
        {Mask, Value},
        Rest
    ).

%% The single cursor needs no more than three bits for eight selected offers.
-spec cursor_bits(non_neg_integer()) -> pos_integer().
cursor_bits(0) -> 1;
cursor_bits(N) -> max(1, integer_bits(N)).

%% Integer dimensions remain compile-time metadata.
-spec integer_bits(non_neg_integer()) -> non_neg_integer().
integer_bits(0) -> 0;
integer_bits(N) -> 1 + integer_bits(N bsr 1).

%% Atomic packet buffers belong to the carrier; raw endpoint frame pins remain separate per receiver.
-spec ports([route()], [atom()]) -> {ports(), ports()}.
ports(Routes, Fields) ->
    Inputs =
        [
            {"reset", 1},
            {"carrier_fault", 1},
            {"packet_tx_ready", 1},
            {"packet_rx", 1024},
            {"packet_rx_words", 6},
            {"packet_rx_valid", 1}
        ] ++
            lists:append([offer_ports(R, Fields) || R <- Routes]),
    Outputs =
        [
            {"packet_tx", 1024},
            {"packet_tx_words", 6},
            {"packet_tx_valid", 1},
            {"packet_rx_ready", 1},
            {"router_fault", 1}
        ] ++
            lists:append([endpoint_ports(R, Fields) || R <- Routes]),
    {Inputs, Outputs}.

%% TX supplies DATA and consumes credits; RX supplies ACK and consumes received DATA.
-spec offer_ports(route(), [atom()]) -> ports().
offer_ports(#{id := Id, kind := Kind}, Fields) ->
    P = prefix(Id),
    {Offer, Ready, Data} =
        case Kind of
            tx -> {"tx_", "credit_ready", [{P ++ "tx_slot", 8}, {P ++ "tx_frame", 672}]};
            rx -> {"ack_", "data_ready", []}
        end,
    [{P ++ Offer ++ "valid", 1}] ++ [{P ++ Offer ++ atom_to_list(F), 64} || F <- Fields] ++
        [{P ++ Offer ++ "sequence", 32}, {P ++ Ready, 1}] ++ Data.

%% Native kernels alone decide whether a well-formed stale/current packet changes endpoint ownership.
-spec endpoint_ports(route(), [atom()]) -> ports().
endpoint_ports(#{id := Id, kind := Kind}, Fields) ->
    P = prefix(Id),
    {Packet, Ready, Data} =
        case Kind of
            tx -> {"credit_", "data_tx_ready", []};
            rx -> {"data_", "ack_tx_ready", [{P ++ "data_slot", 8}, {P ++ "data_frame", 672}]}
        end,
    [{P ++ Ready, 1}, {P ++ Packet ++ "valid", 1}] ++
        [{P ++ Packet ++ atom_to_list(F), 64} || F <- Fields] ++ [{P ++ Packet ++ "sequence", 32}] ++
        Data.

%% Arbitration reads only eight or fewer valid bits before selecting any payload.
-spec valid_offers([route()], pos_integer()) -> iodata().
valid_offers(Routes, Bits) ->
    [
        "match index {\n",
        [
            ["uN[", n(Bits), "]:", n(I), " => io.", prefix(Id), offer_name(Kind), "valid,\n"]
         || {I, #{id := Id, kind := Kind}} <- lists:enumerate(0, Routes)
        ],
        "_ => false,\n}"
    ].

%% Only the selected endpoint's complete packet fields enter shared packing and TX validation.
-spec offers([route()], [atom()], pos_integer()) -> iodata().
offers(Routes, Fields, Bits) ->
    [
        "match index {\n",
        [
            [
                "uN[",
                n(Bits),
                "]:",
                n(I),
                " => Offer { kind: u8:",
                n(wire_kind(Kind)),
                ", channel: u32:",
                n(Id),
                ", binding: Binding {\n",
                [
                    [atom_to_list(F), ": io.", prefix(Id), offer_name(Kind), atom_to_list(F), ",\n"]
                 || F <- Fields
                ],
                "}, sequence: io.",
                prefix(Id),
                offer_name(Kind),
                "sequence,\n",
                case Kind of
                    tx ->
                        ["slot: io.", prefix(Id), "tx_slot, frame: io.", prefix(Id), "tx_frame,\n"];
                    rx ->
                        "slot: u8:0, frame: Frame:0,\n"
                end,
                "},\n"
            ]
         || {I, #{id := Id, kind := Kind}} <- lists:enumerate(0, Routes)
        ],
        "_ => zero!<Offer>(),\n}"
    ].

%% Static local direction determines the only incoming kind legal for a channel ID.
-spec receive_routes([route()]) -> iodata().
receive_routes(Routes) ->
    [
        "match channel {\n",
        [
            [
                "u32:",
                n(Id),
                " => Route { known: true, kind: u8:",
                n(
                    case Kind of
                        tx -> 2;
                        rx -> 1
                    end
                ),
                ", ready: io.",
                prefix(Id),
                case Kind of
                    tx -> "credit_ready";
                    rx -> "data_ready"
                end,
                " },\n"
            ]
         || #{id := Id, kind := Kind} <- Routes
        ],
        "_ => zero!<Route>(),\n}"
    ].

%% Source constants are selected first; one shared frame comparison follows for each direction.
-spec classes([route()]) -> iodata().
classes(Routes) ->
    [
        "match channel {\n",
        [
            [
                "u32:",
                n(Id),
                " => match slot {\n",
                [
                    [
                        "u8:",
                        n(Slot),
                        " => Class { known: true, mask: Frame:0x",
                        hex(Mask),
                        ", value: Frame:0x",
                        hex(Value),
                        " },\n"
                    ]
                 || #{slot := Slot, codec := #{mask := Mask, value := Value}} <- Classes
                ],
                "_ => zero!<Class>(),\n},\n"
            ]
         || #{id := Id, classes := Classes} <- Routes
        ],
        "_ => zero!<Class>(),\n}"
    ].

%% Incoming identities stay untouched; RX restoration exposes only source-agreed fixed bits after validation.
-spec endpoint_outputs([route()], [atom()]) -> iodata().
endpoint_outputs(Routes, Fields) ->
    [
        [
            begin
                P = prefix(Id),
                {Ready, Packet, KindCode} =
                    case Kind of
                        tx -> {"data_tx_ready", "credit_", 2};
                        rx -> {"ack_tx_ready", "data_", 1}
                    end,
                [
                    P,
                    Ready,
                    ": tx_take && selected.index == Cursor:",
                    n(I),
                    ",\n",
                    P,
                    Packet,
                    "valid: rx_live && rx_channel == u32:",
                    n(Id),
                    " && rx_kind == u8:",
                    n(KindCode),
                    ",\n",
                    [
                        [P, Packet, atom_to_list(F), ": rx_binding.", atom_to_list(F), ",\n"]
                     || F <- Fields
                    ],
                    P,
                    Packet,
                    "sequence: rx_sequence,\n",
                    case Kind of
                        tx ->
                            [];
                        rx ->
                            [
                                P,
                                "data_slot: rx_slot,\n",
                                P,
                                "data_frame: (rx_frame & !Frame:0x",
                                hex(CommonMask),
                                ") | Frame:0x",
                                hex(CommonValue),
                                ",\n"
                            ]
                    end
                ]
            end
        ]
     || {I, #{id := Id, kind := Kind, common_mask := CommonMask, common_value := CommonValue}} <- lists:enumerate(
            0, Routes
        )
    ].

%% Outgoing packet kind follows local endpoint direction, never runtime packet contents.
-spec wire_kind(tx | rx) -> 1 | 2.
wire_kind(tx) -> 1;
wire_kind(rx) -> 2.

%% Raw endpoint builders already name their outgoing packet pins by ownership direction.
-spec offer_name(tx | rx) -> string().
offer_name(tx) -> "tx_";
offer_name(rx) -> "ack_".

%% Static channel IDs produce distinct legal mechanical port names.
-spec prefix(hls_nums:u32()) -> string().
prefix(Id) -> "endpoint_" ++ n(Id) ++ "_".

%% Ordered sampled structs share the mechanical adapter's exact packing order.
-spec structure(string(), ports()) -> iodata().
structure(Name, Fields) ->
    ["pub struct ", Name, " {\n", [[F, ": bits[", n(W), "],\n"] || {F, W} <- Fields], "}\n"].

%% Checked dimensions and IDs are compile-time decimal literals.
-spec n(non_neg_integer()) -> string().
n(Value) -> integer_to_list(Value).

%% Source-derived fixed frame bits use compact literal text without changing bit order.
-spec hex(non_neg_integer()) -> string().
hex(Value) -> integer_to_list(Value, 16).

%% Bundle unit paths and names are UTF-8 byte strings.
-spec b(string()) -> binary().
b(Value) -> unicode:characters_to_binary(Value).
