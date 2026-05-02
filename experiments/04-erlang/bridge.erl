%%%% bridge.erl
%%%%
%%%% Bridge between DMA engine and Erlang message system.

-module(bridge).
% -compile(export_all).
-export([get/1, set/2, set/3, bulk_get/2, ping/1]).
-export([start_link/0, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).
-behavior(gen_server).

-define(DEVICE_NODE, "/dev/axismsg0").
-define(RX_SIGIL, '$pl_message').

-define(debug(Msg),
    io:format("~s@~w: ~p~n", [?FILE, ?LINE, Msg])
).

%%%
%%% Types
%%%

-type op() :: ping | get | set | bulk_get | error | event.

-record(state, {
    fh,
    tx_id = 10 :: integer,
    child :: pid(),
    pending = #{} :: #{integer() => gen_server:from()}
}).

-record(header, {
    op :: op(),
    tx_id :: integer,
    flags = 0 :: integer
}).

%%%
%%% Communication with server
%%%

get(Register) ->
    gen_server:call(?MODULE, {get, Register}).

set(Register, Value) ->
    set(Register, Value, 16#ffffffff).
set(Register, Value, Mask) ->
    gen_server:cast(?MODULE, {set, Register, Value, Mask}).

bulk_get(Register, Count) ->
    gen_server:call(?MODULE, {bulk_get, Register, Count}).

ping(Value) ->
    gen_server:call(?MODULE, {ping, Value}).

%%%
%%% Server management
%%%

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop(PID) ->
    gen_server:stop(PID).

%%%
%%% gen_server behavior
%%%

init([]) ->
    % can't use raw bc we fork the listener, but can't use wrapped bc read blocks
    {ok, FHRead} = file:open(?DEVICE_NODE, [write, raw, binary]),
    Self = self(),
    Child = spawn_link(fun () ->
        {ok, FHWrite} = file:open(?DEVICE_NODE, [read, raw, binary]),
        listener(FHWrite, Self)
    end),
    State = #state{fh = FHRead, child = Child},
    {ok, State}.

handle_call({get, Register}, From, State) ->
    Header = #header{op = get, tx_id = State#state.tx_id},
    Payload = <<Register:32/little-integer>>,
    transmit(State#state.fh, Header, Payload),
    NewState = State#state{
        tx_id = (State#state.tx_id + 1) rem 256,
        pending = (State#state.pending)#{State#state.tx_id => From}
    },
    {noreply, NewState};
handle_call({bulk_get, Register, Count}, From, State) ->
    Header = #header{op = bulk_get, tx_id = State#state.tx_id},
    Payload = <<
        (Register band 16#ff):32/little-integer,
        (Count band 16#ff):32/little-integer
    >>,
    transmit(State#state.fh, Header, Payload),
    NewState = State#state{
        tx_id = (State#state.tx_id + 1) rem 256,
        pending = (State#state.pending)#{State#state.tx_id => From}
    },
    {noreply, NewState};
handle_call({ping, Value}, From, State) ->
    Header = #header{op = ping, tx_id = State#state.tx_id},
    Payload = <<Value:32/little-integer>>,
    transmit(State#state.fh, Header, Payload),
    NewState = State#state{
        tx_id = (State#state.tx_id + 1) rem 256,
        pending = (State#state.pending)#{State#state.tx_id => From}
    },
    {noreply, NewState}.

handle_cast({set, Register, Value, Mask}, State) ->
    %% TODO: oops, this actually does generate an "ACK" message.
    Header = #header{op=set, tx_id=State#state.tx_id},
    Payload = <<
        (Register band 16#ff):32/integer-unsigned-little,
        Value:32/integer-unsigned-little,
        Mask:32/integer-unsigned-little
    >>,
    transmit(State#state.fh, Header, Payload),
    NewState = State#state{
        tx_id = (State#state.tx_id + 1) rem 256
    },
    {noreply, NewState};
handle_cast({?RX_SIGIL, Header, Payload}, State) ->
    NewState = case Header#header.op of
        ping ->
            {From, NewPending} = maps:take(Header#header.tx_id, State#state.pending),
            <<Value:32/little-integer>> = Payload,
            gen_server:reply(From, Value),
            State#state{pending = NewPending};
        get ->
            {From, NewPending} = maps:take(Header#header.tx_id, State#state.pending),
            <<_Register:32/little-integer, Value:32/little-integer>> = Payload,
            gen_server:reply(From, Value),
            State#state{pending = NewPending};
        bulk_get ->
            {From, NewPending} = maps:take(Header#header.tx_id, State#state.pending),
            <<_Request:32/integer, Rest/binary>> = Payload,
            UnpackedValues = [X || <<X:32/little-integer>> <= Rest],
            gen_server:reply(From, UnpackedValues),
            State#state{pending = NewPending};
        error ->
            State;
        event ->
            State
    end,
    {noreply, NewState}.

terminate(normal, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%
%%% Helper
%%%

transmit(FH, Header, Payload) ->
    PackedHeader = <<
        (size(Payload) div 4):8/integer,
        (Header#header.tx_id):8/integer,
        (Header#header.flags):8/integer,
        (opcode(Header#header.op)):8/integer
    >>,
    ?debug({PackedHeader, Payload}),
    file:write(FH, <<PackedHeader/binary, Payload/binary>>).

opcode(get)      -> 16#01;
opcode(set)      -> 16#02;
opcode(bulk_get) -> 16#03;
opcode(ping)     -> 16#04.

header(16#81) -> ping;
header(16#82) -> get;
header(16#83) -> bulk_get;
header(16#E0) -> error;
header(16#F0) -> event.

%%%
%%% Subordinate process which listens on the character device
%%%

listener(FH, Parent) ->
    {ok, Header} = file:read(FH, 4),
    ?debug(Header),
    <<
        PayloadLength:8/integer,
        TxID:8/integer,
        Flags:8/integer,
        Op:8/integer
    >> = Header,
    UnpackedHeader = #header{op = header(Op), tx_id = TxID, flags = Flags},
    {ok, Payload} = file:read(FH, 4*PayloadLength),
    ?debug(Payload),
    gen_server:cast(Parent, {?RX_SIGIL, UnpackedHeader, Payload}),
    listener(FH, Parent).
