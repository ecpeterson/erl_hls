-module(hls_fabric_io).
-moduledoc false.

%% Each raw descriptor belongs to one worker. The broker never enters an
%% operating-system open/read/write, and permits at most one frame per worker.
-export([writer/2, reader/2, encode/3, valid_route/1]).

writer(Path, Broker) ->
    {ok, FD} = file:open(Path, [write, raw, binary]),
    Broker ! {writer_ready, self()},
    try write_loop(FD, Broker) after file:close(FD) end.

write_loop(FD, Broker) ->
    receive
        {write, ID, Bytes} ->
            Broker ! {written, self(), ID, file:write(FD, Bytes)},
            write_loop(FD, Broker)
    end.

reader(Path, Broker) ->
    {ok, FD} = file:open(Path, [read, raw, binary]),
    try read_loop(FD, Broker) after file:close(FD) end.

read_loop(FD, Broker) ->
    receive
        read ->
            {ok, <<Destination:16/little, Source:16/little>>} = read_exact(FD, 4),
            {ok, <<Words:8, TxID:8, Flags:8, Tag:8>>} = read_exact(FD, 4),
            {ok, Payload} = read_exact(FD, 4 * Words),
            Broker ! {received, self(), {Source, Destination}, {Tag, TxID, Flags}, Payload},
            read_loop(FD, Broker)
    end.

read_exact(FD, Length) -> read_exact(FD, Length, <<>>).
read_exact(_FD, Length, Acc) when byte_size(Acc) =:= Length -> {ok, Acc};
read_exact(FD, Length, Acc) ->
    case file:read(FD, Length - byte_size(Acc)) of
        {ok, Bytes} -> read_exact(FD, Length, <<Acc/binary, Bytes/binary>>);
        eof -> {error, unexpected_eof};
        {error, _} = Error -> Error
    end.

encode({Source, Destination} = Route, {Tag, TxID, Flags}, Payload)
        when is_integer(Tag), Tag >= 0, Tag =< 255,
             is_integer(TxID), TxID >= 0, TxID =< 255,
             is_integer(Flags), Flags >= 0, Flags =< 255,
             is_binary(Payload) ->
    case {valid_route(Route), byte_size(Payload)} of
        {false, _} -> {error, {invalid_route, Route}};
        {true, Size} when Size rem 4 =/= 0 -> {error, {unaligned_payload, Size}};
        {true, Size} when Size > 1020 -> {error, {payload_too_large, Size}};
        {true, Size} ->
            {ok, <<Destination:16/little, Source:16/little,
                (Size div 4):8, TxID:8, Flags:8, Tag:8, Payload/binary>>}
    end;
encode(Route, Header, Payload) -> {error, {invalid_frame, Route, Header, Payload}}.

valid_route({Source, Destination}) ->
    is_integer(Source) andalso Source >= 0 andalso Source =< 65535 andalso
        is_integer(Destination) andalso Destination >= 0 andalso Destination =< 65535;
valid_route(_) -> false.
