-module(hls_domain_store).
-moduledoc """
VM-local store-path ownership for hls_domain. This registry handles only owner
claims, releases and process deaths; counter writes and domain management do not
pass through it. Backend control-session authority remains independent.

Claims survive a registry crash while their local owners live. They disappear on
owner death or explicit release, and require no distributed registry or per-path
registered atoms. Callers supply the same absolute pathname for a store; this is
not an operating-system lock and does not resolve filesystem aliases.
""".
-behaviour(gen_server).

%% Internal store-owner interface.
-export([claim/1, release/1]).
%% gen_server callbacks.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%% Monitors are local to the current registry; only owner PIDs survive its restart.
-type claims() :: #{file:filename() => {pid(), reference()}}.

-doc "Claims an absolute pathname for the caller, or rejects an existing live owner. Repeated claims by the same local caller are idempotent; registry unavailability exits the call.".
-spec claim(file:filename()) -> ok | {error, owned | nonlocal_owner}.
claim(Path) ->
    ensure_started(),
    gen_server:call(?MODULE, {claim, Path}).

-doc "Releases the caller's pathname claim; another owner cannot release it. Owner death also releases claims. Registry unavailability exits the call.".
-spec release(file:filename()) -> ok | {error, not_owner}.
release(Path) ->
    ensure_started(),
    gen_server:call(?MODULE, {release, Path}).

%% A fixed local name serializes rare claims without linking the registry to any owner.
-spec ensure_started() -> ok.
ensure_started() ->
    case gen_server:start({local, ?MODULE}, ?MODULE, [], []) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end.

-doc "Restores live local ownership before accepting requests; dead owners cannot retain a path.".
-spec init([]) -> {ok, claims()}.
init([]) ->
    Claims = maps:fold(
        fun(Path, Owner, Acc) ->
            case is_process_alive(Owner) of
                true -> Acc#{Path => {Owner, monitor(process, Owner)}};
                false -> Acc
            end
        end,
        #{},
        persistent_term:get({?MODULE, owners}, #{})
    ),
    {ok, save(Claims)}.

-doc "Serializes pathname claims and releases; the caller itself owns the claim.".
-spec handle_call(term(), gen_server:from(), claims()) -> {reply, term(), claims()}.
%% A local process can acquire several paths, but each path has only one owner.
handle_call({claim, Path}, {Owner, _}, Claims) when node(Owner) =:= node() ->
    claim_path(Path, Owner, Claims);
%% Local liveness is definitive; remote disconnects are not proof of owner death.
handle_call({claim, _Path}, _From, Claims) ->
    {reply, {error, nonlocal_owner}, Claims};
%% Explicit release belongs to the actual owner, never a competing caller.
handle_call({release, Path}, {Owner, _}, Claims) ->
    case maps:find(Path, Claims) of
        {ok, {Owner, _}} -> {reply, ok, save(drop(Path, Claims))};
        {ok, _} -> {reply, {error, not_owner}, Claims};
        error -> {reply, ok, Claims}
    end;
%% The registry has no actor-traffic or lifecycle-request interface.
handle_call(_Request, _From, Claims) ->
    {reply, {error, unsupported_request}, Claims}.

-doc "Ignores casts; asynchronous requests cannot grant or release ownership.".
-spec handle_cast(term(), claims()) -> {noreply, claims()}.
handle_cast(_Message, Claims) -> {noreply, Claims}.

-doc "Releases claims on matching local owner death; stale notifications are inert.".
-spec handle_info(term(), claims()) -> {noreply, claims()}.
%% A monitor observation retires only the exact owner and monitor it names.
handle_info({'DOWN', Monitor, process, Owner, _Reason}, Claims) ->
    Remaining = maps:filter(fun(_Path, Entry) -> Entry =/= {Owner, Monitor} end, Claims),
    case Remaining =:= Claims of
        true -> {noreply, Claims};
        false -> {noreply, save(Remaining)}
    end;
%% Unrelated messages cannot change the fail-closed ownership copy.
handle_info(_Message, Claims) ->
    {noreply, Claims}.

%% Check actual local death as well as monitors, so a queued DOWN does not delay reuse.
-spec claim_path(file:filename(), pid(), claims()) -> {reply, ok | {error, owned}, claims()}.
claim_path(Path, Owner, Claims) ->
    case maps:find(Path, Claims) of
        {ok, {Owner, _}} ->
            {reply, ok, Claims};
        {ok, {Previous, _}} ->
            case is_process_alive(Previous) of
                true -> {reply, {error, owned}, Claims};
                false -> reserve(Path, Owner, drop(Path, Claims))
            end;
        error ->
            reserve(Path, Owner, Claims)
    end.

%% Persist before acknowledgement: a crash cannot forget a successfully granted claim.
-spec reserve(file:filename(), pid(), claims()) -> {reply, ok, claims()}.
reserve(Path, Owner, Claims) ->
    Next = save(Claims#{Path => {Owner, monitor(process, Owner)}}),
    {reply, ok, Next}.

%% Remove a monitor when explicitly releasing or replacing a dead owner.
-spec drop(file:filename(), claims()) -> claims().
drop(Path, Claims) ->
    {{_Owner, Monitor}, Remaining} = maps:take(Path, Claims),
    demonitor(Monitor, [flush]),
    Remaining.

%% The copy outlives this process, not the VM. Writes occur only on ownership changes.
-spec save(claims()) -> claims().
save(Claims) ->
    Owners = maps:map(fun(_Path, {Owner, _Monitor}) -> Owner end, Claims),
    persistent_term:put({?MODULE, owners}, Owners),
    Claims.
