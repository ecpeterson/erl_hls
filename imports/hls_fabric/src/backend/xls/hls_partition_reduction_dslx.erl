-module(hls_partition_reduction_dslx).
-moduledoc """
hls_partition_dslx delegates source-fragment reduction wiring to this emitter. Checked lane and aggregate placement comes from hls_partition_reduction; execution comes from existing actor renderers.

Binds partition lanes to the existing aggregate-only actor executor without changing wire frames.
""".
%% Reduction support and channels.
-export([support/2, channels/2, aggregate_parameter/2]).
%% Reduction instances and publication wiring.
-export([spawn/2, collector/3, outbox_input/2]).

-doc "Emits typed opening/mux procs and one complete-set collector per selected local actor.".
-spec support(map(), map()) -> iolist().
support(Partition, #{actors := Actors, schedulers := Groups}) ->
    Modules = lists:usort([
        M
     || G = #{module := M} <- Groups, hls_partition_reduction:group(G, Partition)
    ]),
    [
        case Modules of
            [] -> [];
            _ -> "import hls_reduction_fragments;\n"
        end,
        [template(M) || M <- Modules],
        [
            collector_proc(A, Inputs)
         || A <- Actors,
            Inputs <- [hls_partition_reduction:inputs(A, Partition)],
            Inputs =/= []
        ]
    ].

%% The opening proc calls concrete actor callbacks; its polling mux is still emitted beside it.
-spec template(module()) -> binary().
template(Module) ->
    Path = filename:join([code:priv_dir(hls_fabric), "xls", "partition_reduction.x.in"]),
    {ok, Source} = file:read_file(Path),
    Name = atom_to_binary(Module),
    Typed = binary:replace(Source, <<"actor::">>, <<Name/binary, "::">>, [global]),
    lists:foldl(
        fun(Proc, Text) ->
            binary:replace(Text, Proc, <<Name/binary, "_", Proc/binary>>, [global])
        end,
        Typed,
        [<<"ReductionOpen">>, <<"ReductionMux">>]
    ).

%% Receive every contributor before invoking the public fold; failures therefore still drain the full population.
-spec collector_proc(map(), [map()]) -> iolist().
collector_proc(#{index := Id, module := Module}, Inputs) ->
    N = lists:sum([M || #{multiplicity := M} <- Inputs]),
    Members =
        [["frame_", n(I), ": chan<axis::Frame> in"] || I <- lists:seq(0, N - 1)] ++
            [
                "opened: chan<u1> in",
                ["aggregate: chan<", atom_to_list(Module), "::ReductionAggregateRequest> out"]
            ],
    Names = [["frame_", n(I)] || I <- lists:seq(0, N - 1)] ++ ["opened", "aggregate"],
    [
        "// Join a complete reduction window for one destination; no actor state is read.\n",
        "proc ReductionCollector",
        n(Id),
        "<SLOT: u32> {\n",
        [["  ", M, ";\n"] || M <- Members],
        "  // Inputs retain source order; the opening token belongs to SLOT.\n",
        "  config(",
        lists:join(", ", Members),
        ") { (",
        lists:join(", ", Names),
        ") }\n",
        "  // Window storage belongs to the bounded input channels.\n  init { () }\n",
        "  // Aggregates cannot overtake installation of the matching actor window.\n  next(state: ()) {\n",
        "    let (open_tok, _) = recv(join(), opened);\n",
        [
            ["    let (tok_", n(I), ", value_", n(I), ") = recv(join(), frame_", n(I), ");\n"]
         || I <- lists:seq(0, N - 1)
        ],
        "    let value = ",
        atom_to_list(Module),
        "::reduction_aggregate_batch<u32:",
        n(N),
        ">([",
        lists:join(", ", [["value_", n(I)] || I <- lists:seq(0, N - 1)]),
        "]);\n",
        "    let _sent = send(join(open_tok",
        [[", tok_", n(I)] || I <- lists:seq(0, N - 1)],
        "), aggregate, ",
        atom_to_list(Module),
        "::ReductionAggregateRequest { slot: SLOT, aggregate: value });\n",
        "    state\n  }\n}\n\n"
    ].

-doc "Declares per-actor opening tokens and aggregate receptacles for selected scheduler groups.".
-spec channels(map(), map()) -> iolist().
channels(Partition, #{schedulers := Groups}) ->
    [
        [
            "    let (",
            Stem,
            "_opened_p, ",
            Stem,
            "_opened_c) = chan<u1, u32:1>[u32:",
            n(N),
            "](\"",
            Stem,
            "_opened\");\n",
            "    let (",
            Stem,
            "_announced_p, ",
            Stem,
            "_announced_c) = chan<",
            M,
            "::ScheduledEffects, u32:0>(\"",
            Stem,
            "_announced\");\n",
            "    let (",
            Stem,
            "_aggregates_p, ",
            Stem,
            "_aggregates_c) = chan<",
            M,
            "::ReductionAggregateRequest, u32:1>[u32:",
            n(N),
            "](\"",
            Stem,
            "_aggregates\");\n",
            "    let (",
            Stem,
            "_aggregate_p, ",
            Stem,
            "_aggregate_c) = chan<",
            M,
            "::ReductionAggregateRequest, u32:1>(\"",
            Stem,
            "_aggregate\");\n"
        ]
     || G = #{stem := Stem, module_name := M, slot_count := N} <- Groups,
        hls_partition_reduction:group(G, Partition)
    ].

-doc "Connects independent opening notifications and completed aggregates to each selected scheduler.".
-spec spawn(map(), map()) -> iolist().
spawn(Partition, #{schedulers := Groups}) ->
    [
        [
            "    spawn ",
            M,
            "_ReductionOpen<u32:",
            n(N),
            ">(",
            Stem,
            "_egress_c, ",
            Stem,
            "_announced_p, ",
            Stem,
            "_opened_p);\n",
            "    spawn ",
            M,
            "_ReductionMux<u32:",
            n(N),
            ">(",
            Stem,
            "_aggregates_c, ",
            Stem,
            "_aggregate_p);\n"
        ]
     || G = #{stem := Stem, module_name := M, slot_count := N} <- Groups,
        hls_partition_reduction:group(G, Partition)
    ].

-doc "Connects local and remote contribution lanes to bounded fragments, bypassing the ordinary mailbox.".
-spec collector(map(), map(), map()) -> iolist().
collector(A = #{identity := Id, index := Index}, Partition, Local = #{schedulers := Groups}) ->
    Inputs = hls_partition_reduction:inputs(A, Partition),
    case Inputs of
        [] ->
            [];
        _ ->
            [{Stem, Slot}] = [
                {S, Slot}
             || #{stem := S, actors := Actors} <- Groups,
                #{identity := Candidate, slot := Slot} <- Actors,
                Candidate =:= Id
            ],
            [
                [fragment(L, Local) || L <- Inputs],
                "    spawn ReductionCollector",
                n(Index),
                "<u32:",
                n(Slot),
                ">(",
                lists:join(", ", [
                    fragment_input(L, I, Local)
                 || L = #{multiplicity := N} <- Inputs, I <- lists:seq(0, N - 1)
                ]),
                ", ",
                Stem,
                "_opened_c[u32:",
                n(Slot),
                "], ",
                Stem,
                "_aggregates_p[u32:",
                n(Slot),
                "]);\n"
            ]
    end.

%% Two slots per aliased prefix position retain the current and following windows independently.
-spec fragment(map(), map()) -> iolist().
fragment(#{multiplicity := 1}, _Local) ->
    [];
fragment(L = #{id := Id, multiplicity := N}, Local) ->
    Input = lane_input(L, Local),
    [
        "    let (fragment_",
        n(Id),
        "_p, fragment_",
        n(Id),
        "_c) = chan<axis::Frame, u32:2>[u32:",
        n(N),
        "](\"fragment_",
        n(Id),
        "\");\n",
        "    spawn hls_reduction_fragments::Split<u32:",
        n(N),
        ">(",
        Input,
        ", fragment_",
        n(Id),
        "_p);\n"
    ].

%% A single position uses its existing ordered lane, whose queue includes the removed slots.
-spec fragment_input(map(), non_neg_integer(), map()) -> iolist().
fragment_input(L = #{multiplicity := 1}, 0, Local) -> lane_input(L, Local);
fragment_input(#{id := Id}, Position, _Local) -> ["fragment_", n(Id), "_c[u32:", n(Position), "]"].

%% Locate the same source lane for direct collection and aliased splitting.
-spec lane_input(map(), map()) -> iolist().
lane_input(L = #{kind := remote}, Local) -> hls_partition_links:channel(Local, L, in);
lane_input(L, _Local) -> ["lane_", n(hls_partition_tile:lane_id(L)), "_c"].

-doc "Returns the batch endpoint after any opening-token announcement.".
-spec outbox_input(map(), map()) -> iolist().
outbox_input(G = #{stem := Stem}, Partition) ->
    [
        Stem,
        case hls_partition_reduction:group(G, Partition) of
            true -> "_announced_c";
            false -> "_egress_c"
        end
    ].

-doc "Returns the optional aggregate input argument of the compiled shared-service artifact.".
-spec aggregate_parameter(map(), map()) -> iolist().
aggregate_parameter(G = #{stem := Stem}, Partition) ->
    case hls_partition_reduction:group(G, Partition) of
        true -> [", ", Stem, "_aggregate_c"];
        false -> []
    end.

%% Render bounded elaboration constants.
-spec n(non_neg_integer()) -> string().
n(N) -> integer_to_list(N).
