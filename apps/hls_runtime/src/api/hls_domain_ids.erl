-module(hls_domain_ids).
-moduledoc """
Deployment commissioning and delegated incarnation-ID allocation.

The eight-byte store contains an identity high-water mark, never actor state.
Create it once for a new deployment; never recreate a lost store to recover live
hardware. Preserve it across owner restarts. Owner attachment excludes other users
of the same path in this BEAM VM, not across machines. Writes sync the file before
rename; directory power-loss durability is not established. Reconcile identity
independently after host/storage loss before reusing the store.
""".

%% One-time deployment commissioning.
-export([create/1]).
%% Advanced setup for a separately controlled static supervisor.
-export([reserve/2]).

-doc "Creates a new deployment's counter exclusively. An existing or lost store is never silently replaced.".
-spec create(file:filename()) -> ok | {error, term()}.
create(Path) ->
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
-spec reserve(pid(), pos_integer()) ->
    {ok, {hls_domain:incarnation(), hls_domain:incarnation()}} | {error, term()}.
reserve(Owner, Count) -> gen_server:call(Owner, {reserve_incarnations, Count}).
