-module(hls_recovery_policy_fixture).
-moduledoc "Host policy witness which retains resource ownership and conditional-result meaning independently of a source actuator's incarnation.".
-behaviour(gen_server).
-include("hls_recovery_profile.hrl").

%% Ordinary Erlang application interface used by the finite witness.
-export([start_link/1, select/4, apply_profile/3, observe/3, result/3, branch/2, status/1, reserve/2, stop/1]).
%% Native process callbacks; this policy is not compiled into the actuator.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Host evidence can be revised independently of digital actuator completion.
-type result_map() :: #{common | deferred => {ok, 0 | 1} | {error, term()}}.
%% A result is usable only when each input selected by the chosen branch is available.
-type logical_result() :: pending | unavailable | {ok, 0 | 1}.
%% Reachability, reservation and logical validity are deliberately separate observations.
-type snapshot() :: #{control := available | unavailable, held := hls_nums:u8(), logical := logical_result()}.

%% This policy owns one fixed reservation and one logical result; no fabric work history is required.
-record(policy, {
    actuator :: pid(), monitor :: reference(),
    control = available :: available | unavailable,
    held = 16#ff :: hls_nums:u8(),
    choice = none :: none | simple | extended,
    results = #{} :: result_map()
}).

-doc "Starts a policy owner separate from the actuator's replacement domain.".
-spec start_link(pid()) -> gen_server:start_ret().
start_link(Actuator) -> gen_server:start_link(?MODULE, Actuator, []).

-doc "Requests a predeclared profile; control loss is not an instruction to retry or rebind.".
-spec select(pid(), pos_integer(), non_neg_integer(), non_neg_integer()) -> term().
select(Pid, Request, Epoch, Profile) -> gen_server:call(Pid, {select, Request, Epoch, Profile}).

-doc "Triggers the admitted request at its expected configuration epoch; stale triggers are inert and lost control leaves the outcome uncertain.".
-spec apply_profile(pid(), 1..((1 bsl 32) - 1), hls_nums:u32()) -> term().
apply_profile(Pid, Request, Epoch) -> gen_server:call(Pid, {apply, Request, Epoch}).

-doc "Reads the actuator's retained transition without treating unknown as non-execution.".
-spec observe(pid(), hls_nums:u32(), hls_nums:u32()) -> term().
observe(Pid, Request, Epoch) -> gen_server:call(Pid, {observe, Request, Epoch}).

-doc "Supplies or invalidates one application-level result; no device command is issued.".
-spec result(pid(), common | deferred, {ok, 0 | 1} | {error, term()}) -> ok.
result(Pid, Name, Value) -> gen_server:call(Pid, {result, Name, Value}).

-doc "Chooses which deferred values the current logical result actually requires.".
-spec branch(pid(), simple | extended) -> ok.
branch(Pid, Choice) -> gen_server:call(Pid, {branch, Choice}).

-doc "Reports controller reachability, retained reservation and the independent logical result.".
-spec status(pid()) -> snapshot().
status(Pid) -> gen_server:call(Pid, status).

-doc "Attempts to reserve a resource mask; live or uncertain owned resources remain occupied.".
-spec reserve(pid(), hls_nums:u8()) -> {error, occupied} | ok.
reserve(Pid, Mask) -> gen_server:call(Pid, {reserve, Mask}).

-doc "Stops only the host policy; it does not undo or replay an actuator effect.".
-spec stop(pid()) -> ok.
stop(Pid) -> gen_server:stop(Pid).

