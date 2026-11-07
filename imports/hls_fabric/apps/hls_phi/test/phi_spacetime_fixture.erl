-module(phi_spacetime_fixture).
-moduledoc "Finite repetition-case interpretation of accepted public wire samples; source-protocol capture itself remains application independent.".
-export([summary/2]).

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
    S#{reset => true, frame => [], expected => unknown};
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
    S = #{binding := Binding, events := Events, steps := Steps, epoch := Epoch}
) ->
    #{op := Tag, txid := Tx, flags := Flags} = hls_frame_layout:unpack_header(<<Header:32/little>>),
    Payload = <<<<W:32/little>> || W <- Words>>,
    case Tag of
        16#81 ->
            S#{frame => [], expected => unknown};
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
            S#{
                frame => [],
                expected => unknown,
                steps => NewSteps,
                events => [
                    #{
                        cycle => C,
                        incarnation => Epoch,
                        stream => Stream,
                        event => tuple_to_list(Event)
                    }
                    | Events
                ]
            }
    end.

%% Convert a checked predicate to a sampled bit/count.
-spec bit(boolean()) -> 0 | 1.
bit(true) -> 1;
bit(false) -> 0.
