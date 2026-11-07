-module(xls_protocol_spacetime).
-moduledoc "Binds passive source-protocol observations to an exact XLS RTL build. Source callsite positions distinguish committed receiver work from preview evaluation. This trusted generated-code adapter emits no hardware and does not infer causal inputs or decode narrowed state.".

%% Observation manifest and simulator table.
-export([plan/4, tsv/1, observation_digest/1]).
-export_type([plan/0, signal/0]).

-doc "One exact module-local signal and its intended observation role. actor=null denotes shared state or transport. Paths use the protocol application's VPI top hierarchy; the recorder must verify every path before simulation.".
-type signal() :: #{
    id := binary(),
    name := binary(),
    path := binary(),
    width := pos_integer(),
    actor := non_neg_integer() | null,
    meaning := binary(),
    evidence := binary()
}.
-doc "Build-bound passive taps, physical register update expressions and explicit unsupported semantic requests. Register expressions are generated Verilog, not commands or a portable IR.".
-type plan() :: #{
    schema := 1,
    signals := [signal()],
    actors := [map()],
    registers := [map()],
    state := [map()],
    unsupported := [map()],
    inputs := map()
}.

-doc "Reads the frozen source bundle, raw/optimized XLS IR and exact boundary RTL. Requires the generated single-stage source-protocol boundary interface. Missing/ambiguous required controls are retained as unsupported; malformed declarations or state structure reject. No filename suffix is accepted as semantic evidence by itself.".
-spec plan(file:filename(), file:filename(), file:filename(), file:filename()) -> plan().
plan(Source, RawFile, OptFile, RtlFile) ->
    SourceBuild = read(filename:join(Source, "source-build.json")),
    SourceFiles = verified_source(Source, SourceBuild),
    Raw = read(RawFile),
    Opt = read(OptFile),
    Rtl = read(RtlFile),
    Network = json(maps:get(<<"network/manifest.json">>, SourceFiles)),
    true = maps:get(<<"arithmetic">>, Network) =:= [],
    Count = maps:get(<<"actors">>, Network),
    Boundary = maps:get(<<"boundary/boundary.x">>, SourceFiles),
    CommittedLine = unique_line(Boundary, <<"let step = network::tick">>),
    Files = file_numbers(Opt),
    BoundaryNumber = file_number(Files, <<"boundary/boundary.x">>),
    Nodes = ir_nodes(Opt),
    Declarations = declarations(Rtl),
    Context = #{
        files => Files,
        nodes => Nodes,
        declarations => Declarations,
        source_files => SourceFiles,
        committed => {BoundaryNumber, CommittedLine}
    },
    Actors = [actor(I, Context) || I <- lists:seq(0, Count - 1)],
    Registers = registers(Rtl, Declarations),
    RegisterSignals = lists:append([register_signals(R, Declarations) || R <- Registers]),
    ControlSignals = lists:append([maps:get(signals, A) || A <- Actors]),
    Controls = [
        declared_signal(<<"p0_stage_done">>, <<"stage_advance">>, Declarations),
        declared_signal(<<"input_reset">>, <<"reset">>, Declarations)
    ],
    Signals = unique_signals(RegisterSignals ++ ControlSignals ++ Controls),
    Leaves = state_leaves(Raw),
    #{
        schema => 1,
        signals => Signals,
        actors => [maps:remove(signals, A) || A <- Actors],
        registers => Registers,
        state => [
            state_leaf(I, Path, W, Registers)
         || {I, {Path, W}} <- lists:enumerate(0, Leaves)
        ],
        unsupported => lists:append([maps:get(unsupported, A) || A <- Actors]),
        inputs => #{
            raw_ir => digest(Raw),
            optimized_ir => digest(Opt),
            rtl => digest(Rtl),
            source_build => digest(SourceBuild)
        }
    }.

-doc "Hashes the complete observation plan using deterministic Erlang external-term encoding. Equal plans keep this identity across construction order, persistence and fresh processes on the pinned OTP toolchain. Keep exact file hashes separately; a plan identity is not the hash of an arbitrary ETF serialization and is not a cross-OTP encoding promise.".
-spec observation_digest(plan()) -> binary().
observation_digest(Plan) ->
    digest(term_to_binary(Plan, [deterministic])).

