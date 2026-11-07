-module(xls_protocol_spacetime_stream).
-moduledoc "Checks the generated application gateway and connects accepted endpoint frames to completed public frames. Called by the passive tap planner and capture adapter; source actors remain unknown ancestors until independently observed. FIFO occurrence, endpoint and reset identity select each transfer, while payload equality only validates that selection.".

%% Build binding and passive stream conversion.
-export([plan/1, attach/3]).
-export_type([plan/0, observation/0, capture/0]).

-doc "Qualified single-application gateway routes and exact top-level taps. The source closure supplies the endpoint mapping; the eight-word management capacity is the qualified gateway ABI.".
-type plan() :: #{
    endpoints := [map()],
    host := pos_integer(),
    control := non_neg_integer(),
    payload_words := pos_integer(),
    signals := [xls_protocol_spacetime:signal()],
    source_files := #{binary() => binary()}
}.

%% Routed streams carry complete 32-bit words, with route source/destination in the two half-words.
-type word() :: 0..((1 bsl 32) - 1).

%% A completed output identifies its consumed boundary occurrence; management has no such input.
-type frame() :: #{
    event := binary(),
    transfer := binary() | null,
    incarnation := binary(),
    route := word(),
    endpoint := non_neg_integer(),
    host := pos_integer(),
    ordinal := non_neg_integer(),
    cycle := non_neg_integer(),
    first_cycle := non_neg_integer(),
    words := [word()]
}.

%% Accepted but unfinished occurrences retain their original graph value and admission cycle.
-type transfer() :: #{
    event := binary(),
    version := binary(),
    incarnation := binary(),
    route := word(),
    endpoint := non_neg_integer(),
    host := pos_integer(),
    ordinal := non_neg_integer(),
    cycle := non_neg_integer(),
    words := [word()]
}.

%% A serialization prefix belongs to the enclosing current or retired reset incarnation.
-type partial() :: #{
    route := word(),
    first_cycle := non_neg_integer(),
    words := [word()],
    remaining := header | non_neg_integer()
}.

%% Reset terminates queued and partly serialized occurrences without completing them.
-type retired() :: #{
    cycle := non_neg_integer(),
    incarnation := binary(),
    pending := [transfer()],
    partial := null | partial()
}.

-doc "Backend stream sidecar, separate from the generic graph. Frames are completed public occurrences; pending/partial disclose the finite capture tail, and retired records disclose reset cancellation. Its event/version IDs refer to the companion bundle and never derive from payload equality.".
-type observation() :: #{
    schema := 1,
    frames := [frame()],
    pending := [transfer()],
    partial := null | partial(),
    retired := [retired()],
    evidence := binary()
}.

-doc "Validated graph vocabulary stays in bundle; stream retains backend frame identity and pending/reset diagnostics. Serialize the graph with hls_spacetime:encode/1 and the sidecar independently.".
-type capture() :: #{bundle := hls_spacetime:bundle(), stream := observation()}.

%% Queues hold accepted occurrences, never payload-indexed matches; lists of records accumulate backwards.
-record(stream, {
    plan :: plan(),
    queues = #{} :: map(),
    admitted = #{} :: map(),
    emitted = #{} :: map(),
    partial = null :: null | map(),
    frames = [] :: [map()],
    retired = [] :: [map()],
    events = [] :: [map()],
    versions = [] :: [map()],
    sequence = 0 :: non_neg_integer(),
    incarnation = 0 :: non_neg_integer(),
    reset = false :: boolean()
}).

