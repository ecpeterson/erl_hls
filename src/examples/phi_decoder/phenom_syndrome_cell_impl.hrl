%% Shared callbacks for the grid and line wrappers; geometry is compile-time.
-include("phi_protocol.hrl").
-include("phi_neighborhood.hrl").

-export([
    start_link/0,
    start_link/1,
    connect/2,
    stop/1,
    configure/3,
    configure/5,
    noise_cutoff/2,
    offer_request/2,
    offer_data/4,
    runtime_info/1
]).
-export([configuring/3, collecting/3, announcing/3, init/1]).

-define(MAILBOX_CAPACITY, (?NEIGHBOR_COUNT + 1)).
-define(U16_MASK, 16#ffff).
-define(U32_MASK, 16#ffffffff).

-behavior(hls_statem).
-hls_data(syndrome).
-hls_phases([configuring, collecting, announcing]).
-ifdef(PHI_REPETITION).
-hls_outputs([east, west, phi]).
-else.
-hls_outputs([north, east, west, south, phi]).
-endif.
-ifdef(PHI_REPETITION).
-hls_mailbox_capacity(3).
-else.
-hls_mailbox_capacity(5).
-endif.
-compile({parse_transform, hls_pack}).

-record(syndrome, {
    step = hls_type:zero() :: hls_nums:u32(),
    seen_sources = hls_type:zero() :: hls_nums:u32(),
    data_parity = hls_type:zero() :: hls_nums:u32(),
    previous_measurement = hls_type:zero() :: hls_nums:u32(),
    announcement = hls_type:zero() :: hls_nums:u32(),
    data_quiet = hls_type:zero() :: hls_nums:u32(),
    announcement_quiet = hls_type:zero() :: hls_nums:u32(),
    random_state = hls_type:zero() :: hls_nums:u32(),
    threshold = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16(),
    noise_disabled = hls_type:zero() :: hls_bool:bool(),
    cutoff_armed = hls_type:zero() :: hls_bool:bool(),
    cutoff_step = hls_type:zero() :: hls_nums:u32()
}).

%% Named protocol barriers; state entry emits each barrier's actions.
-type phase() :: configuring | collecting | announcing.
-ifdef(PHI_REPETITION).
%% Required connections for the two-neighbor protocol.
-type outputs() :: #{
    east := pid(), west := pid(),
    phi := pid()
}.
-else.
%% Required connections for the four-neighbor protocol.
-type outputs() :: #{
    north := pid(), east := pid(), west := pid(), south := pid(),
    phi := pid()
}.
-endif.
%% Direction names are the actor's physically present ports.
-type direction() :: ?NEIGHBOR_TYPE.

%%%
%%% CPU interface
%%%

-doc "Starts a syndrome whose output ports will be connected later.".
-spec start_link() -> {ok, pid()}.
start_link() ->
    hls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, ?MAILBOX_CAPACITY}]
    ).

-doc "Starts and immediately connects the data ports and phi port.".
-spec start_link(outputs()) -> {ok, pid()}.
start_link(Outputs) ->
    case valid_outputs(Outputs) of
        true ->
            Options = [
                {mailbox_capacity, ?MAILBOX_CAPACITY},
                {outputs, Outputs}
            ],
            hls_statem:start_link(?MODULE, [], Options);
        false ->
            error(badarg)
    end.

-doc "Connects a deferred syndrome to its data neighbors and paired phi.".
-spec connect(pid(), outputs()) -> ok | {error, already_connected}.
connect(PID, Outputs) ->
    case valid_outputs(Outputs) of
        true -> hls_statem:connect(PID, Outputs);
        false -> error(badarg)
    end.

-doc "Stops the CPU actor and releases its scheduler.".
-spec stop(pid()) -> ok.
stop(PID) ->
    hls_statem:stop(PID).

-doc "Configures a nonzero PRNG seed and `u32` error threshold.".
-spec configure(pid(), hls_nums:u32(), hls_nums:u32()) -> ok.
configure(PID, Seed, Threshold) ->
    configure(PID, Seed, Threshold, 0, 0).

