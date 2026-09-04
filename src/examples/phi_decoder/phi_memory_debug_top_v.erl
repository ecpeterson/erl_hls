%%%% phi_memory_debug_top_v
%%%%
%%%% Verilog boundary wrapper for one generated phi-memory scheduler plan.

-module(phi_memory_debug_top_v).
-moduledoc """
Renders the Verilog wrapper which connects every shared scheduler RAM port to
one simple 1R1W memory and attaches the passive debug monitor.

The fixed shell lives in `priv/rtl/phi_memory_debug_top.template.v`; only the
scheduler-dependent wires, gateway ports, and RAM instances are generated.
""".

-export([to_verilog/0, to_verilog/1]).

-doc "Renders the checked wrapper for the default scheduler profile.".
-spec to_verilog() -> binary().
to_verilog() ->
    to_verilog(2).

-doc "Renders a wrapper for one phi scheduler profile.".
-spec to_verilog(1 | 2 | {phi_shards, pos_integer()}) -> binary().
to_verilog(Profile) ->
    #{groups := Groups} = phi_noise_topology_dslx:scheduler_plan(Profile),
    Schedulers = [scheduler(Index, Group)
        || {Index, Group} <- lists:enumerate(0, Groups)],
    Template = template(),
    Replacements = [
        {<<"@SCHEDULER_WIRES@">>, iolist_to_binary([
            scheduler_wires(Scheduler) || Scheduler <- Schedulers
        ])},
        {<<"@APPLICATION_RAM_PORTS@">>, iolist_to_binary([
            application_ports(Scheduler) || Scheduler <- Schedulers
        ])},
        {<<"@SCHEDULER_RAMS@">>, iolist_to_binary([
            scheduler_rams(Scheduler) || Scheduler <- Schedulers
        ])}
    ],
    lists:foldl(
        fun({Pattern, Replacement}, Source) ->
            binary:replace(Source, Pattern, Replacement, [global])
        end,
        Template,
        Replacements
    ).

scheduler(Index, Group) ->
    StateWidth = xls_statem_codegen:shared_machine_width(
        maps:get(width, maps:get(state, Group))
    ),
    SlotCount = maps:get(slot_count, Group),
    MailboxCapacity = maps:get(mailbox_capacity, Group),
    #{
        index => Index,
        state_width => StateWidth,
        state_address_width => address_width(SlotCount),
        mailbox_width => 128,
        mailbox_address_width => address_width(SlotCount * MailboxCapacity)
    }.

scheduler_wires(#{
    index := Index,
    state_width := StateWidth,
    mailbox_width := MailboxWidth
}) ->
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
        "_mailbox_rd_data;\n\n"
    ].

application_ports(#{index := Index}) ->
    Stem = stem(Index),
    lists:append([
        [",\n        .", Stem, "_", Port, "(", Stem, "_", Port, ")"]
        || Port <- ram_ports()
    ]).

ram_ports() ->
    [
        "state_rd_addr", "state_wr_addr", "state_wr_data",
        "state_wr_en", "state_rd_en", "state_rd_data",
        "mailbox_rd_addr", "mailbox_wr_addr", "mailbox_wr_data",
        "mailbox_wr_en", "mailbox_rd_en", "mailbox_rd_data"
    ].

scheduler_rams(#{
    index := Index,
    state_width := StateWidth,
    state_address_width := StateAddressWidth,
    mailbox_width := MailboxWidth,
    mailbox_address_width := MailboxAddressWidth
}) ->
    Stem = stem(Index),
    [
        ram(Stem, "state", StateWidth, StateAddressWidth),
        ram(Stem, "mailbox", MailboxWidth, MailboxAddressWidth)
    ].

ram(Stem, Kind, Width, AddressWidth) ->
    [
        "    hls_1r1w_ram #(.WIDTH(", integer_to_list(Width),
        "), .ADDRESS_WIDTH(", integer_to_list(AddressWidth), ")) ",
        Stem, "_", Kind, " (\n",
        "        .clk(aclk),\n",
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

template() ->
    Priv = code:priv_dir(erl_hls),
    Path = filename:join([Priv, "rtl", "phi_memory_debug_top.template.v"]),
    {ok, Template} = file:read_file(Path),
    Template.