-doc "Checks trusted, already hash-verified source-build bytes against the installed mechanical wrapper and gateway support. Requires the ordered protocol application gateway, explicit start and no inspection. Retained deployment terms are trusted build inputs, not untrusted uploads. No source or RTL is written; changed wiring or support rejects and requires observer qualification.".
-spec plan(#{binary() => binary()}) -> plan().
plan(Files) ->
    #{devices := Devices, source_boundary := Boundary} = binary_to_term(
        maps:get(<<"deployment.etf">>, Files)
    ),
    [
        Binding = #{
            host := Host,
            control := Control,
            events := Events,
            control_adapter := #{gateway_source := GatewaySource}
        }
    ] = maps:values(Devices),
    Source = iolist_to_binary(GatewaySource),
    require(Source =:= <<"xls/templates/protocol_application.x">>, {unsupported_gateway, Source}),
    #{
        inspection := none,
        activation := explicit_start,
        frame_layout := Layout,
        externals := Externals
    } = Boundary,
    Top = <<"application/protocol_application_top.sv">>,
    ok = same(Top, sv_protocol_application:emit(Binding, Boundary), Files),
    Gateway = xls_protocol_application:emit(Binding),
    maps:foreach(
        fun(Name, Bytes) ->
            ok = same(iolist_to_binary(["application/", Name]), Bytes, Files)
        end,
        Gateway
    ),
    Libraries = [
        {hls_lowering, <<"support/fabric/">>, "xls/hls_partition_io.x"},
        {hls_lowering, <<"support/fabric/">>, "xls/lib/protocol_framing.x"},
        {erl_hls, <<"support/compiler/">>, "xls/lib/axis.x"}
    ],
    lists:foreach(
        fun({App, Prefix, Name}) ->
            {ok, Bytes} = file:read_file(filename:join(code:priv_dir(App), Name)),
            ok = same(iolist_to_binary([Prefix, Name]), Bytes, Files)
        end,
        Libraries
    ),
    FrameConfig = iolist_to_binary(xls_frame_layout:config(Layout)),
    Configs = [
        {Name, Bytes}
     || {Name, Bytes} <- maps:to_list(Files),
        filename:basename(Name) =:= <<"frame_config.x">>
    ],
    true = Configs =/= [],
    lists:foreach(fun({Name, _}) -> ok = same(Name, FrameConfig, Files) end, Configs),
    Io = maps:get(<<"support/fabric/xls/hls_partition_io.x">>, Files),
    {match, [[FirstText]]} = re:run(
        Io,
        <<"const FIRST_EVENT_ENDPOINT = u16:([0-9]+);">>,
        [global, {capture, [1], binary}]
    ),
    First = binary_to_integer(FirstText),
    Indices = lists:sort([I || #{index := I} <- Externals]),
    true = Indices =:= lists:seq(0, length(Externals) - 1),
    true = lists:sort(maps:keys(Events)) =:= [First + I || I <- Indices],
    false = maps:is_key(Control, Events),
    Width = hls_frame_layout:frame_bits(Layout),
    PayloadWords = hls_frame_layout:payload_words(Layout),
    true = PayloadWords =< 8,
    Endpoints = [
        begin
            Endpoint = First + I,
            #{port := Port} = maps:get(Endpoint, Events),
            true = iolist_to_binary(Port) =:= <<"external_", (integer_to_binary(I))/binary>>,
            #{
                index => I,
                endpoint => Endpoint,
                route => (Endpoint bsl 16) bor Host,
                data => tap_id(I, <<"data">>),
                valid => tap_id(I, <<"valid">>),
                ready => tap_id(I, <<"ready">>)
            }
        end
     || I <- Indices
    ],
    BoundFiles =
        [
            Top,
            <<"deployment.etf">>,
            <<"application/gateway.x">>,
            <<"application/application_config.x">>
        ] ++
            [iolist_to_binary([P, N]) || {_, P, N} <- Libraries] ++ [N || {N, _} <- Configs],
    #{
        endpoints => Endpoints,
        host => Host,
        control => Control,
        payload_words => PayloadWords,
        signals => [
            tap(I, Field, W)
         || I <- Indices,
            {Field, W} <- [{<<"data">>, Width}, {<<"valid">>, 1}, {<<"ready">>, 1}]
        ],
        source_files => maps:from_list([{N, digest(maps:get(N, Files))} || N <- BoundFiles])
    }.

