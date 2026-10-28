-module(phi_protocol_repetition).
-moduledoc """
Finite host repetition-code loop used by source-protocol application, networked-deployment and mixed-runtime witnesses. The caller attaches a matching typed stream; this module feeds corrections back through its ordered control lane and finishes with bounded readout. Source construction, stream lifecycle and hardware programming remain outside this loop.
""".
%% Finite host correction and readout loop.
-export([run/5, run/6]).

%% One application loop uses either typed transport API without another process or queue.
-type stream() :: {hls_partition_stream | hls_protocol_stream | hls_protocol_mixed_stream, pid()}.

-doc "Configures a finite noise cutoff, starts the bound line, feeds back corrections, then queries all data cells after a common quiet-empty status fence. Returns per-source events, corrections and readout. The caller supplies a fresh explicit-start deployment of the specified width, sufficient command capacity and the matching source codecs. Timeout, queue rejection or malformed events abort without replay; reset the whole activation before retrying. This finite run does not establish convergence or live-device performance.".
-spec run(pid(), pos_integer(), non_neg_integer(), non_neg_integer(), pos_integer()) -> map().
run(Stream, Width, Cutoff, Request, Timeout) ->
    run(hls_partition_stream, Stream, Width, Cutoff, Request, Timeout).

-doc "Runs the same finite correction/readout loop through hls_partition_stream, a typed hls_protocol_stream deployment, or hls_protocol_mixed_stream. Transport selection changes attachment and placement, not application semantics. The caller starts and retires the matching stream; run/5 supplies the single-gateway API by default.".
-spec run(
    hls_partition_stream | hls_protocol_stream | hls_protocol_mixed_stream,
    pid(),
    pos_integer(),
    non_neg_integer(),
    non_neg_integer(),
    pos_integer()
) -> map().
run(Module, Pid, Width, Cutoff, Request, Timeout) when
    (Module =:= hls_partition_stream orelse Module =:= hls_protocol_stream orelse
        Module =:= hls_protocol_mixed_stream),
    Width >= 2,
    Width =< 65535,
    Cutoff >= 0,
    Cutoff < 512,
    Request >= 0,
    Request < (1 bsl 32),
    Timeout > 0
->
    Stream = {Module, Pid},
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    send(Stream, noise, {0, 0, Width - 1, 0}, {noise_cutoff, Cutoff}),
    {ok, 1} = Module:submit(Pid, start),
    {ok, _, application, {started}} = next(Stream, Deadline),
    {Fence, Events, Corrections} = collect(Stream, Width, #{}, [], [], Deadline),
    send(Stream, data, {0, 0, Width - 1, 0}, {pauli_query, Request, x}),
    Replies = replies(Stream, Width, Request, #{}, Deadline),
    #{
        fence => Fence,
        events => lists:reverse(Events),
        corrections => lists:reverse(Corrections),
        replies => lists:sort(maps:to_list(Replies)),
        cutoff => Cutoff,
        request => Request,
        basis => x
    }.

%% Same-sender correction-before-status ordering supplies the common-step fence.
-spec collect(stream(), pos_integer(), map(), [list()], [list()], integer()) ->
    {non_neg_integer(), [list()], [list()]}.
collect(Stream, Width, Rounds, Events, Corrections, Deadline) ->
    case next(Stream, Deadline) of
        {ok, _, decoder_events, C = {phi_correction, Step, X, 0, Direction}} when
            X >= 0, X < Width, Step >= 0, Step < 512
        ->
            {{DX, 0}, Pauli} = phi_repetition_topology:correction_update(C, Width),
            send(Stream, data, {DX, 0, DX, 0}, {pauli_update, Pauli}),
            collect(
                Stream,
                Width,
                Rounds,
                [[X, 0, Step, phi_correction, Direction] | Events],
                [[X, 0, Step, Direction, DX] | Corrections],
                Deadline
            );
        {ok, _, decoder_events, {phi_status, Step, X, 0, Flags}} when
            X >= 0, X < Width, Step >= 0, Step < 512, Flags >= 0, Flags =< 3
        ->
            Round = maps:get(Step, Rounds, #{}),
            false = maps:is_key(X, Round),
            Updated = Round#{X => Flags},
            NewEvents = [[X, 0, Step, phi_status, Flags] | Events],
            case
                map_size(Updated) =:= Width andalso
                    lists:all(fun(F) -> F =:= 2 end, maps:values(Updated))
            of
                true ->
                    {Step, NewEvents, Corrections};
                false ->
                    collect(
                        Stream, Width, Rounds#{Step => Updated}, NewEvents, Corrections, Deadline
                    )
            end;
        Other ->
            error({unexpected_application_event, Other})
    end.

%% The ordered query follows all corrections admitted before the quiet fence.
-spec replies(stream(), pos_integer(), non_neg_integer(), map(), integer()) -> map().
replies(_Stream, Width, _Request, Replies, _Deadline) when map_size(Replies) =:= Width -> Replies;
replies(Stream, Width, Request, Replies, Deadline) ->
    case next(Stream, Deadline) of
        {ok, _, data_measurements, {pauli_reply, Request, X, 0, Bit}} when
            X >= 0, X < Width, Bit >= 0, Bit =< 1
        ->
            false = maps:is_key(X, Replies),
            replies(Stream, Width, Request, Replies#{X => Bit}, Deadline);
        {ok, _, decoder_events, {phi_status, Step, X, 0, 2}} when
            Step >= 0, Step < 512, X >= 0, X < Width
        ->
            replies(Stream, Width, Request, Replies, Deadline);
        Other ->
            error({late_application_event, Other})
    end.

%% Queue rejection is explicit and never retries a partially completed activation.
-spec send(stream(), atom(), tuple(), tuple()) -> ok.
send({Module, Pid}, Target, Bounds, Message) ->
    {ok, 1} = Module:submit(Pid, {control_router, Target, Bounds, Message}),
    ok.

%% One absolute deadline covers setup, activation, feedback and final readout.
-spec next(stream(), integer()) -> term().
next({Module, Pid}, Deadline) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    case Remaining > 0 of
        true ->
            case Module:next(Pid, Remaining) of
                timeout -> error(application_timeout);
                Event -> Event
            end;
        false ->
            error(application_timeout)
    end.
