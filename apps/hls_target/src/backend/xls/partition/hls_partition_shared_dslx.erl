-module(hls_partition_shared_dslx).
-moduledoc """
hls_partition_dslx uses this emitter for RAM-backed groups. It combines checked local placement with scheduler channels, ingress selection and per-actor outbox wiring.

RAM scheduler wiring for private partitions; public code owns execution and independent actor outboxes.
""".
%% Scheduler support and external channel interface.
-export([support/1, parameters/1, names/1]).
%% Scheduler channel and instance composition.
-export([channels/2, spawn/2]).
%% Ingress and egress wiring.
-export([input/3, ingress_support/3, egress/2]).

-doc "Emits startup adapters and independent outboxes for each actor module.".
-spec support(map()) -> iolist().
support(Local = #{schedulers := Groups}) ->
    [
        [xls_actor_outbox_dslx:emit(M) || M <- lists:usort([M || #{module := M} <- Groups])],
        [startup(G, Local) || G <- Groups],
        hls_partition_outbox:support(Local)
    ].

-doc "Returns external RAM and passive mailbox-observation channel declarations.".
-spec parameters(map()) -> [iodata()].
parameters(#{schedulers := Groups}) ->
    lists:append([
        xls_scheduler_ram_dslx:parameters([Stem, "_"], [Module, "::"]) ++
            [[Stem, "_mailbox_debug_out: chan<u24[u32:", n(Slots), "]> out"]]
     || #{stem := Stem, module_name := Module, slot_count := Slots} <- Groups
    ]).

-doc "Returns RAM and observation endpoints in the same order as parameters/1.".
-spec names(map()) -> [iodata()].
names(#{schedulers := Groups}) ->
    lists:append([
        xls_scheduler_ram_dslx:names([Stem, "_"]) ++ [[Stem, "_mailbox_debug_out"]]
     || #{stem := Stem} <- Groups
    ]).

-doc "Declares separate request and return-credit receptacles for each actor.".
-spec channels(map(), map()) -> iolist().
channels(_, #{schedulers := Groups}) ->
    [
        [
            "    let (",
            Stem,
            "_requests_p, ",
            Stem,
            "_requests_c) = chan<",
            Module,
            "::ScheduledRequest, CHANNEL_DEPTH>[u32:",
            n(2 * Slots),
            "](\"",
            Stem,
            "_requests\");\n",
            "    let (",
            Stem,
            "_startup_p, ",
            Stem,
            "_startup_c) = chan<",
            Module,
            "::ScheduledRequest, CHANNEL_DEPTH>(\"",
            Stem,
            "_startup\");\n",
            "    let (",
            Stem,
            "_egress_p, ",
            Stem,
            "_egress_c) = chan<",
            Module,
            "::ScheduledEffects, CHANNEL_DEPTH>(\"",
            Stem,
            "_egress\");\n",
            "    let (",
            Stem,
            "_credits_p, ",
            Stem,
            "_credits_c) = chan<",
            Module,
            "::ScheduledRequest, u32:0>[u32:",
            n(Slots),
            "](\"",
            Stem,
            "_credits\");\n",
            "    let (",
            Stem,
            "_effects_p, ",
            Stem,
            "_effects_c) = chan<",
            Module,
            "::Egress, u32:0>[u32:",
            n(Slots),
            "](\"",
            Stem,
            "_effects\");\n"
        ]
     || #{stem := Stem, module_name := Module, slot_count := Slots} <- Groups
    ].

-doc "Instantiates RAM executors and per-actor outboxes; no remote grants are needed.".
-spec spawn(map(), map()) -> iolist().
spawn(Partition, Local = #{schedulers := Groups}) ->
    [spawn_group(G, Partition, Local) || G <- Groups].

-doc "Returns the independent output endpoint consumed by this actor's ordinary router.".
-spec egress(map(), map()) -> iolist().
egress(A, Local) ->
    {#{stem := Stem}, Slot} = binding(A, Local),
    [Stem, "_effects_c[u32:", n(Slot), "]"].

%% Match one logical identity to its unique scheduler and dense local slot.
-spec binding(map(), map()) -> {map(), non_neg_integer()}.
binding(#{identity := Id}, #{schedulers := Groups}) ->
    [Bound] = [
        {G, Slot}
     || G = #{actors := Actors} <- Groups,
        #{identity := A, slot := Slot} <- Actors,
        A =:= Id
    ],
    Bound.

-doc "Connects the actor's final one or two ingress streams to its scheduled-request queue.".
-spec input(map(), map(), [iodata(), ...]) -> iolist().
input(A = #{index := Id}, Local, Inputs) ->
    {#{stem := Stem}, Slot} = binding(A, Local),
    [
        "    spawn SchedulerIngress",
        n(Id),
        "<u32:",
        n(Slot),
        ">(",
        lists:join(", ", Inputs),
        ", ",
        Stem,
        "_requests_p[u32:",
        n(Slot),
        "]);\n"
    ].

-doc "Emits a request wrapper which alternates between at most two ordered producer lanes.".
-spec ingress_support(map(), map(), [iodata()]) -> iodata().
ingress_support(_Actor, _Local, []) ->
    [];
ingress_support(A = #{index := Id}, Local, Inputs) ->
    {#{module_name := Module}, _} = binding(A, Local),
    Count = min(2, length(Inputs)),
    Names = [["frame_", n(I)] || I <- lists:seq(0, Count - 1)],
    Parameters = [[Name, ": chan<axis::Frame> in"] || Name <- Names],
    Path = filename:join([code:priv_dir(hls_target), "xls", "scheduler_ingress.x.in"]),
    {ok, Template} = file:read_file(Path),
    Replacements = [
        {<<"@ACTOR@">>, n(Id)},
        {<<"@MODULE@">>, Module},
        {<<"@NAMES@">>, lists:join(", ", Names)},
        {<<"@PARAMETERS@">>, lists:join(", ", Parameters)},
        {<<"@FIELDS@">>, [["  ", Field, ";\n"] || Field <- Parameters]},
        {<<"@RECEIVES@">>, [ingress_receive(I) || I <- lists:seq(0, Count - 1)]},
        {<<"@COUNT@">>, n(Count)}
    ],
    lists:foldl(
        fun({Key, Value}, Text) ->
            binary:replace(Text, Key, iolist_to_binary(Value), [global])
        end,
        Template,
        Replacements
    ).

%% Match the two-way merger's alternating grants; a lone input is always eligible.
-spec ingress_receive(non_neg_integer()) -> iolist().
ingress_receive(I) ->
    [
        "    let attempt = if u32:@COUNT@ == u32:1 { true } else { prefer_right == u1:",
        n(I),
        " };\n",
        "    let (tok, frame, valid) = recv_if_non_blocking(selected.0, frame_",
        n(I),
        ", attempt, zero!<axis::Frame>());\n",
        "    let selected = (tok, selected.1 || valid, if valid { frame } else { selected.2 });\n"
    ].

%% Startup is preloaded by SharedService before any ordinary producer becomes eligible.
-spec startup(map(), map()) -> iolist().
startup(#{index := I, module_name := Module, actors := Actors}, Local = #{tile := true}) ->
    Items = [{Slot, F} || #{slot := Slot, startup := Frames} <- Actors, F <- Frames],
    Count = length(Items),
    FrameBits = hls_frame_layout:frame_bits(
        maps:get(frame_layout, Local, hls_frame_layout:default())
    ),
    [
        "proc SchedulerStartup",
        n(I),
        " {\n",
        "  values: chan<bits[",
        n(FrameBits * Count),
        "]> in;\n",
        "  request_out: chan<",
        Module,
        "::ScheduledRequest> out;\n",
        "  config(values: chan<bits[",
        n(FrameBits * Count),
        "]> in, request_out: chan<",
        Module,
        "::ScheduledRequest> out) { (values, request_out) }\n",
        "  init { u32:0 }\n  next(index: u32) {\n",
        "    let starting = index < u32:",
        n(Count),
        ";\n",
        "    let (tok, data) = recv_if(join(), values, starting, bits[",
        n(FrameBits * Count),
        "]:0);\n",
        "    let slot = match index {\n",
        [
            ["      u32:", n(J), " => u32:", n(Slot), ",\n"]
         || {J, {Slot, _}} <- lists:enumerate(0, Items)
        ],
        "      _ => u32:0,\n    };\n",
        "    let request = ",
        Module,
        "::ScheduledRequest { slot, credit: u1:0,\n",
        "      frame: axis::frame_from_bits(data[index*axis::FRAME_BITS+:bits[axis::FRAME_BITS]]) };\n",
        "    let _done = send_if(tok, request_out, starting, request);\n",
        "    if starting { index + u32:1 } else { index }\n  }\n}\n\n"
    ];
startup(#{index := I, module_name := Module, actors := Actors}, _) ->
    Items = [{Slot, F} || #{slot := Slot, startup := Frames} <- Actors, F <- Frames],
    [
        "proc SchedulerStartup",
        n(I),
        " {\n  request_out: chan<",
        Module,
        "::ScheduledRequest> out;\n",
        "  config(request_out: chan<",
        Module,
        "::ScheduledRequest> out) { (request_out,) }\n",
        "  init { u32:0 }\n  next(index: u32) {\n    let starting = index < u32:",
        n(length(Items)),
        ";\n",
        "    let request = match index {\n",
        [
            [
                "      u32:",
                n(J),
                " => ",
                Module,
                "::ScheduledRequest { slot: u32:",
                n(Slot),
                ", frame: ",
                frame(F),
                ", credit: u1:0 },\n"
            ]
         || {J, {Slot, F}} <- lists:enumerate(0, Items)
        ],
        "      _ => zero!<",
        Module,
        "::ScheduledRequest>(),\n    };\n",
        "    let _done = send_if(join(), request_out, starting, request);\n",
        "    if starting { index + u32:1 } else { index }\n  }\n}\n\n"
    ].

%% Render the same selected prepacked startup ABI as the direct partition.
-spec frame(map()) -> iolist().
frame(#{selector := Tag, payload := Payload}) ->
    Value =
        case Payload of
            <<>> -> "bits[axis::PAYLOAD_BITS]:0";
            _ -> [xls_nums:packed_unsigned_literal(Payload), " as bits[axis::PAYLOAD_BITS]"]
        end,
    [
        "axis::Frame { header: axis::Header { op: u8:",
        n(Tag),
        ", payload_words: u8:",
        n(bit_size(Payload) div 32),
        ", ..zero!<axis::Header>() }, payload: ",
        Value,
        " }"
    ].

%% The scheduler reserves one complete batch before issue. Each return identifies its actor.
-spec spawn_group(map(), map(), map()) -> iolist().
spawn_group(
    G = #{
        index := I,
        stem := Stem,
        module_name := Module,
        slot_count := Slots,
        actors := Actors
    },
    Partition,
    Local
) ->
    Count = lists:sum([length(Frames) || #{startup := Frames} <- Actors]),
    [
        "    spawn SchedulerStartup",
        n(I),
        "(",
        case Local of
            #{tile := true} -> ["tile_startup_", n(I), ", "];
            _ -> []
        end,
        Stem,
        "_startup_p);\n",
        "    spawn ",
        Module,
        "::SharedService<u32:",
        n(Slots),
        ", u32:",
        n(2 * Slots),
        ", u32:",
        n(Count),
        ", u32:",
        n(I),
        ", true>(",
        Stem,
        "_requests_c, ",
        Stem,
        "_startup_c, ",
        Stem,
        "_egress_p, ",
        lists:join(", ", xls_scheduler_ram_dslx:names([Stem, "_"])),
        hls_partition_reduction_dslx:aggregate_parameter(G, Partition),
        ", ",
        Stem,
        "_mailbox_debug_out);\n",
        [
            [
                "    spawn mailbox::RequestRelay(",
                Stem,
                "_credits_c[u32:",
                n(Slot),
                "], ",
                Stem,
                "_requests_p[u32:",
                n(Slots + Slot),
                "]);\n"
            ]
         || Slot <- lists:seq(0, Slots - 1)
        ],
        hls_partition_outbox:spawn(G, Partition, Local)
    ].

%% Render bounded elaboration constants.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