%% Exact byte comparison includes the whole generated wiring, not merely a familiar pin spelling.
-spec same(binary(), iodata(), #{binary() => binary()}) -> ok.
same(Name, Expected, Files) ->
    case maps:get(Name, Files) =:= iolist_to_binary(Expected) of
        true -> ok;
        false -> error({spacetime_stream_source, Name})
    end.

%% Tap identities are disjoint from register/actor observation IDs.
-spec tap_id(non_neg_integer(), binary()) -> binary().
tap_id(Index, Field) ->
    <<"stream/event/", (integer_to_binary(Index))/binary, "/", Field/binary>>.

%% These exact declared wires connect the boundary's external port to its gateway input.
-spec tap(non_neg_integer(), binary(), pos_integer()) -> xls_protocol_spacetime:signal().
tap(Index, Field, Width) ->
    Name = <<"event", (integer_to_binary(Index))/binary, "_", Field/binary>>,
    #{
        id => tap_id(Index, Field),
        name => Name,
        path => <<"TOP.protocol_application_top.", Name/binary>>,
        width => Width,
        actor => null,
        meaning => <<"accepted_endpoint_", Field/binary>>,
        evidence => <<"Exact retained deployment, wrapper wiring and gateway support">>
    }.

%% Keep source hashes separate from the overall observation-plan identity.
-spec digest(binary()) -> binary().
digest(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).

