-module(phi_protocol_repetition).
-moduledoc "Finite repetition-code demonstration through an attached source-protocol application stream. Corrections return through the same ordered control lane as setup and final readout.".
-export([run/5]).

-doc "Configures a finite noise cutoff, starts the bound line, feeds back corrections, then queries all data cells after a common quiet-empty status fence. Returns per-source events, corrections and readout. The caller supplies a fresh explicit-start deployment of the specified width, sufficient command capacity and the matching source codecs. Timeout, queue rejection or malformed events abort without replay; reset the whole activation before retrying. This finite run does not establish convergence or live-device performance.".
-spec run(pid(), pos_integer(), non_neg_integer(), non_neg_integer(), pos_integer()) -> map().
run(Stream, Width, Cutoff, Request, Timeout)
        when Width >= 2, Width =< 65535, Cutoff >= 0, Cutoff < 512,
             Request >= 0, Request < (1 bsl 32), Timeout > 0 ->
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    send(Stream, noise, {0,0,Width-1,0}, {noise_cutoff,Cutoff}),
    {ok,1} = hls_partition_stream:submit(Stream,start),
    {ok,_,application,{started}} = next(Stream,Deadline),
    {Fence, Events, Corrections} = collect(Stream,Width,#{},[],[],Deadline),
    send(Stream,data,{0,0,Width-1,0},{pauli_query,Request,x}),
    Replies = replies(Stream,Width,Request,#{},Deadline),
    #{fence=>Fence,events=>lists:reverse(Events),corrections=>lists:reverse(Corrections),
      replies=>lists:sort(maps:to_list(Replies)),cutoff=>Cutoff,request=>Request,basis=>x}.

%% Same-sender correction-before-status ordering supplies the common-step fence.
-spec collect(pid(), pos_integer(), map(), [list()], [list()], integer()) -> {non_neg_integer(),[list()],[list()]}.
collect(Stream,Width,Rounds,Events,Corrections,Deadline) ->
    case next(Stream,Deadline) of
        {ok,_,decoder_events,C={phi_correction,Step,X,0,Direction}} when X >= 0, X < Width, Step >= 0, Step < 512 ->
            {{DX,0},Pauli} = phi_repetition_topology:correction_update(C,Width),
            send(Stream,data,{DX,0,DX,0},{pauli_update,Pauli}),
            collect(Stream,Width,Rounds,[[X,0,Step,phi_correction,Direction]|Events],
                [[X,0,Step,Direction,DX]|Corrections],Deadline);
        {ok,_,decoder_events,{phi_status,Step,X,0,Flags}} when X >= 0, X < Width, Step >= 0, Step < 512, Flags >= 0, Flags =< 3 ->
            Round = maps:get(Step,Rounds,#{}),
            false = maps:is_key(X,Round),
            Updated = Round#{X=>Flags},
            NewEvents = [[X,0,Step,phi_status,Flags]|Events],
            case map_size(Updated) =:= Width andalso lists:all(fun(F)->F=:=2 end,maps:values(Updated)) of
                true -> {Step,NewEvents,Corrections};
                false -> collect(Stream,Width,Rounds#{Step=>Updated},NewEvents,Corrections,Deadline)
            end;
        Other -> error({unexpected_application_event,Other})
    end.

%% The ordered query follows all corrections admitted before the quiet fence.
-spec replies(pid(), pos_integer(), non_neg_integer(), map(), integer()) -> map().
replies(_Stream,Width,_Request,Replies,_Deadline) when map_size(Replies) =:= Width -> Replies;
replies(Stream,Width,Request,Replies,Deadline) ->
    case next(Stream,Deadline) of
        {ok,_,data_measurements,{pauli_reply,Request,X,0,Bit}} when X >= 0, X < Width, Bit >= 0, Bit =< 1 ->
            false = maps:is_key(X,Replies),
            replies(Stream,Width,Request,Replies#{X=>Bit},Deadline);
        {ok,_,decoder_events,{phi_status,Step,X,0,2}} when Step >= 0, Step < 512, X >= 0, X < Width ->
            replies(Stream,Width,Request,Replies,Deadline);
        Other -> error({late_application_event,Other})
    end.

%% Queue rejection is explicit and never retries a partially completed activation.
-spec send(pid(), atom(), tuple(), tuple()) -> ok.
send(Stream,Target,Bounds,Message) ->
    {ok,1} = hls_partition_stream:submit(Stream,{control_router,Target,Bounds,Message}),ok.

%% One absolute deadline covers setup, activation, feedback and final readout.
-spec next(pid(), integer()) -> term().
next(Stream,Deadline) ->
    Remaining = Deadline-erlang:monotonic_time(millisecond),
    case Remaining > 0 of
        true -> case hls_partition_stream:next(Stream,Remaining) of timeout -> error(application_timeout); Event -> Event end;
        false -> error(application_timeout)
    end.
