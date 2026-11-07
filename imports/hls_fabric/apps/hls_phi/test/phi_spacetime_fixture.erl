-module(phi_spacetime_fixture).
-moduledoc "Finite repetition-case interpretation of accepted public wire samples; source-protocol capture itself remains application independent.".
-export([summary/2, bind_summary/2]).

-doc "Decodes complete accepted output frames with the retained deployment codec, reports all-coordinate step boundaries and actual stalls. Reset retires partial frames. Requires complete cycle coverage; no physical clock period is inferred.".
-spec summary(hls_spacetime_trace:trace(), map()) -> map().
summary(Trace = #{complete := true}, #{devices := #{board := Binding}}) ->
    S = hls_spacetime_trace:fold(
        fun sample/3,
        #{
            binding => Binding,
            frame => [],
            expected => unknown,
            events => [],
            ordinals => #{},
            steps => #{},
            epoch => 0,
            reset => true,
            input_stalls => 0,
            output_stalls => 0
        },
        Trace
    ),
    #{frame := [], events := Events, steps := Steps} = S,
    Boundaries = [
        #{incarnation => Epoch, step => Step, cycle => lists:max(maps:values(Coordinates))}
     || {{Epoch, Step}, Coordinates} <- lists:sort(maps:to_list(Steps)), map_size(Coordinates) =:= 2
    ],
    #{
        events => lists:reverse(Events),
        boundaries => Boundaries,
        input_stalls => maps:get(input_stalls, S),
        output_stalls => maps:get(output_stalls, S)
    }.

