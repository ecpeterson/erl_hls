-module(hls_domain).
-moduledoc """
Host ownership of fixed actor domains and their non-reused incarnation IDs.

Backends own the finite lifecycle controller and establish physical completion.
This process attaches without resetting, orders management separately per domain,
and persists each allocated incarnation ID before submitting it. Backend waits are
asynchronous; only counter persistence is shared across domains. A timeout is an
unknown outcome, never permission to replay application work. Backend endpoints remain incarnation-specific.

The incarnation file stores only an eight-byte identity counter, never actor state.
It must be created explicitly for a newly commissioned deployment.
Do not recreate a lost file to recover a running deployment. Its lock excludes other
owners in this BEAM VM; the backend separately excludes conflicting control sessions.
Use one durable store per authority and preserve it across software restarts. Storage
loss or migration to another authority requires independent retirement/reconciliation.
The file is synced before rename; containing-directory power-loss durability is not
established. After host/storage crash, reconcile identity before reusing this store.
""".
-behaviour(gen_server).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Deployment ownership and explicit lifecycle operations.
-export([
    create_store/1,
    reserve_incarnations/2,
    start_link/2,
    status/2,
    activate/2,
    replace/2,
    stop/2,
    reattach/3,
    resolve/3,
    policy/2,
    supervise/2,
    release/2
]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% Public ownership contracts.
-export_type([catalog/0, backend/0, handle/0, incarnation/0, domain/0, policy/0, snapshot/0]).

-doc "A fixed deployment-local domain name.".
-type domain() :: atom().
-doc "A nonzero incarnation ID which never wraps within one deployment.".
-type incarnation() :: 1..((1 bsl 64) - 1).
-doc "An incarnation-specific domain handle, not a mutable stable name.".
-type handle() :: {domain(), incarnation()}.
-doc "Automatic replacement is permitted only when the deployment declares it acceptable.".
-type policy() :: manual | automatic.
-doc "Declared domains and their replacement policy; actor/source layout belongs to the backend.".
-type catalog() :: #{domain() := policy()}.
-doc "One backend implementation, a distinct existing endpoint for each domain, and a durable incarnation counter file.".
-type backend() :: #{
    module := module(), endpoints := #{domain() := pid()}, incarnation_file := file:filename()
}.
-doc "Observed lifecycle state; readiness and a handle refer to the same incarnation.".
-type snapshot() :: #{
    domain := domain(),
    phase := hls_domain_lifecycle:phase(),
    handle := none | handle(),
    target := non_neg_integer(),
    transition := non_neg_integer(),
    fault := hls_domain_lifecycle:fault(),
    detail := term(),
    actors := #{term() => pid()}
}.

%% One active operation and eight waiting requests bound retained work per domain.
-define(WAITING_LIMIT, 8).
-define(BACKEND_TIMEOUT, 5000).

%% All stages of one operation precede the next accepted operation in its domain.
-type operation() ::
    status
    | {transition, non_neg_integer(), hls_domain_lifecycle:operation()}
    | {resolve, any | incarnation(), term()}
    | {reattach, incarnation(), pid()}
    | {supervise, pid()}
    | retire.
%% Internal retirement requests have no external response alias.
-type caller() :: gen_server:from() | retirement.
%% Inspection precedes authenticated resolution/submission; ready submission needs fresh actors.
-type stage() :: inspecting | resolving | submitting | confirming | attaching | reattached.
%% Correlation belongs to this owner, so backends still observe the actual attached caller.
-record(pending, {
    from :: caller(),
    operation :: operation(),
    stage = inspecting :: stage(),
    request :: undefined | gen_server:request_id(),
    timer :: undefined | reference()
}).
%% The queue retains only management requests, never application work or actor state.
-record(work, {
    active = none :: none | #pending{},
    waiting = queue:new() :: queue:queue({caller(), operation()}),
    queued = 0 :: 0..?WAITING_LIMIT
}).
%% A supervised representative's exact incarnation and retirement intent outlive that local process.
-record(supervision, {
    child :: pid(),
    monitor :: reference(),
    incarnation = unknown :: unknown | non_neg_integer(),
    retiring = false :: boolean(),
    waiter = none :: none | gen_server:from(),
    retry = false :: boolean()
}).
%% The owner retains authority tokens, never source actor state or an application work log.
-record(owner, {
    catalog :: catalog(),
    module :: module(),
    endpoints :: #{domain() := pid()},
    authorities :: #{domain() := hls_domain_backend:authority()},
    file :: file:filename(),
    next :: non_neg_integer(),
    work = #{} :: #{domain() := #work{}},
    requests = gen_server:reqids_new() :: gen_server:request_id_collection(),
    supervision = #{} :: #{domain() => #supervision{}}
}).

-doc "Creates a new deployment's counter exclusively. An existing or lost store is never silently replaced.".
-spec create_store(file:filename()) -> ok | {error, term()}.
create_store(Path) ->
    case file:open(Path, [write, binary, raw, exclusive]) of
        {ok, File} ->
            try
                ok = file:write(File, <<0:64>>),
                file:sync(File)
            after
                file:close(File)
            end;
        Error ->
            Error
    end.

-doc "Durably consumes a nonempty interval of fresh incarnation IDs for a delegated authority. Reservation transfers no backend control, and unused or uncertain grants are never reclaimed. The caller must bind the interval to one supervisor incarnation and exclude competing child control; retry after a lost reply reserves another interval. Counter synchronization is shared with ordinary domain allocation. This operation trusts an intact or independently reconciled persisted high-water mark. Backend attachment/status is not grant reconciliation: current incarnation snapshots cannot recover unused reserved ranges.".
-spec reserve_incarnations(pid(), pos_integer()) ->
    {ok, {incarnation(), incarnation()}} | {error, term()}.