-doc "Returns a generic graph plus backend stream sidecar, adding a separate observer without renaming existing events. Completed public frames consume the oldest occurrence accepted by their first public word on the declared route; unexpected frames, byte mismatches and malformed framing reject. Reset retires queues and partial serialization. Capture-end queues/prefixes are disclosed as pending, not fabricated completions or lost frames.".
-spec attach(plan(), hls_spacetime_trace:trace(), hls_spacetime:bundle()) -> capture().
attach(
    Plan = #{endpoints := Endpoints, control := Control, host := Host},
    Trace,
    Bundle = #{capture := Capture, events := Events, versions := Versions, resources := Resources}
) ->
    Final = hls_spacetime_trace:fold(fun sample/3, #stream{plan = Plan}, Trace),
    Scope =
        <<"Accepted endpoint frames joined to completed public frames by declared route, reset incarnation and FIFO occurrence. Payload equality validates only. Source-publication and management ancestry remain unknown. Pending capture tails and reset retirement are explicit; no queue-drain or sensitized ancestry claim.">>,
    Routes = [maps:get(route, E) || E <- Endpoints] ++ [(Control bsl 16) bor Host],
    Observer = #{
        id => <<"stream">>,
        first_sequence => 0,
        next_sequence => Final#stream.sequence,
        gaps => [],
        scope => Scope
    },
    Added = [
        #{
            id => resource(R),
            kind => logic,
            evidence => <<"Declared application gateway endpoint; physical placement unknown">>
        }
     || R <- Routes
    ],
    Joined = Bundle#{
        capture := Capture#{observers := maps:get(observers, Capture) ++ [Observer]},
        events := Events ++ lists:reverse(Final#stream.events),
        versions := Versions ++ lists:reverse(Final#stream.versions),
        resources := Resources ++ Added
    },
    #{
        bundle => Joined,
        stream => #{
            schema => 1,
            frames => lists:reverse(Final#stream.frames),
            pending => pending(Final#stream.queues),
            partial => Final#stream.partial,
            retired => lists:reverse(Final#stream.retired),
            evidence => Scope
        }
    }.

%% Match the register observer's reset epochs; initial reset belongs to incarnation zero.
-spec sample(non_neg_integer(), map(), #stream{}) -> #stream{}.
sample(Cycle, Values, S = #stream{reset = WasReset, incarnation = Inc}) ->
    Reset = maps:get(<<"reset">>, Values) =:= 1,
    case Reset of
        true when not WasReset, Cycle > 0 ->
            Retired = #{
                cycle => Cycle,
                incarnation => incarnation(Inc),
                pending => pending(S#stream.queues),
                partial => S#stream.partial
            },
            S#stream{
                reset = true,
                incarnation = Inc + 1,
                queues = #{},
                admitted = #{},
                emitted = #{},
                partial = null,
                retired = [Retired | S#stream.retired]
            };
        true ->
            S#stream{reset = true};
        false ->
            #{endpoints := Endpoints} = S#stream.plan,
            Admitted = lists:foldl(
                fun(E, Acc) -> admission(Cycle, Values, E, Acc) end,
                S#stream{reset = false},
                Endpoints
            ),
            case {maps:get(<<"output_valid">>, Values), maps:get(<<"output_ready">>, Values)} of
                {1, 1} ->
                    word(
                        Cycle,
                        maps:get(<<"output_data">>, Values),
                        maps:get(<<"output_last">>, Values) =:= 1,
                        Admitted
                    );
                _ ->
                    Admitted
            end
    end.

%% A ready/valid edge mints an occurrence even when its payload equals the preceding frame.
-spec admission(non_neg_integer(), map(), map(), #stream{}) -> #stream{}.
admission(Cycle, Values, #{data := Data, valid := Valid, ready := Ready, route := Route}, S) ->
    case {maps:get(Valid, Values), maps:get(Ready, Values)} of
        {1, 1} ->
            Raw = maps:get(Data, Values),
            #{payload_words := Capacity, host := Host} = S#stream.plan,
            Header = Raw band ((1 bsl 32) - 1),
            Count = Header band 255,
            require(Count =< Capacity, {endpoint_length, Route, Count}),
            Words = [
                Route,
                Header
                | [(Raw bsr (32 * (I + 1))) band ((1 bsl 32) - 1) || I <- lists:seq(0, Count - 1)]
            ],
            Ordinal = maps:get(Route, S#stream.admitted, 0),
            Id = identity(<<"transfer">>, S#stream.incarnation, Route, Ordinal),
            Meta = #{
                event => Id,
                incarnation => incarnation(S#stream.incarnation),
                route => Route,
                endpoint => Route bsr 16,
                host => Host,
                ordinal => Ordinal,
                cycle => Cycle,
                words => Words
            },
            {Value, Next} = action(Id, <<"boundary_transfer">>, Cycle, Route, Id, unknown, S),
            Q = maps:get(Route, S#stream.queues, queue:new()),
            require(queue:len(Q) < 65536, {pending_limit, Route}),
            Next#stream{
                admitted = (S#stream.admitted)#{Route => Ordinal + 1},
                queues = (S#stream.queues)#{Route => queue:in(Meta#{version => Value}, Q)}
            };
        _ ->
            S
    end.

%% Accepted words alone advance framing. No stability promise is imposed on unaccepted offers.
-spec word(non_neg_integer(), non_neg_integer(), boolean(), #stream{}) -> #stream{}.
word(
    Cycle,
    Word,
    Last,
    S = #stream{
        partial = null,
        plan = #{
            endpoints := Endpoints,
            host := Host,
            control := Control
        }
    }
) ->
    Routes = [maps:get(route, E) || E <- Endpoints] ++ [(Control bsl 16) bor Host],
    require(lists:member(Word, Routes), {unknown_route, Word}),
    require(not Last, route_last),
    S#stream{
        partial = #{route => Word, first_cycle => Cycle, words => [Word], remaining => header}
    };
word(Cycle, Word, Last, S = #stream{partial = P = #{remaining := header, words := Words}}) ->
    Count = Word band 255,
    require(Count =< 8, {public_length, Count}),
    require(Last =:= (Count =:= 0), header_last),
    Next = S#stream{partial = P#{words := Words ++ [Word], remaining := Count}},
    case Last of
        true -> complete(Cycle, Next);
        false -> Next
    end;
word(Cycle, Word, Last, S = #stream{partial = P = #{remaining := Left, words := Words}}) ->
    require(Left > 0 andalso Last =:= (Left =:= 1), payload_last),
    Next = S#stream{partial = P#{words := Words ++ [Word], remaining := Left - 1}},
    case Last of
        true -> complete(Cycle, Next);
        false -> Next
    end.

%% Select FIFO identity first; comparing bytes cannot rescue missing or reordered admissions.
-spec complete(non_neg_integer(), #stream{}) -> #stream{}.
complete(
    Cycle,
    S = #stream{
        partial = #{route := Route, first_cycle := First, words := Words},
        plan = #{host := Host, control := Control}
    }
) ->
    Ordinal = maps:get(Route, S#stream.emitted, 0),
    Id = identity(<<"public">>, S#stream.incarnation, Route, Ordinal),
    {Transfer, Input, Queues} =
        case Route bsr 16 of
            Control ->
                {null, unknown, S#stream.queues};
            _ ->
                Q = maps:get(Route, S#stream.queues, queue:new()),
                case queue:out(Q) of
                    {empty, _} ->
                        error({spacetime_stream, {missing_admission, Route, Ordinal}});
                    {
                        {value, #{
                            event := T,
                            version := V,
                            ordinal := O,
                            words := Expected,
                            cycle := Admission
                        }},
                        Rest
                    } ->
                        require(Admission =< First, {admission_after_output, T, Admission, First}),
                        require(O =:= Ordinal, {occurrence_order, Route, O, Ordinal}),
                        require(Expected =:= Words, {frame_mismatch, T, Expected, Words}),
                        {T, V, (S#stream.queues)#{Route => Rest}}
                end
        end,
    Meta = #{
        event => Id,
        transfer => Transfer,
        incarnation => incarnation(S#stream.incarnation),
        route => Route,
        endpoint => Route bsr 16,
        host => Host,
        ordinal => Ordinal,
        cycle => Cycle,
        first_cycle => First,
        words => Words
    },
    Activation =
        case Transfer of
            null -> Id;
            _ -> Transfer
        end,
    {_, Next} = action(Id, <<"public_frame">>, Cycle, Route, Activation, Input, S),
    Next#stream{
        partial = null,
        queues = Queues,
        emitted = (S#stream.emitted)#{Route => Ordinal + 1},
        frames = [Meta | S#stream.frames]
    }.

%% Unknown upstream ancestry is represented by a root; downstream edges remain ordinary graph edges.
-spec action(
    binary(),
    binary(),
    non_neg_integer(),
    non_neg_integer(),
    binary(),
    unknown | binary(),
    #stream{}
) -> {binary(), #stream{}}.
action(Id, Operation, Cycle, Route, Activation, Input, S) ->
    require(S#stream.sequence < 1000000, event_limit),
    Inc = incarnation(S#stream.incarnation),
    Evidence = <<"Sampled ready/valid acceptance; declared route and FIFO occurrence identity">>,
    {Inputs, Roots} =
        case Input of
            unknown ->
                Root = <<Id/binary, "/unknown-source">>,
                {[Root], [
                    #{
                        id => Root,
                        incarnation => Inc,
                        producer => root,
                        origin => unknown,
                        storage => null,
                        evidence => <<"Source publication or management ancestry not observed">>
                    }
                ]};
            _ ->
                {[Input], []}
        end,
    Value = <<Id/binary, "/value">>,
    Version = #{
        id => Value,
        incarnation => Inc,
        producer => Id,
        origin => event,
        storage => null,
        evidence => Evidence
    },
    Event = #{
        id => Id,
        observer => <<"stream">>,
        sequence => S#stream.sequence,
        cycle => Cycle,
        incarnation => Inc,
        actor => resource(Route),
        task => <<"public-stream">>,
        activation => Activation,
        operation => Operation,
        inputs => Inputs,
        outputs => [Value],
        resources => [resource(Route)],
        evidence => Evidence
    },
    {Value, S#stream{
        sequence = S#stream.sequence + 1,
        events = [Event | S#stream.events],
        versions = [Version | Roots] ++ S#stream.versions
    }}.

%% Endpoint resources are logical transport locations until a physical catalogue binds them.
-spec resource(non_neg_integer()) -> binary().
resource(Route) -> <<"stream/route/", (integer_to_binary(Route))/binary>>.

%% Reset epochs agree with the register observer rather than wall time or payload contents.
-spec incarnation(non_neg_integer()) -> binary().
incarnation(Inc) -> <<"reset/", (integer_to_binary(Inc))/binary>>.

%% Every accepted occurrence has a stable namespace independent of register event allocation.
-spec identity(binary(), non_neg_integer(), non_neg_integer(), non_neg_integer()) -> binary().
identity(Kind, Inc, Route, Ordinal) ->
    iolist_to_binary([
        "stream/",
        Kind,
        "/",
        integer_to_binary(Inc),
        "/",
        integer_to_binary(Route),
        "/",
        integer_to_binary(Ordinal)
    ]).

%% Deterministic pending order is presentation only; matching remains per-route FIFO.
-spec pending(map()) -> [map()].
pending(Queues) -> lists:append([queue:to_list(Q) || {_, Q} <- lists:sort(maps:to_list(Queues))]).

%% Fail at the first unsupported or contradictory observation instead of guessing a link.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> error({spacetime_stream, Reason}).