-doc "Configures the PRNG, error threshold, and lattice coordinate.".
-spec configure(
    pid(),
    hls_nums:u32(),
    hls_nums:u32(),
    hls_nums:u16(),
    hls_nums:u16()
) -> ok.
configure(PID, Seed, Threshold, X, Y)
        when Seed > 0, Seed =< ?U32_MASK,
             Threshold >= 0, Threshold =< ?U32_MASK,
             X >= 0, X =< ?U16_MASK,
             Y >= 0, Y =< ?U16_MASK ->
    hls_statem:cast(PID, #phenom_config{
        seed = Seed,
        threshold = Threshold,
        x = X,
        y = Y
    });
configure(_PID, _Seed, _Threshold, _X, _Y) ->
    error(badarg).

-doc "Arms the first round which must inject no new measurement noise.".
-spec noise_cutoff(pid(), hls_nums:u32()) -> ok.
noise_cutoff(PID, FirstQuietStep)
        when FirstQuietStep >= 0, FirstQuietStep =< ?U32_MASK ->
    hls_statem:cast(PID, #noise_cutoff{
        first_quiet_step = FirstQuietStep
    });
noise_cutoff(_PID, _FirstQuietStep) ->
    error(badarg).

-doc "Releases one computed result and permits computation of the next.".
-spec offer_request(pid(), hls_nums:u32()) -> ok.
offer_request(PID, Step)
        when Step >= 0, Step =< ?U32_MASK ->
    hls_statem:cast(PID, #phenom_request{step = Step});
offer_request(_PID, _Step) ->
    error(badarg).

-doc "Offers one Boolean data event from a named neighboring edge.".
-spec offer_data(pid(), hls_nums:u32(), direction(), boolean()) -> ok.
offer_data(PID, Step, Source, Present)
        when Step >= 0, Step =< ?U32_MASK ->
    SourceMask = source_mask(Source),
    PresentWord = case Present of
        false -> 0;
        true -> 1
    end,
    hls_statem:cast(PID, #phenom_data{
        step = Step,
        source = SourceMask,
        flags = PresentWord
    }).

-doc "Returns scheduler diagnostics and the syndrome's current data.".
-spec runtime_info(pid()) -> map().
runtime_info(PID) ->
    hls_statem:info(PID).

%%%
%%% hls_statem callbacks
%%%

