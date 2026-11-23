-module(hls_partition_outbox).
-moduledoc """
Partition DSLX renderers delegate actor publication wiring here. It consumes the checked reduction/lane plan and emits ordinary or independent outbox connections.

Independent publication of proved reduction prefixes; ordinary effects retain serial routing.
""".
%% Publication lane selection.
-export([lanes/2, ordinary/2]).
%% DSLX outbox support and instances.
-export([support/1, spawn/3]).

-doc "Returns the source's proved contribution lanes. Other actors have no parallel outputs.".
-spec lanes(map(), map()) -> [map()].
lanes(A = #{identity := Id}, Local = #{lanes := Lanes}) ->
    Inputs = hls_partition_reduction:inputs(A, Local),
    Ports = lists:usort(lists:append([Ps || #{ports := Ps} <- Inputs])),
    [
        L
     || L = #{source := S, ports := Ps} <- Lanes,
        S =:= Id,
        Ps =/= [],
        lists:all(fun(P) -> lists:member(P, Ports) end, Ps)
    ].

-doc "Returns source lanes still served by the ordinary effect router.".
-spec ordinary(map(), map()) -> [map()].
ordinary(A = #{identity := Id}, Local = #{lanes := Lanes}) ->
    Captured = [I || #{id := I} <- lanes(A, Local)],
    [L || L = #{source := S, id := I} <- Lanes, S =:= Id, not lists:member(I, Captured)].

-doc "Emits concrete drainers for actors whose source-fragment prefix has a global proof.".
-spec support(map()) -> iolist().
support(Local = #{schedulers := Groups}) ->
    [
        drainer(G, A, Lanes)
     || G = #{actors := Actors} <- Groups,
        A <- Actors,
        Lanes <- [lanes(A, Local)],
        Lanes =/= []
    ].

%% Substitute only elaboration constants and typed port declarations into the static proc.
-spec drainer(map(), map(), [map(), ...]) -> binary().
drainer(G, A = #{module := M, slot := Slot}, Lanes) ->
    Module = atom_to_list(M),
    Count = lists:sum([length(Ps) || #{ports := Ps} <- Lanes]),
    Names = [fragment(L) || L <- Lanes],
    Parameters = [[F, ": chan<", Module, "::Egress> out"] || F <- Names],
    {ok, Template} = file:read_file(
        filename:join([code:priv_dir(hls_lowering), "xls", "parallel_outbox.x.in"])
    ),
    Replacements = [
        {"@NAME@", name(G, A)},
        {"@MODULE@", Module},
        {"@SLOT@", n(Slot)},
        {"@COUNT@", n(Count)},
        {"@FIELDS@", [["  ", P, ";\n"] || P <- Parameters]},
        {"@PARAMETERS@", lists:join(", ", Parameters)},
        {"@NAMES@", lists:join(", ", Names)},
        {"@SCAN@", [scan_lane(Module, L, Count) || L <- Lanes]},
        {"@LIMIT@", [
            [
                "    let limit = if selected_",
                fragment(L),
                ".2 < limit { selected_",
                fragment(L),
                ".2 } else { limit };\n"
            ]
         || L <- Lanes
        ]},
        {"@SEND@", [send_lane(L) || L <- Lanes]}
    ],
    lists:foldl(
        fun({Key, Value}, Text) ->
            binary:replace(Text, list_to_binary(Key), iolist_to_binary(Value), [global])
        end,
        Template,
        Replacements
    ).

%% Find the first two remaining effects for each lane. The earliest second
%% occurrence ends a contiguous source-order segment, avoiding later-effect waits.
-spec scan_lane(string(), map(), pos_integer()) -> iolist().
scan_lane(Module, L = #{ports := Ports}, Count) ->
    F = fragment(L),
    [
        "    let selected_",
        F,
        " = unroll_for! (position, selected): (u8, (",
        Module,
        "::Egress, u8, u8)) in u8:0..u8:",
        n(Count),
        " {\n",
        "      let (candidate, valid, _) = ",
        Module,
        "::scheduled_effect(batch, position);\n",
        "      let port_matches = valid && position >= index && match candidate.port {\n",
        [
            ["        ", Module, "::OutputPort::", xls_names:enum_member(P), " => true,\n"]
         || P <- Ports
        ],
        "        _ => false,\n      };\n",
        "      if !port_matches { selected }\n",
        "      else if selected.1 == u8:",
        n(Count),
        " { (candidate, position, selected.2) }\n",
        "      else if selected.2 == u8:",
        n(Count),
        " { (selected.0, selected.1, position) }\n",
        "      else { selected }\n",
        "    }((zero!<",
        Module,
        "::Egress>(), u8:",
        n(Count),
        ", u8:",
        n(Count),
        "));\n"
    ].

%% Every send in this segment may finish independently; none can hold an earlier unsent effect.
-spec send_lane(map()) -> iolist().
send_lane(L) ->
    F = fragment(L),
    [
        "    let sent_",
        F,
        " = send_if(tok, ",
        F,
        ", active && !retiring && prefix && selected_",
        F,
        ".1 < limit, selected_",
        F,
        ".0);\n"
    ].

-doc "Connects independent actor outboxes, using parallel drains only where proved safe.".
-spec spawn(map(), map(), map()) -> iolist().
spawn(
    G = #{stem := Stem, module := M, module_name := Module, slot_count := Slots, actors := Actors},
    Partition,
    Local
) ->
    case lists:any(fun(A) -> lanes(A, Local) =/= [] end, Actors) of
        false ->
            [
                "    spawn ",
                xls_actor_outbox_dslx:name(M),
                "<u32:",
                n(Slots),
                ">(",
                hls_partition_reduction_dslx:outbox_input(G, Partition),
                ", ",
                Stem,
                "_effects_p, ",
                Stem,
                "_credits_p);\n"
            ];
        true ->
            [
                "    let (",
                Stem,
                "_batches_p, ",
                Stem,
                "_batches_c) = chan<",
                Module,
                "::ScheduledEffects, u32:1>[u32:",
                n(Slots),
                "](\"",
                Stem,
                "_outboxes\");\n",
                "    spawn ",
                Module,
                "_ActorOutboxDispatch<u32:",
                n(Slots),
                ">(",
                hls_partition_reduction_dslx:outbox_input(G, Partition),
                ", ",
                Stem,
                "_batches_p);\n",
                [spawn_actor(G, A, lanes(A, Local), Local) || A <- Actors]
            ]
    end.

%% All lanes retain their existing queues and capacities; only their producer changes.
-spec spawn_actor(map(), map(), [map()], map()) -> iolist().
spawn_actor(#{stem := Stem, module_name := M}, #{slot := Slot}, [], _) ->
    [
        "    spawn ",
        M,
        "_ActorOutboxDrain<u32:",
        n(Slot),
        ">(",
        Stem,
        "_batches_c[u32:",
        n(Slot),
        "], ",
        Stem,
        "_effects_p[u32:",
        n(Slot),
        "], ",
        Stem,
        "_credits_p[u32:",
        n(Slot),
        "]);\n"
    ];
spawn_actor(G = #{stem := Stem, module_name := M}, A = #{slot := Slot}, Lanes, Local) ->
    Name = name(G, A),
    [
        [
            begin
                F = [Name, "_", fragment(L)],
                [
                    "    let (",
                    F,
                    "_p, ",
                    F,
                    "_c) = chan<",
                    M,
                    "::Egress, u32:0>(\"",
                    F,
                    "\");\n",
                    "    spawn ",
                    Name,
                    "_ReductionFrame(",
                    F,
                    "_c, ",
                    lane_output(L, Local),
                    ");\n"
                ]
            end
         || L <- Lanes
        ],
        "    spawn ",
        Name,
        "(",
        Stem,
        "_batches_c[u32:",
        n(Slot),
        "], ",
        Stem,
        "_effects_p[u32:",
        n(Slot),
        "], ",
        Stem,
        "_credits_p[u32:",
        n(Slot),
        "]",
        [[", ", Name, "_", fragment(L), "_p"] || L <- Lanes],
        ");\n"
    ].

%% Use the same source-local lane bindings as the ordinary router.
-spec lane_output(map(), map()) -> iolist().
lane_output(L = #{kind := remote}, Local) -> hls_partition_links:channel(Local, L, out);
lane_output(L, _) -> ["lane_", n(hls_partition_tile:lane_id(L)), "_p"].

%% Stable physical bank/slot names let passive profiling identify concurrent publications.
-spec name(map(), map()) -> iolist().
name(#{index := Bank}, #{module := M, slot := Slot}) ->
    [atom_to_list(M), "_ParallelActorOutboxDrainB", n(Bank), "S", n(Slot)].

%% Retain a distinct effect-valued port at each lane's publication boundary.
-spec fragment(map()) -> iolist().
fragment(L) -> ["fragment_", n(hls_partition_tile:lane_id(L))].

%% Render bounded elaboration constants.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
