-module(hls_link_diagnostics_tests).

-include_lib("eunit/include/eunit.hrl").

%% Decode packet masks, retain events and classify every instrumented boundary.
-spec packet_diagnostics_test() -> ok.
packet_diagnostics_test() ->
    Counters = (counters())#{app_rx_frames => 2, app_rx_beats => 7,
                           app_rx_stall_cycles => 3,
                           app_tx_frames => 4, app_tx_beats => 5},
    #{graph_to_packet := #{frames := 2, beats := 7, stall_cycles := 3},
      boundary_events := #{frames := 4, beats := 5}} =
        hls_link_diagnostics:packet_counters(Counters),
    {255, 63} = hls_link_diagnostics:packet_trace_flags([
        #{kind => application_tx, op => 16#d1, tx_id => 255},
        #{kind => application_tx, op => 16#d2, tx_id => 63},
        #{kind => application_rx, op => 16#d1, tx_id => 0}
    ]),
    #{cycle := 8, adapter := #{raw := 255, tx_frame_accepted := true,
                               rx_link := true}} =
        hls_link_diagnostics:packet_trace_event(
            #{cycle => 8, op => 16#d1, tx_id => 255}),
    #{cycle := 9, mac := #{raw := 63, tx_accepted := true, crc_error := true}} =
        hls_link_diagnostics:packet_trace_event(
            #{cycle => 9, op => 16#d2, tx_id => 63}),
    Zero = hls_link_diagnostics:packet_adapter_flags(0),
    Tx = hls_link_diagnostics:packet_adapter_flags(1),
    Rx = hls_link_diagnostics:packet_adapter_flags(3),
    Delivered = hls_link_diagnostics:packet_adapter_flags(7),
    NoMac = hls_link_diagnostics:packet_mac_flags(0),
    TxMac = hls_link_diagnostics:packet_mac_flags(1),
    RxMac = hls_link_diagnostics:packet_mac_flags(5),
    ?assertEqual("the graph emitted no private frame",
        hls_link_diagnostics:packet_boundary(counters(), Zero, NoMac)),
    ?assertEqual("a graph frame did not enter the transmit CDC slot",
        hls_link_diagnostics:packet_boundary(Counters, Zero, NoMac)),
    ?assertEqual("the transmit CDC accepted a frame but the TX MAC did not",
        hls_link_diagnostics:packet_boundary(Counters, Tx, NoMac)),
    ?assertEqual("the local TX MAC accepted a frame but the local RX MAC accepted none",
        hls_link_diagnostics:packet_boundary(Counters, Tx, TxMac)),
    ?assertEqual("the RX MAC accepted a frame but it did not return through the receive CDC",
        hls_link_diagnostics:packet_boundary(Counters, Tx, RxMac)),
    ?assertEqual("a received frame returned through the CDC but the validator did not deliver it",
        hls_link_diagnostics:packet_boundary(Counters, Rx, RxMac)),
    ?assertEqual("a private frame crossed every instrumented local packet boundary",
        hls_link_diagnostics:packet_boundary(Counters, Delivered, RxMac)).

%% Decode scheduler flags and distinguish each request/output boundary.
-spec stage_diagnostics_test() -> ok.
stage_diagnostics_test() ->
    Counters = (counters())#{app_rx_frames => 2, app_rx_beats => 7,
                           app_rx_stall_cycles => 3,
                           app_tx_frames => 4, app_tx_beats => 5},
    #{graph_to_link := #{frames := 2, beats := 7, stall_cycles := 3},
      scheduler_memory := #{event_frames := 4, request_cycles := 5}} =
        hls_link_diagnostics:stage_counters(Counters),
    31 = hls_link_diagnostics:stage_trace_flags([
        #{kind => application_tx, tx_id => 3},
        #{kind => application_tx, tx_id => 28},
        #{kind => application_rx, tx_id => 31}
    ]),
    #{raw := 31, state_read := true, state_write := true,
      mailbox_read := true, mailbox_write := true, mailbox_snapshot := true} =
        hls_link_diagnostics:stage_flags(31),
    ?assertEqual("no scheduler RAM request followed the accepted host command",
        hls_link_diagnostics:stage_boundary(counters())),
    ?assertEqual("scheduler RAM activity occurred but the graph emitted no private frame",
        hls_link_diagnostics:stage_boundary((counters())#{app_tx_beats => 1})),
    ?assertEqual("the graph emitted a private frame without a retained scheduler RAM request",
        hls_link_diagnostics:stage_boundary((counters())#{app_rx_frames => 1})),
    ?assertEqual("scheduler RAM activity and graph output both occurred",
        hls_link_diagnostics:stage_boundary(Counters)).

%% Preserve private-link directions and modular counter progress classifications.
-spec private_diagnostics_test() -> ok.
private_diagnostics_test() ->
    Before = (counters())#{cycles => 16#fffffffe},
    Final = (counters())#{cycles => 1, app_rx_beats => 7, app_rx_frames => 2,
                        app_rx_stall_cycles => 3, app_tx_beats => 6,
                        app_tx_frames => 4, app_tx_stall_cycles => 5},
    #{cycles := 3,
      graph_to_link := #{beats := 7, frames := 2, stall_cycles := 3},
      link_to_graph := #{beats := 6, frames := 4, stall_cycles := 5}} = Delta =
        hls_link_diagnostics:private_delta(Before, Final),
    #{framing := #{tx := boundary},
      graph_to_link := #{frames := 2}, link_to_graph := #{frames := 4}} =
        hls_link_diagnostics:private_counters(Final),
    ?assertEqual("no private frame reached either tap",
        hls_link_diagnostics:private_boundary(counters(), zero_private_delta())),
    ?assertEqual("the graph emitted private frames but none returned from Ethernet",
        hls_link_diagnostics:private_boundary(
            (counters())#{app_rx_frames => 1}, zero_private_delta())),
    ?assertEqual("Ethernet delivered private frames without a local graph emission",
        hls_link_diagnostics:private_boundary(
            (counters())#{app_tx_frames => 1}, zero_private_delta())),
    ?assertEqual("bidirectional private frames are present but currently quiescent",
        hls_link_diagnostics:private_boundary(
            (counters())#{app_rx_frames => 1, app_tx_frames => 1}, zero_private_delta())),
    ?assertEqual("bidirectional private frames are still progressing",
        hls_link_diagnostics:private_boundary(Final, Delta)).

%% Subtract non-wrapping broker counters by key.
-spec broker_counter_delta_test() -> ok.
broker_counter_delta_test() ->
    ?assertEqual(#{received => 3, written => 4},
        hls_link_diagnostics:counter_delta(
            #{received => 2, written => 3}, #{received => 5, written => 7})).

%% Construct every standard counter expected by the passive monitor decoders.
-spec counters() -> map().
counters() ->
    #{cycles => 0, observation_drops => 0,
      framing => #{tx => boundary},
      app_rx_beats => 0, app_rx_frames => 0, app_rx_stall_cycles => 0,
      app_tx_beats => 0, app_tx_frames => 0, app_tx_stall_cycles => 0}.

%% Construct the renamed private-link shape for a quiescent sample window.
-spec zero_private_delta() -> map().
zero_private_delta() ->
    #{cycles => 0, observation_drops => 0,
      graph_to_link => #{beats => 0, frames => 0, stall_cycles => 0},
      link_to_graph => #{beats => 0, frames => 0, stall_cycles => 0}}.
