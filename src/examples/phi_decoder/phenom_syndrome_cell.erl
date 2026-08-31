%%%% phenom_syndrome_cell.erl
%%%%
%%%% One syndrome cell from a request-paced phenomenological-noise experiment.

-module(phenom_syndrome_cell).
-moduledoc """
A source-aware syndrome cell which supplies noise events to one phi cell.

## Protocol

The paired phi cell starts each round by sending one `phenom_request`. The
syndrome then enters `collecting` and casts a `phenom_query` to each of its
four neighboring data cells. Four distinct `phenom_data` responses are
combined by parity. Entering `announcing` sends the resulting detection event
to the paired phi cell as one `phenom_anyon`.

There is deliberately no timer in this actor. The phi request is its clock, so
the CPU reference process and generated module observe the same round
boundaries. Configuration and all protocol messages share the module's one
framed input channel; the five named outputs are separate, backpressured
channels in generated hardware.

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

## Source labels and capacity

Queries label the sender as seen by the recipient: a query sent north names
its source as `south`, and so on. Data responses follow the same convention.
The source mask rejects duplicate or invalid participants, so completion does
not depend on cross-sender arrival order.

The five-slot mailbox can retain four early data responses for the following
round plus the request which changes the phase and releases them.
""".

-include("phi_protocol.hrl").

-export([
    start_link/0,
    start_link/1,
    connect/2,
    stop/1,
    configure/3,
    configure/5,
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
-hls_phases([configuring, waiting, collecting, announcing]).
-hls_outputs([north, east, west, south, phi]).
-hls_mailbox_capacity(?MAILBOX_CAPACITY).
-compile({parse_transform, hls_pack}).

-record(syndrome, {
    step = hls_type:zero() :: hls_nums:u32(),
    seen_sources = hls_type:zero() :: hls_nums:u32(),
    data_parity = hls_type:zero() :: hls_nums:u32(),
    previous_measurement = hls_type:zero() :: hls_nums:u32(),
    announcement = hls_type:zero() :: hls_nums:u32(),
    random_state = hls_type:zero() :: hls_nums:u32(),
    threshold = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16()
}).

-type phase() :: configuring | waiting | collecting | announcing.
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
        when is_integer(Seed), Seed > 0, Seed =< ?U32_MASK,
             is_integer(Threshold), Threshold >= 0,
             Threshold =< ?U32_MASK,
             is_integer(X), X >= 0, X =< ?U16_MASK,
             is_integer(Y), Y >= 0, Y =< ?U16_MASK ->
    hls_statem:cast(PID, #phenom_config{
        seed = Seed,
        threshold = Threshold,
        x = X,
        y = Y
    });
configure(_PID, _Seed, _Threshold, _X, _Y) ->
    error(badarg).

-doc "Offers one round request from the paired phi cell.".
-spec offer_request(pid(), hls_nums:u32()) -> ok.
offer_request(PID, Step)
        when is_integer(Step), Step >= 0, Step =< ?U32_MASK ->
    hls_statem:cast(PID, #phenom_request{step = Step});
offer_request(_PID, _Step) ->
    error(badarg).

-doc "Offers one Boolean data event from a named neighboring edge.".
-spec offer_data(pid(), hls_nums:u32(), direction(), boolean()) -> ok.
offer_data(PID, Step, Source, Present)
        when is_integer(Step), Step >= 0, Step =< ?U32_MASK,
             is_boolean(Present) ->
    SourceMask = source_mask(Source),
    PresentWord = case Present of
        false -> 0;
        true -> 1
    end,
    hls_statem:cast(PID, #phenom_data{
        step = Step,
        source = SourceMask,
        present = PresentWord
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
handle_enter(_OldPhase, waiting, Syndrome) ->
    {Syndrome, []};
handle_enter(_OldPhase, collecting, Syndrome) ->
    Query = #phenom_query{step = Syndrome#syndrome.step},
    {Syndrome, [
        {cast, north, Query#phenom_query{source = ?PHI_SOUTH_MASK}},
        {cast, east, Query#phenom_query{source = ?PHI_WEST_MASK}},
        {cast, west, Query#phenom_query{source = ?PHI_EAST_MASK}},
        {cast, south, Query#phenom_query{source = ?PHI_NORTH_MASK}}
    ]};
handle_enter(_OldPhase, announcing, Syndrome) ->
    Anyon = #phenom_anyon{
        step = Syndrome#syndrome.step,
        present = Syndrome#syndrome.announcement,
        x = Syndrome#syndrome.x,
        y = Syndrome#syndrome.y
    },
    {Syndrome, [{cast, phi, Anyon}]}.

-spec handle_cast(
    #phenom_config{} | #phenom_request{} | #phenom_data{},
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
        random_state = Seed,
        threshold = Threshold,
        x = X,
        y = Y
    },
    {waiting, Configured, consume};
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

handle_cast(#phenom_config{}, waiting, Syndrome) ->
    {waiting, Syndrome, fail};
handle_cast(
    #phenom_request{step = Step},
    waiting,
    Syndrome = #syndrome{step = Step}
) ->
    Collecting = Syndrome#syndrome{
        seen_sources = 0,
        data_parity = 0,
        announcement = 0
    },
    {collecting, Collecting, consume};
handle_cast(#phenom_request{}, waiting, Syndrome) ->
    {waiting, Syndrome, fail};
handle_cast(
    #phenom_data{step = Step},
    waiting,
    Syndrome = #syndrome{step = Step}
) ->
    {waiting, Syndrome, postpone};
handle_cast(#phenom_data{}, waiting, Syndrome) ->
    {waiting, Syndrome, fail};

handle_cast(#phenom_config{}, collecting, Syndrome) ->
    {collecting, Syndrome, fail};
handle_cast(
    #phenom_request{step = NextStep},
    collecting,
    Syndrome = #syndrome{step = Step}
) when NextStep =:= ((Step + 1) band ?U32_MASK) ->
    {collecting, Syndrome, postpone};
handle_cast(#phenom_request{}, collecting, Syndrome) ->
    {collecting, Syndrome, fail};
handle_cast(
    #phenom_data{step = Step, source = Source, present = Present},
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
       Present < 2 ->
    NewSeen = Seen bor Source,
    NewParity = Parity bxor Present,
    case NewSeen =:= ?PHI_ALL_DIRECTIONS of
        false ->
            Collected = Syndrome#syndrome{
                seen_sources = NewSeen,
                data_parity = NewParity
            },
            {collecting, Collected, consume};
        true ->
            NextRandom = hls_prng:xorshift32(RandomState),
            Measurement = case NextRandom < Threshold of
                false -> hls_type:as(hls_nums:u32(), 0);
                true -> hls_type:as(hls_nums:u32(), 1)
            end,
            Detection = NewParity bxor Measurement bxor PreviousMeasurement,
            Complete = Syndrome#syndrome{
                seen_sources = NewSeen,
                data_parity = NewParity,
                previous_measurement = Measurement,
                announcement = Detection,
                random_state = NextRandom
            },
            {announcing, Complete, consume}
    end;
handle_cast(#phenom_data{}, collecting, Syndrome) ->
    {collecting, Syndrome, fail};

handle_cast(#phenom_config{}, announcing, Syndrome) ->
    {announcing, Syndrome, fail};
handle_cast(
    #phenom_request{step = NextStep},
    announcing,
    Syndrome = #syndrome{step = Step}
) when NextStep =:= ((Step + 1) band ?U32_MASK) ->
    Collecting = Syndrome#syndrome{
        step = NextStep,
        seen_sources = 0,
        data_parity = 0,
        announcement = 0
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
