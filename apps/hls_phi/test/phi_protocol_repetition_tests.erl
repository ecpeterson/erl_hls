-module(phi_protocol_repetition_tests).
-moduledoc "Host-loop ordering and rejection tests; the connected RTL witness is separate.".
-include_lib("eunit/include/eunit.hrl").

%% Corrections must be queued before the final query, even with interleaved quiet statuses.
-spec ordered_feedback_test() -> ok.
ordered_feedback_test() ->
    Events=[{ok,board,application,{started}},event({phi_correction,8,0,0,2}),
        event({phi_status,9,1,0,2}),event({phi_status,9,0,0,2}),event({phi_status,10,1,0,2}),
        {ok,board,data_measurements,{pauli_reply,123,1,0,1}},
        {ok,board,data_measurements,{pauli_reply,123,0,0,0}}],
    with_stream(Events,fun(P)->
        ?assertMatch(#{fence:=9,replies:=[{0,0},{1,1}],corrections:=[[0,0,8,2,1]]},
            phi_protocol_repetition:run(P,2,8,123,1000)),
        ?assertEqual([{control_router,noise,{0,0,1,0},{noise_cutoff,8}},start,
            {control_router,data,{1,0,1,0},{pauli_update,z}},
            {control_router,data,{0,0,1,0},{pauli_query,123,x}}],gen_server:call(P,commands))
    end).

%% Bad coordinates and duplicate statuses cannot form a valid quiet fence.
-spec rejected_events_test() -> ok.
rejected_events_test() ->
    lists:foreach(fun(Events)->with_stream([{ok,board,application,{started}}|Events],fun(P)->
        ?assertException(error,_,phi_protocol_repetition:run(P,2,8,123,1000))
    end) end,[[event({phi_status,9,2,0,2})],[event({phi_status,9,0,0,2}),event({phi_status,9,0,0,2})],
        [event({phi_correction,8,0,0,1})]]).

%% A missing event aborts; unsupported finite-domain arguments reject before issuing commands.
-spec bounds_timeout_test() -> ok.
bounds_timeout_test() ->
    with_stream([{ok,board,application,{started}}],fun(P)->
        ?assertError(application_timeout,phi_protocol_repetition:run(P,2,8,123,1000))
    end),
    ?assertError(function_clause,phi_protocol_repetition:run(self(),2,-1,123,1000)),
    ?assertError(function_clause,phi_protocol_repetition:run(self(),2,512,123,1000)),
    ?assertError(function_clause,phi_protocol_repetition:run(self(),2,8,123,0)).

%% Supply only the public stream call protocol; no broker or hardware behavior is mocked as proof.
-spec with_stream([term()],fun((pid())->term())) -> ok.
with_stream(Events,F) ->
    P=spawn_link(fun()->stream(Events,[]) end),
    try F(P),ok after unlink(P),exit(P,kill) end.

%% Deterministic replies let the tests examine the host's command order.
-spec stream([term()],[term()]) -> no_return().
stream(Events,Commands) ->
    receive
        {'$gen_call',From,{submit,Command}}->gen_server:reply(From,{ok,1}),stream(Events,[Command|Commands]);
        {'$gen_call',From,{next,_}}->
            {Reply,Rest}=case Events of []->{timeout,[]};[E|Tail]->{E,Tail} end,
            gen_server:reply(From,Reply),stream(Rest,Commands);
        {'$gen_call',From,commands}->gen_server:reply(From,lists:reverse(Commands)),stream(Events,Commands)
    end.

%% Decoder events carry the same bound endpoint identifier as the production deployment.
-spec event(tuple()) -> tuple().
event(Record) -> {ok,board,decoder_events,Record}.
