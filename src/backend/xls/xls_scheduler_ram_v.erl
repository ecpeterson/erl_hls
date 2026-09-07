%%%% xls_scheduler_ram_v
%%%%
%%%% Verilog plumbing for the external RAMs of a shared-scheduler plan.

-module(xls_scheduler_ram_v).
-moduledoc """
Renders the repetitive Verilog boundary around scheduler-owned 1R1W RAMs.

The generated XLS module exposes 32-bit addresses and one pair of state and
mailbox ports per scheduler.  A scheduler whose actors use a reduction also
exposes a separate reduction-state pair.  This helper derives the actual
widths and depths from a normalized scheduler plan, then renders declarations,
application port bindings, and `hls_1r1w_ram` instances for a surrounding
Verilog shell.
""".

-export([bindings/1, wires/1, application_ports/1, instances/2]).

-doc "Derives indexed RAM bindings from a normalized scheduler plan.".
-spec bindings(hls_scheduler_plan:plan()) -> [map()].
bindings(#{groups := Groups}) ->
    [binding(Index, Group) || {Index, Group} <- lists:enumerate(0, Groups)].

-doc "Declares every wire needed between an XLS application and its RAMs.".
-spec wires([map()]) -> iolist().
wires(Bindings) ->
    [binding_wires(Binding) || Binding <- Bindings].

-doc "Connects every scheduler RAM port on an XLS application instance.".
-spec application_ports([map()]) -> iolist().
application_ports(Bindings) ->
    [binding_application_ports(Binding) || Binding <- Bindings].

-doc "Instantiates the state, mailbox, and optional reduction RAMs.".
-spec instances([map()], iodata()) -> iolist().
instances(Bindings, Clock) ->
    [binding_instances(Binding, Clock) || Binding <- Bindings].

binding(Index, Group) ->
    StateWidth = xls_statem_codegen:shared_machine_width(
        maps:get(width, maps:get(state, Group))
    ),
    SlotCount = maps:get(slot_count, Group),
    MailboxCapacity = maps:get(mailbox_capacity, Group),
    Binding = #{
        index => Index,
        state_width => StateWidth,
        state_address_width => address_width(SlotCount),
        mailbox_width => 128,
        mailbox_address_width => address_width(SlotCount * MailboxCapacity)
    },
    case maps:get(reduction_storage_width, Group, 0) of
        0 -> Binding;
        ReductionWidth -> Binding#{
            reduction_width => ReductionWidth,
            reduction_address_width => address_width(SlotCount)
        }
    end.

binding_wires(#{
    index := Index,
    state_width := StateWidth,
    mailbox_width := MailboxWidth
} = Binding) ->
    Stem = stem(Index),
    [
        "    wire [31:0] ", Stem, "_state_rd_addr;\n",
        "    wire [31:0] ", Stem, "_state_wr_addr;\n",
        "    wire [", integer_to_list(StateWidth - 1), ":0] ", Stem,
        "_state_wr_data;\n",
        "    wire ", Stem, "_state_wr_en;\n",
        "    wire ", Stem, "_state_rd_en;\n",
        "    wire [", integer_to_list(StateWidth - 1), ":0] ", Stem,
        "_state_rd_data;\n",
        "    wire [31:0] ", Stem, "_mailbox_rd_addr;\n",
        "    wire [31:0] ", Stem, "_mailbox_wr_addr;\n",
        "    wire [", integer_to_list(MailboxWidth - 1), ":0] ", Stem,
        "_mailbox_wr_data;\n",
        "    wire ", Stem, "_mailbox_wr_en;\n",
        "    wire ", Stem, "_mailbox_rd_en;\n",
        "    wire [", integer_to_list(MailboxWidth - 1), ":0] ", Stem,
        "_mailbox_rd_data;\n",
        reduction_wires(Binding, Stem),
        "\n"
    ].

reduction_wires(#{reduction_width := Width}, Stem) ->
    [
        "    wire [31:0] ", Stem, "_reduction_rd_addr;\n",
        "    wire [31:0] ", Stem, "_reduction_wr_addr;\n",
        "    wire [", integer_to_list(Width - 1), ":0] ", Stem,
        "_reduction_wr_data;\n",
        "    wire ", Stem, "_reduction_wr_en;\n",
        "    wire ", Stem, "_reduction_rd_en;\n",
        "    wire [", integer_to_list(Width - 1), ":0] ", Stem,
        "_reduction_rd_data;\n"
    ];
reduction_wires(_Binding, _Stem) ->
    [].

binding_application_ports(#{index := Index} = Binding) ->
    Stem = stem(Index),
    lists:append([
        [",\n        .", Stem, "_", Port, "(", Stem, "_", Port, ")"]
        || Port <- binding_ram_ports(Binding)
    ]).

binding_ram_ports(Binding) ->
    ram_ports() ++ reduction_ram_ports(Binding).

ram_ports() ->
    [
        "state_rd_addr", "state_wr_addr", "state_wr_data",
        "state_wr_en", "state_rd_en", "state_rd_data",
        "mailbox_rd_addr", "mailbox_wr_addr", "mailbox_wr_data",
        "mailbox_wr_en", "mailbox_rd_en", "mailbox_rd_data"
    ].

reduction_ram_ports(#{reduction_width := _Width}) ->
    [
        "reduction_rd_addr", "reduction_wr_addr", "reduction_wr_data",
        "reduction_wr_en", "reduction_rd_en", "reduction_rd_data"
    ];
reduction_ram_ports(_Binding) ->
    [].

binding_instances(#{
    index := Index,
    state_width := StateWidth,
    state_address_width := StateAddressWidth,
    mailbox_width := MailboxWidth,
    mailbox_address_width := MailboxAddressWidth
} = Binding, Clock) ->
    Stem = stem(Index),
    [
        ram(Stem, "state", StateWidth, StateAddressWidth, Clock),
        ram(Stem, "mailbox", MailboxWidth, MailboxAddressWidth, Clock),
        reduction_instance(Binding, Stem, Clock)
    ].

reduction_instance(#{
    reduction_width := Width,
    reduction_address_width := AddressWidth
}, Stem, Clock) ->
    ram(Stem, "reduction", Width, AddressWidth, Clock);
reduction_instance(_Binding, _Stem, _Clock) ->
    [].

ram(Stem, Kind, Width, AddressWidth, Clock) ->
    [
        "    hls_1r1w_ram #(.WIDTH(", integer_to_list(Width),
        "), .ADDRESS_WIDTH(", integer_to_list(AddressWidth), ")) ",
        Stem, "_", Kind, " (\n",
        "        .clk(", Clock, "),\n",
        "        .rd_addr(", Stem, "_", Kind, "_rd_addr[",
        integer_to_list(AddressWidth - 1), ":0]),\n",
        "        .wr_addr(", Stem, "_", Kind, "_wr_addr[",
        integer_to_list(AddressWidth - 1), ":0]),\n",
        "        .wr_data(", Stem, "_", Kind, "_wr_data),\n",
        "        .wr_en(", Stem, "_", Kind, "_wr_en),\n",
        "        .rd_en(", Stem, "_", Kind, "_rd_en),\n",
        "        .rd_data(", Stem, "_", Kind, "_rd_data)\n",
        "    );\n\n"
    ].

address_width(Count) when Count > 0 ->
    address_width(Count - 1, 0).

address_width(0, 0) -> 1;
address_width(0, Width) -> Width;
address_width(Value, Width) -> address_width(Value bsr 1, Width + 1).

stem(Index) -> ["scheduler_", integer_to_list(Index)].
