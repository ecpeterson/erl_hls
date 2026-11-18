-module(hls_domain_owner).
-moduledoc false.
%% Internal gen_server behind hls_domain and hls_domain_instance. One owner retains
%% bounded per-domain management lanes, startup claims and shutdown intent; no
%% application messages pass through it. Caller identity is the actual OTP child.
-behaviour(gen_server).
-include_lib("hls_runtime/include/hls_domain_lifecycle.hrl").

%% Facade attachment; this creates the existing owner, not a relay process.
-export([start_link/2]).
%% OTP adapter protocol: policy, single-use preparation, lifetime claim and release.
-export([policy/2, prepare/2, claim/2, claim/3, release/2]).
%% Internal asynchronous transition access for lifecycle adapters and witnesses.
-export([request_stop/2]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% Private protocol token; applications use hls_domain_instance:startup() instead.
-export_type([startup_token/0]).

-doc "One owner's single-use startup token, invalid after consumption, revocation or owner death.".
-opaque startup_token() :: reference().
%% Shared facade contract for domain.
-type domain() :: hls_domain:domain().
%% Shared facade contract for incarnation.
-type incarnation() :: hls_domain:incarnation().
%% Shared facade contract for handle.
-type handle() :: hls_domain:handle().
%% Shared facade contract for policy.
-type policy() :: hls_domain:policy().
%% Shared facade contract for catalog.
-type catalog() :: hls_domain:catalog().
%% Shared facade contract for backend.
-type backend() :: hls_domain:backend().
%% Shared facade contract for snapshot.
-type snapshot() :: hls_domain:snapshot().

%% One active operation and eight waiting requests bound retained work per domain.
-define(WAITING_LIMIT, 8).
-define(BACKEND_TIMEOUT, 5000).

%% All stages of one operation precede the next accepted operation in its domain.
-type operation() ::
    status
    | {transition, non_neg_integer(), hls_domain_lifecycle:operation()}
    | {resolve, any | incarnation(), term()}
    | {reattach, incarnation(), pid()}
    | {claim, pid()}
    | {claim, pid(), non_neg_integer()}
    | {prepare, startup_token()}
    | {begin_stop, incarnation()}
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
    startup = automatic :: automatic | {prepared, non_neg_integer()} | spent,
    retiring = false :: boolean(),
    retired = false :: boolean(),
    waiter = none :: none | gen_server:from(),
    retry = false :: boolean()
}).
%% The owner retains authority tokens, never source actor state or an application work log.
-record(owner, {
    %% Pending inspection reserves the slot; only confirmed retirement binds its predecessor.
    preparations = #{} :: #{domain() => {startup_token(), pending | non_neg_integer()}},
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

-doc "Attaches to existing domain controllers without resetting or activating their actors.".
-spec start_link(catalog(), backend()) -> gen_server:start_ret().
start_link(Catalog, Backend) -> gen_server:start_link(?MODULE, {Catalog, Backend}, []).

-doc "Returns the deployment's declared policy without initiating a lifecycle operation.".
-spec policy(pid(), domain()) -> {ok, policy()} | {error, unknown_domain}.
policy(Owner, Domain) -> gen_server:call(Owner, {policy, Domain}).

-doc "Prepares one supervised startup of a manual domain, only after observed unbound/stopped state and prior lifetime release. Does not start hardware. Duplicate grants reject; an uncertain reply must be reconciled with hls_domain:stop/3 before requesting another. No permission survives owner restart.".
-spec prepare(pid(), domain()) -> {ok, startup_token()} | {error, term()}.
prepare(Owner, Domain) -> gen_server:call(Owner, {prepare, Domain}).

-doc "Claims this local caller as the sole supervised representative before startup. Its death retains retirement intent in the surviving owner. Existing retirement must finish before another child can claim the domain.".
-spec claim(pid(), domain()) -> {ok, snapshot()} | {error, term()}.
claim(Owner, Domain) -> gen_server:call(Owner, {claim, Domain}).

-doc "Requests retirement of this caller's supervised lifetime and waits for backend confirmation. The caller's supervisor supplies the shutdown deadline; killing the caller does not cancel retained intent. Owner or transport failure cannot establish successful retirement.".
-spec release(pid(), domain()) -> ok | {error, term()}.
release(Owner, Domain) -> gen_server:call(Owner, {release, Domain}, infinity).

-doc "Consumes a manual domain's prepared startup for this local supervised child. Consumption precedes asynchronous startup; a spent, revoked or foreign grant cannot acquire another incarnation. Busy admission leaves an unconsumed grant intact.".
-spec claim(pid(), domain(), startup_token()) -> {ok, snapshot()} | {error, term()}.
claim(Owner, Domain, Token) ->
    gen_server:call(Owner, {claim, Domain, Token}).

-doc "Stops exactly this incarnation without allocating a successor or replaying work. A closing result is accepted intent; stopped requires actual backend retirement. Repetition is idempotent, and a stale handle cannot stop its successor.".
-spec request_stop(pid(), handle()) -> {ok, snapshot()} | {error, term()}.
request_stop(Owner, {Domain, Incarnation}) -> gen_server:call(Owner, {stop, Domain, Incarnation}).

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
%% Reserve one grant before inspection so revocation also cancels a delayed preparation.
handle_call({prepare, Domain}, From, Owner) ->
    begin_preparation(Domain, From, Owner);
%% Withdrawal cannot erase an already-owned lifetime's stop intent.
handle_call(
    {begin_stop, Domain, unknown}, _From, Owner = #owner{catalog = Catalog, preparations = Grants}
) ->
    case maps:is_key(Domain, Catalog) of
        true ->
            Next = Owner#owner{preparations = maps:remove(Domain, Grants)},
            {reply, ok, retire_supervision(Domain, Next)};
        false ->
            {reply, {error, unknown_domain}, Owner}
    end;
%% An exact stop must first inspect the current/target identity before withdrawing startup.
handle_call({begin_stop, Domain, Expected}, From, Owner) ->
    enqueue(Domain, {begin_stop, Expected}, From, Owner);
%% A stopped backend alone does not release a still-owned supervised lifetime.
handle_call({retirement_released, Domain}, _From, Owner = #owner{supervision = Supervision}) ->
    {reply, not maps:is_key(Domain, Supervision), Owner};
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
handle_call({claim, Domain}, From = {Child, _}, Owner) when node(Child) =:= node() ->
    claim_supervision(Domain, Child, From, Owner);
%% An explicit grant permits supervision without enabling automatic replacement.
handle_call({claim, Domain, Token}, From = {Child, _}, Owner) when
    node(Child) =:= node()
->
    claim_prepared(Domain, Token, Child, From, Owner);
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
%% Do not revoke a successor's prepared startup or lifetime on a stale exact request.
inspected(
    Domain,
    {begin_stop, Expected},
    {ok, #{state := State}},
    Owner = #owner{preparations = Preparations}
) ->
    case observed_incarnation(State) of
        Expected ->
            Next = Owner#owner{preparations = maps:remove(Domain, Preparations)},
            complete(Domain, ok, retire_supervision(Domain, Next));
        Actual ->
            complete(Domain, {error, {incarnation_changed, Expected, Actual}}, Owner)
    end;
%% Ordinary status preserves the backend's full observation.
inspected(Domain, status, Reply, Owner) ->
    finish_snapshot(Domain, Reply, Owner);
%% Permission names the retired predecessor; a live or uncertain controller cannot grant it.
inspected(
    Domain,
    {prepare, Token},
    {ok, #{state := #domain_state{phase = Phase, current = Current}}},
    Owner = #owner{preparations = Grants}
) ->
    case {maps:find(Domain, Grants), Phase} of
        {{ok, {Token, pending}}, P} when P =:= unbound; P =:= stopped ->
            complete(Domain, {ok, Token}, Owner#owner{
                preparations = Grants#{Domain := {Token, Current}}
            });
        {{ok, {Token, pending}}, _} ->
            complete(Domain, {error, not_retired}, Owner);
        _ ->
            complete(Domain, {error, startup_revoked}, Owner)
    end;
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
inspected(Domain, {claim, Child}, {ok, Evidence = #{state := State}}, Owner) ->
    Next = bind_supervision(Domain, Child, observed_incarnation(State), Owner),
    complete(Domain, {ok, describe_evidence(Domain, Evidence)}, Next);
%% A single-use claim cannot attach to live work or follow a changed predecessor.
inspected(
    Domain,
    {claim, Child, Expected},
    {ok, #{state := #domain_state{current = Expected, phase = Phase}}} = Reply,
    Owner
) when
    Phase =:= unbound; Phase =:= stopped
->
    inspected(Domain, {claim, Child}, Reply, Owner);
inspected(Domain, {claim, _Child, _Expected}, {ok, _}, Owner) ->
    complete(Domain, {error, startup_stale}, Owner);
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
    W =
        #work{active = #pending{from = From, timer = Timer, operation = Operation}} = maps:get(
            Domain, Work
        ),
    cancel_timer(Timer),
    Cleared = finish_preparation(Domain, Operation, Reply, Owner),
    Next = Cleared#owner{work = Work#{Domain := W#work{active = none}}},
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
        {ok, #supervision{retiring = true, retired = false, retry = false}} ->
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
    Domain, _Operation, _State, Owner = #owner{preparations = Grants}
) when is_map_key(Domain, Grants) ->
    complete(Domain, {error, prepared}, Owner);
allocate_transition(
    Domain, Operation, State, Owner = #owner{work = Work, supervision = Supervision}
) ->
    #work{active = #pending{from = From}} = maps:get(Domain, Work),
    case {From, maps:find(Domain, Supervision)} of
        {{Child, _}, {ok, #supervision{child = Child, retiring = false, startup = Startup}}} when
            Startup =:= automatic; Startup =:= {prepared, State#domain_state.current}
        ->
            allocate_live_transition(Domain, Operation, State, Owner);
        {{Child, _}, {ok, #supervision{child = Child, retiring = false}}} ->
            complete(Domain, {error, startup_spent}, Owner);
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
    Domain, _Operation, _From, Owner = #owner{preparations = Grants}
) when is_map_key(Domain, Grants) ->
    {reply, {error, prepared}, Owner};
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

%% Reservation precedes the asynchronous observation; busy admission restores the unreserved owner.
-spec begin_preparation(domain(), gen_server:from(), #owner{}) ->
    {reply, {error, term()}, #owner{}} | {noreply, #owner{}}.
begin_preparation(
    Domain,
    From,
    Owner = #owner{
        catalog = Catalog,
        preparations = Grants,
        supervision = Supervision
    }
) ->
    case
        {maps:find(Domain, Catalog), maps:is_key(Domain, Grants), maps:is_key(Domain, Supervision)}
    of
        {error, _, _} ->
            {reply, {error, unknown_domain}, Owner};
        {{ok, automatic}, _, _} ->
            {reply, {error, automatic_replacement}, Owner};
        {_, true, _} ->
            {reply, {error, already_prepared}, Owner};
        {_, _, true} ->
            {reply, {error, supervised}, Owner};
        {{ok, manual}, false, false} ->
            Token = make_ref(),
            Reserved = Owner#owner{preparations = Grants#{Domain => {Token, pending}}},
            case enqueue(Domain, {prepare, Token}, From, Reserved) of
                {reply, Error, _} -> {reply, Error, Owner};
                Accepted -> Accepted
            end
    end.

%% A failed old request cannot erase a newer reservation made after revocation.
-spec finish_preparation(domain(), operation(), term(), #owner{}) -> #owner{}.
finish_preparation(_Domain, {prepare, Token}, {ok, Token}, Owner) ->
    Owner;
finish_preparation(Domain, {prepare, Token}, _Reply, Owner = #owner{preparations = Grants}) ->
    case maps:find(Domain, Grants) of
        {ok, {Token, _}} -> Owner#owner{preparations = maps:remove(Domain, Grants)};
        _ -> Owner
    end;
finish_preparation(_Domain, _Operation, _Reply, Owner) ->
    Owner.

%% Consume exactly once when the claim enters its lane; no other child can reuse the token.
-spec claim_prepared(domain(), startup_token(), pid(), gen_server:from(), #owner{}) ->
    {reply, {error, term()}, #owner{}} | {noreply, #owner{}}.
claim_prepared(
    Domain,
    Token,
    Child,
    From,
    Owner = #owner{
        preparations = Grants,
        supervision = Supervision
    }
) ->
    case {maps:find(Domain, Grants), maps:is_key(Domain, Supervision)} of
        {{ok, {Token, Expected}}, false} when is_integer(Expected) ->
            S = #supervision{
                child = Child,
                monitor = monitor(process, Child),
                incarnation = Expected,
                startup = {prepared, Expected}
            },
            Claimed = Owner#owner{
                preparations = maps:remove(Domain, Grants),
                supervision = Supervision#{Domain => S}
            },
            case enqueue(Domain, {claim, Child, Expected}, From, Claimed) of
                {reply, Error, _} ->
                    demonitor(S#supervision.monitor, [flush]),
                    {reply, Error, Owner};
                Accepted ->
                    Accepted
            end;
        _ ->
            {reply, {error, invalid_startup}, Owner}
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
                    case enqueue(Domain, {claim, Child}, From, Claimed) of
                        {reply, Error, _Rejected} ->
                            demonitor(S#supervision.monitor, [flush]),
                            {reply, Error, Owner};
                        Accepted ->
                            Accepted
                    end;
                {ok, #supervision{child = Child, retiring = false}} ->
                    enqueue(Domain, {claim, Child}, From, Owner);
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
            Startup =
                case S#supervision.startup of
                    automatic -> automatic;
                    _ -> spent
                end,
            Owner#owner{
                supervision = Supervision#{
                    Domain := S#supervision{
                        incarnation = Target,
                        startup = Startup
                    }
                }
            };
        _ ->
            Owner
    end.

%% Local death retains shutdown intent even when its notification loses the race to a new child.
-spec retire_supervision(domain(), #owner{}) -> #owner{}.
retire_supervision(Domain, Owner = #owner{supervision = Supervision}) ->
    case maps:find(Domain, Supervision) of
        {ok, S = #supervision{retired = true}} ->
            release_retired(Domain, S, Owner);
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
        {
            {ok, #supervision{retiring = true, retired = false, retry = false}},
            {ok, #work{active = none}}
        } ->
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

%% Remember actual retirement without forgetting a live child's outstanding authority.
-spec retirement_reply(domain(), term(), #owner{}) -> #owner{}.
retirement_reply(Domain, Reply, Owner = #owner{supervision = Supervision}) ->
    S = maps:get(Domain, Supervision),
    case Reply of
        retired ->
            release_retired(Domain, S#supervision{retired = true}, Owner);
        _ ->
            erlang:send_after(50, self(), {retire_supervision, Domain}),
            Owner#owner{supervision = Supervision#{Domain := S#supervision{retry = true}}}
    end.

%% A late startup from a live representative stays fenced until that child releases or dies.
-spec release_retired(domain(), #supervision{}, #owner{}) -> #owner{}.
release_retired(
    Domain,
    S = #supervision{child = Child, waiter = Waiter},
    Owner = #owner{supervision = Supervision}
) ->
    case Waiter =:= none andalso is_process_alive(Child) of
        true ->
            Owner#owner{supervision = Supervision#{Domain := S}};
        false ->
            demonitor(S#supervision.monitor, [flush]),
            case Waiter of
                none -> ok;
                From -> gen_server:reply(From, ok)
            end,
            Owner#owner{supervision = maps:remove(Domain, Supervision)}
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
