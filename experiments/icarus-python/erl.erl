-module(erl).
-export([main/0]).

-define(SHM_PATH, "/dev/shm/xls_fmac_shm").
-define(TIMEOUT, 5000).  % milliseconds

-record(state, {
    seq_in :: integer,
    a :: float,
    b :: float,
    seq_out :: integer,
    out :: float,
    state :: integer
}).

read(FD) ->
    {ok, <<
        SeqIn:32/unsigned-little-integer, A:32/little-float, B:32/little-float,
        SeqOut:32/unsigned-little-integer, Out:32/little-float,
        State:32/unsigned-little-integer
    >>} = file:pread(FD, 0, 4*6),  % 6 fields, each double wide
    #state{
        seq_in = SeqIn, a = A, b = B,
        seq_out = SeqOut, out = Out,
        state = State
    }.

write(FD, State) ->
    ok = file:pwrite(FD, 0, <<
        %% only touch writeable registers
        (State#state.seq_in):32/unsigned-little-integer,
        (State#state.a):32/little-float,
        (State#state.b):32/little-float
    >>).

write_req(FD, Seq, A, B) ->
    write(FD, #state{seq_in=Seq, a=A, b=B}).

wait_resp(FD, Seq) ->
    Timeout = erlang:system_time(millisecond) + ?TIMEOUT,
    wait_resp(FD, Seq, Timeout).

wait_resp(FD, Seq, Timeout) ->
    true = (erlang:system_time(millisecond) =< Timeout),
    %% poll for new state
    case read(FD) of
        State = #state{seq_out = Seq} -> State;
        _ -> wait_resp(FD, Seq, Timeout)
    end.

main() ->
    {ok, FD} = file:open(?SHM_PATH, [read, write, raw, binary]),
    lists:foldl(
        fun({A, B}, OldSeq) ->
            Seq = OldSeq + 1,
            write_req(FD, Seq, A, B),
            State = wait_resp(FD, Seq),
            io:format("~p~n", [State]),
            Seq
        end,
        0,
        [{1.0, 2.0}, {2.0, 3.0}, {3.0, 4.0}]
    ),
    ok = file:close(FD).
