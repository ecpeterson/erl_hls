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
-export([create_store/1, start_link/2, status/2, activate/2, replace/2, resolve/3, policy/2]).
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
    | {resolve, any | incarnation(), term()}.
%% Inspection precedes authenticated resolution/submission; ready submission needs fresh actors.
-type stage() :: inspecting | resolving | submitting | confirming.
%% Correlation belongs to this owner, so backends still observe the actual attached caller.
-record(pending, {
    from :: gen_server:from(),
    operation :: operation(),
    stage = inspecting :: stage(),
    request :: undefined | gen_server:request_id(),
    timer :: undefined | reference()
}).
%% The queue retains only management requests, never application work or actor state.
-record(work, {
    active = none :: none | #pending{},
    waiting = queue:new() :: queue:queue({gen_server:from(), operation()}),
    queued = 0 :: 0..?WAITING_LIMIT
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
    requests = gen_server:reqids_new() :: gen_server:request_id_collection()
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
    enqueue(Domain, {transition, 0, activate}, From, Owner);
%% Compare-and-replace preserves the old handle's retained transition on retry.
handle_call({replace, Domain, Expected}, From, Owner) ->
    enqueue(Domain, {transition, Expected, replace}, From, Owner);
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
%% OTP request aliases preserve the owner PID used by backend authority checks.
handle_info(Message, Owner = #owner{requests = Requests}) ->
    case gen_server:check_response(Message, Requests, true) of
        {{reply, Reply}, Domain, Remaining} ->
            {noreply, backend_reply(Domain, Reply, Owner#owner{requests = Remaining})};
        {{error, {Reason, _Backend}}, Domain, Remaining} ->
            {noreply,
                complete(
                    Domain,
                    {error, {unavailable, Reason}},
                    Owner#owner{requests = Remaining}
                )};
        _ ->
            {noreply, Owner}
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
-spec enqueue(domain(), operation(), gen_server:from(), #owner{}) ->
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
-spec start_operation(domain(), operation(), gen_server:from(), #owner{}) -> #owner{}.
start_operation(Domain, Operation, From, Owner = #owner{work = Work}) ->
    W = maps:get(Domain, Work),
    Pending = #pending{from = From, operation = Operation},
    Next = Owner#owner{work = Work#{Domain := W#work{active = Pending}}},
    send_backend(Domain, status, inspecting, Next).

%% Submission runs in the attached owner process; backend waits never run in its callback.
-spec send_backend(domain(), hls_domain_backend:request(), stage(), #owner{}) -> #owner{}.
send_backend(
    Domain,
    Input,
    Stage,
    Owner = #owner{module = Module, endpoints = Endpoints, work = Work, requests = Requests}
) ->
    Request = Module:send_request(maps:get(Domain, Endpoints), Input),
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
        resolving -> complete(Domain, Reply, Owner)
    end.

%% Inspect before allocating or resolving; backend readiness is never inferred from elapsed time.
-spec inspected(domain(), operation(), term(), #owner{}) -> #owner{}.
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
inspected(
    Domain,
    {transition, Expected, _Operation},
    {ok, #{state := #domain_state{previous = Expected, transition = Id}} = Evidence},
    Owner
) when
    Id =/= 0
->
    complete(Domain, {ok, describe_evidence(Domain, Evidence)}, Owner);
inspected(
    Domain,
    {transition, Expected, Operation},
    {ok, #{state := State = #domain_state{current = Expected, phase = Phase}}},
    Owner
) when
    Phase =:= unbound; Phase =:= ready; Phase =:= failed
->
    allocate_transition(Domain, Operation, State, Owner);
inspected(Domain, {transition, _Expected, _Operation}, {ok, _}, Owner) ->
    complete(Domain, {error, stale_or_busy}, Owner);
inspected(Domain, _Operation, Error, Owner) ->
    complete(Domain, Error, Owner).

%% A synchronous ready disposition requires matching actor evidence before binding a supervisor.
-spec submitted(domain(), term(), #owner{}) -> #owner{}.
submitted(Domain, #domain_output{status = Status, state = Result}, Owner) when
    Status =:= accepted; Status =:= replay
->
    case Result#domain_state.phase of
        ready -> send_backend(Domain, status, confirming, Owner);
        _ -> complete(Domain, {ok, describe(Domain, Result, none)}, Owner)
    end;
submitted(Domain, #domain_output{status = Status}, Owner) ->
    complete(Domain, {error, {rejected, Status}}, Owner);
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
    W =
        #work{active = #pending{from = From, timer = Timer}, waiting = Waiting, queued = Count} =
        maps:get(Domain, Work),
    cancel_timer(Timer),
    gen_server:reply(From, Reply),
    case queue:out(Waiting) of
        {empty, _} ->
            Owner#owner{work = Work#{Domain := W#work{active = none}}};
        {{value, {NextFrom, Operation}}, Remaining} ->
            Next = W#work{active = none, waiting = Remaining, queued = Count - 1},
            start_operation(Domain, Operation, NextFrom, Owner#owner{work = Work#{Domain := Next}})
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
            gen_server:reply(From, {error, {owner_stopped, Reason}})
    end,
    lists:foreach(
        fun({From, _}) -> gen_server:reply(From, {error, {owner_stopped, Reason}}) end,
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
allocate_transition(Domain, Operation, State, Owner = #owner{next = Counter, file = File}) ->
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
                    Next = Owner#owner{next = Target},
                    send_backend(
                        Domain, {request, authority(Domain, Owner), Input}, submitting, Next
                    );
                {error, Reason} ->
                    complete(Domain, {error, {incarnation_store, Reason}}, Owner)
            end
    end.

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
