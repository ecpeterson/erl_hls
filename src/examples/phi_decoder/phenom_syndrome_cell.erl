%%%% phenom_syndrome_cell.erl
%%%%
%%%% One syndrome cell from a request-paced phenomenological-noise experiment.

-module(phenom_syndrome_cell).
-moduledoc """
A source-aware syndrome cell which supplies noise events to one phi cell.

## Protocol

Configuration starts the first round by casting a `phenom_query` to each of
the four neighboring data cells. Four distinct `phenom_data` responses are
combined by parity. Their quiet bits are ANDed with the syndrome source's own
quiet state, and the completed result is retained in `announcing`.

The paired phi cell sends one `phenom_request` for that completed step. The
request releases the retained detection event and neighborhood quiet
certificate as one `phenom_anyon`, then starts computation of the following
step. The source can therefore compute one result while phi processes the
preceding result, but it cannot run a second step ahead or fill the phi
mailbox with unrequested announcements.

There is deliberately no timer in this actor. Phi requests provide the credit
which advances the one-result lookahead, so the CPU reference process and
generated module associate the same PRNG draw with each step. Configuration
and all protocol messages share the module's one framed input channel; the
five named outputs are separate, backpressured channels in generated hardware.

## Measurement noise

Before participating, the cell must receive a nonzero `xorshift32` seed and a
`u32` threshold. Once the fourth data response arrives, the generator advances
exactly once. A measurement error is present when the new random word is below
the threshold. The announced event is the parity of the data responses, the
current measurement error, and the previous round's measurement error. Thus a
one-round measurement fault appears at both of its temporal boundaries.

The threshold is a runtime message until the generated topology can supply
static per-instance configuration. A host should configure every syndrome
before allowing its paired phi cell to issue the first request.

A `noise_cutoff` names the first quiet step. It is consumed immediately when
received before that step's random decision. At and after the boundary the
measurement contribution is zero and the PRNG no longer advances. The first
quiet announcement can still contain the trailing edge of a preceding
measurement fault.

## Source labels and capacity

Queries label the sender as seen by the recipient: a query sent north names
its source as `south`, and so on. Data responses follow the same convention.
The source mask rejects duplicate or invalid participants, so completion does
not depend on cross-sender arrival order.

The five-slot mailbox can retain four responses for the result being computed
plus an early request for that result. A completed result lives in actor state,
not in the paired phi actor's mailbox.
""".

-include("phi_protocol.hrl").

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
-export([init/1, handle_enter/3, handle_cast/3]).

-define(MAILBOX_CAPACITY, 5).
-define(U16_MASK, 16#ffff).
-define(U32_MASK, 16#ffffffff).

-behavior(hls_statem).
-hls_data(syndrome).
-hls_phases([configuring, collecting, announcing]).
-hls_outputs([north, east, west, south, phi]).
-hls_mailbox_capacity(?MAILBOX_CAPACITY).
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
    noise_disabled = hls_type:zero() :: hls_nums:u32(),
    cutoff_armed = hls_type:zero() :: hls_nums:u32(),
    cutoff_step = hls_type:zero() :: hls_nums:u32()
}).

-type phase() :: configuring | collecting | announcing.
-type directive() :: consume | postpone | fail.
-type conclusion() :: {phase(), #syndrome{}, directive()}.
-type outputs() :: #{
    north := pid(),
    east := pid(),
    west := pid(),
    south := pid(),
    phi := pid()
}.
-type direction() :: north | east | west | south.

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

-doc "Starts and immediately connects the four data ports and phi port.".
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

-doc "Connects a deferred syndrome to its four data cells and paired phi.".
-spec connect(pid(), outputs()) -> ok | {error, already_connected}.
connect(PID, Outputs) ->
    case valid_outputs(Outputs) of
        true -> hls_statem:connect(PID, Outputs);
        false -> error(badarg)
    end.

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