-doc "Returns the unconfigured actor state; no protocol traffic is emitted.".
-spec init(any()) -> {ok, phase(), #syndrome{}}.
init([]) ->
    {ok, configuring, #syndrome{}}.

-doc "Accepts one valid configuration before beginning the request-paced protocol.".
-spec configuring(enter, phase(), #syndrome{}) ->
    hls_statem:enter_result(#syndrome{});
    (cast,
        #phenom_config{} | #phenom_request{} | #phenom_data{} |
            #noise_cutoff{},
        #syndrome{}) -> hls_statem:cast_result(phase(), #syndrome{}).
configuring(enter, _OldPhase, Syndrome) ->
    {Syndrome, []};
configuring(
    cast,
    #phenom_config{seed = Seed, threshold = Threshold, x = X, y = Y},
    Syndrome
) when Seed > 0, Seed =< ?U32_MASK,
       Threshold >= 0, Threshold =< ?U32_MASK,
       X >= 0, X =< ?U16_MASK,
       Y >= 0, Y =< ?U16_MASK ->
    Configured = Syndrome#syndrome{
        seen_sources = 0,
        data_parity = 0,
        announcement = 0,
        data_quiet = 1,
        announcement_quiet = 0,
        random_state = Seed,
        threshold = Threshold,
        x = X,
        y = Y
    },
    {collecting, Configured, consume};
configuring(cast, #phenom_config{}, Syndrome) ->
    {configuring, Syndrome, fail};
configuring(
    cast,
    #phenom_request{step = Step},
    Syndrome = #syndrome{step = Step}
) ->
    {configuring, Syndrome, postpone};
configuring(cast, #phenom_request{}, Syndrome) ->
    {configuring, Syndrome, fail};
configuring(cast, #phenom_data{}, Syndrome) ->
    {configuring, Syndrome, fail};
configuring(cast, #noise_cutoff{}, Syndrome) ->
    {configuring, Syndrome, fail}.

-doc "Collects directional data and computes one detection event with measurement noise.".
-spec collecting(enter, phase(), #syndrome{}) ->
    hls_statem:enter_result(#syndrome{});
    (cast,
        #phenom_config{} | #phenom_request{} | #phenom_data{} |
            #noise_cutoff{},
        #syndrome{}) -> hls_statem:cast_result(phase(), #syndrome{}).
collecting(enter, _OldPhase, Syndrome) ->
    {NextStep, Announcements} = case Syndrome#syndrome.seen_sources of
        ?NEIGHBOR_MASK ->
            {(Syndrome#syndrome.step + 1) band ?U32_MASK,
                [{cast, phi, #phenom_anyon{
                    step = Syndrome#syndrome.step,
                    flags = Syndrome#syndrome.announcement bor
                        (Syndrome#syndrome.announcement_quiet bsl 1),
                    x = Syndrome#syndrome.x,
                    y = Syndrome#syndrome.y
                }}]};
        _ -> {Syndrome#syndrome.step, []}
    end,
    Query = #phenom_query{step = NextStep},
    Cleared = Syndrome#syndrome{
        step = NextStep,
        seen_sources = 0,
        announcement = 0,
        data_quiet = 1,
        announcement_quiet = 0
    },
    {Cleared, Announcements ++ ?NEIGHBOR_ACTIONS(
        {cast, north, Query#phenom_query{source = ?PHI_SOUTH_MASK}},
        {cast, east, Query#phenom_query{source = ?PHI_WEST_MASK}},
        {cast, west, Query#phenom_query{source = ?PHI_EAST_MASK}},
        {cast, south, Query#phenom_query{source = ?PHI_NORTH_MASK}})};
collecting(cast, #phenom_config{}, Syndrome) ->
    {collecting, Syndrome, fail};
collecting(
    cast,
    #noise_cutoff{
        first_quiet_step = FirstQuietStep
    },
    Syndrome = #syndrome{
        step = Step,
        noise_disabled = false,
        cutoff_armed = false
    }
) when FirstQuietStep >= Step ->
    {collecting, Syndrome#syndrome{
        cutoff_armed = true,
        cutoff_step = FirstQuietStep
    }, consume};
collecting(cast, #noise_cutoff{}, Syndrome) ->
    {collecting, Syndrome, fail};
collecting(
    cast,
    #phenom_request{step = Step},
    Syndrome = #syndrome{step = Step}
) ->
    {collecting, Syndrome, postpone};
collecting(cast, #phenom_request{}, Syndrome) ->
    {collecting, Syndrome, fail};
collecting(
    cast,
    #phenom_data{step = Step, source = Source, flags = Flags},
    Syndrome = #syndrome{
        step = Step,
        seen_sources = Seen,
        data_parity = Parity,
        previous_measurement = PreviousMeasurement,
        random_state = RandomState,
        threshold = Threshold
    }
) when ?SOURCE_VALID(Source),
       Seen band Source =:= 0,
       Flags < 4 ->
    Present = Flags band ?PHENOM_PRESENT_MASK,
    Quiet = (Flags band ?PHENOM_QUIET_MASK) bsr 1,
    NewSeen = Seen bor Source,
    NewParity = Parity bxor Present,
    NewDataQuiet = Syndrome#syndrome.data_quiet band Quiet,
    Collected = Syndrome#syndrome{
        seen_sources = NewSeen,
        data_parity = NewParity,
        data_quiet = NewDataQuiet
    },
    {NextPhase, NextSyndrome} = case NewSeen =:= ?NEIGHBOR_MASK of
        false -> {collecting, Collected};
        true ->
            CutoffApplies = Syndrome#syndrome.cutoff_armed andalso
                Step >= Syndrome#syndrome.cutoff_step,
            NoiseDisabled = Syndrome#syndrome.noise_disabled orelse
                CutoffApplies,
            {NextRandom, Measurement} = case NoiseDisabled of
                true -> {RandomState, 0};
                false ->
                    Sample = hls_prng:xorshift32(RandomState),
                    Hit = if
                        Sample < Threshold -> 1;
                        true -> 0
                    end,
                    {Sample, Hit}
            end,
            Detection = NewParity bxor Measurement bxor PreviousMeasurement,
            Complete = Collected#syndrome{
                previous_measurement = Measurement,
                announcement = Detection,
                announcement_quiet = case NoiseDisabled of
                    true -> NewDataQuiet;
                    false -> 0
                end,
                random_state = NextRandom,
                noise_disabled = NoiseDisabled,
                cutoff_armed = Syndrome#syndrome.cutoff_armed andalso not CutoffApplies
            },
            {announcing, Complete}
    end,
    {NextPhase, NextSyndrome, consume};
collecting(cast, #phenom_data{}, Syndrome) ->
    {collecting, Syndrome, fail}.

-doc "Retains a completed detection event until its matching phi request arrives.".
-spec announcing(enter, phase(), #syndrome{}) ->
    hls_statem:enter_result(#syndrome{});
    (cast,
        #phenom_config{} | #phenom_request{} | #phenom_data{} |
            #noise_cutoff{},
        #syndrome{}) -> hls_statem:cast_result(phase(), #syndrome{}).
announcing(enter, _OldPhase, Syndrome) ->
    {Syndrome, []};
announcing(cast, #phenom_config{}, Syndrome) ->
    {announcing, Syndrome, fail};
announcing(
    cast,
    #noise_cutoff{
        first_quiet_step = FirstQuietStep
    },
    Syndrome = #syndrome{
        step = Step,
        noise_disabled = false,
        cutoff_armed = false
    }
) when FirstQuietStep > Step ->
    {announcing, Syndrome#syndrome{
        cutoff_armed = true,
        cutoff_step = FirstQuietStep
    }, consume};
announcing(cast, #noise_cutoff{}, Syndrome) ->
    {announcing, Syndrome, fail};
announcing(
    cast,
    #phenom_request{step = Step},
    Syndrome = #syndrome{step = Step}
) ->
    Collecting = Syndrome#syndrome{
        data_parity = 0
    },
    {collecting, Collecting, consume};
announcing(cast, #phenom_request{}, Syndrome) ->
    {announcing, Syndrome, fail};
announcing(
    cast,
    #phenom_data{step = NextStep},
    Syndrome = #syndrome{step = Step}
) when NextStep =:= ((Step + 1) band ?U32_MASK) ->
    {announcing, Syndrome, postpone};
announcing(cast, #phenom_data{}, Syndrome) ->
    {announcing, Syndrome, fail}.

%% Reject names absent from this specialization before admitting a CPU message.
-spec source_mask(direction()) -> hls_nums:u32().
source_mask(Direction) ->
    Mask = case Direction of
        north -> ?PHI_NORTH_MASK;
        east -> ?PHI_EAST_MASK;
        west -> ?PHI_WEST_MASK;
        south -> ?PHI_SOUTH_MASK;
        _ -> error(badarg)
    end,
    case Mask band ?NEIGHBOR_MASK of
        Mask -> Mask;
        _ -> error(badarg)
    end.

%% Require exactly the specialization's named output PIDs.
-spec valid_outputs(map()) -> boolean().
valid_outputs(Outputs) ->
    is_map(Outputs) andalso
        lists:sort(maps:keys(Outputs)) =:=
            lists:sort(?NEIGHBOR_PORTS ++ [phi]) andalso
        lists:all(fun is_pid/1, maps:values(Outputs)).
