-module(hls_domain_async_fixture).
-moduledoc "Finite management-only controller fixture. Real lifecycle transitions and owner checks surround deliberately delayed responses; no actors or physical recovery are modeled.".
-behaviour(gen_server).
-behaviour(hls_domain_backend).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Test controls and the production backend interface.
-export([start_link/1, start_link/2, hold/2, release/1, pause/2, advance/1, reject/1, attach/2, status/1, request/3, endpoint/4, send_request/2]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% The fixture retains at most one delayed response, independently of controller progress.
-record(fixture, {
    observer :: pid(),
    owner = undefined :: undefined | pid(),
    monitor = undefined :: undefined | reference(),
    authority = undefined :: undefined | reference(),
    state = #domain_state{} :: hls_domain_lifecycle:state(),
    actors = #{} :: hls_domain_backend:actors(),
    reject = false :: boolean(),
    pause = none :: none | fence | reset | initialize,
    hold = none :: none | status | endpoint | request | attach,
    delayed = none :: none | {gen_server:from(), term()}
}).

-doc "Starts an isolated controller whose endpoint identity is the test observer.".
-spec start_link(pid()) -> gen_server:start_ret().
start_link(Observer) ->
    start_link(Observer, #{state => hls_domain_lifecycle:new(), actors => #{actor => Observer},
        fault_reason => none}).

-doc "Models a replacement host adapter observing retained controller evidence; this is not physical persistence evidence.".
-spec start_link(pid(), hls_domain_backend:snapshot()) -> gen_server:start_ret().
start_link(Observer, Evidence) -> gen_server:start_link(?MODULE, {Observer, Evidence}, []).

-doc "Delays the next selected response after processing its request.".
-spec hold(pid(), status | endpoint | request | attach) -> ok.
hold(Backend, Kind) -> gen_server:call(Backend, {hold, Kind}).

-doc "Sends the retained response, including after its caller has retired the alias.".
-spec release(pid()) -> ok.
release(Backend) -> gen_server:call(Backend, release).

-doc "Withholds the named backend completion while retaining the kernel's pending action.".
-spec pause(pid(), fence | reset | initialize) -> ok.
pause(Backend, Action) -> gen_server:call(Backend, {pause, Action}).

-doc "Allows retained phase work to complete; this is fixture evidence, not a physical acknowledgement.".
-spec advance(pid()) -> ok.
advance(Backend) -> gen_server:call(Backend, advance).

-doc "Rejects the next management command with unchanged controller state.".
-spec reject(pid()) -> ok.
reject(Backend) -> gen_server:call(Backend, reject).

-doc "Attaches only the actual calling owner and monitors that same PID.".
-spec attach(pid(), pid()) -> {ok, hls_domain_backend:authority()} | {error, term()}.
attach(Backend, Owner) -> gen_server:call(Backend, {attach, Owner}).

-doc "Reads the fixture's actual finite lifecycle state.".
-spec status(pid()) -> {ok, hls_domain_backend:snapshot()}.
status(Backend) -> gen_server:call(Backend, status).

-doc "Runs the finite kernel and immediately acknowledges its requested phases.".
-spec request(pid(), hls_domain_backend:authority(), hls_domain_lifecycle:input()) ->
    hls_domain_lifecycle:output() | {error, term()}.
request(Backend, Authority, Input) -> gen_server:call(Backend, {request, Authority, Input}).

-doc "Resolves the observer only for the attached owner and current ready incarnation.".
-spec endpoint(pid(), hls_domain_backend:authority(), hls_nums:u64(), term()) ->
    {ok, pid()} | {error, term()}.
endpoint(Backend, Authority, Incarnation, Actor) ->
    gen_server:call(Backend, {endpoint, Authority, Incarnation, Actor}).

-doc "Uses ordinary OTP response aliases while retaining actual owner caller identity.".
-spec send_request(pid(), hls_domain_backend:request()) -> gen_server:request_id().
send_request(Backend, Request) -> gen_server:send_request(Backend, Request).

