%%%% phi_syndrome_replay_cell
%%%%
%%%% Compact deterministic syndrome source for decoder-only profiling.

-module(phi_syndrome_replay_cell).
-moduledoc """
Request-paced nontrivial syndrome source for the phi decoder diagnostic.

This actor deliberately replaces the phenomenological data and syndrome
network; it is not a physical measurement model.  Each `phenom_request`
advances one deterministic PRNG stream and replies with the transition of its
Boolean measurement bit.  Using the transition rather than the level matches
the temporal-boundary convention of `phenom_syndrome_cell` when its four data
inputs are zero.

The paired phi actor therefore sees the same `phenom_request` /
`phenom_anyon` contract as it does in the complete memory experiment, while
the diagnostic removes data-qubit actors, measurement-noise actors, host
correction feedback, and final Pauli-frame queries.  A half-scale threshold
keeps the workload nontrivial.  The generated profiling topology realizes
each source family with a separate scheduler so its activity remains distinct
from the six phi schedulers under measurement.
""".

-behavior(hls_statem).
-compile({parse_transform, hls_pack}).

-include("phi_protocol.hrl").

-hls_data(source).
-hls_phases([configuring, waiting, announcing]).
-hls_outputs([phi]).
-hls_mailbox_capacity(1).

-export([
    start_link/0,
    start_link/1,
    connect/2,
    stop/1,
    configure/5,
    offer_request/2
]).
-export([configuring/3, waiting/3, announcing/3, init/1]).