%% Verify every listed input once and interpret those same bytes, avoiding later rereads.
-spec verified_source(file:filename(), binary()) -> #{binary() => binary()}.
verified_source(Source, Manifest) ->
    #{<<"inputs">> := Inputs} = json(Manifest),
    true = is_list(Inputs) andalso Inputs =/= [],
    lists:foldl(
        fun(#{<<"file">> := Path, <<"sha256">> := Expected}, Files) ->
            true = filename:pathtype(Path) =:= relative,
            false = lists:member(<<"..">>, filename:split(Path)),
            false = maps:is_key(Path, Files),
            Bytes = read(filename:join(Source, Path)),
            Actual = digest(Bytes),
            case Actual of
                Expected -> Files#{Path => Bytes};
                _ -> error({spacetime_source_binding, Path, Expected, Actual})
            end
        end,
        #{},
        Inputs
    ).

-doc "Returns tab-separated ID, bit width and VPI path columns for the passive recorder. The producer owns file writes; semantic ownership remains in the manifest. Table fields contain only generated identifiers and checked labels.".
-spec tsv(plan()) -> iodata().
tsv(#{signals := Signals}) ->
    [
        [
            maps:get(id, S),
            $\t,
            integer_to_binary(maps:get(width, S)),
            $\t,
            maps:get(path, S),
            $\n
        ]
     || S <- Signals
    ].

%% Match control sites through their original source stack, then verify an actual RTL declaration.
-spec actor(non_neg_integer(), map()) -> map().
actor(I, Context = #{files := Files, source_files := SourceFiles}) ->
    ReceiverPath = <<"actors/receiver_", (integer_to_binary(I))/binary, ".x">>,
    ReceiverNumber = file_number(Files, ReceiverPath),
    Metadata = json(maps:get(<<ReceiverPath/binary, ".json">>, SourceFiles)),
    #{<<"owner_import">> := #{<<"file">> := OwnerPath}, <<"inbox">> := Inbox} = Metadata,
    OwnerNumber = file_number(Files, OwnerPath),
    OwnerSource = maps:get(OwnerPath, SourceFiles),
    ReceiverSource = maps:get(ReceiverPath, SourceFiles),
    AcceptLine = unique_line(OwnerSource, <<"let accepted = ready && io.received;">>),
    ReservationLine = unique_line(ReceiverSource, <<"let reservation = if s.held">>),
    Specs = [
        {<<"accept">>, <<"^accepted(__[0-9]+)?$">>, [{OwnerNumber, AcceptLine}], 1},
        {<<"reservation">>, <<"^reservation(__[0-9]+)?$">>, [{ReceiverNumber, ReservationLine}],
            maps:get(<<"mask_bits">>, Inbox)},
        {<<"head_done">>, actor_pattern(I, <<"head_done">>), [], 1},
        {<<"phase_boundary">>, actor_pattern(I, <<"phase_boundary">>), [], 1},
        {<<"take">>, step_pattern(I, <<"take">>), [], maps:get(<<"mask_bits">>, Inbox)},
        {<<"release">>, step_pattern(I, <<"release">>), [], maps:get(<<"mask_bits">>, Inbox)},
        {<<"postpone">>, <<"^postpone(__[0-9]+)?$">>, [], maps:get(<<"mask_bits">>, Inbox)},
        {<<"egress_blocked">>, <<"^entered_egress_blocked(__[0-9]+)?$">>, [], 1}
    ],
    Results = [
        control(I, Meaning, Pattern, [{ReceiverNumber, any} | Sites], Width, Context)
     || {Meaning, Pattern, Sites, Width} <- Specs
    ],
    TransportSource = maps:get(<<"dslx/transport.x">>, SourceFiles),
    PublicationLine = unique_line(
        TransportSource, <<"source_", (integer_to_binary(I))/binary, ": next_">>
    ),
    TransportNumber = file_number(Files, <<"dslx/transport.x">>),
    Publish = control(
        I,
        <<"publication_accept">>,
        <<"^accepted(__[0-9]+)?$">>,
        [{TransportNumber, PublicationLine}],
        1,
        Context
    ),
    All = Results ++ [Publish],
    #{
        actor => I,
        inbox => Inbox,
        machine_layout => maps:get(<<"machine_layout">>, Metadata),
        source => ReceiverPath,
        source_sha256 => digest(ReceiverSource),
        signals => [S || {ok, S} <- All],
        unsupported => [U || {unsupported, U} <- All],
        conditions =>
            <<"Receiver controls are internal pre-edge expressions; qualify with !reset, initialized and sampled stage advance. head_done/directive describe reserved-head completion; accept alone is not consumption. Publication acceptance is a separate outbox-to-transport transaction.">>
    }.

%% Generated tuple-derived names retain actor/field identity after inlining.
-spec actor_pattern(non_neg_integer(), binary()) -> binary().
actor_pattern(I, Field) ->
    <<"^__state.*network_actor_", (integer_to_binary(I))/binary, ".*output.*_", Field/binary,
        "(__[0-9]+)?$">>.

%% The renderer's step_N identity refers only to the final receiver transition.
-spec step_pattern(non_neg_integer(), binary()) -> binary().
step_pattern(I, Field) ->
    <<"^__state.*networktep_", (integer_to_binary(I))/binary, "_output.*_", Field/binary,
        "(__[0-9]+)?$">>.

%% A name plus exact callsite stack and width must resolve uniquely in both IR and RTL.
-spec control(non_neg_integer(), binary(), binary(), list(), pos_integer(), map()) -> tuple().
control(I, Meaning, Pattern, Sites, Width, #{
    nodes := Nodes, declarations := Ds, committed := Commit
}) ->
    Candidates = [
        N
     || N = #{name := Name, width := W, positions := Pos} <- Nodes,
        W =:= Width,
        matches(Name, Pattern),
        has_site(Pos, Commit),
        lists:all(fun(Site) -> has_site(Pos, Site) end, Sites),
        maps:is_key(Name, Ds)
    ],
    case Candidates of
        [#{name := Name, positions := Positions}] ->
            #{width := Width} = maps:get(Name, Ds),
            {ok, (signal(Name, Width, I, Meaning))#{
                id := <<"actor/", (integer_to_binary(I))/binary, "/", Meaning/binary>>,
                evidence := iolist_to_binary(io_lib:format("XLS source callsites ~w", [Positions]))
            }};
        _ ->
            {unsupported, #{
                actor => I,
                meaning => Meaning,
                reason => missing_or_ambiguous_control,
                candidates => [maps:get(name, N) || N <- Candidates]
            }}
    end.