-spec init(any()) -> {ok, phase(), #syndrome{}}.
init([]) ->
    {ok, configuring, #syndrome{}}.

-spec handle_enter(phase(), phase(), #syndrome{}) ->
    hls_statem:enter_result().
handle_enter(_OldPhase, configuring, Syndrome) ->
    {Syndrome, []};
handle_enter(_OldPhase, collecting, Syndrome) ->
    Releasing = Syndrome#syndrome.seen_sources =:= ?PHI_ALL_DIRECTIONS,
    NextStep = case Releasing of
        false -> Syndrome#syndrome.step;
        true -> (Syndrome#syndrome.step + 1) band ?U32_MASK
    end,
    Anyon = #phenom_anyon{
        step = Syndrome#syndrome.step,
        flags = Syndrome#syndrome.announcement bor
            (Syndrome#syndrome.announcement_quiet bsl 1),
        x = Syndrome#syndrome.x,
        y = Syndrome#syndrome.y
    },
    Query = #phenom_query{step = NextStep},
    Cleared = Syndrome#syndrome{
        step = NextStep,
        seen_sources = 0,
        announcement = 0,
        data_quiet = 1,
        announcement_quiet = 0
    },
    {Cleared, [
        {cast_if, Releasing, phi, Anyon},
        {cast, north, Query#phenom_query{source = ?PHI_SOUTH_MASK}},
        {cast, east, Query#phenom_query{source = ?PHI_WEST_MASK}},
        {cast, west, Query#phenom_query{source = ?PHI_EAST_MASK}},
        {cast, south, Query#phenom_query{source = ?PHI_NORTH_MASK}}
    ]};
handle_enter(_OldPhase, announcing, Syndrome) ->
    {Syndrome, []}.

-spec handle_cast(
    #phenom_config{} | #phenom_request{} | #phenom_data{} |
        #noise_cutoff{},
    phase(),
    #syndrome{}
) -> conclusion().
handle_cast(
    #phenom_config{seed = Seed, threshold = Threshold, x = X, y = Y},
    configuring,
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
handle_cast(#phenom_config{}, configuring, Syndrome) ->
    {configuring, Syndrome, fail};
handle_cast(
    #phenom_request{step = Step},
    configuring,
    Syndrome = #syndrome{step = Step}
) ->
    {configuring, Syndrome, postpone};
handle_cast(#phenom_request{}, configuring, Syndrome) ->
    {configuring, Syndrome, fail};
handle_cast(#phenom_data{}, configuring, Syndrome) ->
    {configuring, Syndrome, fail};
handle_cast(#noise_cutoff{}, configuring, Syndrome) ->
    {configuring, Syndrome, fail};

handle_cast(#phenom_config{}, collecting, Syndrome) ->
    {collecting, Syndrome, fail};
handle_cast(
    #noise_cutoff{
        first_quiet_step = FirstQuietStep
    },
    collecting,
    Syndrome = #syndrome{
        step = Step,
        noise_disabled = 0,
        cutoff_armed = 0
    }
) when FirstQuietStep >= Step ->
    {collecting, Syndrome#syndrome{
        cutoff_armed = 1,
        cutoff_step = FirstQuietStep
    }, consume};
handle_cast(#noise_cutoff{}, collecting, Syndrome) ->
    {collecting, Syndrome, fail};
handle_cast(
    #phenom_request{step = Step},
    collecting,
    Syndrome = #syndrome{step = Step}
) ->
    {collecting, Syndrome, postpone};
handle_cast(#phenom_request{}, collecting, Syndrome) ->
    {collecting, Syndrome, fail};
handle_cast(
    #phenom_data{step = Step, source = Source, flags = Flags},
    collecting,
    Syndrome = #syndrome{
        step = Step,
        seen_sources = Seen,
        data_parity = Parity,
        previous_measurement = PreviousMeasurement,
        random_state = RandomState,
        threshold = Threshold
    }
) when (Source =:= ?PHI_NORTH_MASK orelse
        Source =:= ?PHI_EAST_MASK orelse
        Source =:= ?PHI_WEST_MASK orelse
        Source =:= ?PHI_SOUTH_MASK),
       Seen band Source =:= 0,
       Flags < 4 ->
    Present = Flags band ?PHENOM_PRESENT_MASK,
    Quiet = (Flags band ?PHENOM_QUIET_MASK) bsr 1,
    NewSeen = Seen bor Source,
    NewParity = Parity bxor Present,
    NewDataQuiet = Syndrome#syndrome.data_quiet band Quiet,
    case NewSeen =:= ?PHI_ALL_DIRECTIONS of
        false ->
            Collected = Syndrome#syndrome{
                seen_sources = NewSeen,
                data_parity = NewParity,
                data_quiet = NewDataQuiet
            },
            {collecting, Collected, consume};
        true ->
            CutoffApplies = Syndrome#syndrome.cutoff_armed =:= 1 andalso
                Step >= Syndrome#syndrome.cutoff_step,
            NoiseDisabled = Syndrome#syndrome.noise_disabled =:= 1 orelse
                CutoffApplies,
            NoiseDisabledWord = case NoiseDisabled of
                false -> hls_type:as(hls_nums:u32(), 0);
                true -> hls_type:as(hls_nums:u32(), 1)
            end,
            NextRandom = case NoiseDisabled of
                true -> RandomState;
                false -> hls_prng:xorshift32(RandomState)
            end,
            Measurement = case NoiseDisabled of
                true -> hls_type:as(hls_nums:u32(), 0);
                false -> case NextRandom < Threshold of
                    false -> hls_type:as(hls_nums:u32(), 0);
                    true -> hls_type:as(hls_nums:u32(), 1)
                end
            end,
            Detection = NewParity bxor Measurement bxor PreviousMeasurement,
            Complete = Syndrome#syndrome{
                seen_sources = NewSeen,
                data_parity = NewParity,
                previous_measurement = Measurement,
                announcement = Detection,
                data_quiet = NewDataQuiet,
                announcement_quiet = NewDataQuiet band NoiseDisabledWord,
                random_state = NextRandom,
                noise_disabled = NoiseDisabledWord,
                cutoff_armed = case CutoffApplies of
                    false -> Syndrome#syndrome.cutoff_armed;
                    true -> hls_type:as(hls_nums:u32(), 0)
                end
            },
            {announcing, Complete, consume}
    end;
handle_cast(#phenom_data{}, collecting, Syndrome) ->
    {collecting, Syndrome, fail};

handle_cast(#phenom_config{}, announcing, Syndrome) ->
    {announcing, Syndrome, fail};
handle_cast(
    #noise_cutoff{
        first_quiet_step = FirstQuietStep
    },
    announcing,
    Syndrome = #syndrome{
        step = Step,
        noise_disabled = 0,
        cutoff_armed = 0
    }
) when FirstQuietStep > Step ->
    {announcing, Syndrome#syndrome{
        cutoff_armed = 1,
        cutoff_step = FirstQuietStep
    }, consume};
handle_cast(#noise_cutoff{}, announcing, Syndrome) ->
    {announcing, Syndrome, fail};
handle_cast(
    #phenom_request{step = Step},
    announcing,
    Syndrome = #syndrome{step = Step}
) ->
    Collecting = Syndrome#syndrome{
        data_parity = 0
    },
    {collecting, Collecting, consume};
handle_cast(#phenom_request{}, announcing, Syndrome) ->
    {announcing, Syndrome, fail};
handle_cast(
    #phenom_data{step = NextStep},
    announcing,
    Syndrome = #syndrome{step = Step}
) when NextStep =:= ((Step + 1) band ?U32_MASK) ->
    {announcing, Syndrome, postpone};
handle_cast(#phenom_data{}, announcing, Syndrome) ->
    {announcing, Syndrome, fail}.

source_mask(north) -> ?PHI_NORTH_MASK;
source_mask(east) -> ?PHI_EAST_MASK;
source_mask(west) -> ?PHI_WEST_MASK;
source_mask(south) -> ?PHI_SOUTH_MASK;
source_mask(_Direction) -> error(badarg).

valid_outputs(Outputs) ->
    is_map(Outputs) andalso
        lists:sort(maps:keys(Outputs)) =:=
            lists:sort([north, east, west, south, phi]) andalso
        lists:all(fun is_pid/1, maps:values(Outputs)).
