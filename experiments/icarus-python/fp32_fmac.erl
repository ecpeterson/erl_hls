-module(fp32_fmac).
-export([fmac/3, reset/1]).
-export([start_link/0, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).
-behavior(gen_server).

%%%
%%% Communication with server
%%%

fmac(PID, A, B) ->
    {ok, <<Reply/float>>} = gen_server:call(PID, {
        fmac, <<A/float>>, <<B/float>>
    }),
    Reply.

reset(PID) ->
    gen_server:call(PID, reset).

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
    {ok, <<0.0/float>>}.

handle_call(reset, _From, _State) ->
    {ok, NewState} = init([]),
    {reply, ok, NewState};
%% do un/packing inline to get type info
handle_call({fmac, <<A/float>>, <<B/float>>}, _From, _State = <<Acc/float>>) ->
    NewAcc = Acc + A * B,  % ideally map this onto APFloat::fma, can come later
    {reply, {ok, <<NewAcc/float>>}, <<NewAcc/float>>}.

handle_cast(_Message, _State) ->
    error(function_clause).

terminate(normal, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