%% IR source positions are zero-based and include all retained inline callsites.
-spec has_site([{integer(), integer(), integer()}], tuple()) -> boolean().
has_site(Positions, {File, any}) ->
    lists:any(fun({F, _, _}) -> F =:= File end, Positions);
has_site(Positions, {File, Line}) ->
    lists:any(fun({F, L, _}) -> F =:= File andalso L =:= Line end, Positions).

%% Only generated scalar/packed bit wires and registers are observable in this ABI.
-spec declarations(binary()) -> map().
declarations(Text) ->
    Rows = captures(
        Text, <<"(?m)^  (wire|reg) (?:\\[([0-9]+):0\\] )?([A-Za-z_][A-Za-z_0-9]*);$">>, [1, 2, 3]
    ),
    maps:from_list([
        {Name, #{
            kind => Kind,
            width =>
                case W of
                    <<>> -> 1;
                    _ -> binary_to_integer(W) + 1
                end
        }}
     || [Kind, W, Name] <- Rows
    ]).

%% Physical register updates retain actual enables even for repeated equal data.
-spec registers(binary(), map()) -> [map()].
registers(Text, Declarations) ->
    [
        register(Name, Width, Text)
     || {Name, #{kind := <<"reg">>, width := Width}} <- lists:sort(maps:to_list(Declarations))
    ].

%% Recognize the generated self-hold mux. Reset initialization is separately identified by raw RTL.
-spec register(binary(), pos_integer(), binary()) -> map().
register(Name, Width, Text) ->
    Pattern =
        <<"(?m)^      ", Name/binary,
            " <= ([A-Za-z_][A-Za-z_0-9]*) \\? ([A-Za-z_][A-Za-z_0-9]*) : ", Name/binary, ";$">>,
    case captures(Text, Pattern, [1, 2]) of
        [[Enable, Data]] ->
            #{
                name => Name,
                width => Width,
                enable => Enable,
                data => Data,
                rule => enabled_same_edge_register_write
            };
        [] ->
            #{name => Name, width => Width, rule => unsupported_register_update};
        _ ->
            error({ambiguous_register_update, Name})
    end.

