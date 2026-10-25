-module(hls_link_diagnostics).
-moduledoc "Decodes passive packet, scheduler-stage and private-link monitor evidence.".

-export([
    counter_delta/2,
    packet_adapter_flags/1,
    packet_boundary/3,
    packet_counters/1,
    packet_delta/2,
    packet_mac_flags/1,
    packet_trace_event/1,
    packet_trace_flags/1,
    private_boundary/2,
    private_counters/1,
    private_delta/2,
    stage_boundary/1,
    stage_counters/1,
    stage_delta/2,
    stage_flags/1,
    stage_trace_flags/1
]).

-doc "Subtracts two monotone broker counter maps.".
-spec counter_delta(map(), map()) -> map().
counter_delta(Baseline, Final) ->
    maps:map(fun(Key, Value) -> Value - maps:get(Key, Baseline) end, Final).

-doc "Renames standard counters according to the packet monitor's tap wiring.".
-spec packet_counters(map()) -> map().
packet_counters(Counters) ->
    #{cycles => maps:get(cycles, Counters),
      observation_drops => maps:get(observation_drops, Counters),
      graph_to_packet => #{beats => maps:get(app_rx_beats, Counters),
                           frames => maps:get(app_rx_frames, Counters),
                           stall_cycles => maps:get(app_rx_stall_cycles, Counters)},
      boundary_events => #{beats => maps:get(app_tx_beats, Counters),
                           frames => maps:get(app_tx_frames, Counters)}}.

-doc "Subtracts packet-monitor counters over one bounded sample window.".
-spec packet_delta(map(), map()) -> map().
packet_delta(Before, Final) ->
    #{cycles => counter32_delta(Before, Final, cycles),
      observation_drops => counter32_delta(Before, Final, observation_drops),
      graph_to_packet => #{beats => counter32_delta(Before, Final, app_rx_beats),
                           frames => counter32_delta(Before, Final, app_rx_frames),
                           stall_cycles => counter32_delta(
                               Before, Final, app_rx_stall_cycles)},
      boundary_events => #{beats => counter32_delta(Before, Final, app_tx_beats),
                           frames => counter32_delta(Before, Final, app_tx_frames)}}.

-doc "Combines retained adapter and MAC event masks by diagnostic opcode.".
-spec packet_trace_flags([map()]) -> {0 .. ((1 bsl 8) - 1), 0 .. ((1 bsl 6) - 1)}.
packet_trace_flags(Events) ->
    lists:foldl(fun
        (#{kind := application_tx, op := 16#d1, tx_id := Flags}, {Adapter, Mac}) ->
            {Adapter bor (Flags band 255), Mac};
        (#{kind := application_tx, op := 16#d2, tx_id := Flags}, {Adapter, Mac}) ->
            {Adapter, Mac bor (Flags band 63)};
        (_, Acc) -> Acc
    end, {0, 0}, Events).

-doc "Names one retained packet event while preserving its cycle and raw mask.".
-spec packet_trace_event(map()) -> map().
packet_trace_event(#{cycle := Cycle, op := 16#d1, tx_id := Flags}) ->
    #{cycle => Cycle, adapter => packet_adapter_flags(Flags band 255)};
packet_trace_event(#{cycle := Cycle, op := 16#d2, tx_id := Flags}) ->
    #{cycle => Cycle, mac => packet_mac_flags(Flags band 63)}.

-doc "Names packet-adapter transitions retained under opcode 0xd1.".
-spec packet_adapter_flags(0 .. ((1 bsl 8) - 1)) -> map().
packet_adapter_flags(Flags) ->
    #{raw => Flags,
      tx_frame_accepted => Flags band 1 =/= 0,
      rx_frame_accepted => Flags band 2 =/= 0,
      link_rx_frame_delivered => Flags band 4 =/= 0,
      tx_invalid => Flags band 8 =/= 0,
      tx_protocol_fault => Flags band 16 =/= 0,
      rx_protocol_fault => Flags band 32 =/= 0,
      tx_link => Flags band 64 =/= 0,
      rx_link => Flags band 128 =/= 0}.

-doc "Names monotone MAC-counter transitions retained under opcode 0xd2.".
-spec packet_mac_flags(0 .. ((1 bsl 6) - 1)) -> map().
packet_mac_flags(Flags) ->
    #{raw => Flags,
      tx_accepted => Flags band 1 =/= 0,
      tx_failed => Flags band 2 =/= 0,
      rx_accepted => Flags band 4 =/= 0,
      rx_failed => Flags band 8 =/= 0,
      preamble_error => Flags band 16 =/= 0,
      crc_error => Flags band 32 =/= 0}.

-doc "Locates the first unobserved packet boundary without assigning its cause.".
-spec packet_boundary(map(), map(), map()) -> string().
packet_boundary(Counters, Adapter, Mac) ->
    GraphFrames = maps:get(app_rx_frames, Counters),
    case {GraphFrames > 0,
          maps:get(tx_frame_accepted, Adapter),
          maps:get(tx_accepted, Mac),
          maps:get(rx_accepted, Mac),
          maps:get(rx_frame_accepted, Adapter),
          maps:get(link_rx_frame_delivered, Adapter)} of
        {false, _, _, _, _, _} ->
            "the graph emitted no private frame";
        {true, false, _, _, _, _} ->
            "a graph frame did not enter the transmit CDC slot";
        {true, true, false, _, _, _} ->
            "the transmit CDC accepted a frame but the TX MAC did not";
        {true, true, true, false, _, _} ->
            "the local TX MAC accepted a frame but the local RX MAC accepted none";
        {true, true, true, true, false, _} ->
            "the RX MAC accepted a frame but it did not return through the receive CDC";
        {true, true, true, true, true, false} ->
            "a received frame returned through the CDC but the validator did not deliver it";
        {true, true, true, true, true, true} ->
            "a private frame crossed every instrumented local packet boundary"
    end.

-doc "Renames standard counters according to the scheduler-stage monitor's tap wiring.".
-spec stage_counters(map()) -> map().
stage_counters(Counters) ->
    #{cycles => maps:get(cycles, Counters),
      observation_drops => maps:get(observation_drops, Counters),
      graph_to_link => #{beats => maps:get(app_rx_beats, Counters),
                         frames => maps:get(app_rx_frames, Counters),
                         stall_cycles => maps:get(app_rx_stall_cycles, Counters)},
      scheduler_memory => #{request_cycles => maps:get(app_tx_beats, Counters),
                            event_frames => maps:get(app_tx_frames, Counters)}}.