-define(U16_MASK, 16#ffff).
-define(U32_MASK, 16#ffffffff).

-record(source, {
    step = hls_type:zero() :: hls_nums:u32(),
    random_state = hls_type:zero() :: hls_nums:u32(),
    threshold = hls_type:zero() :: hls_nums:u32(),
    previous_measurement = hls_type:zero() :: hls_nums:u32(),
    announcement = hls_type:zero() :: hls_nums:u32(),
    x = hls_type:zero() :: hls_nums:u16(),
    y = hls_type:zero() :: hls_nums:u16()
}).

-type phase() :: configuring | waiting | announcing.

-doc "Starts one disconnected diagnostic syndrome source.".
-spec start_link() -> {ok, pid()}.
start_link() ->
    hls_statem:start_link(?MODULE, [], [{mailbox_capacity, 1}]).

-doc "Starts one source connected to its paired phi actor.".
-spec start_link(#{phi := pid()}) -> {ok, pid()}.
start_link(Outputs = #{phi := Phi}) when is_pid(Phi), map_size(Outputs) =:= 1 ->
    hls_statem:start_link(
        ?MODULE,
        [],
        [{mailbox_capacity, 1}, {outputs, Outputs}]
    );
start_link(_Outputs) ->
    error(badarg).

-doc "Connects a deferred source to its paired phi actor.".
-spec connect(pid(), #{phi := pid()}) -> ok | {error, already_connected}.
connect(Pid, Outputs = #{phi := Phi})
        when is_pid(Pid), is_pid(Phi), map_size(Outputs) =:= 1 ->
    hls_statem:connect(Pid, Outputs);
connect(_Pid, _Outputs) ->
    error(badarg).

-doc "Stops one diagnostic source.".
-spec stop(pid()) -> ok.
stop(Pid) ->
    hls_statem:stop(Pid).

-doc "Configures the deterministic stream and reported lattice coordinate.".
-spec configure(
    pid(),
    hls_nums:u32(),
    hls_nums:u32(),
    hls_nums:u16(),
    hls_nums:u16()
) -> ok.
configure(Pid, Seed, Threshold, X, Y)
        when Seed > 0, Seed =< ?U32_MASK,
             Threshold >= 0, Threshold =< ?U32_MASK,
             X >= 0, X =< ?U16_MASK,
             Y >= 0, Y =< ?U16_MASK ->
    hls_statem:cast(Pid, #phenom_config{
        seed = Seed,
        threshold = Threshold,
        x = X,
        y = Y
    });
configure(_Pid, _Seed, _Threshold, _X, _Y) ->
    error(badarg).

-doc "Offers the next request from the paired phi actor.".
-spec offer_request(pid(), hls_nums:u32()) -> ok.
offer_request(Pid, Step) when Step >= 0, Step =< ?U32_MASK ->
    hls_statem:cast(Pid, #phenom_request{step = Step});
offer_request(_Pid, _Step) ->
    error(badarg).

-spec init(any()) -> {ok, phase(), #source{}}.
init([]) ->
    {ok, configuring, #source{}}.

-spec configuring(enter, phase(), #source{}) ->
    hls_statem:enter_result(#source{});
    (cast, #phenom_config{} | #phenom_request{}, #source{}) ->
        hls_statem:cast_result(phase(), #source{}).
configuring(enter, _OldPhase, Source) ->
    {Source, []};
configuring(
    cast,
    #phenom_config{seed = Seed, threshold = Threshold, x = X, y = Y},
    Source
) when Seed > 0, Seed =< ?U32_MASK,
       Threshold >= 0, Threshold =< ?U32_MASK,
       X >= 0, X =< ?U16_MASK,
       Y >= 0, Y =< ?U16_MASK ->
    {waiting, Source#source{
        random_state = Seed,
        threshold = Threshold,
        x = X,
        y = Y
    }, consume};
configuring(cast, #phenom_config{}, Source) ->
    {configuring, Source, fail};
configuring(cast, #phenom_request{step = 0}, Source) ->
    {configuring, Source, postpone};
configuring(cast, #phenom_request{}, Source) ->
    {configuring, Source, fail}.

-spec waiting(enter, phase(), #source{}) -> hls_statem:enter_result(#source{});
    (cast, #phenom_config{} | #phenom_request{}, #source{}) ->
        hls_statem:cast_result(phase(), #source{}).
waiting(enter, _OldPhase, Source) ->
    {Source, []};
waiting(cast, #phenom_config{}, Source) ->
    {waiting, Source, fail};
waiting(
    cast,
    #phenom_request{step = 0},
    Source = #source{
        random_state = RandomState,
        threshold = Threshold,
        previous_measurement = PreviousMeasurement
    }
) ->
    NextRandom = hls_prng:xorshift32(RandomState),
    Measurement = case NextRandom < Threshold of
        false -> hls_type:as(hls_nums:u32(), 0);
        true -> hls_type:as(hls_nums:u32(), 1)
    end,
    {announcing, Source#source{
        step = 0,
        random_state = NextRandom,
        previous_measurement = Measurement,
        announcement = Measurement bxor PreviousMeasurement
    }, consume};
waiting(cast, #phenom_request{}, Source) ->
    {waiting, Source, fail}.

-spec announcing(enter, phase(), #source{}) ->
    hls_statem:enter_result(#source{});
    (cast, #phenom_config{} | #phenom_request{}, #source{}) ->
        hls_statem:cast_result(phase(), #source{}).
announcing(enter, _OldPhase, Source) ->
    Event = #phenom_anyon{
        step = Source#source.step,
        flags = Source#source.announcement,
        x = Source#source.x,
        y = Source#source.y
    },
    {Source, [{cast, phi, Event}]};
announcing(cast, #phenom_config{}, Source) ->
    {announcing, Source, fail};
announcing(
    cast,
    #phenom_request{step = Step},
    Source = #source{
        step = PreviousStep,
        random_state = RandomState,
        threshold = Threshold,
        previous_measurement = PreviousMeasurement
    }
) when Step =:= ((PreviousStep + 1) band ?U32_MASK) ->
    NextRandom = hls_prng:xorshift32(RandomState),
    Measurement = case NextRandom < Threshold of
        false -> hls_type:as(hls_nums:u32(), 0);
        true -> hls_type:as(hls_nums:u32(), 1)
    end,
    {repeat_phase, Source#source{
        step = Step,
        random_state = NextRandom,
        previous_measurement = Measurement,
        announcement = Measurement bxor PreviousMeasurement
    }, consume};
announcing(cast, #phenom_request{}, Source) ->
    {announcing, Source, fail}.