reserve_incarnations(Owner, Count) -> gen_server:call(Owner, {reserve_incarnations, Count}).

-doc "Attaches to existing domain controllers without resetting or activating their actors.".
-spec start_link(catalog(), backend()) -> gen_server:start_ret().
start_link(Catalog, Backend) -> gen_server:start_link(?MODULE, {Catalog, Backend}, []).

-doc "Reads backend evidence in per-domain request order. A full management queue returns busy; an unavailable backend returns an error rather than a synthetic phase.".
-spec status(pid(), domain()) -> {ok, snapshot()} | {error, term()}.
status(Owner, Domain) -> gen_server:call(Owner, {status, Domain}).

-doc "Creates the first incarnation of an unbound domain; repeating an in-flight request observes its transition. A full management queue returns busy without allocating an identity.".
-spec activate(pid(), domain()) -> {ok, snapshot()} | {error, term()}.
activate(Owner, Domain) -> gen_server:call(Owner, {activate, Domain}).

-doc "Replaces exactly the supplied incarnation. Repetition retrieves its retained successor; older handles reject. A full management queue returns busy without allocating an identity.".
-spec replace(pid(), handle()) -> {ok, snapshot()} | {error, term()}.
replace(Owner, {Domain, Incarnation}) -> gen_server:call(Owner, {replace, Domain, Incarnation}).

-doc "Stops exactly this incarnation without allocating a successor or replaying work. A closing result is accepted intent; stopped requires actual backend retirement. Repetition is idempotent, and a stale handle cannot stop its successor.".
-spec stop(pid(), handle()) -> {ok, snapshot()} | {error, term()}.
stop(Owner, {Domain, Incarnation}) -> gen_server:call(Owner, {stop, Domain, Incarnation}).

-doc "Claims this local caller as the sole supervised representative before startup. Its death retains retirement intent in the surviving owner. Existing retirement must finish before another child can claim the domain.".
-spec supervise(pid(), domain()) -> {ok, snapshot()} | {error, term()}.
supervise(Owner, Domain) -> gen_server:call(Owner, {supervise, Domain}).

-doc "Requests retirement of this caller's supervised lifetime and waits for backend confirmation. The caller's supervisor supplies the shutdown deadline; killing the caller does not cancel retained intent. Owner or transport failure cannot establish successful retirement.".
-spec release(pid(), domain()) -> ok | {error, term()}.
release(Owner, Domain) -> gen_server:call(Owner, {release, Domain}, infinity).

-doc "Reattaches a surviving incarnation through a new local backend after the old backend process has died. Checks matching incarnation identity before attachment and again afterward; non-ready evidence permits management reconciliation without exposing actors; never resets or replays work. A failed final observation can leave the new binding installed: inspect status to reconcile it.".
-spec reattach(pid(), handle(), pid()) -> {ok, snapshot()} | {error, term()}.
reattach(Owner, {Domain, Incarnation}, Backend) ->
    gen_server:call(Owner, {reattach, Domain, Incarnation, Backend}).

-doc "Returns an actor endpoint only from the currently ready incarnation, in per-domain request order. Previously returned PIDs are never rebound; a full management queue returns busy.".
-spec resolve(pid(), domain() | handle(), term()) -> {ok, pid()} | {error, term()}.
resolve(Owner, Domain, Actor) -> gen_server:call(Owner, {resolve, Domain, Actor}).

-doc "Returns the deployment's declared policy without initiating a lifecycle operation.".
-spec policy(pid(), domain()) -> {ok, policy()} | {error, unknown_domain}.
policy(Owner, Domain) -> gen_server:call(Owner, {policy, Domain}).

