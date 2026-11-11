-module(hls_domain).
-moduledoc """
Host ownership of fixed actor domains and their non-reused activations.

Backends own the finite lifecycle controller and establish physical completion.
This process attaches without resetting, serializes management, and persists each
allocated activation before submitting it. A timeout is an unknown outcome, never
permission to replay application work. Backend endpoints remain incarnation-specific.

The activation file must be created explicitly for a newly commissioned deployment.
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
-export_type([catalog/0, backend/0, handle/0, activation/0, domain/0, policy/0, snapshot/0]).

-doc "A fixed deployment-local domain name.".
-type domain() :: atom().
-doc "A nonzero activation which never wraps within one deployment.".
-type activation() :: 1..((1 bsl 64) - 1).
-doc "An incarnation-specific domain handle, not a mutable stable name.".
-type handle() :: {domain(), activation()}.
-doc "Automatic replacement is permitted only when the deployment declares it acceptable.".
-type policy() :: manual | automatic.
-doc "Declared domains and their replacement policy; actor/source layout belongs to the backend.".
-type catalog() :: #{domain() := policy()}.
-doc "One backend implementation, a distinct existing endpoint for each domain, and a durable activation store.".
-type backend() :: #{
    module := module(), endpoints := #{domain() := pid()}, activation_file := file:filename()
}.
-doc "Observed lifecycle state; readiness and a handle refer to the same activation.".
-type snapshot() :: #{
    domain := domain(),
    phase := atom(),
    handle := none | handle(),
    target := non_neg_integer(),
    transition := non_neg_integer(),
    fault := non_neg_integer(),
    detail := term(),
    actors := #{term() => pid()}
}.

%% The owner retains authority tokens, never source actor state or an application work log.
-record(owner, {
    catalog :: catalog(),
    module :: module(),
    endpoints :: #{domain() := pid()},
    authorities :: #{domain() := hls_domain_backend:authority()},
    file :: file:filename(),
    next :: non_neg_integer()
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

-doc "Reads current backend evidence; an unavailable backend returns an error rather than a synthetic phase.".
-spec status(pid(), domain()) -> {ok, snapshot()} | {error, term()}.
status(Owner, Domain) -> gen_server:call(Owner, {status, Domain}).

-doc "Requests first activation of an unbound domain; repeating an in-flight request observes its transition.".
-spec activate(pid(), domain()) -> {ok, snapshot()} | {error, term()}.
activate(Owner, Domain) -> gen_server:call(Owner, {activate, Domain}).

-doc "Replaces exactly the supplied incarnation. Repetition retrieves its retained successor; older handles reject.".
-spec replace(pid(), handle()) -> {ok, snapshot()} | {error, term()}.
replace(Owner, {Domain, Activation}) -> gen_server:call(Owner, {replace, Domain, Activation}).

-doc "Returns an actor endpoint only from the currently ready incarnation. Previously returned PIDs are never rebound.".
-spec resolve(pid(), domain() | handle(), term()) -> {ok, pid()} | {error, term()}.
resolve(Owner, Domain, Actor) -> gen_server:call(Owner, {resolve, Domain, Actor}).

-doc "Returns the deployment's declared policy without initiating a lifecycle operation.".
-spec policy(pid(), domain()) -> {ok, policy()} | {error, unknown_domain}.
policy(Owner, Domain) -> gen_server:call(Owner, {policy, Domain}).

-doc "Claims one durable counter and each backend's control session; no actor starts here.".
-spec init({catalog(), backend()}) -> {ok, #owner{}} | {stop, term()}.
init({Catalog, #{module := Module, endpoints := Endpoints, activation_file := Path}}) ->
    File = filename:absname(Path),
    case validate(Catalog, Endpoints) of
        false ->
            {stop, invalid_domain_catalog};
        true ->
            case global:register_name({?MODULE, File}, self()) of
                no -> {stop, activation_store_owned};
                yes -> initialize_owner(Catalog, Module, Endpoints, File)
            end
    end.

-doc "Serializes inspection, explicit lifecycle requests and endpoint resolution.".
-spec handle_call(term(), gen_server:from(), #owner{}) -> {reply, term(), #owner{}}.
%% Policy is host configuration, not a remote readiness claim.
handle_call({policy, Domain}, _From, Owner = #owner{catalog = Catalog}) ->
    Reply =
        case maps:find(Domain, Catalog) of
            {ok, P} -> {ok, P};
            error -> {error, unknown_domain}
        end,
    {reply, Reply, Owner};
%% Status always comes from the controller instead of a stale host mirror.
handle_call({status, Domain}, _From, Owner) ->
    {reply, snapshot(Domain, Owner), Owner};
%% Activation and replacement share durable allocation and request correlation.
handle_call({activate, Domain}, _From, Owner) ->
    {Reply, Next} = transition(Domain, 0, ?HLS_DOMAIN_ACTIVATE, Owner),
    {reply, Reply, Next};
%% Compare-and-replace preserves the old handle's retained transition on retry.
handle_call({replace, Domain, Expected}, _From, Owner) ->
    {Reply, Next} = transition(Domain, Expected, ?HLS_DOMAIN_REPLACE, Owner),
    {reply, Reply, Next};
%% The backend checks readiness and authority atomically with resolving an endpoint.
handle_call({resolve, Identity, Actor}, _From, Owner) ->
    {Domain, Expected} =
        case Identity of
            {D, E} -> {D, E};
            D -> {D, any}
        end,
    Reply =
        case inspect(Domain, Owner) of
            {ok, #{state := #domain_state{phase = ?HLS_DOMAIN_READY, current = Current}}} when
                Expected =:= any; Expected =:= Current
            ->
                backend(Owner, Domain, endpoint, [authority(Domain, Owner), Current, Actor]);
            {ok, _} ->
                {error, not_ready};
            Error ->
                Error
        end,
    {reply, Reply, Owner};
%% Unknown management messages do not become application work.
handle_call(_Request, _From, Owner) ->
    {reply, {error, unsupported_request}, Owner}.

-doc "Unrecognized casts cannot alter domain lifecycle state.".
-spec handle_cast(term(), #owner{}) -> {noreply, #owner{}}.
handle_cast(_Message, Owner) -> {noreply, Owner}.

-doc "Unsolicited observations do not invent backend transitions; callers inspect the current controller.".
-spec handle_info(term(), #owner{}) -> {noreply, #owner{}}.
handle_info(_Message, Owner) -> {noreply, Owner}.

-doc "Releases the local store lock; backend owner monitors implement their declared disconnect behavior.".
-spec terminate(term(), #owner{}) -> ok.
terminate(_Reason, #owner{file = File}) ->
    global:unregister_name({?MODULE, File}),
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
                    next = Counter
                }}
            catch
                Class:Reason -> {stop, {domain_attach_failed, Class, Reason}}
            end;
        {ok, _} ->
            {stop, invalid_activation_store};
        {error, Reason} ->
            {stop, {activation_store, Reason}}
    end.

%% Inspect validates the stable domain name before using its backend.
-spec inspect(domain(), #owner{}) -> {ok, hls_domain_backend:snapshot()} | {error, term()}.
inspect(Domain, Owner = #owner{endpoints = Endpoints}) ->
    case maps:is_key(Domain, Endpoints) of
        true -> backend(Owner, Domain, status, []);
        false -> {error, unknown_domain}
    end.

%% Keep the control token private to the deployment owner.
-spec authority(domain(), #owner{}) -> hls_domain_backend:authority().
authority(Domain, #owner{authorities = Authorities}) -> maps:get(Domain, Authorities).

%% Only expected backend call exits become reachability errors; source programming errors remain visible.
-spec backend(#owner{}, domain(), atom(), [term()]) -> term().
backend(#owner{module = Module, endpoints = Endpoints}, Domain, Function, Args) ->
    try
        apply(Module, Function, [maps:get(Domain, Endpoints) | Args])
    catch
        exit:Reason -> {error, {unavailable, Reason}}
    end.

%% Public snapshots deliberately separate pending target from admitted current incarnation.
-spec snapshot(domain(), #owner{}) -> {ok, snapshot()} | {error, term()}.
snapshot(Domain, Owner) ->
    case inspect(Domain, Owner) of
        {ok, Evidence} -> {ok, describe_evidence(Domain, Evidence)};
        Error -> Error
    end.

%% Readiness and its actor identities come from the same backend observation.
-spec describe_evidence(domain(), hls_domain_backend:snapshot()) -> snapshot().
describe_evidence(Domain, #{state := State, actors := Actors, fault_reason := Reason}) ->
    Description = describe(Domain, State, Reason),
    case State#domain_state.phase of
        ?HLS_DOMAIN_READY -> Description#{actors := Actors};
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
        phase => phase(Phase),
        handle => Handle,
        target => Target,
        transition => Transition,
        fault => Fault,
        detail => Detail,
        actors => #{}
    }.

%% Refuse unsupported phase encodings instead of silently advertising readiness.
-spec phase(hls_nums:uN(3)) -> atom().
phase(?HLS_DOMAIN_UNBOUND) -> unbound;
phase(?HLS_DOMAIN_READY) -> ready;
phase(?HLS_DOMAIN_CLOSING) -> closing;
phase(?HLS_DOMAIN_ISOLATED) -> isolated;
phase(?HLS_DOMAIN_INITIALIZING) -> initializing;
phase(?HLS_DOMAIN_FAILED) -> failed.

%% A repeated old handle resolves its retained transition before any new ID is allocated.
-spec transition(domain(), non_neg_integer(), hls_nums:uN(4), #owner{}) -> {term(), #owner{}}.
transition(Domain, Expected, Operation, Owner) ->
    case inspect(Domain, Owner) of
        {ok, #{state := #domain_state{previous = Expected, transition = Id}} = Evidence} when
            Id =/= 0
        ->
            {{ok, describe_evidence(Domain, Evidence)}, Owner};
        {ok, #{state := State = #domain_state{current = Expected, phase = Phase}}} when
            Phase =:= ?HLS_DOMAIN_UNBOUND; Phase =:= ?HLS_DOMAIN_READY; Phase =:= ?HLS_DOMAIN_FAILED
        ->
            allocate_transition(Domain, Operation, State, Owner);
        {ok, _} ->
            {{error, stale_or_busy}, Owner};
        Error ->
            {Error, Owner}
    end.

%% The durable ID is burned before submission, including an uncertain/lost response.
-spec allocate_transition(domain(), hls_nums:uN(4), hls_domain_lifecycle:state(), #owner{}) ->
    {term(), #owner{}}.
allocate_transition(Domain, Operation, State, Owner = #owner{next = Counter, file = File}) ->
    Previous = State#domain_state.current,
    Last = max(Counter, max(Previous, State#domain_state.target)),
    case Last < (1 bsl 64) - 1 of
        false ->
            {{error, activation_exhausted}, Owner};
        true ->
            Target = Last + 1,
            case persist(File, Target) of
                ok ->
                    Input = #domain_input{
                        op = Operation, expected = Previous, target = Target, transition = Target
                    },
                    Next = Owner#owner{next = Target},
                    Reply =
                        case backend(Owner, Domain, request, [authority(Domain, Owner), Input]) of
                            #domain_output{status = Status, state = Result} when
                                Status =:= ?HLS_DOMAIN_ACCEPTED; Status =:= ?HLS_DOMAIN_REPLAY
                            ->
                                transition_result(Domain, Result, Next);
                            #domain_output{status = Status} ->
                                {error, {rejected, Status}};
                            Error ->
                                Error
                        end,
                    {Reply, Next};
                {error, Reason} ->
                    {{error, {activation_store, Reason}}, Owner}
            end
    end.

%% A synchronous ready reply needs the matching actor evidence before a supervisor can bind.
-spec transition_result(domain(), hls_domain_lifecycle:state(), #owner{}) ->
    {ok, snapshot()} | {error, term()}.
transition_result(Domain, #domain_state{phase = ?HLS_DOMAIN_READY}, Owner) ->
    snapshot(Domain, Owner);
transition_result(Domain, State, _Owner) ->
    {ok, describe(Domain, State, none)}.

%% Atomic replacement preserves the previous valid counter if writing fails before rename.
-spec persist(file:filename(), activation()) -> ok | {error, term()}.
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
