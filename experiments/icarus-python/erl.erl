-module(erl).
-export([start_link/0, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).
-behavior(gen_server).

-define(SHM_PATH, "/dev/shm/xls_fmac_shm").
-define(TIMEOUT, 5000).  % milliseconds

-record(bridge, {
    seq_in :: integer(),
    b :: float(),
    a :: float(),
    opcode :: opcode(),
    seq_out :: integer(),
    out :: float(),
    state :: integer()
}).

%%% too bad EEP 13's -enum hasn't been realized
-type opcode() :: fmac | reset.
opcode_to_int(fmac) -> 0;
opcode_to_int(reset) -> 1.

int_to_opcode(0) -> fmac;
int_to_opcode(1) -> reset.

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
    Bridge = read(FD),
    NewSeq = Bridge#bridge.seq_in + 1,
    write_req(FD, NewSeq, reset),
    _NewBridge = wait_resp(FD, NewSeq),
    {reply, ok, FD};
%% do un/packing inline to get type info
handle_call({fmac, <<A/float>>, <<B/float>>}, _From, FD) ->
    Bridge = read(FD),
    NewSeq = Bridge#bridge.seq_in + 1,
    write_req(FD, NewSeq, {fmac, A, B}),
    NewBridge = wait_resp(FD, NewSeq),
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
        SeqIn:64/unsigned-little-integer,
        B:64/little-float, A:64/little-float, Opcode:64/unsigned-little-integer,
        SeqOut:64/unsigned-little-integer, Out:64/little-float,
        State:64/unsigned-little-integer
    >>} = file:pread(FD, 0, 0*4 + 7*8),  % sizeof would be nice
    #bridge{
        seq_in = SeqIn, opcode = int_to_opcode(Opcode), a = A, b = B,
        seq_out = SeqOut, out = Out,
        state = State
    }.

write(FD, Bridge) ->
    ok = file:pwrite(FD, 0, <<
        %% only touch writeable registers, which are in the first half
        (Bridge#bridge.seq_in):64/unsigned-little-integer,
        (Bridge#bridge.b):64/little-float,
        (Bridge#bridge.a):64/little-float,
        (opcode_to_int(Bridge#bridge.opcode)):64/unsigned-little-integer
    >>).

write_req(FD, Seq, Req) ->
    Bridge = case Req of
        reset -> #bridge{seq_in=Seq, opcode=reset, a=0, b=0};
        {fmac, A, B} -> #bridge{seq_in=Seq, opcode=fmac, a=A, b=B}
    end,
    write(FD, Bridge).

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