-doc "Claims one durable counter and each backend's control session; no actor starts here.".
-spec init({catalog(), backend()}) -> {ok, #owner{}} | {stop, term()}.
init({Catalog, #{module := Module, endpoints := Endpoints, incarnation_file := Path}}) ->
    File = filename:absname(Path),
    case validate(Catalog, Endpoints) of
        false ->
            {stop, invalid_domain_catalog};
        true ->
            case hls_domain_store:claim(File) of
                {error, owned} -> {stop, incarnation_store_owned};
                ok -> initialize_owner(Catalog, Module, Endpoints, File)
            end
    end.

-doc "Orders each domain's management independently; retains at most one active operation and eight waiting calls per domain. Policy lookup never waits for backend evidence.".
-spec handle_call(term(), gen_server:from(), #owner{}) ->
    {reply, term(), #owner{}} | {noreply, #owner{}}.
%% A grant consumes its entire interval before acknowledgement, independently of child availability.
handle_call({reserve_incarnations, Count}, _From, Owner = #owner{next = Counter, file = File}) when
    is_integer(Count), Count > 0, Count =< ((1 bsl 64) - 1)
->
    case Counter =< ((1 bsl 64) - 1) - Count of
        false ->
            {reply, {error, incarnation_exhausted}, Owner};
        true ->
            Last = Counter + Count,
            case persist(File, Last) of
                ok -> {reply, {ok, {Counter + 1, Last}}, Owner#owner{next = Last}};
                {error, Reason} -> {reply, {error, {incarnation_store, Reason}}, Owner}
            end
    end;
%% Reject malformed untyped counts before touching the store or allocating an ID.
handle_call({reserve_incarnations, _Count}, _From, Owner) ->
    {reply, {error, invalid_incarnation_count}, Owner};
%% Policy is host configuration, not a remote readiness claim.
handle_call({policy, Domain}, _From, Owner = #owner{catalog = Catalog}) ->
    Reply =
        case maps:find(Domain, Catalog) of
            {ok, P} -> {ok, P};
            error -> {error, unknown_domain}
        end,
    {reply, Reply, Owner};
%% Status always comes from the controller instead of a stale host mirror.
handle_call({status, Domain}, From, Owner) ->
    enqueue(Domain, status, From, Owner);
%% Initial creation and replacement share durable allocation and request correlation.
handle_call({activate, Domain}, From, Owner) ->
    enqueue_transition(Domain, {transition, 0, activate}, From, Owner);
%% Compare-and-replace preserves the old handle's retained transition on retry.
handle_call({replace, Domain, Expected}, From, Owner) ->
    enqueue_transition(Domain, {transition, Expected, replace}, From, Owner);
%% Stop uses the incarnation itself as a deterministic operation identity and allocates no successor.
handle_call({stop, Domain, Expected}, From, Owner) ->
    enqueue(Domain, {transition, Expected, stop}, From, Owner);
%% Lifetime ownership is explicit; ordinary observers never enter this registry.
handle_call({supervise, Domain}, From = {Child, _}, Owner) when node(Child) =:= node() ->
    claim_supervision(Domain, Child, From, Owner);
%% Shutdown intent is retained before waiting, including if OTP later kills this child.
handle_call({release, Domain}, From = {Child, _}, Owner = #owner{supervision = Supervision}) ->
    case maps:find(Domain, Supervision) of
        {ok, S = #supervision{child = Child, waiter = none}} ->
            Next = Owner#owner{
                supervision = Supervision#{
                    Domain := S#supervision{
                        retiring = true, waiter = From
                    }
                }
            },
            {noreply, retire_supervision(Domain, Next)};
        _ ->
            {reply, {error, not_supervised_owner}, Owner}
    end;
%% Reconnection shares the domain lane and cannot take over another live backend.
handle_call({reattach, Domain, Expected, Backend}, From, Owner) ->
    enqueue(Domain, {reattach, Expected, Backend}, From, Owner);
%% The backend checks readiness and authority atomically with resolving an endpoint.
handle_call({resolve, Identity, Actor}, From, Owner) ->
    {Domain, Expected} =
        case Identity of
            {D, E} -> {D, E};
            D -> {D, any}
        end,
    enqueue(Domain, {resolve, Expected, Actor}, From, Owner);
%% Unknown management messages do not become application work.
handle_call(_Request, _From, Owner) ->
    {reply, {error, unsupported_request}, Owner}.

-doc "Unrecognized casts cannot alter domain lifecycle state.".
-spec handle_cast(term(), #owner{}) -> {noreply, #owner{}}.
handle_cast(_Message, Owner) -> {noreply, Owner}.

-doc "Advances only the domain matching a backend response or deadline; unrelated domains remain runnable and stale observations cannot invent transitions.".
-spec handle_info(term(), #owner{}) -> {noreply, #owner{}}.
%% Deadline expiry abandons only response delivery, never an already submitted operation.
handle_info({timeout, Timer, {backend_timeout, Domain, Request}}, Owner) ->
    {noreply, timeout(Domain, Request, Timer, Owner)};
%% The owner survives the child and retains the exact lifetime that still needs retirement.
handle_info(
    Message = {'DOWN', Monitor, process, Child, _Reason}, Owner = #owner{supervision = Supervision}
) ->
    Matches = [
        Domain
     || {Domain, #supervision{child = Pid, monitor = Ref}} <- maps:to_list(Supervision),
        Pid =:= Child,
        Ref =:= Monitor
    ],
    case Matches of
        [] -> {noreply, response_message(Message, Owner)};
        _ -> {noreply, lists:foldl(fun retire_supervision/2, Owner, Matches)}
    end;
%% Failed observations retain intent; they never count as an acknowledged stop.
handle_info({retire_supervision, Domain}, Owner = #owner{supervision = Supervision}) ->
    Next =
        case maps:find(Domain, Supervision) of
            {ok, S} ->
                Owner#owner{supervision = Supervision#{Domain := S#supervision{retry = false}}};
            error ->
                Owner
        end,
    {noreply, drive_retirement(Domain, Next)};
%% OTP request aliases preserve the owner PID used by backend authority checks.
handle_info(Message, Owner) ->
    {noreply, response_message(Message, Owner)}.

%% Request aliases remain separate from lifetime monitors and consume only their own responses.
-spec response_message(term(), #owner{}) -> #owner{}.
response_message(Message, Owner = #owner{requests = Requests}) ->
    case gen_server:check_response(Message, Requests, true) of
        {{reply, Reply}, Domain, Remaining} ->
            backend_reply(Domain, Reply, Owner#owner{requests = Remaining});
        {{error, {Reason, _Backend}}, Domain, Remaining} ->
            complete(Domain, {error, {unavailable, Reason}}, Owner#owner{requests = Remaining});
        _ ->
            Owner
    end.

-doc "Retires pending response aliases and queued callers, then releases the local store lock. Backends continue to monitor this owner, not a temporary request worker.".
-spec terminate(term(), #owner{}) -> ok.
terminate(Reason, #owner{file = File, work = Work}) ->
    maps:foreach(fun(_Domain, DomainWork) -> stop_work(Reason, DomainWork) end, Work),
    hls_domain_store:release(File),
    ok.

-doc "Preserves the current owner during a host code change; no reset is implied.".
-spec code_change(term(), #owner{}, term()) -> {ok, #owner{}}.
code_change(_Old, Owner, _Extra) -> {ok, Owner}.

%% Each domain has a distinct existing controller; aliases would bypass isolation and policy.
-spec validate(catalog(), #{domain() := pid()}) -> boolean().
validate(Catalog, Endpoints) ->
    is_map(Catalog) andalso is_map(Endpoints) andalso map_size(Catalog) > 0 andalso
        lists:sort(maps:keys(Catalog)) =:= lists:sort(maps:keys(Endpoints)) andalso
        length(lists:usort(maps:values(Endpoints))) =:= map_size(Endpoints) andalso
        maps:fold(
            fun(D, P, Acc) ->
                Acc andalso is_atom(D) andalso
                    (P =:= manual orelse P =:= automatic) andalso is_pid(maps:get(D, Endpoints))
            end,
            true,
            Catalog
        ).

%% A malformed/missing store is a recovery problem rather than a fresh deployment.
-spec initialize_owner(catalog(), module(), #{domain() := pid()}, file:filename()) ->
    {ok, #owner{}} | {stop, term()}.
initialize_owner(Catalog, Module, Endpoints, File) ->
    case file:read_file(File) of
        {ok, <<Counter:64>>} ->
            try
                Authorities = maps:map(
                    fun(_D, Endpoint) ->
                        {ok, Token} = Module:attach(Endpoint, self()),
                        Token
                    end,
                    Endpoints
                ),
                {ok, #owner{
                    catalog = Catalog,
                    module = Module,
                    endpoints = Endpoints,
                    authorities = Authorities,
                    file = File,
                    next = Counter,
                    work = maps:map(fun(_Domain, _Endpoint) -> #work{} end, Endpoints)
                }}
            catch
                Class:Reason -> {stop, {domain_attach_failed, Class, Reason}}
            end;
        {ok, _} ->
            {stop, invalid_incarnation_store};
        {error, Reason} ->
            {stop, {incarnation_store, Reason}}
    end.

%% Admission order is the owner's receive order, with independent bounded queues.
-spec enqueue(domain(), operation(), caller(), #owner{}) ->
    {reply, {error, unknown_domain | busy}, #owner{}} | {noreply, #owner{}}.
enqueue(Domain, Operation, From, Owner = #owner{work = Work}) ->
    case maps:find(Domain, Work) of
        error ->
            {reply, {error, unknown_domain}, Owner};
        {ok, #work{active = none}} ->
            {noreply, start_operation(Domain, Operation, From, Owner)};
        {ok, W = #work{waiting = Waiting, queued = Count}} when Count < ?WAITING_LIMIT ->
            Next = W#work{waiting = queue:in({From, Operation}, Waiting), queued = Count + 1},
            {noreply, Owner#owner{work = Work#{Domain := Next}}};
        {ok, _} ->
            {reply, {error, busy}, Owner}
    end.

%% The full operation, including follow-up evidence, occupies one domain lane.
-spec start_operation(domain(), operation(), caller(), #owner{}) -> #owner{}.
start_operation(Domain, Operation, From, Owner = #owner{work = Work}) ->
    W = maps:get(Domain, Work),
    Pending = #pending{from = From, operation = Operation},
    Next = Owner#owner{work = Work#{Domain := W#work{active = Pending}}},
    case Operation of
        {reattach, Expected, Backend} ->
            begin_reattach(Domain, Expected, Backend, Next);
        _ ->
            send_backend(Domain, status, inspecting, Next)
    end.

%% Local process death establishes old transport retirement, not application-actor death.
-spec begin_reattach(domain(), incarnation(), pid(), #owner{}) -> #owner{}.
begin_reattach(Domain, Expected, Backend, Owner = #owner{endpoints = Endpoints}) ->
    Previous = maps:get(Domain, Endpoints),
    case
        is_integer(Expected) andalso Expected > 0 andalso Expected < (1 bsl 64) andalso
            is_pid(Backend) andalso node(Previous) =:= node() andalso
            node(Backend) =:= node()
    of
        false ->
            complete(Domain, {error, invalid_reattachment}, Owner);
        true ->
            case is_process_alive(Previous) of
                true ->
                    complete(Domain, {error, backend_still_alive}, Owner);
                false ->
                    case backend_reserved(Domain, Backend, Owner) of
                        true -> complete(Domain, {error, backend_already_bound}, Owner);
                        false -> send_backend_to(Domain, Backend, status, inspecting, Owner)
                    end
            end
    end.

%% Independent domain lanes may not concurrently claim the same candidate controller.
-spec backend_reserved(domain(), pid(), #owner{}) -> boolean().
backend_reserved(Domain, Backend, #owner{endpoints = Endpoints, work = Work}) ->
    lists:member(Backend, maps:values(Endpoints)) orelse
        maps:fold(
            fun(Other, #work{active = Active}, Reserved) ->
                Reserved orelse
                    case Active of
                        #pending{operation = {reattach, _Expected, Backend}} when
                            Other =/= Domain
                        ->
                            true;
                        _ ->
                            false
                    end
            end,
            false,
            Work
        ).

%% Submission runs in the attached owner process; backend waits never run in its callback.
-spec send_backend(domain(), hls_domain_backend:request(), stage(), #owner{}) -> #owner{}.
send_backend(
    Domain,
    Input,
    Stage,
    Owner = #owner{endpoints = Endpoints}
) ->
    send_backend_to(Domain, maps:get(Domain, Endpoints), Input, Stage, Owner).

%% Reattachment probes a candidate endpoint before it becomes the domain's binding.
-spec send_backend_to(domain(), pid(), hls_domain_backend:request(), stage(), #owner{}) -> #owner{}.
send_backend_to(
    Domain,
    Backend,
    Input,
    Stage,
    Owner = #owner{module = Module, work = Work, requests = Requests}
) ->
    Request = Module:send_request(Backend, Input),
    Timer = erlang:start_timer(?BACKEND_TIMEOUT, self(), {backend_timeout, Domain, Request}),
    W = #work{active = Pending} = maps:get(Domain, Work),
    Next = Pending#pending{stage = Stage, request = Request, timer = Timer},
    Owner#owner{
        work = Work#{Domain := W#work{active = Next}},
        requests = gen_server:reqids_add(Request, Domain, Requests)
    }.

%% Only matched evidence advances the active operation; finishing releases its FIFO successor.
-spec backend_reply(domain(), term(), #owner{}) -> #owner{}.
backend_reply(Domain, Reply, Owner = #owner{work = Work}) ->
    #work{active = #pending{operation = Operation, stage = Stage, timer = Timer}} =
        maps:get(Domain, Work),
    cancel_timer(Timer),
    case Stage of
        inspecting -> inspected(Domain, Operation, Reply, Owner);
        submitting -> submitted(Domain, Reply, Owner);
        confirming -> finish_snapshot(Domain, Reply, Owner);
        attaching -> attached(Domain, Operation, Reply, Owner);
        reattached -> confirmed_reattachment(Domain, Operation, Reply, Owner);
        resolving -> complete(Domain, Reply, Owner)
    end.

%% Inspect before allocating or resolving; backend readiness is never inferred from elapsed time.
-spec inspected(domain(), operation(), term(), #owner{}) -> #owner{}.
inspected(
    Domain,
    {reattach, Expected, Backend},
    {ok, #{state := #domain_state{current = Expected}}},
    Owner
) ->
    send_backend_to(Domain, Backend, {attach, self()}, attaching, Owner);
%% A mismatching candidate never acquires this owner or becomes its binding.
inspected(Domain, {reattach, _Expected, _Backend}, {ok, _}, Owner) ->
    complete(Domain, {error, incarnation_not_ready}, Owner);
%% Ordinary status preserves the backend's full observation.
inspected(Domain, status, Reply, Owner) ->
    finish_snapshot(Domain, Reply, Owner);
inspected(
    Domain,
    {resolve, Expected, Actor},
    {ok, #{state := #domain_state{phase = ready, current = Current}}},
    Owner
) when
    Expected =:= any; Expected =:= Current
->
    send_backend(Domain, {endpoint, authority(Domain, Owner), Current, Actor}, resolving, Owner);
inspected(Domain, {resolve, _Expected, _Actor}, {ok, _}, Owner) ->
    complete(Domain, {error, not_ready}, Owner);
%% Claim inspection binds the representative before it can submit startup or expose endpoints.
inspected(Domain, {supervise, Child}, {ok, Evidence = #{state := State}}, Owner) ->
    Next = bind_supervision(Domain, Child, observed_incarnation(State), Owner),
    complete(Domain, {ok, describe_evidence(Domain, Evidence)}, Next);
%% An acquired lifetime excludes other transition callers while its initial identity observation is unresolved.
inspected(Domain, retire, {ok, Evidence}, Owner) ->
    retire_evidence(Domain, Evidence, Owner);
%% A stale explicit stop never aliases the previous replace operation.
inspected(
    Domain, {transition, Expected, stop}, {ok, #{state := #domain_state{current = Current}}}, Owner
) when
    Expected =/= Current; Expected =:= 0
->
    complete(Domain, {error, stale}, Owner);
%% A repeated completed stop reuses its retained evidence and cannot create a successor.
inspected(
    Domain,
    {transition, _Expected, stop},
    {ok, #{state := #domain_state{phase = stopped}} = Evidence},
    Owner
) ->
    complete(Domain, {ok, describe_evidence(Domain, Evidence)}, Owner);
%% The kernel rejects unresolved replacement or initialization rather than erasing its target.
inspected(Domain, {transition, Expected, stop}, {ok, _Evidence}, Owner) ->
    Input = #domain_input{op = stop, expected = Expected, target = Expected, transition = Expected},
    send_backend(Domain, {request, authority(Domain, Owner), Input}, submitting, Owner);
inspected(
    Domain,
    {transition, Expected, Operation},
    {ok,
        #{state := #domain_state{previous = Expected, target = Target, transition = Id}} = Evidence},
    Owner
) when
    Id =/= 0,
    Target > Expected,
    ((Operation =:= activate andalso Expected =:= 0) orelse
        (Operation =:= replace andalso Expected =/= 0))
->
    complete(Domain, {ok, describe_evidence(Domain, Evidence)}, Owner);
inspected(
    Domain,
    {transition, Expected, Operation},
    {ok, #{state := State = #domain_state{current = Expected, phase = Phase}}},
    Owner
) when
    Phase =:= unbound; Phase =:= ready; Phase =:= failed; Phase =:= stopped
->
    allocate_transition(Domain, Operation, State, Owner);
inspected(Domain, {transition, _Expected, _Operation}, {ok, _}, Owner) ->
    complete(Domain, {error, stale_or_busy}, Owner);
inspected(Domain, _Operation, Error, Owner) ->
    complete(Domain, Error, Owner).

%% Only a matching ready observation permits attachment; the backend checks the actual owner PID.
-spec attached(domain(), operation(), term(), #owner{}) -> #owner{}.
attached(
    Domain,
    {reattach, _Expected, Backend},
    {ok, Authority},
    Owner = #owner{endpoints = Endpoints, authorities = Authorities}
) when is_reference(Authority) ->
    Next = Owner#owner{
        endpoints = Endpoints#{Domain := Backend},
        authorities = Authorities#{Domain := Authority}
    },
    send_backend(Domain, status, reattached, Next);
%% Refused attachment leaves the old dead binding in place.
attached(Domain, _Operation, Error, Owner) ->
    complete(Domain, Error, Owner).

%% A changed or unavailable confirmation is not proof of reconnection; the new binding remains inspectable.
-spec confirmed_reattachment(domain(), operation(), term(), #owner{}) -> #owner{}.
confirmed_reattachment(
    Domain,
    {reattach, Expected, _Backend},
    {ok, #{state := #domain_state{current = Expected}}} = Reply,
    Owner
) ->
    finish_snapshot(Domain, Reply, Owner);
%% Identity or readiness may change while attachment is in flight.
confirmed_reattachment(Domain, _Operation, {ok, _}, Owner) ->
    complete(Domain, {error, incarnation_not_ready}, Owner);
%% A lost confirmation is an unknown outcome, not a cancellation of attachment.
confirmed_reattachment(Domain, _Operation, Error, Owner) ->
    complete(Domain, Error, Owner).

%% A synchronous ready disposition requires matching actor evidence before binding a supervisor.
-spec submitted(domain(), term(), #owner{}) -> #owner{}.
submitted(Domain, #domain_output{status = Status, state = Result}, Owner) when
    Status =:= accepted; Status =:= replay
->
    case Result#domain_state.phase of
        Phase when Phase =:= ready; Phase =:= stopped ->
            send_backend(Domain, status, confirming, Owner);
        _ ->
            complete(Domain, {ok, describe(Domain, Result, none)}, Owner)
    end;
submitted(Domain, #domain_output{status = Status, state = State}, Owner) ->
    Next = reconcile_rejected_target(Domain, State, Owner),
    complete(Domain, {error, {rejected, Status}}, Next);
submitted(Domain, Error, Owner) ->
    complete(Domain, Error, Owner).

%% Backend snapshots carry the actors and lifecycle phase observed together.
-spec finish_snapshot(domain(), term(), #owner{}) -> #owner{}.
finish_snapshot(Domain, {ok, Evidence}, Owner) ->
    complete(Domain, {ok, describe_evidence(Domain, Evidence)}, Owner);
finish_snapshot(Domain, Error, Owner) ->
    complete(Domain, Error, Owner).

%% Replies to abandoned caller aliases are discarded by OTP; they never repeat the operation.
-spec complete(domain(), term(), #owner{}) -> #owner{}.
complete(Domain, Reply, Owner = #owner{work = Work}) ->
    W = #work{active = #pending{from = From, timer = Timer}} = maps:get(Domain, Work),
    cancel_timer(Timer),
    Next = Owner#owner{work = Work#{Domain := W#work{active = none}}},
    Replied =
        case From of
            retirement ->
                retirement_reply(Domain, Reply, Next);
            _ ->
                gen_server:reply(From, Reply),
                Next
        end,
    advance_queue(Domain, Replied).

%% Retirement gets a reserved turn after the active operation; external waiting calls retain relative FIFO order.
-spec advance_queue(domain(), #owner{}) -> #owner{}.
advance_queue(Domain, Owner = #owner{work = Work, supervision = Supervision}) ->
    case maps:find(Domain, Supervision) of
        {ok, #supervision{retiring = true, retry = false}} ->
            drive_retirement(Domain, Owner);
        _ ->
            W = #work{waiting = Waiting, queued = Count} = maps:get(Domain, Work),
            case queue:out(Waiting) of
                {empty, _} ->
                    Owner;
                {{value, {NextFrom, Operation}}, Remaining} ->
                    Next = W#work{waiting = Remaining, queued = Count - 1},
                    start_operation(Domain, Operation, NextFrom, Owner#owner{
                        work = Work#{Domain := Next}
                    })
            end
    end.

%% A deadline races only its own response; a later stage or operation has a different timer.
-spec timeout(domain(), gen_server:request_id(), reference(), #owner{}) -> #owner{}.
timeout(Domain, Request, Timer, Owner = #owner{work = Work, requests = Requests}) ->
    case maps:find(Domain, Work) of
        {ok, #work{active = #pending{request = Request, timer = Timer}}} ->
            Remaining = lists:foldl(
                fun({Id, Label}, Acc) ->
                    case Id =:= Request of
                        true -> Acc;
                        false -> gen_server:reqids_add(Id, Label, Acc)
                    end
                end,
                gen_server:reqids_new(),
                gen_server:reqids_to_list(Requests)
            ),
            Next = Owner#owner{requests = Remaining},
            case gen_server:receive_response(Request, 0) of
                {reply, Reply} ->
                    backend_reply(Domain, Reply, Next);
                {error, {Reason, _Backend}} ->
                    complete(Domain, {error, {unavailable, Reason}}, Next);
                timeout ->
                    complete(Domain, {error, {unavailable, timeout}}, Next)
            end;
        _ ->
            Owner
    end.

%% Retiring a timer does not flush another stage's deadline already in the mailbox.
-spec cancel_timer(undefined | reference()) -> ok.
cancel_timer(undefined) ->
    ok;
cancel_timer(Timer) ->
    erlang:cancel_timer(Timer, [{async, true}, {info, false}]),
    ok.

%% Owner shutdown abandons responses but does not cancel or replay hardware work.
-spec stop_work(term(), #work{}) -> ok.
stop_work(Reason, #work{active = Active, waiting = Waiting}) ->
    case Active of
        none ->
            ok;
        #pending{from = From, request = Request, timer = Timer} ->
            cancel_timer(Timer),
            _ = catch gen_server:receive_response(Request, 0),
            reply_caller(From, {error, {owner_stopped, Reason}})
    end,
    lists:foreach(
        fun({From, _}) -> reply_caller(From, {error, {owner_stopped, Reason}}) end,
        queue:to_list(Waiting)
    ),
    ok.

%% Keep the control token private to the deployment owner.
-spec authority(domain(), #owner{}) -> hls_domain_backend:authority().
authority(Domain, #owner{authorities = Authorities}) -> maps:get(Domain, Authorities).

%% Readiness and its actor identities come from the same backend observation.
-spec describe_evidence(domain(), hls_domain_backend:snapshot()) -> snapshot().
describe_evidence(Domain, #{state := State, actors := Actors, fault_reason := Reason}) ->
    Description = describe(Domain, State, Reason),
    case State#domain_state.phase of
        ready -> Description#{actors := Actors};
        _ -> Description
    end.

%% Phase names are presentation of the shared finite enum, not another state machine.
-spec describe(domain(), hls_domain_lifecycle:state(), term()) -> snapshot().
describe(
    Domain,
    #domain_state{
        phase = Phase, current = Current, target = Target, transition = Transition, fault = Fault
    },
    Detail
) ->
    Handle =
        case Current of
            0 -> none;
            _ -> {Domain, Current}
        end,
    #{
        domain => Domain,
        phase => Phase,
        handle => Handle,
        target => Target,
        transition => Transition,
        fault => Fault,
        detail => Detail,
        actors => #{}
    }.

%% The owner alone burns a durable ID before asynchronous submission, including lost replies.
-spec allocate_transition(
    domain(), hls_domain_lifecycle:operation(), hls_domain_lifecycle:state(), #owner{}
) -> #owner{}.
allocate_transition(
    Domain, Operation, State, Owner = #owner{work = Work, supervision = Supervision}
) ->
    #work{active = #pending{from = From}} = maps:get(Domain, Work),
    case {From, maps:find(Domain, Supervision)} of
        {{Child, _}, {ok, #supervision{child = Child, retiring = false}}} ->
            allocate_live_transition(Domain, Operation, State, Owner);
        {_, {ok, _}} ->
            complete(Domain, {error, supervised}, Owner);
        _ ->
            allocate_live_transition(Domain, Operation, State, Owner)
    end.

%% The identity is persisted before submission and retained by the supervising owner before any reply.
-spec allocate_live_transition(
    domain(), hls_domain_lifecycle:operation(), hls_domain_lifecycle:state(), #owner{}
) -> #owner{}.
allocate_live_transition(Domain, Operation, State, Owner = #owner{next = Counter, file = File}) ->
    Previous = State#domain_state.current,
    Last = max(Counter, max(Previous, State#domain_state.target)),
    case Last < (1 bsl 64) - 1 of
        false ->
            complete(Domain, {error, incarnation_exhausted}, Owner);
        true ->
            Target = Last + 1,
            case persist(File, Target) of
                ok ->
                    Input = #domain_input{
                        op = Operation, expected = Previous, target = Target, transition = Target
                    },
                    Next = bind_allocated(Domain, Target, Owner#owner{next = Target}),
                    send_backend(
                        Domain, {request, authority(Domain, Owner), Input}, submitting, Next
                    );
                {error, Reason} ->
                    complete(Domain, {error, {incarnation_store, Reason}}, Owner)
            end
    end.

%% An explicit supervised lifetime has one transition authority; independent callers may still stop its exact incarnation.
-spec enqueue_transition(domain(), operation(), gen_server:from(), #owner{}) ->
    {reply, {error, term()}, #owner{}} | {noreply, #owner{}}.
enqueue_transition(
    Domain, Operation, From = {Caller, _}, Owner = #owner{supervision = Supervision}
) ->
    case maps:find(Domain, Supervision) of
        error ->
            enqueue(Domain, Operation, From, Owner);
        {ok, #supervision{child = Caller, retiring = false}} ->
            enqueue(Domain, Operation, From, Owner);
        {ok, _} ->
            {reply, {error, supervised}, Owner}
    end.

%% Registry ownership is local and exclusive; another live representative cannot steal the lifetime.
-spec claim_supervision(domain(), pid(), gen_server:from(), #owner{}) ->
    {reply, {error, term()}, #owner{}} | {noreply, #owner{}}.
claim_supervision(
    Domain, Child, From, Owner = #owner{catalog = Catalog, supervision = Supervision}
) ->
    case maps:find(Domain, Catalog) of
        {ok, automatic} ->
            case maps:find(Domain, Supervision) of
                error ->
                    S = #supervision{child = Child, monitor = monitor(process, Child)},
                    Claimed = Owner#owner{supervision = Supervision#{Domain => S}},
                    case enqueue(Domain, {supervise, Child}, From, Claimed) of
                        {reply, Error, _Rejected} ->
                            demonitor(S#supervision.monitor, [flush]),
                            {reply, Error, Owner};
                        Accepted ->
                            Accepted
                    end;
                {ok, #supervision{child = Child, retiring = false}} ->
                    enqueue(Domain, {supervise, Child}, From, Owner);
                {ok, #supervision{child = Previous, retiring = Retiring}} ->
                    case Retiring orelse not is_process_alive(Previous) of
                        true -> {reply, {error, retiring}, retire_supervision(Domain, Owner)};
                        false -> {reply, {error, supervised}, Owner}
                    end
            end;
        {ok, manual} ->
            {reply, {error, manual_replacement_required}, Owner};
        error ->
            {reply, {error, unknown_domain}, Owner}
    end.

%% A startup transition owns its target even before reset installs it as current.
-spec observed_incarnation(hls_domain_lifecycle:state()) -> non_neg_integer().
observed_incarnation(#domain_state{current = Current, target = Target}) -> max(Current, Target).

%% Only this representative's own inspection can bind its previously unknown lifetime.
-spec bind_supervision(domain(), pid(), non_neg_integer(), #owner{}) -> #owner{}.
bind_supervision(Domain, Child, Incarnation, Owner = #owner{supervision = Supervision}) ->
    case maps:find(Domain, Supervision) of
        {ok, S = #supervision{child = Child, incarnation = unknown}} ->
            Owner#owner{
                supervision = Supervision#{Domain := S#supervision{incarnation = Incarnation}}
            };
        _ ->
            Owner
    end.

%% Allocation records an owning child's exact target before an asynchronous request can reach hardware.
-spec bind_allocated(domain(), incarnation(), #owner{}) -> #owner{}.
bind_allocated(Domain, Target, Owner = #owner{work = Work, supervision = Supervision}) ->
    #work{active = #pending{from = From}} = maps:get(Domain, Work),
    case {From, maps:find(Domain, Supervision)} of
        {{Child, _}, {ok, S = #supervision{child = Child, retiring = false}}} ->
            Owner#owner{supervision = Supervision#{Domain := S#supervision{incarnation = Target}}};
        _ ->
            Owner
    end.

%% Local death retains shutdown intent even when its notification loses the race to a new child.
-spec retire_supervision(domain(), #owner{}) -> #owner{}.
retire_supervision(Domain, Owner = #owner{supervision = Supervision}) ->
    case maps:find(Domain, Supervision) of
        {ok, S} ->
            Next = Owner#owner{
                supervision = Supervision#{Domain := S#supervision{retiring = true}}
            },
            drive_retirement(Domain, withdraw_startup(Domain, S#supervision.child, Next));
        error ->
            Owner
    end.

%% Only a supervised caller's not-yet-submitted startup can be withdrawn; accepted backend work is retained.
-spec withdraw_startup(domain(), pid(), #owner{}) -> #owner{}.
withdraw_startup(Domain, Child, Owner = #owner{work = Work}) ->
    W = #work{waiting = Waiting} = maps:get(Domain, Work),
    Retained = lists:filter(
        fun
            ({{Caller, _} = From, {transition, _Expected, Op}}) when
                Caller =:= Child, (Op =:= activate orelse Op =:= replace)
            ->
                gen_server:reply(From, {error, supervised}),
                false;
            (_) ->
                true
        end,
        queue:to_list(Waiting)
    ),
    Owner#owner{
        work = Work#{
            Domain := W#work{waiting = queue:from_list(Retained), queued = length(Retained)}
        }
    }.

%% A definitive kernel rejection supplies current controller state; a transport error supplies no such evidence.
-spec reconcile_rejected_target(domain(), hls_domain_lifecycle:state(), #owner{}) -> #owner{}.
reconcile_rejected_target(Domain, State, Owner = #owner{work = Work, supervision = Supervision}) ->
    #work{active = #pending{from = From}} = maps:get(Domain, Work),
    case {From, maps:find(Domain, Supervision)} of
        {{Child, _}, {ok, S = #supervision{child = Child}}} ->
            Owner#owner{
                supervision = Supervision#{
                    Domain := S#supervision{
                        incarnation = observed_incarnation(State)
                    }
                }
            };
        _ ->
            Owner
    end.

%% One internal observation uses the existing asynchronous lane; no application messages pass here.
-spec drive_retirement(domain(), #owner{}) -> #owner{}.
drive_retirement(Domain, Owner = #owner{supervision = Supervision, work = Work}) ->
    case {maps:find(Domain, Supervision), maps:find(Domain, Work)} of
        {{ok, #supervision{retiring = true, retry = false}}, {ok, #work{active = none}}} ->
            start_operation(Domain, retire, retirement, Owner);
        _ ->
            Owner
    end.

%% Initial claim reconciliation observes only the already-owned controller; exclusive transition authority prevents a later claimant from replacing it.
-spec retire_evidence(domain(), hls_domain_backend:snapshot(), #owner{}) -> #owner{}.
retire_evidence(Domain, Evidence = #{state := State}, Owner = #owner{supervision = Supervision}) ->
    S = #supervision{incarnation = Expected} = maps:get(Domain, Supervision),
    case Expected of
        unknown ->
            Next = Owner#owner{
                supervision = Supervision#{
                    Domain := S#supervision{
                        incarnation = observed_incarnation(State)
                    }
                }
            },
            retire_evidence(Domain, Evidence, Next);
        0 ->
            complete(Domain, retired, Owner);
        _ ->
            Current = State#domain_state.current,
            case {Current, State#domain_state.phase} of
                {Expected, stopped} ->
                    complete(Domain, retired, Owner);
                {Newer, _} when Newer > Expected -> complete(Domain, retired, Owner);
                {Expected, Phase} when Phase =:= ready; Phase =:= failed ->
                    Input = #domain_input{
                        op = stop,
                        expected = Expected,
                        target = Expected,
                        transition = Expected
                    },
                    send_backend(
                        Domain, {request, authority(Domain, Owner), Input}, submitting, Owner
                    );
                _ ->
                    complete(Domain, pending, Owner)
            end
    end.

%% Only an observed retired boundary releases ownership; all other outcomes retain bounded intent.
-spec retirement_reply(domain(), term(), #owner{}) -> #owner{}.
retirement_reply(Domain, Reply, Owner = #owner{supervision = Supervision}) ->
    S = maps:get(Domain, Supervision),
    case Reply of
        retired ->
            demonitor(S#supervision.monitor, [flush]),
            case S#supervision.waiter of
                none -> ok;
                From -> gen_server:reply(From, ok)
            end,
            Owner#owner{supervision = maps:remove(Domain, Supervision)};
        _ ->
            erlang:send_after(50, self(), {retire_supervision, Domain}),
            Owner#owner{supervision = Supervision#{Domain := S#supervision{retry = true}}}
    end.

%% Internal observations have no waiting user; external aliases retain ordinary OTP delivery behavior.
-spec reply_caller(caller(), term()) -> ok.
reply_caller(retirement, _Reply) -> ok;
reply_caller(From, Reply) -> gen_server:reply(From, Reply).

%% Atomic replacement preserves the previous valid counter if writing fails before rename.
-spec persist(file:filename(), incarnation()) -> ok | {error, term()}.
persist(Path, Counter) ->
    Temporary = Path ++ "." ++ integer_to_list(erlang:unique_integer([positive, monotonic])),
    case file:open(Temporary, [write, binary, raw, exclusive]) of
        {ok, File} ->
            Result =
                try
                    ok = file:write(File, <<Counter:64>>),
                    ok = file:sync(File),
                    ok = file:close(File),
                    file:rename(Temporary, Path)
                catch
                    error:{badmatch, {error, Reason}} -> {error, Reason}
                after
                    file:close(File)
                end,
            case Result of
                ok ->
                    ok;
                _ ->
                    file:delete(Temporary),
                    Result
            end;
        Error ->
            Error
    end.
