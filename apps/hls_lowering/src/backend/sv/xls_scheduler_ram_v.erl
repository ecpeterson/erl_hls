%%%% xls_scheduler_ram_v
%%%%
%%%% Verilog plumbing for the external RAMs of a shared-scheduler plan.

-module(xls_scheduler_ram_v).
-moduledoc """
Derives physical RAM bindings and renders the SystemVerilog shell around XLS scheduler RAM ports. Public scheduler and explicit partition builders reuse these bindings for codegen configurations, widths and 1R1W instances; XLS channel signatures remain in xls_scheduler_ram_dslx.

The generated XLS interface uses 32-bit addresses. Ordered bindings derive actual bank widths and depths, rather than treating that interface width as physical memory capacity.
""".

%% Physical bindings and codegen configurations.
-export([bindings/1, bindings/2, bindings/3, configurations/1, mailbox_stride/2]).

%% SystemVerilog declarations and instances.
-export([wires/1, application_ports/1, instances/2]).

%% Required generic RAM support files.
-export([assets/1]).

-doc "Derives indexed RAM bindings from a normalized scheduler plan.".
-spec bindings(hls_scheduler_plan:plan()) -> [map()].
bindings(Plan) -> bindings(Plan, hls_frame_layout:default()).

-doc "Derives RAM bindings with the selected ordinary-frame width; actor state, gather storage and debug words remain independently sized.".
-spec bindings(hls_scheduler_plan:plan(), hls_frame_layout:layout()) -> [map()].
bindings(Plan = #{interfaces := Interfaces}, Layout) ->
    maps:foreach(fun(_, #{frame_layout := Selected}) -> Layout = Selected end, Interfaces),
    bindings(Plan, Layout, Interfaces).

-doc "Derives RAM bindings from retained scheduler facts and supplied actor summaries without reloading interfaces. Only optional collection observations consume an interface; ordinary groups need no additional summary fields.".
-spec bindings(
    hls_scheduler_plan:plan(),
    hls_frame_layout:layout(),
    hls_scheduler_plan:interfaces()
) -> [map()].
bindings(#{groups := Groups}, Layout, Interfaces) ->
    [binding(Index, Group, Layout, Interfaces) || {Index, Group} <- lists:enumerate(0, Groups)].

-doc "Returns the XLS --ram_configurations value for these ordered physical bindings. Uses the scheduler DSLX channel interface for state, mailbox and optional masked-gather stores; indices need not be contiguous. An empty binding list returns empty IO data.".
-spec configurations([map()]) -> iodata().
configurations(Bindings) ->
    lists:join(",", lists:append([binding_configurations(Binding) || Binding <- Bindings])).

%% The wrapper bank names and DSLX endpoint order describe the same physical stores.
-spec binding_configurations(map()) -> [iodata()].
binding_configurations(Binding = #{index := Index}) ->
    Gather = maps:is_key(gather_members, Binding),
    Stores =
        ["state", "mailbox"] ++
            case Gather of
                true -> ["gather"];
                false -> []
            end,
    Names = xls_scheduler_ram_dslx:names(all, ["_", stem(Index), "_"], #{
        gather_collection => Gather
    }),
    configurations(stem(Index), Stores, Names).

%% XLS names each bank followed by its read request/response and write request/response.
-spec configurations(iodata(), [string()], [iodata()]) -> [iodata()].
configurations(_, [], []) ->
    [];
configurations(Stem, [Store | Stores], [
    ReadRequest, ReadResponse, WriteRequest, WriteResponse | Names
]) ->
    [
        [
            Stem,
            "_",
            Store,
            ":1R1W:",
            lists:join(":", [ReadRequest, ReadResponse, WriteRequest, WriteResponse])
        ]
        | configurations(Stem, Stores, Names)
    ].

-doc "Declares every wire needed between an XLS application and its RAMs.".
-spec wires([map()]) -> iolist().
wires(Bindings) ->
    [
        [[binding_wires(Binding), gather_wires(Binding)] || Binding <- Bindings],
        xls_collection_observation:wires(Bindings)
    ].

-doc "Connects every scheduler RAM port on an XLS application instance.".
-spec application_ports([map()]) -> iolist().
application_ports(Bindings) ->
    [
        [[binding_application_ports(Binding), gather_ports(Binding)] || Binding <- Bindings],
        xls_collection_observation:ports(Bindings)
    ].

-doc "Instantiates one state and one mailbox RAM per scheduler.".
-spec instances([map()], iodata()) -> iolist().
instances(Bindings, Clock) ->
    [[binding_instances(Binding, Clock), gather_instance(Binding, Clock)] || Binding <- Bindings].

-doc "Lists generic RTL sources required by these physical storage bindings.".
-spec assets([map()]) -> [file:filename()].
assets(Bindings) ->
    case Bindings of
        [] ->
            [];
        _ ->
            [filename:join([code:priv_dir(erl_hls), "rtl", "hls_1r1w_ram.v"])] ++
                case lists:any(fun(B) -> maps:is_key(gather_members, B) end, Bindings) of
                    false ->
                        [];
                    true ->
                        [
                            filename:join([
                                code:priv_dir(hls_lowering), "rtl", "hls_indexed_gather_ram.v"
                            ])
                        ]
                end
    end.

%% Derive physical row widths including optional actor-private state.
-spec binding(non_neg_integer(), map(), hls_frame_layout:layout(), hls_scheduler_plan:interfaces()) ->
    map().
binding(Index, Group, Layout, Interfaces) ->
    MachineLayout = xls_machine_layout:from_group(Group),
    StateWidth = xls_machine_layout:width(MachineLayout),
    SlotCount = maps:get(slot_count, Group),
    MailboxCapacity = maps:get(mailbox_capacity, Group),
    Interface = maps:get(maps:get(module, Group, none), Interfaces, #{}),
    maps:merge(
        maps:merge(xls_collection_observation:binding(Group, Interface), gather_binding(Group)), #{
            index => Index,
            state_width => StateWidth,
            state_address_width => address_width(SlotCount),
            mailbox_width => hls_frame_layout:frame_bits(Layout),
            mailbox_stride => mailbox_stride(SlotCount, MailboxCapacity),
            mailbox_address_width => address_width(SlotCount * MailboxCapacity)
        }
    ).

-doc "Returns a power-of-two mailbox row stride when it fits the already allocated RAM; otherwise returns capacity.".
-spec mailbox_stride(pos_integer(), 1..((1 bsl 8) - 1)) -> pos_integer().
mailbox_stride(Slots, Capacity) ->
    Padded =
        case Capacity of
            1 -> 1;
            _ -> 1 bsl address_width(Capacity)
        end,
    case address_width(Slots * Padded) =:= address_width(Slots * Capacity) of
        true -> Padded;
        false -> Capacity
    end.

%% Declares the wrapper signals for one physical RAM bank.
-spec binding_wires(map()) -> iodata().
binding_wires(#{
    index := Index,
    state_width := StateWidth,
    mailbox_width := MailboxWidth
}) ->
    Stem = stem(Index),
    [
        "    wire [31:0] ",
        Stem,
        "_state_rd_addr;\n",
        "    wire [31:0] ",
        Stem,
        "_state_wr_addr;\n",
        "    wire [",
        integer_to_list(StateWidth - 1),
        ":0] ",
        Stem,
        "_state_wr_data;\n",
        "    wire ",
        Stem,
        "_state_wr_en;\n",
        "    wire ",
        Stem,
        "_state_rd_en;\n",
        "    wire [",
        integer_to_list(StateWidth - 1),
        ":0] ",
        Stem,
        "_state_rd_data;\n",
        "    wire [31:0] ",
        Stem,
        "_mailbox_rd_addr;\n",
        "    wire [31:0] ",
        Stem,
        "_mailbox_wr_addr;\n",
        "    wire [",
        integer_to_list(MailboxWidth - 1),
        ":0] ",
        Stem,
        "_mailbox_wr_data;\n",
        "    wire ",
        Stem,
        "_mailbox_wr_en;\n",
        "    wire ",
        Stem,
        "_mailbox_rd_en;\n",
        "    wire [",
        integer_to_list(MailboxWidth - 1),
        ":0] ",
        Stem,
        "_mailbox_rd_data;\n\n"
    ].

%% Connects the application's RAM request and response ports.
-spec binding_application_ports(map()) -> [any()].
binding_application_ports(#{index := Index}) ->
    Stem = stem(Index),
    lists:append([
        [",\n        .", Stem, "_", Port, "(", Stem, "_", Port, ")"]
     || Port <- ram_ports()
    ]).

%% Lists the standard single-read/single-write request and response signals.
-spec ram_ports() -> iodata().
ram_ports() ->
    [
        "state_rd_addr",
        "state_wr_addr",
        "state_wr_data",
        "state_wr_en",
        "state_rd_en",
        "state_rd_data",
        "mailbox_rd_addr",
        "mailbox_wr_addr",
        "mailbox_wr_data",
        "mailbox_wr_en",
        "mailbox_rd_en",
        "mailbox_rd_data"
    ].

%% Instantiates the state and mailbox RAMs for one shared group.
-spec binding_instances(map(), term()) -> [[any(), ...], ...].
binding_instances(
    #{
        index := Index,
        state_width := StateWidth,
        state_address_width := StateAddressWidth,
        mailbox_width := MailboxWidth,
        mailbox_address_width := MailboxAddressWidth
    },
    Clock
) ->
    Stem = stem(Index),
    [
        ram(Stem, "state", StateWidth, StateAddressWidth, Clock),
        ram(Stem, "mailbox", MailboxWidth, MailboxAddressWidth, Clock)
    ].

%% Renders a RAM instance with the selected width, depth and implementation.
-spec ram(
    [string(), ...],
    [97 | 98 | 101 | 105 | 108 | 109 | 111 | 115 | 116 | 120, ...],
    integer(),
    integer(),
    term()
) -> [any(), ...].
ram(Stem, Kind, Width, AddressWidth, Clock) ->
    [
        "    hls_1r1w_ram #(.WIDTH(",
        integer_to_list(Width),
        "), .ADDRESS_WIDTH(",
        integer_to_list(AddressWidth),
        ")) ",
        Stem,
        "_",
        Kind,
        " (\n",
        "        .clk(",
        Clock,
        "),\n",
        "        .rd_addr(",
        Stem,
        "_",
        Kind,
        "_rd_addr[",
        integer_to_list(AddressWidth - 1),
        ":0]),\n",
        "        .wr_addr(",
        Stem,
        "_",
        Kind,
        "_wr_addr[",
        integer_to_list(AddressWidth - 1),
        ":0]),\n",
        "        .wr_data(",
        Stem,
        "_",
        Kind,
        "_wr_data),\n",
        "        .wr_en(",
        Stem,
        "_",
        Kind,
        "_wr_en),\n",
        "        .rd_en(",
        Stem,
        "_",
        Kind,
        "_rd_en),\n",
        "        .rd_data(",
        Stem,
        "_",
        Kind,
        "_rd_data)\n",
        "    );\n\n"
    ].

%% Computes the minimum nonzero address width for the storage depth.
-spec address_width(pos_integer()) -> pos_integer().
address_width(Count) when Count > 0 ->
    address_width(Count - 1, 0).

%% Computes the minimum nonzero address width for the storage depth.
-spec address_width(integer(), non_neg_integer()) -> pos_integer().
address_width(0, 0) -> 1;
address_width(0, Width) -> Width;
address_width(Value, Width) -> address_width(Value bsr 1, Width + 1).

%% Builds the stable signal prefix for a physical bank.
-spec stem(integer()) -> [string(), ...].
stem(Index) -> ["scheduler_", integer_to_list(Index)].

%% One masked row contains all member lanes, with two epoch banks per logical actor.
-spec gather_binding(map()) -> map().
gather_binding(#{
    gather_collection := true,
    slot_count := Slots,
    gathers := #{sites := [#{element := Element, population := #{size := Members}}]}
}) ->
    #{
        gather_members => Members,
        gather_element_bits => xls_statem_reduction_ir:type_width(Element),
        gather_address_width => address_width(Slots * 2)
    };
gather_binding(#{gather_collection := true}) ->
    error(indexed_gather_requires_one_site);
gather_binding(_) ->
    #{}.

%% Keep masks separate from data: only selected member lanes are written.
-spec gather_wires(map()) -> iodata().
gather_wires(#{index := Index, gather_members := Members, gather_element_bits := Element}) ->
    Stem = [stem(Index), "_gather"],
    Width = integer_to_list(Members * Element - 1),
    [["    wire [31:0] ", Stem, "_", Port, ";\n"] || Port <- ["rd_addr", "wr_addr"]] ++
        [["    wire [", Width, ":0] ", Stem, "_", Port, ";\n"] || Port <- ["rd_data", "wr_data"]] ++
        [["    wire ", Stem, "_", Port, ";\n"] || Port <- ["rd_en", "wr_en"]] ++
        [["    wire [", integer_to_list(Members - 1), ":0] ", Stem, "_wr_mask;\n"]];
gather_wires(_) ->
    [].

%% The XLS RAM adapter exports unhandshaken, fixed-latency physical memory signals.
-spec gather_ports(map()) -> iodata().
gather_ports(#{index := Index, gather_members := _}) ->
    Stem = [stem(Index), "_gather"],
    [
        [",\n        .", Stem, "_", Port, "(", Stem, "_", Port, ")"]
     || Port <- ["rd_addr", "wr_addr", "rd_data", "wr_data", "rd_en", "wr_en", "wr_mask"]
    ];
gather_ports(_) ->
    [].

%% Shallow independent member lanes use distributed RAM without forcing many block RAMs.
-spec gather_instance(map(), iodata()) -> iodata().
gather_instance(
    #{
        index := Index,
        gather_members := Members,
        gather_element_bits := Element,
        gather_address_width := AddressWidth
    },
    Clock
) ->
    Stem = [stem(Index), "_gather"],
    [
        "    hls_indexed_gather_ram #(.ELEMENT_BITS(",
        integer_to_list(Element),
        "), .MEMBERS(",
        integer_to_list(Members),
        "), .ADDRESS_WIDTH(",
        integer_to_list(AddressWidth),
        ")) ",
        Stem,
        " (.clk(",
        Clock,
        ")",
        [
            [", .", Port, "(", Stem, "_", Port, "[", integer_to_list(AddressWidth - 1), ":0])"]
         || Port <- ["rd_addr", "wr_addr"]
        ],
        [
            [", .", Port, "(", Stem, "_", Port, ")"]
         || Port <- ["rd_data", "wr_data", "rd_en", "wr_en", "wr_mask"]
        ],
        ");\n"
    ];
gather_instance(_, _) ->
    [].
