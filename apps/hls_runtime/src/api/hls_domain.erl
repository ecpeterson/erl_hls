-module(hls_domain).
-moduledoc """
Application control of fixed actor domains and incarnation-specific endpoints.

start_link attaches an owner without starting actors. activate creates the first
incarnation; replace compares an exact handle before creating its successor; stop
waits for confirmed retirement. Reattachment preserves a surviving incarnation.
Use hls_domain_instance for OTP children and hls_domain_counter for commissioning.
The internal owner orders management per domain; application messages bypass it.
Timeout is an unknown outcome, never permission to replay application work.
""".

%% Deployment attachment and lifecycle inspection.
-export([start_link/2, status/2]).
%% Explicit incarnation creation, replacement and confirmed retirement.
-export([activate/2, replace/2, stop/3]).
%% Actor endpoints and reconnection to a surviving hardware incarnation.
-export([resolve/3, reattach/3]).
%% Deployment configuration and incarnation-specific observations.
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

-doc "Attaches to existing domain controllers without resetting or activating their actors.".
-spec start_link(catalog(), backend()) -> gen_server:start_ret().
start_link(Catalog, Backend) -> hls_domain_owner:start_link(Catalog, Backend).

-doc "Reads backend evidence in per-domain request order. A full management queue returns busy; an unavailable backend returns an error rather than a synthetic phase.".
-spec status(pid(), domain()) -> {ok, snapshot()} | {error, term()}.
status(Owner, Domain) -> gen_server:call(Owner, {status, Domain}).

-doc "Creates the first incarnation of an unbound domain; repeating an in-flight request observes its transition. A full management queue returns busy without allocating an identity.".
-spec activate(pid(), domain()) -> {ok, snapshot()} | {error, term()}.
activate(Owner, Domain) -> gen_server:call(Owner, {activate, Domain}).

-doc "Replaces exactly the supplied incarnation. Repetition retrieves its retained successor; older handles reject. A full management queue returns busy without allocating an identity.".
-spec replace(pid(), handle()) -> {ok, snapshot()} | {error, term()}.
replace(Owner, {Domain, Incarnation}) -> gen_server:call(Owner, {replace, Domain, Incarnation}).

-doc "Stops the selected lifetime within Timeout milliseconds, returning ok only after backend retirement and supervised lifetime release. A domain name selects the current lifetime and revokes unused prepared startup; an exact handle rejects a changed incarnation before revoking anything. Stop the representative through its supervisor first: this call does not kill it. Timeout or transport loss leaves the outcome unknown; retained supervised retirement continues. Serialize preparation/start/stop at the application boundary.".
-spec stop(pid(), domain() | handle(), pos_integer()) -> ok | {error, term()}.
stop(Owner, Selection, Timeout) ->
    {Domain, Expected} =
        case Selection of
            {Name, Incarnation} -> {Name, Incarnation};
            Name -> {Name, unknown}
        end,
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    try
        ok = lifecycle_call(Owner, {begin_stop, Domain, Expected}, Deadline),
        retire_until(Owner, Domain, Expected, Deadline)
    catch
        throw:Reason -> {error, Reason};
        exit:Reason -> {error, {unavailable, Reason}}
    end.

%% Poll one exact lifetime; startup may install its target before it can accept stop.
-spec retire_until(pid(), domain(), unknown | non_neg_integer(), integer()) -> ok.
retire_until(Owner, Domain, Expected, Deadline) ->
    {ok, #{phase := Phase, handle := Handle, target := Target}} =
        lifecycle_call(Owner, {status, Domain}, Deadline),
    Current =
        case Handle of
            none -> 0;
            {Domain, I} -> I
        end,
    Observed = max(Current, Target),
    case Expected =:= unknown orelse Expected =:= Observed of
        true -> ok;
        false -> throw({incarnation_changed, Expected, Observed})
    end,
    case Phase of
        Retired when Retired =:= unbound; Retired =:= stopped ->
            case lifecycle_call(Owner, {retirement_released, Domain}, Deadline) of
                true -> ok;
                false -> retire_later(Owner, Domain, Observed, Deadline)
            end;
        Live when (Live =:= ready orelse Live =:= failed), Current =/= 0 ->
            {ok, _} = lifecycle_call(Owner, {stop, Domain, Current}, Deadline),
            retire_later(Owner, Domain, Observed, Deadline);
        _ ->
            retire_later(Owner, Domain, Observed, Deadline)
    end.

%% Each observation spends the same finite deadline; elapsed time never certifies retirement.
-spec retire_later(pid(), domain(), non_neg_integer(), integer()) -> ok.
retire_later(Owner, Domain, Expected, Deadline) ->
    timer:sleep(5),
    retire_until(Owner, Domain, Expected, Deadline).

%% Convert rejected observations into a failure without renewing the caller's timeout.
-spec lifecycle_call(pid(), term(), integer()) -> term().
lifecycle_call(Owner, Request, Deadline) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    case Remaining > 0 of
        false ->
            throw(timeout);
        true ->
            case gen_server:call(Owner, Request, Remaining) of
                {error, Reason} -> throw(Reason);
                Reply -> Reply
            end
    end.

-doc "Reattaches a surviving incarnation through a new local backend after the old backend process has died. Checks matching incarnation identity before attachment and again afterward; non-ready evidence permits management reconciliation without exposing actors; never resets or replays work. A failed final observation can leave the new binding installed: inspect status to reconcile it.".
-spec reattach(pid(), handle(), pid()) -> {ok, snapshot()} | {error, term()}.
reattach(Owner, {Domain, Incarnation}, Backend) ->
    gen_server:call(Owner, {reattach, Domain, Incarnation, Backend}).

-doc "Returns an actor endpoint only from the currently ready incarnation, in per-domain request order. Previously returned PIDs are never rebound; a full management queue returns busy.".
-spec resolve(pid(), domain() | handle(), term()) -> {ok, pid()} | {error, term()}.
resolve(Owner, Domain, Actor) -> gen_server:call(Owner, {resolve, Domain, Actor}).
