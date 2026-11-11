# Actor domains and replacement

Replacing a domain starts its actors again from `init([])` and the declared startup configuration. It does not restore their previous data. A **domain** is the fixed group replaced together, including its private mailboxes, pending calls and routes. A **domain incarnation** is one lifetime of that whole group; its actor PIDs and non-reused **incarnation ID** change on replacement.

`activate/2` starts the first incarnation; `replace/2` starts a successor. `stop/2` retires an exact incarnation without initializing another. The **incarnation counter** allocates these IDs; it contains no checkpoint of the application.

The implementation separates the actors being replaced from the controller coordinating their replacement. This is similar to keeping a supervisor outside its children's lifetimes. The additional requirement is that a hardware backend can outlive the host process controlling it, and old traffic can remain in a transport after that host process exits.

## What survives which restart?

| Event | Result |
| --- | --- |
| Replace the source-actor domain | Old actors and private pending work are retired. Fresh actors run initialization with new PIDs and a new incarnation ID. |
| Restart an observing `hls_domain_instance` child | The new child inspects the surviving controller. It attaches to a healthy incarnation, or requests replacement if failure and the declared policy permit it. |
| Stop or lose an explicitly supervised child | The surviving deployment owner retains retirement intent for that child’s exact lifetime. A replacement child waits for actual retirement before starting a fresh incarnation. |
| Restart the `hls_domain` deployment owner | The new owner reads its identity counter and attaches to the surviving backend. It does not restore actor data or issue reset merely by attaching. The native backend preserves actors and accepted lifecycle work by default; `owner_loss => fail` explicitly retires the group when its owner dies. |
| Lose a hardware transport/backend adapter | Reachability and pending results become uncertain. No actor reset follows from connection loss alone. Explicit reattachment requires the same established incarnation; non-ready states permit management reconciliation only; accepted application work is never replayed. |
| Restart `hls_domain_erts` itself | Its old actors are retired; a new backend starts `unbound`. No backend state is recovered from the counter file. |

A host restart need not restart the FPGA. Conversely, a new FPGA process or bitstream need not retain the former controller's state. The owner therefore asks the backend what happened rather than guessing from its own restart. Losing reachability leaves the outcome unknown until the backend can be reconciled.

## The incarnation counter

The counter file named by `incarnation_file` is exactly **eight bytes: the highest allocated unsigned 64-bit incarnation number** for that owner's catalog. `create_store/1` creates it exclusively with value zero. Before requesting an incarnation, the owner writes a fresh number to the file; an unsuccessful or uncertain request can consume a number. The numbers need not be consecutive among successful incarnations, and exhaustion rejects instead of wrapping.

It contains no actor data, mailbox contents, application results, route table, native PIDs, or completed-command history. The backend separately holds its current lifecycle phase, incarnation and one live/last management transition in memory. That small transition record lets a repeated `replace(Owner, OldHandle)` observe its original successor after a lost reply; it is not an application replay log, and it does not survive loss of the backend itself.

For example, traffic tagged with incarnation 41 must not become valid again merely because its host owner restarted. The counter prevents the owner from assigning 41 to a new incarnation. The current backend observation can raise the next number further if it already knows a higher incarnation. An Erlang PID already distinguishes native process lifetimes; the numeric ID supplies a corresponding finite identity for hardware and transport boundaries.

Create this store once when establishing a new deployment, outside an ordinary restart loop, and preserve it across owner restarts. Missing or corrupt metadata is an error. Deliberately abandoning a store requires an independently established retirement boundary for its old endpoints and traffic; recreating a missing file is not such a boundary.

The file is synchronized before rename, but containing-directory durability across host power loss has not been established. After a host/storage failure, reconcile identities before admitting work. This counter design is a means of obtaining non-reused identities, not a general persistence or checkpoint facility.

Owner startup claims the store within its BEAM VM and separately attaches exclusive control authority at each backend. The local claim registry is not a multi-host lock or authority-election service; moving control to another host requires exclusion of the previous backend session.

## Control processes and application traffic

```text
OTP supervisor / management client
                  |
       hls_domain_instance (optional supervisor child)
                  |
              hls_domain owner
                  |
       hls_domain_erts backend -- phase worker
                  |
        starts, connects and monitors
                  |
           source actor A ------> source actor B
                  ^                     |
                  |                     v
           application caller      external recipient
```