-doc "Starts with supplied controller evidence but no control authority; no actor state is restored.".
-spec init({pid(), hls_domain_backend:snapshot()}) -> {ok, #fixture{}}.
init({Observer, #{state := State, actors := Actors}}) ->
    {ok, #fixture{observer = Observer, state = State, actors = Actors}}.

-doc "Applies management requests and optionally delays exactly one response.".
-spec handle_call(term(), gen_server:from(), #fixture{}) ->
    {reply, term(), #fixture{}} | {noreply, #fixture{}}.
%% Withheld backend acknowledgements must remain distinguishable from status-response delivery.
handle_call(reject, _From, S) -> {reply, ok, S#fixture{reject = true}};
%% Hold one selected acknowledgement without rejecting its operation.
handle_call({pause, Action}, _From, S) -> {reply, ok, S#fixture{pause = Action}};
%% Advancing acknowledges the already requested phase, rather than issuing another command.
handle_call(advance, _From, S = #fixture{state = State}) ->
    Output = #domain_output{state = State, action = hls_domain_lifecycle:action(State)},
    {reply, ok, S#fixture{state = finish(Output), pause = none}};
%% Fixture controls remain available while a response is delayed.
handle_call({hold, Kind}, _From, S = #fixture{hold = none}) ->
    {reply, ok, S#fixture{hold = Kind}};
%% Releasing an abandoned alias must not cause the owner to replay its operation.
handle_call(release, _From, S = #fixture{delayed = {Waiting, Reply}}) ->
    gen_server:reply(Waiting, Reply),
    {reply, ok, S#fixture{delayed = none}};
%% The fixture enforces the real backend's owner-PID check, not just token equality.
handle_call({attach, Owner}, From = {Owner, _}, S = #fixture{owner = undefined}) ->
    Authority = make_ref(),
    deliver(attach, From, {ok, Authority}, S#fixture{owner = Owner, monitor = monitor(process, Owner),
        authority = Authority});
%% Inspection remains a controller observation even when delivery is delayed.
handle_call(status, From, S = #fixture{state = State, actors = Actors}) ->
    deliver(status, From, {ok, #{state => State, actors => Actors,
        fault_reason => none}}, S);
%% A definitive command rejection supplies unchanged controller evidence, unlike a lost transport response.
handle_call({request, Authority, _Input}, From = {Owner, _},
    S = #fixture{owner = Owner, authority = Authority, state = State, reject = true}) ->
    Output = #domain_output{status = invalid, state = State, action = hls_domain_lifecycle:action(State)},
    deliver(request, From, Output, S#fixture{reject = false});
%% Complete the kernel's real phases but preserve the request's accepted/replay disposition.
handle_call({request, Authority, Input}, From = {Owner, _},
    S = #fixture{owner = Owner, authority = Authority, state = State}) ->
    Output = hls_domain_lifecycle:step(Input, State),
    Result = finish(Output, S#fixture.pause),
    deliver(request, From, Output#domain_output{state = Result, action = none}, S#fixture{state = Result});
%% The supplied incarnation, actual caller and authority must all agree.
handle_call({endpoint, Authority, Incarnation, actor}, From = {Owner, _},
    S = #fixture{owner = Owner, authority = Authority, state = State, actors = Actors}) ->
    Reply = case hls_domain_lifecycle:admitted(Incarnation, State) of
        true -> {ok, maps:get(actor, Actors)};
        false -> {error, not_ready_or_stale}
    end,
    deliver(endpoint, From, Reply, S);
%% A worker impersonating the owner would fail here.
handle_call(_Request, _From, S) -> {reply, {error, unauthorized}, S}.

-doc "Casts have no control authority in this fixture.".
-spec handle_cast(term(), #fixture{}) -> {noreply, #fixture{}}.
handle_cast(_Message, S) -> {noreply, S}.

-doc "Reports owner death independently of any held response.".
-spec handle_info(term(), #fixture{}) -> {noreply, #fixture{}}.
%% The lifetime monitor remains attached to the deployment owner throughout asynchronous calls.
handle_info({'DOWN', Monitor, process, Owner, Reason},
    S = #fixture{owner = Owner, monitor = Monitor, observer = Observer}) ->
    Observer ! {fixture_owner_down, self(), Owner, Reason},
    {noreply, S#fixture{owner = undefined, monitor = undefined, authority = undefined}};
%% Late or unrelated traffic cannot change lifecycle state.
handle_info(_Message, S) -> {noreply, S}.

%% Report withholding deterministically so tests never rely on a short sleep for ordering.
-spec deliver(status | endpoint | request | attach, gen_server:from(), term(), #fixture{}) ->
    {reply, term(), #fixture{}} | {noreply, #fixture{}}.
deliver(Kind, From = {Owner, _}, Reply, S = #fixture{hold = Kind, observer = Observer}) ->
    Observer ! {fixture_held, self(), Kind, Owner},
    {noreply, S#fixture{hold = none, delayed = {From, Reply}}};
deliver(_Kind, _From, Reply, S) -> {reply, Reply, S}.

%% This models management completion only, not native actor initialization or hardware progress.
-spec finish(hls_domain_lifecycle:output()) -> hls_domain_lifecycle:state().
finish(Output) -> finish(Output, none).

%% A paused physical phase remains pending until the test explicitly supplies completion.
-spec finish(hls_domain_lifecycle:output(), none | fence | reset | initialize) -> hls_domain_lifecycle:state().
finish(#domain_output{action = Action, state = State}, Action) when Action =/= none -> State;
finish(#domain_output{action = Action, state = State}, _Pause)
    when Action =:= none; Action =:= publish -> State;
finish(#domain_output{action = Action, state = State}, Pause) ->
    Operation = case Action of fence -> fenced; reset -> reset_done; initialize -> initialized end,
    Input = #domain_input{op = Operation, expected = State#domain_state.previous,
        target = State#domain_state.target, transition = State#domain_state.transition},
    finish(hls_domain_lifecycle:step(Input, State), Pause).
