-module(phenom_pipeline_tests).

-include_lib("eunit/include/eunit.hrl").
-include("phi_protocol.hrl").

-define(PRNG_SEED, 16#6d2b79f5).
-define(HALF_THRESHOLD, 16#80000000).
-define(SYNDROME_X, 7).
-define(SYNDROME_Y, 11).

closed_noise_pipeline_advances_phi_test() ->
    {ok, Data} = phenom_data_cell:start_link(),
    {ok, Syndrome} = phenom_syndrome_cell:start_link(),
    {ok, Phi} = phi_halo_cell:start_link(),
    Parent = self(),
    AnyonTap = spawn_link(fun() -> forward_anyons(Parent, Phi) end),
    CorrectionSink = spawn_link(fun discard_casts/0),
    try
        ok = phenom_data_cell:connect(Data, four_ports(Syndrome)),
        ok = phenom_syndrome_cell:connect(Syndrome,
            (four_ports(Data))#{phi => AnyonTap}),
        ok = phenom_data_cell:configure(
            Data,
            ?PRNG_SEED,
            ?HALF_THRESHOLD
        ),
        ok = phenom_syndrome_cell:configure(
            Syndrome,
            ?PRNG_SEED,
            ?HALF_THRESHOLD,
            ?SYNDROME_X,
            ?SYNDROME_Y
        ),
        await_phase(phenom_data_cell, Data, collecting),
        await_phase(phenom_syndrome_cell, Syndrome, waiting),

        %% A one-cell periodic decoder is enough to exercise the complete
        %% pacing path. Its four logical edges share a PID but retain distinct
        %% port identities in their messages.
        PhiOutputs = (four_ports(Phi))#{
            syndrome => Syndrome,
            correction => CorrectionSink
        },
        ok = phi_halo_cell:connect(Phi, PhiOutputs),
        ok = phi_halo_cell:configure(Phi, ?PRNG_SEED),

        %% The data event is reported on four edges and cancels by parity in
        %% this degenerate topology. The syndrome PRNG's first measurement
        %% fault, and then its falling edge, therefore produce these two
        %% consecutive detection events.
        expect_anyon(0, 1, ?SYNDROME_X, ?SYNDROME_Y),
        expect_anyon(1, 1, ?SYNDROME_X, ?SYNDROME_Y),
        await_step(Phi, 1),

        DataInfo = phenom_data_cell:runtime_info(Data),
        SyndromeInfo = phenom_syndrome_cell:runtime_info(Syndrome),
        ?assertNotEqual(?PRNG_SEED,
            element(6, maps:get(data, DataInfo))),
        ?assertNotEqual(?PRNG_SEED,
            element(7, maps:get(data, SyndromeInfo)))
    after
        stop_if_alive(phi_halo_cell, Phi),
        stop_if_alive(phenom_syndrome_cell, Syndrome),
        stop_if_alive(phenom_data_cell, Data),
        AnyonTap ! stop,
        CorrectionSink ! stop
    end.

odd_data_error_reaches_phi_test() ->
    Directions = [north, east, west, south],
    Data = maps:from_list([
        {Direction, begin
            {ok, PID} = phenom_data_cell:start_link(),
            PID
        end}
        || Direction <- Directions
    ]),
    {ok, Syndrome} = phenom_syndrome_cell:start_link(),
    {ok, Phi} = phi_halo_cell:start_link(),
    Sink = spawn_link(fun discard_casts/0),
    Parent = self(),
    AnyonTap = spawn_link(fun() -> forward_anyons(Parent, Phi) end),
    try
        maps:foreach(
            fun(Direction, PID) ->
                ReturnPort = opposite(Direction),
                Outputs = (four_ports(Sink))#{ReturnPort => Syndrome},
                ok = phenom_data_cell:connect(PID, Outputs),
                Threshold = case Direction of
                    north -> ?HALF_THRESHOLD;
                    _ -> 0
                end,
                ok = phenom_data_cell:configure(
                    PID,
                    ?PRNG_SEED,
                    Threshold
                )
            end,
            Data
        ),
        ok = phenom_syndrome_cell:connect(
            Syndrome,
            Data#{phi => AnyonTap}
        ),
        ok = phenom_syndrome_cell:configure(
            Syndrome,
            ?PRNG_SEED,
            0,
            ?SYNDROME_X,
            ?SYNDROME_Y
        ),
        maps:foreach(
            fun(_Direction, PID) ->
                await_phase(phenom_data_cell, PID, collecting)
            end,
            Data
        ),
        await_phase(phenom_syndrome_cell, Syndrome, waiting),
        ok = phi_halo_cell:connect(
            Phi,
            (four_ports(Sink))#{syndrome => Syndrome, correction => Sink}
        ),
        ok = phi_halo_cell:configure(Phi, ?PRNG_SEED),

        %% The paired syndrome supplies one query to each data cell. Stand-in
        %% neighboring syndromes supply the other three edge identities. Only
        %% the north data cell samples an error, and only the output edge back
        %% to this syndrome is connected to it, so the four-way parity is odd.
        maps:foreach(
            fun(Direction, PID) ->
                TargetSource = opposite(Direction),
                lists:foreach(
                    fun(Source) ->
                        ok = phenom_data_cell:offer_query(PID, 0, Source)
                    end,
                    Directions -- [TargetSource]
                )
            end,
            Data
        ),
        expect_anyon(0, 1, ?SYNDROME_X, ?SYNDROME_Y),
        await_phase(phi_halo_cell, Phi, gathering),
        #{data := PhiData} = phi_halo_cell:runtime_info(Phi),
        ?assertEqual(1, element(11, PhiData))
    after
        stop_if_alive(phi_halo_cell, Phi),
        stop_if_alive(phenom_syndrome_cell, Syndrome),
        maps:foreach(
            fun(_Direction, PID) ->
                stop_if_alive(phenom_data_cell, PID)
            end,
            Data
        ),
        AnyonTap ! stop,
        Sink ! stop
    end.

four_ports(PID) ->
    #{north => PID, east => PID, west => PID, south => PID}.

opposite(north) -> south;
opposite(east) -> west;
opposite(west) -> east;
opposite(south) -> north.

discard_casts() ->
    receive
        {'$gen_cast', _Message} -> discard_casts();
        stop -> ok
    end.

forward_anyons(Parent, Phi) ->
    receive
        {'$gen_cast', Message = #phenom_anyon{}} ->
            Parent ! {phenom_pipeline, Message},
            hls_statem:cast(Phi, Message),
            forward_anyons(Parent, Phi);
        stop ->
            ok
    end.

expect_anyon(Step, Present, X, Y) ->
    receive
        {phenom_pipeline, #phenom_anyon{
                step = Step,
                present = Present,
                x = X,
                y = Y
            }} ->
            ok
    after 2000 ->
        error({missing_phenom_anyon, Step, Present, X, Y})
    end.

await_phase(Module, PID, Phase) ->
    await(
        fun() ->
            case Module:runtime_info(PID) of
                #{phase := Phase} -> true;
                _ -> false
            end
        end,
        {phase, Module, Phase}
    ).

await_step(PID, Minimum) ->
    await(
        fun() ->
            #{data := Data} = phi_halo_cell:runtime_info(PID),
            element(2, Data) >= Minimum
        end,
        {phi_step, Minimum}
    ).

await(Predicate, Failure) ->
    await(Predicate, Failure, 200).

await(_Predicate, Failure, 0) ->
    error({timeout, Failure});
await(Predicate, Failure, Attempts) ->
    case Predicate() of
        true -> ok;
        false ->
            timer:sleep(5),
            await(Predicate, Failure, Attempts - 1)
    end.

stop_if_alive(Module, PID) ->
    case is_process_alive(PID) of
        true -> Module:stop(PID);
        false -> ok
    end.
