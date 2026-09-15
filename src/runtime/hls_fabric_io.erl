-module(hls_fabric_io).
-moduledoc false.

%% Each raw descriptor belongs to one worker. The broker never enters an
%% operating-system open/read/write, and permits at most one frame per worker.
-export([run/4, encode/3, valid_route/1]).

run(Direction, Path, Broker, Lease) ->
    Mode = case Direction of writer -> write; reader -> read end,
    case file:open(Path, [Mode, raw, binary]) of
        {ok, FD} ->
            try
                case is_process_alive(Broker) of
                    false -> ok;
                    true when Direction =:= writer ->
                        Broker ! {writer_ready, self()}, write_loop(FD, Broker);
                    true -> read_loop(FD, Broker)
                end
            after hls_fabric_lease:closed(Lease, file:close(FD)) end;
        {error, Reason} ->
            hls_fabric_lease:closed(Lease, ok),
            exit({open_failed, Reason})
    end.

write_loop(FD, Broker) ->
    receive
        {write, ID, Bytes} ->
            Broker ! {written, self(), ID, file:write(FD, Bytes)},
            write_loop(FD, Broker);
        stop -> ok;
        {'EXIT', Broker, _Reason} -> ok
    end.

read_loop(FD, Broker) ->
    receive
        read ->
            case read_frame(FD) of
                {ok, Route, Header, Payload} ->
                    Broker ! {received, self(), Route, Header, Payload},
                    read_loop(FD, Broker);
                {error, Reason} ->
                    case is_process_alive(Broker) of
                        true -> exit({read_failed, Reason});
                        false -> ok
                    end
            end;
        stop -> ok;
        {'EXIT', Broker, _Reason} -> ok
    end.

read_frame(FD) ->
    case read_exact(FD, 8) of
        {ok, <<Destination:16/little, Source:16/little, Words:8, TxID:8, Flags:8, Tag:8>>} ->
            case read_exact(FD, 4 * Words) of
                {ok, Payload} -> {ok, {Source, Destination}, {Tag, TxID, Flags}, Payload};
                Error -> Error
            end;
        Error -> Error
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
