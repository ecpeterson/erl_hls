#!/usr/bin/env escript
%%! +S 1:1 +A 2
%% Exercise the actual BEAM raw-file path against the explicit DMA loopback image.
-mode(compile).

%% Open separate direction handles, as hls_fabric_io does, and check every length.
-doc "Check byte-exact routed frame echo through a physical DMA loopback device.".
-spec main([string()]) -> ok.
main([Path]) ->
    {ok, Read} = file:open(Path, [read, raw, binary]),
    {ok, Write} = file:open(Path, [write, raw, binary]),
    try
        lists:foreach(fun(Words) -> exchange(Read, Write, Words) end, lists:seq(0, 255)),
        io:format("PASS: ARM BEAM raw-file DMA loopback, all 256 frame sizes~n")
    after
        file:close(Write),
        file:close(Read)
    end;
main(_) ->
    io:format(standard_error, "usage: check_dma_beam.escript /dev/hls-dma0~n", []),
    halt(2).

%% Encode the current routed format and require byte-exact header/payload echo.
-spec exchange(file:io_device(), file:io_device(), 0..255) -> ok.
exchange(Read, Write, Words) ->
    Payload = << <<(I * 16#12345 + Words):32/little>> || I <- lists:seq(1, Words) >>,
    {ok, Frame} = hls_fabric_io:encode({16#4321, 16#1234}, {7, Words, 0}, Payload),
    ok = file:write(Write, Frame),
    <<Header:8/binary, _/binary>> = Frame,
    {ok, Header} = file:read(Read, 8),
    case Words of
        0 -> ok;
        _ -> {ok, Payload} = file:read(Read, 4 * Words), ok
    end.