-doc "Monitors the current incarnation without gaining authority to reset or replace it.".
-spec init(pid()) -> {ok, #policy{}}.
init(Actuator) -> {ok, #policy{actuator = Actuator, monitor = monitor(process, Actuator)}}.

-doc "Handles resource and logical policy separately from ordinary source-actor calls.".
-spec handle_call(term(), gen_server:from(), #policy{}) -> term().
%% Repeated profile requests retain their original request/epoch rather than allocating a new action.
handle_call({select, Request, Epoch, Profile}, _From, Policy) ->
    invoke(fun(Actor) -> hls_statem:call(Actor,
        #select_profile{request = Request, epoch = Epoch, profile = Profile}) end, Policy);
%% The actor's bounded admission acknowledgement distinguishes rejection from accepted processing.
handle_call({apply, Request, Epoch}, _From, Policy) ->
    invoke(fun(Actor) -> hls_statem:admit_cast(Actor,
        #apply_profile{request = Request, epoch = Epoch}) end, Policy);
%% An observation may remain unknown after the actor retires; this owner never silently rebinds.
handle_call({observe, Request, Epoch}, _From, Policy) ->
    invoke(fun(Actor) -> hls_statem:call(Actor, #query_profile{request = Request, epoch = Epoch}) end, Policy);
%% Application evidence changes logical validity without fabric rollback.
handle_call({result, Name, Value}, _From, Policy = #policy{results = Results}) when
    Name =:= common; Name =:= deferred ->
    {reply, ok, Policy#policy{results = Results#{Name => Value}}};
%% Branch requirements are an explicit application contract, not compiler dependency inference.
handle_call({branch, Choice}, _From, Policy) when Choice =:= simple; Choice =:= extended ->
    {reply, ok, Policy#policy{choice = Choice}};
%% Occupancy survives controller death and replacement; timeouts cannot release a reservation.
handle_call({reserve, Mask}, _From, Policy = #policy{held = Held}) when Mask >= 0, Mask =< 255 ->
    Reply = case Mask band Held of 0 -> ok; _ -> {error, occupied} end,
    {reply, Reply, Policy};
%% Digital control status and usable logical results are deliberately separate observations.
handle_call(status, _From, Policy) ->
    {reply, #{control => Policy#policy.control, held => Policy#policy.held,
        logical => logical(Policy#policy.choice, Policy#policy.results)}, Policy}.

-doc "No asynchronous message bypasses the policy's explicit result/update calls.".
-spec handle_cast(term(), #policy{}) -> {noreply, #policy{}}.
handle_cast(_Message, Policy) -> {noreply, Policy}.

-doc "Controller death withdraws control capability but neither frees resources nor issues replacement work.".
-spec handle_info(term(), #policy{}) -> {noreply, #policy{}}.
%% Only the monitor for this exact actuator incarnation withdraws control.
handle_info({'DOWN', Monitor, process, _Pid, _Reason}, Policy = #policy{monitor = Monitor}) ->
    {noreply, Policy#policy{control = unavailable}};
%% Unrelated observations cannot invalidate this incarnation's reservation.
handle_info(_Message, Policy) -> {noreply, Policy}.

%% Failure is retained as uncertainty; the operation is never replayed with a new request identity.
-spec invoke(fun((pid()) -> term()), #policy{}) -> {reply, term(), #policy{}}.
invoke(_Operation, Policy = #policy{control = unavailable}) ->
    {reply, {error, unavailable}, Policy};
invoke(Operation, Policy = #policy{actuator = Actor}) ->
    try Operation(Actor) of
        Reply -> {reply, Reply, Policy}
    catch exit:_Reason -> {reply, {error, unavailable}, Policy#policy{control = unavailable}}
    end.

%% The simple branch never reads the deferred result, even if it has failed.
-spec logical(none | simple | extended, result_map()) -> logical_result().
logical(none, _Results) -> pending;
logical(simple, Results) -> outcome(maps:get(common, Results, pending));
logical(extended, Results) ->
    case {outcome(maps:get(common, Results, pending)), outcome(maps:get(deferred, Results, pending))} of
        {unavailable, _} -> unavailable;
        {_, unavailable} -> unavailable;
        {{ok, Common}, {ok, Deferred}} -> {ok, Common bxor Deferred};
        _ -> pending
    end.

%% Missing evidence is pending; a failed required input makes this operation unavailable.
-spec outcome(pending | {ok, 0 | 1} | {error, term()}) -> pending | unavailable | {ok, 0 | 1}.
outcome(pending) -> pending;
outcome({ok, Bit}) -> {ok, Bit};
outcome({error, _Reason}) -> unavailable.
