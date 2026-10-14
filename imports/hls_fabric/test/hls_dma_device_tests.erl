-module(hls_dma_device_tests).

-include_lib("eunit/include/eunit.hrl").

%% Distinguish strict debug quiescence from one complete unread application frame.
-spec status_policies_test() -> ok.
status_policies_test() ->
    Clean = status(0, 0, 0, 0, 0),
    Queued = status(0, 1, 0, 0, 0),
    Busy = status(1, 0, 0, 0, 0),
    Fault = status(0, 0, 0, 1, 0),
    ?assert(hls_dma_device:idle(Clean)),
    ?assert(hls_dma_device:healthy(Clean)),
    ?assertNot(hls_dma_device:idle(Queued)),
    ?assert(hls_dma_device:healthy(Queued)),
    ?assertNot(hls_dma_device:healthy(Busy)),
    ?assertNot(hls_dma_device:healthy(Fault)).

%% Preserve the exact target record while adding its logical endpoint label.
-spec status_line_test() -> ok.
status_line_test() ->
    Status = status(0, 0, 0, 0, 0),
    ?assertEqual(
        <<"dma role_endpoint=debug ", Status/binary>>,
        iolist_to_binary(hls_dma_device:status_line(debug, Status))
    ).

%% Build the kernel driver's complete public status fixture.
-spec status(0 | 1, 0 | 1, 0 | 1, 0 | 1, 0 | 1) -> binary().
status(TxBusy, RxFull, RxActive, Fault, Failed) ->
    iolist_to_binary(io_lib:format(
        "tx_busy=~p rx_full=~p rx_active=~p fault=~p failed=~p "
        "rx_bytes=0 events=0 mask=7~n",
        [TxBusy, RxFull, RxActive, Fault, Failed]
    )).