%% Expose only already declared nets; a missing data/enable declaration is not guessed.
-spec register_signals(map(), map()) -> [signal()].
register_signals(#{name := Name, width := Width, enable := Enable, data := Data}, Ds) ->
    [
        signal(Name, Width, null, <<"register_q">>),
        declared_signal(Enable, <<"register_enable">>, Ds),
        declared_signal(Data, <<"register_d">>, Ds)
    ];
register_signals(#{name := Name, width := Width}, _) ->
    [signal(Name, Width, null, <<"register_q">>)].

%% Every update operand must be an actual packed RTL declaration.
-spec declared_signal(binary(), binary(), map()) -> signal().
declared_signal(Name, Meaning, Ds) ->
    #{width := Width} = maps:get(Name, Ds),
    signal(Name, Width, null, Meaning).

%% No synthesized instrumentation is introduced; this path is a simulator hierarchy reference.
-spec signal(binary(), pos_integer(), non_neg_integer() | null, binary()) -> signal().
signal(Name, Width, Actor, Meaning) ->
    #{
        id => <<"signal/", Name/binary>>,
        name => Name,
        path => <<"TOP.protocol_application_top.network.core.", Name/binary>>,
        width => Width,
        actor => Actor,
        meaning => Meaning,
        evidence => <<"Exact emitted RTL declaration">>
    }.

%% Shared physical expressions have one row, while semantic aliases keep their distinct IDs.
-spec unique_signals([signal()]) -> [signal()].
unique_signals(Signals) ->
    lists:sort(
        fun(A, B) -> maps:get(id, A) < maps:get(id, B) end,
        maps:values(maps:from_list([{maps:get(id, S), S} || S <- Signals]))
    ).

%% Parse only the generated top proc's original tuple-of-bits state type.
-spec state_leaves(binary()) -> [{[non_neg_integer()], non_neg_integer()}].
state_leaves(Raw) ->
    [[Type]] = captures(Raw, <<"(?m)^top proc [^\\n]*\\(__state: (.*?) pos=">>, [1]),
    Tokens = [Token || [Token] <- captures(Type, <<"bits\\[[0-9]+\\]|[(),]">>, [0])],
    {Tree, []} = parse_type(Tokens),
    flatten(Tree, []).

%% Nested tuples are parsed structurally rather than counted across unrelated IR functions.
-spec parse_type([binary()]) -> {term(), [binary()]}.
parse_type([<<"(">> | Rest]) ->
    parse_tuple(Rest, []);
parse_type([Bits | Rest]) ->
    [[Width]] = captures(Bits, <<"^bits\\[([0-9]+)\\]$">>, [1]),
    {binary_to_integer(Width), Rest}.

%% Preserve tuple component order, including empty tuples and zero-width leaves.
-spec parse_tuple([binary()], [term()]) -> {term(), [binary()]}.
parse_tuple([<<")">> | Rest], Acc) ->
    {lists:reverse(Acc), Rest};
parse_tuple(Tokens, Acc) ->
    {Child, Rest} = parse_type(Tokens),
    case Rest of
        [<<",">> | Tail] -> parse_tuple(Tail, [Child | Acc]);
        [<<")">> | Tail] -> {lists:reverse([Child | Acc]), Tail}
    end.

%% XLS tuple-state flattening orders leaves depth-first; physical transformation is reported below.
-spec flatten(term(), [non_neg_integer()]) -> [{[non_neg_integer()], non_neg_integer()}].
flatten(Width, Path) when is_integer(Width) -> [{Path, Width}];
flatten(Children, Path) ->
    lists:append([flatten(C, Path ++ [I]) || {I, C} <- lists:enumerate(0, Children)]).

%% Encoded/narrowed state never silently becomes the original source value.
-spec state_leaf(non_neg_integer(), [non_neg_integer()], non_neg_integer(), [map()]) -> map().
state_leaf(I, Path, Width, Registers) ->
    Name = <<"____state_", (integer_to_binary(I))/binary>>,
    case [R || R = #{name := N} <- Registers, N =:= Name] of
        [#{width := PhysicalWidth}] ->
            #{
                index => I,
                tuple_path => Path,
                source_width => Width,
                signal => Name,
                physical_width => PhysicalWidth,
                disposition =>
                    case PhysicalWidth =:= Width of
                        true -> width_preserved;
                        false -> narrowed_encoding
                    end
            };
        [] ->
            #{
                index => I,
                tuple_path => Path,
                source_width => Width,
                signal => null,
                disposition => eliminated_or_reencoded
            }
    end.

%% Extract names, scalar widths and callsite stacks from final optimized IR nodes.
-spec ir_nodes(binary()) -> [map()].
ir_nodes(Text) ->
    [
        #{name => Name, width => binary_to_integer(Width), positions => positions(Line)}
     || [Name, Width, Line] <- captures(
            Text, <<"(?m)^  ([A-Za-z_][A-Za-z_0-9.]*): bits\\[([0-9]+)\\] = ([^\\n]+)$">>, [1, 2, 3]
        )
    ].

%% Missing source metadata is an empty stack and cannot satisfy a semantic control request.
-spec positions(binary()) -> [{integer(), integer(), integer()}].
positions(Line) ->
    [
        {binary_to_integer(F), binary_to_integer(L), binary_to_integer(C)}
     || [F, L, C] <- captures(Line, <<"\\(([0-9]+),([0-9]+),([0-9]+)\\)">>, [1, 2, 3])
    ].

%% Relative source filenames are exact package identities, not basename guesses.
-spec file_numbers(binary()) -> map().
file_numbers(Text) ->
    maps:from_list([
        {Path, binary_to_integer(N)}
     || [N, Path] <-
            captures(Text, <<"(?m)^file_number ([0-9]+) \"([^\"]+)\"$">>, [1, 2])
    ]).

%% Require source ownership present in the exact retained IR.
-spec file_number(map(), binary()) -> non_neg_integer().
file_number(Files, Path) -> maps:get(Path, Files).

%% A source marker identifies one generated declaration; ambiguity rejects rather than choosing first.
-spec unique_line(binary(), binary()) -> non_neg_integer().
unique_line(Text, Marker) ->
    [Line] = [
        I
     || {I, L} <- lists:enumerate(0, binary:split(Text, <<"\n">>, [global])),
        binary:match(L, Marker) =/= nomatch
    ],
    Line.

%% Regex captures are confined to the explicitly supported generated grammars.
-spec captures(binary(), binary(), [non_neg_integer()]) -> [[binary()]].
captures(Text, Pattern, Fields) ->
    case re:run(Text, Pattern, [global, {capture, Fields, binary}]) of
        nomatch -> [];
        {match, Rows} -> Rows
    end.

%% Anchored control names are checked alongside source positions and scalar widths.
-spec matches(binary(), binary()) -> boolean().
matches(Text, Pattern) -> re:run(Text, Pattern, [{capture, none}]) =:= match.

%% The caller owns input trust and total byte bounds.
-spec read(file:filename()) -> binary().
read(File) ->
    {ok, Bytes} = file:read_file(File),
    Bytes.

%% Decode producer JSON without creating atoms.
-spec json(binary()) -> map().
json(Bytes) -> json:decode(Bytes).

%% Identity is over exact bytes, independent of archive path or timestamps.
-spec digest(binary()) -> binary().
digest(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
