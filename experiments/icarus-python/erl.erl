-module(erl).
-export([start_link/0, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).
-behavior(gen_server).

-define(SHM_PATH, "/dev/shm/xls_fmac_shm").
-define(TIMEOUT, 5000).  % milliseconds

-record(bridge, {
    seq_in :: integer,
    a :: float,
    b :: float,
    seq_out :: integer,
    out :: float,
    state :: integer
}).

%%%
%%% Server management
%%%

start_link() ->
    gen_server:start_link(?MODULE, [], []).

stop(PID) ->
    gen_server:stop(PID).

%%%
%%% gen_server behavior
%%%

init([]) ->
    %% TODO: perform an initial reset
    {ok, _FD} = file:open(?SHM_PATH, [read, write, raw, binary]).

handle_call(reset, _From, FD) ->
    %% TODO: implement me!!
    {reply, ok, FD};
%% do un/packing inline to get type info
handle_call({fmac, <<A/float>>, <<B/float>>}, _From, FD) ->
    Bridge = read(FD),
    write_req(FD, Bridge#bridge.seq_in + 1, A, B),
    NewBridge = wait_resp(FD, Bridge#bridge.seq_in + 1),
    {reply, {ok, <<(NewBridge#bridge.out)/float>>}, FD}.

handle_cast(_Message, _State) ->
    error(function_clause).

terminate(normal, FD) ->
    file:close(FD).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%
%%% shm interface
%%%

read(FD) ->
    {ok, <<
        SeqIn:32/unsigned-little-integer, A:64/little-float, B:64/little-float,
        SeqOut:32/unsigned-little-integer, Out:64/little-float,
        State:32/unsigned-little-integer
    >>} = file:pread(FD, 0, 3*4 + 3*8),  % 3 dwords, 3 quads. sizeof would be nice
    #bridge{
        seq_in = SeqIn, a = A, b = B,
        seq_out = SeqOut, out = Out,
        state = State
    }.

write(FD, Bridge) ->
    ok = file:pwrite(FD, 0, <<
        %% only touch writeable registers, which are in the first half
        (Bridge#bridge.seq_in):32/unsigned-little-integer,
        (Bridge#bridge.a):64/little-float,
        (Bridge#bridge.b):64/little-float
    >>).

write_req(FD, Seq, A, B) ->
    write(FD, #bridge{seq_in=Seq, a=A, b=B}).

wait_resp(FD, Seq) ->
    Timeout = erlang:system_time(millisecond) + ?TIMEOUT,
    wait_resp(FD, Seq, Timeout).

wait_resp(FD, Seq, Timeout) ->
    true = (erlang:system_time(millisecond) =< Timeout),
    %% poll for new state
    case read(FD) of
        Bridge = #bridge{seq_out = Seq} -> Bridge;
        _ -> wait_resp(FD, Seq, Timeout)
    end.