%% Samples are before the edge; handshake acceptance and complete-frame timestamps share it.
-spec sample(non_neg_integer(), map(), map()) -> map().
sample(_, #{<<"reset">> := 1}, S) ->
    S#{reset => true, frame => [], expected => unknown, ordinals => #{}};
sample(C, V, S0 = #{reset := Reset, epoch := Epoch, input_stalls := IS, output_stalls := OS}) ->
    S = S0#{
        reset => false,
        epoch =>
            case Reset of
                true -> Epoch + 1;
                false -> Epoch
            end,
        input_stalls => IS +
            bit(maps:get(<<"input_valid">>, V) =:= 1 andalso maps:get(<<"input_ready">>, V) =:= 0),
        output_stalls => OS +
            bit(maps:get(<<"output_valid">>, V) =:= 1 andalso maps:get(<<"output_ready">>, V) =:= 0)
    },
    case {maps:get(<<"output_valid">>, V), maps:get(<<"output_ready">>, V)} of
        {1, 1} -> word(C, maps:get(<<"output_data">>, V), maps:get(<<"output_last">>, V), S);
        _ -> S
    end.

%% Header lengths and the actual last signal independently delimit each routed frame.
-spec word(non_neg_integer(), non_neg_integer(), 0 | 1, map()) -> map().
word(_, W, 0, S = #{frame := []}) ->
    S#{frame => [W]};
word(C, W, Last, S = #{frame := [Route]}) ->
    #{payload_words := Words} = hls_frame_layout:unpack_header(<<W:32/little>>),
    true = Last =:= bit(Words =:= 0),
    case Words of
        0 -> deliver(C, [Route, W], S);
        _ -> S#{frame => [W, Route], expected => Words}
    end;
word(C, W, Last, S = #{frame := Acc, expected := Remaining}) when
    is_integer(Remaining), Remaining > 0
->
    true = Last =:= bit(Remaining =:= 1),
    case Remaining of
        1 -> deliver(C, lists:reverse([W | Acc]), S);
        _ -> S#{frame => [W | Acc], expected => Remaining - 1}
    end.

%% Attachment identity is transport setup; application events reuse the production codec.
-spec deliver(non_neg_integer(), [non_neg_integer()], map()) -> map().
deliver(
    C,
    [Route, Header | Words],
    S = #{
        binding := Binding, events := Events, steps := Steps, epoch := Epoch, ordinals := Ordinals
    }
) ->
    #{op := Tag, txid := Tx, flags := Flags} = hls_frame_layout:unpack_header(<<Header:32/little>>),
    Payload = <<<<W:32/little>> || W <- Words>>,
    Ordinal = maps:get(Route, Ordinals, 0),
    S1 = S#{ordinals => Ordinals#{Route => Ordinal + 1}},
    case Tag of
        16#81 ->
            S1#{frame => [], expected => unknown};
        _ ->
            {Stream, Event} = hls_partition_wire:event(
                Binding, {Route bsr 16, Route band 16#ffff}, {Tag, Tx, Flags}, Payload
            ),
            NewSteps =
                case Event of
                    {phi_status, Step, X, 0, _} ->
                        Key = {Epoch, Step},
                        Old = maps:get(Key, Steps, #{}),
                        false = maps:is_key(X, Old),
                        Steps#{Key => Old#{X => C}};
                    _ ->
                        Steps
                end,
            S1#{
                frame => [],
                expected => unknown,
                steps => NewSteps,
                events => [
                    #{
                        cycle => C,
                        incarnation => Epoch,
                        stream => Stream,
                        route => Route,
                        ordinal => Ordinal,
                        words => [Route, Header | Words],
                        event => tuple_to_list(Event)
                    }
                    | Events
                ]
            }
    end.

-doc "Binds independently decoded public events to the capture envelope’s checked transport-frame occurrences by reset incarnation, route and FIFO ordinal. Final-word cycle and exact words validate the identity; they never select it. Each all-coordinate completion retains both status events as graph anchors. Rejects missing, duplicate or inconsistent identities and incomplete coordinate sets; creates no synthetic graph edges.".
-spec bind_summary(map(), xls_protocol_spacetime_capture:capture()) -> map().
bind_summary(
    Summary = #{events := Rows, boundaries := Boundaries},
    #{bundle := Bundle = #{events := Events}, stream := #{frames := Frames}}
) ->
    FrameIndex = maps:from_list([
        {{maps:get(incarnation, F), maps:get(route, F), maps:get(ordinal, F)}, F}
     || F <- Frames
    ]),
    true = map_size(FrameIndex) =:= length(Frames),
    true = length(lists:usort([maps:get(event, F) || F <- Frames])) =:= length(Frames),
    EventIndex = maps:from_list([{maps:get(id, E), E} || E <- Events]),
    true = map_size(EventIndex) =:= length(Events),
    true =
        length(
            lists:usort([
                {maps:get(incarnation, R), maps:get(route, R), maps:get(ordinal, R)}
             || R <- Rows
            ])
        ) =:= length(Rows),
    Bound = [bind_public(Row, Bundle, FrameIndex, EventIndex) || Row <- Rows],
    Summary#{events => Bound, boundaries => [bind_boundary(B, Bound) || B <- Boundaries]}.

%% Reset membership comes from the declared capture partition, not timestamp matching of events.
-spec capture_epoch(non_neg_integer(), hls_spacetime:bundle()) -> {pos_integer(), binary()}.
capture_epoch(Cycle, #{capture := #{incarnations := Epochs}}) ->
    [Found] = [
        {Ordinal, Id}
     || {Ordinal, #{id := Id, first_cycle := First, end_cycle := End}} <- lists:zip(
            lists:seq(1, length(Epochs)), Epochs
        ),
        First =< Cycle,
        Cycle < End
    ],
    Found.

%% Match the occurrence first, then independently check its decoded bytes and graph endpoint.
-spec bind_public(map(), hls_spacetime:bundle(), map(), map()) -> map().
bind_public(
    Row = #{
        incarnation := SummaryEpoch,
        route := Route,
        ordinal := Ordinal,
        cycle := Cycle,
        words := Words
    },
    Bundle,
    Frames,
    Events
) ->
    {SummaryEpoch, Epoch} = capture_epoch(Cycle, Bundle),
    #{event := Event, cycle := Cycle, words := Words} = maps:get({Epoch, Route, Ordinal}, Frames),
    #{cycle := Cycle, incarnation := Epoch} = maps:get(Event, Events),
    Row#{graph_events => [Event], graph_incarnation => Epoch}.

%% The application defines completion as both distinct coordinate status frames, not chronology alone.
-spec bind_boundary(map(), [map()]) -> map().
bind_boundary(Boundary = #{incarnation := Epoch, step := Step, cycle := Cycle}, Rows) ->
    Statuses = [
        {X, R}
     || R = #{incarnation := E, event := [phi_status, S, X, 0, _]} <- Rows,
        E =:= Epoch,
        S =:= Step
    ],
    [{0, First}, {1, Second}] = lists:sort(Statuses),
    #{graph_incarnation := GraphEpoch, graph_events := [A], cycle := AC} = First,
    #{graph_incarnation := GraphEpoch, graph_events := [B], cycle := BC} = Second,
    Cycle = max(AC, BC),
    Boundary#{graph_events => [A, B], graph_incarnation => GraphEpoch}.

%% Convert a checked predicate to a sampled bit/count.
-spec bit(boolean()) -> 0 | 1.
bit(true) -> 1;
bit(false) -> 0.