-doc "Subtracts scheduler-stage counters over one bounded sample window.".
-spec stage_delta(map(), map()) -> map().
stage_delta(Before, Final) ->
    #{cycles => counter32_delta(Before, Final, cycles),
      observation_drops => counter32_delta(Before, Final, observation_drops),
      graph_to_link => #{beats => counter32_delta(Before, Final, app_rx_beats),
                         frames => counter32_delta(Before, Final, app_rx_frames),
                         stall_cycles => counter32_delta(Before, Final, app_rx_stall_cycles)},
      scheduler_memory => #{request_cycles => counter32_delta(Before, Final, app_tx_beats),
                            event_frames => counter32_delta(Before, Final, app_tx_frames)}}.

-doc "Combines raw scheduler flags retained in application-TX trace headers.".
-spec stage_trace_flags([map()]) -> 0 .. ((1 bsl 5) - 1).
stage_trace_flags(Events) ->
    lists:foldl(fun
        (#{kind := application_tx, tx_id := Flags}, Acc) -> Acc bor (Flags band 31);
        (_, Acc) -> Acc
    end, 0, Events).

-doc "Names each physical wrapper flag while retaining its raw value.".
-spec stage_flags(0 .. ((1 bsl 5) - 1)) -> map().
stage_flags(Flags) ->
    #{raw => Flags,
      state_read => Flags band 1 =/= 0,
      state_write => Flags band 2 =/= 0,
      mailbox_read => Flags band 4 =/= 0,
      mailbox_write => Flags band 8 =/= 0,
      mailbox_snapshot => Flags band 16 =/= 0}.

-doc "Locates the first inactive scheduler boundary without assigning a cause.".
-spec stage_boundary(map()) -> string().
stage_boundary(Counters) ->
    Requests = maps:get(app_tx_beats, Counters),
    Frames = maps:get(app_rx_frames, Counters),
    case {Requests, Frames} of
        {0, 0} -> "no scheduler RAM request followed the accepted host command";
        {_, 0} -> "scheduler RAM activity occurred but the graph emitted no private frame";
        {0, _} -> "the graph emitted a private frame without a retained scheduler RAM request";
        _ -> "scheduler RAM activity and graph output both occurred"
    end.

-doc "Renames standard counters according to the private-link monitor's tap wiring.".
-spec private_counters(map()) -> map().
private_counters(Counters) ->
    #{cycles => maps:get(cycles, Counters),
      observation_drops => maps:get(observation_drops, Counters),
      framing => maps:get(framing, Counters),
      graph_to_link => #{beats => maps:get(app_rx_beats, Counters),
                         frames => maps:get(app_rx_frames, Counters),
                         stall_cycles => maps:get(app_rx_stall_cycles, Counters)},
      link_to_graph => #{beats => maps:get(app_tx_beats, Counters),
                         frames => maps:get(app_tx_frames, Counters),
                         stall_cycles => maps:get(app_tx_stall_cycles, Counters)}}.

-doc "Subtracts wrapping private-link counters over one bounded sample window.".
-spec private_delta(map(), map()) -> map().
private_delta(Before, Final) ->
    #{cycles => counter32_delta(Before, Final, cycles),
      observation_drops => counter32_delta(Before, Final, observation_drops),
      graph_to_link => #{beats => counter32_delta(Before, Final, app_rx_beats),
                         frames => counter32_delta(Before, Final, app_rx_frames),
                         stall_cycles => counter32_delta(Before, Final, app_rx_stall_cycles)},
      link_to_graph => #{beats => counter32_delta(Before, Final, app_tx_beats),
                         frames => counter32_delta(Before, Final, app_tx_frames),
                         stall_cycles => counter32_delta(Before, Final, app_tx_stall_cycles)}}.

-doc "Classifies the private-link boundary without claiming why progress stopped.".
-spec private_boundary(map(), map()) -> string().
private_boundary(Total, Delta) ->
    Out = maps:get(app_rx_frames, Total),
    In = maps:get(app_tx_frames, Total),
    DeltaOut = maps:get(frames, maps:get(graph_to_link, Delta)),
    DeltaIn = maps:get(frames, maps:get(link_to_graph, Delta)),
    case {Out, In, DeltaOut, DeltaIn} of
        {0, 0, _, _} -> "no private frame reached either tap";
        {_, 0, _, _} -> "the graph emitted private frames but none returned from Ethernet";
        {0, _, _, _} -> "Ethernet delivered private frames without a local graph emission";
        {_, _, 0, 0} -> "bidirectional private frames are present but currently quiescent";
        _ -> "bidirectional private frames are still progressing"
    end.

%% Compute one unsigned modular hardware-counter difference.
-spec counter32_delta(map(), map(), atom()) -> non_neg_integer().
counter32_delta(Before, Final, Key) ->
    (maps:get(Key, Final) - maps:get(Key, Before)) band 16#ffffffff.
