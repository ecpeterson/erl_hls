-module(hls_domain_instance).
-moduledoc """
An ordinary OTP supervisor child representing one admitted domain incarnation.

The deployment owner and its backend outlive this child. Startup returns promptly;
initialization completes asynchronously and resolve rejects until ready. The deployment
must explicitly allow automatic replacement. Native endpoint monitors then terminate
this child on actor loss, leaving retry intensity and subtree policy to its supervisor.
No application message is retained or replayed by this wrapper.
""".
-behaviour(gen_server).

%% Supervisor entry point and incarnation-specific endpoint access.
-export([start_link/2, status/1, resolve/2]).
%% gen_server callbacks.
-export([
    init/1,
    handle_continue/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% Endpoint monitors belong to this instance, not to a future replacement.
-record(instance, {
    owner :: pid(),
    owner_monitor :: reference(),
    domain :: hls_domain:domain(),
    deadline :: integer(),
    handle = none :: none | hls_domain:handle(),
    actors = #{} :: #{term() => pid()},
    monitors = #{} :: #{reference() => pid()},
    evidence = starting :: starting | hls_domain:snapshot()
}).

-doc "Starts a supervisor child promptly; readiness is asynchronous and automatic replacement must be permitted.".
-spec start_link(pid(), hls_domain:domain()) -> gen_server:start_ret().
start_link(Owner, Domain) -> gen_server:start_link(?MODULE, {Owner, Domain}, []).

-doc "Returns starting or the last lifecycle observation; it does not assert remote liveness.".
-spec status(pid()) -> starting | hls_domain:snapshot().
status(Instance) -> gen_server:call(Instance, status).

-doc "Resolves an endpoint within this child's admitted incarnation; it never follows a stable name into its replacement.".
-spec resolve(pid(), term()) -> {ok, pid()} | {error, term()}.
resolve(Instance, Actor) -> gen_server:call(Instance, {resolve, Actor}).

-doc "Monitors the owner before scheduling initialization, without blocking supervisor startup.".
-spec init({pid(), hls_domain:domain()}) -> {ok, #instance{}, {continue, activate}}.
init({Owner, Domain}) ->
    Monitor = monitor(process, Owner),
    {ok,
        #instance{
            owner = Owner,
            owner_monitor = Monitor,
            domain = Domain,
            deadline = erlang:monotonic_time(millisecond) + 5000
        },
        {continue, activate}}.

-doc "Applies explicit automatic policy once, then observes the retained lifecycle operation.".
-spec handle_continue(activate, #instance{}) ->
    {noreply, #instance{}} | {stop, term(), #instance{}}.
handle_continue(activate, Instance = #instance{owner = Owner, domain = Domain}) ->
    case hls_domain:policy(Owner, Domain) of
        {ok, automatic} ->
            case hls_domain:status(Owner, Domain) of
                {ok, #{phase := unbound}} ->
                    begin_transition(hls_domain:activate(Owner, Domain), Instance);
                {ok, #{phase := failed, handle := none}} ->
                    {stop, initial_incarnation_failed, Instance};
                {ok, #{phase := failed, handle := Handle}} ->
                    begin_transition(hls_domain:replace(Owner, Handle), Instance);
                {ok, Evidence} ->
                    observe(Evidence, Instance);
                {error, Reason} ->
                    {stop, {domain_unavailable, Reason}, Instance}
            end;
        {ok, manual} ->
            {stop, manual_replacement_required, Instance};
        {error, Reason} ->
            {stop, Reason, Instance}
    end.

-doc "Exposes observations and endpoints without changing the instance's incarnation.".
-spec handle_call(term(), gen_server:from(), #instance{}) -> {reply, term(), #instance{}}.
%% Status is explicit so a successfully started child is not mistaken for a ready device.
handle_call(status, _From, Instance) ->
    {reply, Instance#instance.evidence, Instance};
%% A fresh child has no endpoint until initialization acknowledges completion.
handle_call({resolve, _Actor}, _From, Instance = #instance{handle = none}) ->
    {reply, {error, not_ready}, Instance};
%% The owner's atomic resolution checks the captured incarnation again.
handle_call({resolve, Actor}, _From, Instance = #instance{owner = Owner, handle = Handle}) ->
    {reply, hls_domain:resolve(Owner, Handle, Actor), Instance};
%% Unsupported requests cannot become source-actor work.
handle_call(_Request, _From, Instance) ->
    {reply, {error, unsupported_request}, Instance}.

-doc "Ignores unsupported casts; this child is management, not an application actor.".
-spec handle_cast(term(), #instance{}) -> {noreply, #instance{}}.
handle_cast(_Message, Instance) -> {noreply, Instance}.

-doc "Tracks pending initialization and turns native endpoint/owner loss into supervisor-visible termination.".
-spec handle_info(term(), #instance{}) -> {noreply, #instance{}} | {stop, term(), #instance{}}.
%% Only a retained operation is observed; a poll never allocates a new incarnation.
handle_info(observe, Instance = #instance{owner = Owner, domain = Domain}) ->
    case hls_domain:status(Owner, Domain) of
        {ok, Evidence} -> observe(Evidence, Instance);
        {error, Reason} -> {stop, {domain_unavailable, Reason}, Instance}
    end;
%% Owner loss is distinct from a known source exception.
handle_info(
    {'DOWN', Ref, process, Owner, Reason}, Instance = #instance{owner = Owner, owner_monitor = Ref}
) ->
    {stop, {domain_owner_down, Reason}, Instance};
%% Actor loss retires this instance; replacement policy belongs to its supervisor.
handle_info({'DOWN', Ref, process, Actor, Reason}, Instance = #instance{monitors = Monitors}) when
    is_map_key(Ref, Monitors)
->
    {stop, {domain_actor_down, Actor, Reason}, Instance};
%% Stale unrelated notifications cannot mutate the incarnation.
handle_info(_Message, Instance) ->
    {noreply, Instance}.

-doc "Leaves domain lifecycle with its owner; terminating a host representative does not silently reset hardware.".
-spec terminate(term(), #instance{}) -> ok.
terminate(_Reason, _Instance) -> ok.

-doc "Preserves incarnation identity over a host code change.".
-spec code_change(term(), #instance{}, term()) -> {ok, #instance{}}.
code_change(_Old, Instance, _Extra) -> {ok, Instance}.

%% A known rejected operation stops the child rather than hiding an internal retry loop.
-spec begin_transition({ok, hls_domain:snapshot()} | {error, term()}, #instance{}) ->
    {noreply, #instance{}} | {stop, term(), #instance{}}.
begin_transition({ok, Evidence}, Instance) -> observe(Evidence, Instance);
begin_transition({error, Reason}, Instance) -> {stop, {incarnation_rejected, Reason}, Instance}.

%% Publish only acknowledged readiness, then bind monitors to those exact endpoint PIDs.
-spec observe(hls_domain:snapshot(), #instance{}) ->
    {noreply, #instance{}} | {stop, term(), #instance{}}.
observe(
    #{phase := ready, handle := Handle, actors := Actors} = Evidence,
    Instance = #instance{handle = none}
) ->
    Monitors = maps:from_list([{monitor(process, Pid), Pid} || Pid <- maps:values(Actors)]),
    {noreply, Instance#instance{
        handle = Handle, actors = Actors, monitors = Monitors, evidence = Evidence
    }};
%% Repeated evidence for this incarnation neither duplicates monitors nor follows a stable name.
observe(
    #{phase := ready, handle := Handle, actors := Actors} = Evidence,
    Instance = #instance{handle = Handle, actors = Actors}
) ->
    {noreply, Instance#instance{evidence = Evidence}};
%% A newer ready incarnation belongs to a different supervisor child, even after a delayed poll.
observe(
    #{phase := ready, handle := NewHandle} = Evidence, Instance = #instance{handle = OldHandle}
) when
    NewHandle =/= OldHandle
->
    {stop, {domain_replaced, OldHandle, NewHandle}, Instance#instance{evidence = Evidence}};
%% A backend may not change endpoint identity while retaining the same incarnation.
observe(#{phase := ready} = Evidence, Instance) ->
    {stop, {domain_endpoints_changed, Evidence}, Instance#instance{evidence = Evidence}};
%% Failure never recycles the old handle or generates another reset in this child.
observe(#{phase := failed} = Evidence, Instance) ->
    {stop, {incarnation_failed, Evidence}, Instance#instance{evidence = Evidence}};
%% Loss of readiness retires a bound representative; it cannot wait into a successor.
observe(Evidence, Instance = #instance{handle = Handle}) when Handle =/= none ->
    {stop, {domain_no_longer_ready, Handle, Evidence}, Instance#instance{evidence = Evidence}};
%% Waiting is bounded locally, but expiration does not prove remote cancellation.
observe(Evidence, Instance = #instance{deadline = Deadline}) ->
    case erlang:monotonic_time(millisecond) < Deadline of
        true ->
            erlang:send_after(10, self(), observe),
            {noreply, Instance#instance{evidence = Evidence}};
        false ->
            {stop, {incarnation_outcome_unknown, Evidence}, Instance#instance{evidence = Evidence}}
    end.