After `resolve/3`, the application calls the returned actor PID directly. Source actors send their effects to the configured actor/external PIDs directly. Neither the deployment owner nor `hls_domain_erts` forwards ordinary application messages or schedules each actor step.

There is one `hls_domain_erts` process per domain. It owns that domain's control authority, finite lifecycle state, member PIDs and monitors. Its mailbox receives:

| Input | Purpose |
| --- | --- |
| `attach`, `status`, `request`, `endpoint` calls | Claim exclusive control, inspect state, request creation or replacement, or resolve a ready incarnation's actor. |
| Phase-worker messages | Register provisional actors and acknowledge completed retirement or initialization. |
| Actor monitors and linked-worker exits | Detect failure, retain its reason, and retire the affected domain. |
| Owner monitor messages | Revoke control authority. Retire actors only when the backend explicitly declares `owner_loss => fail`. |

The process serializes competing lifecycle requests and failure observations. It also provides a concrete lifetime to which actors and temporary workers can be linked. Normal phase work runs in a worker so initialization need not occupy the backend's callback; fault cleanup still waits for actual member termination. `hls_domain_lifecycle` remains a pure finite transition function: it requests a fence, reset or initialization, while the backend performs the operation and reports completion. Compiling that kernel does not compile this host `gen_server`, its process monitors or its filesystem access into hardware.

One `hls_domain` owner may manage several domains, but that is a deployment choice, not a global scheduler requirement. Backend waits are asynchronous and independently ordered per domain: a slow status, replacement or endpoint lookup in one domain does not block management of another. Each domain admits one active operation and at most eight waiting calls; further calls return `{error, busy}` without allocating an identity or submitting work. All stages of an admitted operation finish before the next operation in that domain begins. Policy lookup does not wait for a backend. These limits bound retained requests, not messages arriving in the owner's ordinary BEAM mailbox.

The owner remains the exclusive backend authority and the sole identity allocator. Backend attachment occurs during owner startup; every later request still originates from that owner PID. Counter writes and their storage synchronization remain serialized across the catalog, so slow storage can delay all its domains. Owner death removes management authority for every attached domain. Actors and already accepted backend work survive under the default `preserve` owner-loss policy. An explicit `owner_loss => fail` backend option instead couples the group to its owner's lifetime. Use separate owners and stores where independent storage latency or management availability is required. Application traffic continues to bypass these owners. This is not a distributed consensus or automatic authority-failover service.

Each backend response has a five-second deadline. Expiry retires that response alias and reports an unknown outcome; it does not cancel already submitted work or replay it. A timed-out client call likewise does not withdraw an admitted management operation. Later same-domain requests inspect the backend before allocating a new identity, and the retained transition handles replacement retries. Late responses cannot complete a different operation. Stopping the owner rejects its queued calls, retires pending response aliases and revokes backend authority; it does not cancel accepted work or reset actors under the default owner-loss policy.

The native backend uses normal ERTS mailboxes. The bounded `hls_mailbox` inside a source actor models finite hardware admission, but incoming messages can already be waiting in the actor's unbounded BEAM mailbox before that model examines them. The management processes likewise have ordinary BEAM mailboxes. `admit_cast/2` and bounded outstanding requests help the caller respect admission; they do not turn an ERTS simulation into a physical bandwidth or globally bounded-memory guarantee.

## Starting and using a domain

Create the store once. This example assumes `worker` is a supported `hls_statem` source actor and `Observer` is an external recipient:

```erlang
ok = hls_domain:create_store("deployment.incarnations"),
{ok, Backend} = hls_domain_erts:start_link(#{
    actors => #{worker => #{module => worker, mailbox_capacity => 4}},
    routes => #{worker => #{out => {external, Observer}}},
    startup => #{}
}),
{ok, Owner} = hls_domain:start_link(#{compute => manual}, #{
    module => hls_domain_erts,
    endpoints => #{compute => Backend},
    incarnation_file => "deployment.incarnations"
}),
{ok, _Pending} = hls_domain:activate(Owner, compute).
```

Read `hls_domain:status(Owner, compute)` until its phase is `ready`; successful submission alone does not establish readiness. Then resolve an actor within that exact incarnation:

```erlang
{ok, #{phase := ready, handle := Handle}} = hls_domain:status(Owner, compute),
{ok, Pid} = hls_domain:resolve(Owner, Handle, worker),
Reply = hls_statem:call(Pid, Request),
{ok, _Replacement} = hls_domain:replace(Owner, Handle).
```

A handle is `{Domain, IncarnationId}`. Resolve with a handle never follows a stable name into a replacement; resolve with a domain name explicitly asks for its currently ready endpoint. Previously returned PIDs never become replacement actors. Repeating replacement against the old handle retrieves the retained successor rather than resetting twice. Once a later transition replaces that retained record, older handles reject.

Initialization starts actors disconnected, connects all declared routes, and runs silent initial entry/startup before publishing readiness. Setup may change private state but must not return sends, replies or postponed work. Arbitrary Erlang I/O outside the lowered callback contract cannot be rolled back by this check. The ERTS adapter accepts per-actor startup messages; a hardware composer may impose a narrower startup contract.

## Replacement phases and failures

| Phase | Admission and required completion |
| --- | --- |
| `unbound` | Closed; no incarnation has been initialized. |
| `closing` | Closed; retire the old boundary and acknowledge its fence. |
| `isolated` | Closed; reset the complete private domain state. |
| `initializing` | The new identity is installed, but setup has not completed. |
| `ready` | Admit only the current nonzero incarnation. |
| `failed` | Closed; retain the first fault and current transition for inspection. |

Completion acknowledgements identify the expected old incarnation, target incarnation and transition. Timeout is never an acknowledgement. Source failure closes admission without promising that every peer stops at the same instant. In the native backend, actor loss retires its domain's other members; independent domains continue.

A failed callback publishes none of its returned effects and commits no proposed state. Earlier accepted effects remain accepted: replacement cannot reverse them. Pending calls fail with endpoint death. Calls and casts are never transparently replayed. Expected application rejection is a normal typed reply, not an actor failure.

`status` separates the finite domain cause from its `detail`: native source exceptions retain their Erlang reason; hardware adapters can retain actor/site diagnostics. A disconnected backend returns an unavailable error instead of inventing reset or readiness. A failed initial incarnation before reset acknowledgement remains unresolved through the owner API; it needs reconciliation rather than automatic allocation of another identity.

## Transport loss and explicit reattachment

A management connection is not an actor incarnation. Losing it establishes neither actor death nor cancellation of work already accepted. A failed call may have had effects; neither the owner nor the endpoint automatically resends it. Old monitors and reply aliases belong to the failed connection and do not resume after reconnecting. This follows ERTS distribution's uncertainty boundary, not a transparent exactly-once session promise.

After a local hardware backend adapter dies, bring up another adapter against the surviving controller and explicitly request:

```erlang
{ok, Evidence} = hls_domain:reattach(Owner, Handle, NewBackend).
```

The owner serializes this operation with management of that domain. It refuses a live old adapter or a candidate already used by another domain. It checks that the candidate reports the supplied nonzero incarnation as `ready`, attaches as the actual owner PID, installs the new binding, and checks that identity and readiness again. No new incarnation is allocated, reset is not requested, and no application input is replayed. A mismatching initial observation leaves the candidate unattached and the old binding unchanged. Attachment or final-response loss remains uncertain; after successful attachment the new binding can remain installed even if confirmation fails. Inspect `status/2` to reconcile it.

A matching non-ready incarnation may be reattached to reconcile an interrupted lifecycle operation; it exposes no application endpoint until ready.

Both adapter PIDs must be local to the owner. Local process death proves the old adapter has ended; an unavailable remote Erlang node would not establish that exclusion. This is not authority election across hosts. The backend must also establish that its controller evidence belongs to the same deployment and transport session; a host-side integer match alone cannot attest hardware continuity. A restarted native `hls_domain_erts` begins `unbound`, so it cannot claim reattachment to its dead actors.

Returned actor PIDs never become a successor incarnation. A replacement host proxy may represent the same surviving hardware actor after explicit reattachment. It is a new observer endpoint: application callers re-resolve and establish new monitors; old pending calls and monitors do not come back to life. Replacing a failed actor domain remains an explicit, separate operation governed by the catalog's `manual` or `automatic` policy.

## OTP supervision

The catalog chooses `manual` or `automatic` replacement. Use `manual` when reset and reinitialization require application approval. For an explicitly automatic, reset-safe domain, an ordinary supervisor can own its lifetime:

```erlang
#{id => compute,
  start => {hls_domain_instance, start_link,
            [Owner, compute, #{lifetime => supervised}]},
  restart => permanent,
  shutdown => 5000,
  type => worker}
```

The child starts promptly and observes readiness asynchronously. `supervised` claims exclusive lifetime ownership before startup. Competing callers cannot activate or replace that owned domain; an exact-incarnation stop remains available. Its surviving deployment owner retains the exact incarnation or pending initialization target. Supervisor shutdown requests stop and waits for acknowledged retirement. If OTP kills the child before cleanup completes, the owner retains that intent; a replacement child cannot adopt the old healthy incarnation. `one_for_all` and `rest_for_one` therefore retire the affected healthy siblings as well as replacing the failed child. The owner and backend must live outside this subtree. OTP orders representative startup, but hardware readiness remains asynchronous; dependent domains must coordinate readiness explicitly.

Omitting `lifetime`, including the existing `start_link/2`, selects `observed`. Losing an observer preserves a healthy domain; restarting it reattaches rather than resetting. Both modes leave ordinary transport-only `noconnection` unavailable without requesting reset. Old monitors and pending calls do not resume. An explicitly requested shutdown during disconnection remains pending until reattachment supplies actual retirement evidence; elapsed time and death of a local proxy are not acknowledgements.

The supervised retirement record is bounded management state in the owner, not a durable work log. Owner or host loss does not preserve this shutdown intent. The backend's existing default `owner_loss => preserve` still applies. Consequently, this is not a hardware watchdog or a fully transparent remote OTP parent link. Explicit supervision controls a digital domain's lifetime while its management authority survives; external effects and reservations remain outside that lifetime.

## Explicit stop

```erlang
{ok, Observation} = hls_domain:stop(Owner, Handle).
```

`closing` acknowledges accepted intent. Only an observed `stopped` phase confirms retirement, including the backend's required output-delivery and endpoint-termination boundary. A failure or missing acknowledgement leaves the outcome unresolved. Stop consumes no fresh incarnation ID, never initializes a successor, and does not wait for every accepted application call to finish. Outputs already committed to delivery retain their ordering before orderly termination. Unfinished work is not replayed and emitted external effects are not reversed.

Repeating stop for the retained stopped incarnation is idempotent. A stale handle cannot stop a successor, and stop does not cancel a previously accepted replacement. Starting again requires an explicit replacement or the explicitly permitted action of an automatic supervisor child. An observer’s own death preserves healthy actors, but an ordinary permanent supervisor can still restart its child after an explicitly stopped actor terminates. The finite lifecycle uses the same stop transition on ERTS and in generated hardware; a future FPGA-resident supervisor can issue it without host filesystem or PID dependencies.

The generic lifecycle neither releases external reservations nor reconstructs previous application state. Initial support excludes arbitrary actor-local reset of shared state and distributed atomic replacement. Management progress still requires a running backend and working control transport.

See [initialization](initialization.md), [host transaction ownership](host-transactions.md) and [formal evidence labels](formal-contracts.md). Finite native/RTL histories do not establish unrestricted progress, physical reset correctness or external-device safety.

## Endpoint admission

Native source actors and downstream hardware endpoints share a transport request: `{'$hls_submit', Token, call | cast, Message}` sent with `gen_server:send_request/2`. The endpoint sends `{hls_admitted, Endpoint, Token}` before the eventual ordinary reply or terminal signal. Admission means the endpoint accepted responsibility for the input, not that its application call completed. The sender can release transmission credit while retaining bounded reply ownership per actor. Ordinary application callers continue to use `hls_statem:call` and casts.

An exact `{error, busy}` before admission permits waiting for cast capacity with `'$hls_capacity'`; the response `ok` permits another admission attempt but reserves no slot. Each endpoint retains at most 32 monitored capacity observers, one per caller process. The shared `hls_admission` helper carries no application messages or retry history. A lost response, endpoint death or admission already observed never permits automatic resubmission. A call rejected at later source dispatch remains an ordinary call result. Reply ownership must not consume the separate capacity needed by casts that release those replies.

These bounds apply inside the adapters. Ordinary ERTS mailboxes remain unbounded, and a full postponed source mailbox can still prevent progress; the source program must reserve room for its enabling messages.
