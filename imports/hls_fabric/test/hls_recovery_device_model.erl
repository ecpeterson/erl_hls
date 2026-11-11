-module(hls_recovery_device_model).
-moduledoc "External simulated device whose accepted effects and resource ownership survive replacement of its source controller. This is a test device, not a quantum-state model.".
-behaviour(gen_server).
-include("hls_recovery_profile.hrl").

%% Independent device lifetime and public observations.
-export([start_link/0, bind/3, snapshot/1, reserve/2, stop/1]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Keeping history is permissible in this host test device; the fabric retains no work log.
-type state() :: #{effects := [#profile_applied{}], held := hls_nums:u8(),
    observations := [term()], monitors := #{reference() => hls_domain:handle()}}.

-doc "Starts a simulated device with eight occupied capabilities; controller reset is explicitly safe for its digital interface.".
-spec start_link() -> gen_server:start_ret().
start_link() -> gen_server:start_link(?MODULE, [], []).

-doc "Monitors one local incarnation endpoint as the same recipient which receives its external effects; this does not grant reset authority.".
-spec bind(pid(), hls_domain:handle(), pid()) -> ok.
bind(Device, Handle, Endpoint) -> gen_server:call(Device, {bind, Handle, Endpoint}).

-doc "Returns accepted effects and effect/termination observations in arrival order, plus the unchanged reservation mask.".
-spec snapshot(pid()) -> state().
snapshot(Device) -> gen_server:call(Device, snapshot).

-doc "Checks a new reservation against the surviving device owner; process death or controller reset cannot free a capability.".
-spec reserve(pid(), hls_nums:u8()) -> {error, occupied} | ok.
reserve(Device, Mask) -> gen_server:call(Device, {reserve, Mask}).

-doc "Stops the external model only when the entire finite test finishes.".
-spec stop(pid()) -> ok.
stop(Device) -> gen_server:stop(Device).

-doc "Owns its reservation independently of any incarnation's initialization.".
-spec init([]) -> {ok, state()}.
init([]) -> {ok, #{effects => [], held => 16#ff, observations => [], monitors => #{}}}.

-doc "Exposes host observations without changing a device effect.".
-spec handle_call(term(), gen_server:from(), state()) -> {reply, term(), state()}.
%% Monitoring the actual effect sender checks ordering at one recipient, not across unrelated mailboxes.
handle_call({bind, Handle, Endpoint}, _From, State = #{monitors := Monitors}) ->
    Ref = monitor(process, Endpoint),
    {reply, ok, State#{monitors := Monitors#{Ref => Handle}}};
%% Inspection cannot accidentally acknowledge or replay application work.
handle_call(snapshot, _From, State) ->
    {reply, State#{effects := lists:reverse(maps:get(effects, State)),
        observations := lists:reverse(maps:get(observations, State))}, State};
%% Availability is a property of the resource owner, not controller reachability.
handle_call({reserve, Mask}, _From, State = #{held := Held}) when Mask >= 0, Mask < 256 ->
    Result = case Mask band Held of 0 -> ok; _ -> {error, occupied} end,
    {reply, Result, State}.

-doc "Records each actually delivered actuator effect without deduplicating request IDs or rolling back retired incarnations.".
-spec handle_cast(#profile_applied{}, state()) -> {noreply, state()}.
handle_cast(Effect = #profile_applied{}, State = #{effects := Effects, observations := Observations}) ->
    {noreply, State#{effects := [Effect | Effects], observations := [{effect, Effect} | Observations]}}.

-doc "Unrelated process notifications cannot release a reservation or manufacture a device effect.".
-spec handle_info(term(), state()) -> {noreply, state()}.
%% An actual endpoint DOWN is recorded without freeing resources or erasing previous effects.
handle_info({'DOWN', Ref, process, _Endpoint, Reason},
        State = #{monitors := Monitors, observations := Observations}) when is_map_key(Ref, Monitors) ->
    Handle = maps:get(Ref, Monitors),
    {noreply, State#{monitors := maps:remove(Ref, Monitors),
        observations := [{down, Handle, Reason} | Observations]}};
%% Notifications unrelated to a bound incarnation carry no recovery evidence.
handle_info(_Message, State) -> {noreply, State}.
