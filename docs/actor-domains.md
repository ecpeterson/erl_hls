# Actor domains and replacement

Replacing a domain starts its actors again from `init([])` and the declared startup configuration. It does not restore their previous data. A **domain** is the fixed group replaced together, including its private mailboxes, pending calls and routes. An **incarnation** is one lifetime of that whole group; its actor PIDs and numeric incarnation ID change on replacement.

The current API calls that ID an **activation**. `activate/2` starts the first incarnation; `replace/2` starts a successor. “Activation” does not mean a scheduled actor invocation, a clock cycle, or a checkpoint of the application.

The implementation separates the actors being replaced from the controller coordinating their replacement. This is similar to keeping a supervisor outside its children's lifetimes. The additional requirement is that a hardware backend can outlive the host process controlling it, and old traffic can remain in a transport after that host process exits.

## What survives which restart?

| Event | Result |
| --- | --- |
| Replace the source-actor domain | Old actors and private pending work are retired. Fresh actors run initialization with new PIDs and a new incarnation ID. |
| Restart its `hls_domain_instance` supervisor child | The new child inspects the surviving controller. It attaches to a healthy incarnation, or requests replacement if failure and the declared policy permit it. |
| Restart the `hls_domain` deployment owner | The new owner reads its identity counter and attaches to the surviving backend. It does not restore actor data or issue reset merely by attaching. The native backend observes owner death and retires that owner's domain; a hardware backend needs its own declared owner-loss mechanism. |
| Restart `hls_domain_erts` itself | Its old actors are retired; a new backend starts `unbound`. No backend state is recovered from the counter file. |

A host restart need not restart the FPGA. Conversely, a new FPGA process or bitstream need not retain the former controller's state. The owner therefore asks the backend what happened rather than guessing from its own restart. Losing reachability leaves the outcome unknown until the backend can be reconciled.

## The activation store contains only a counter

The file named by `activation_file` is exactly **eight bytes: the highest allocated unsigned 64-bit incarnation number** for that owner's catalog. `create_store/1` creates it exclusively with value zero. Before requesting an incarnation, the owner writes a fresh number to the file; an unsuccessful or uncertain request can consume a number. The numbers need not be consecutive among successful incarnations, and exhaustion rejects instead of wrapping.

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
| `attach`, `status`, `request`, `endpoint` calls | Claim exclusive control, inspect state, request activation/replacement, or resolve a ready incarnation's actor. |
| Phase-worker messages | Register provisional actors and acknowledge completed retirement or initialization. |
| Actor/owner monitor messages and linked-worker exits | Detect failure, retain its reason, and retire the affected domain. |

The process serializes competing lifecycle requests and failure observations. It also provides a concrete lifetime to which actors and temporary workers can be linked. Normal phase work runs in a worker so initialization need not occupy the backend's callback; fault cleanup still waits for actual member termination. `hls_domain_lifecycle` remains a pure finite transition function: it requests a fence, reset or initialization, while the backend performs the operation and reports completion. Compiling that kernel does not compile this host `gen_server`, its process monitors or its filesystem access into hardware.

One `hls_domain` owner may manage several domains, but that is a deployment choice, not a global scheduler requirement. Its implementation serializes their management requests, synchronously calls backends, and synchronizes counter writes. A slow backend or storage operation can therefore delay management of other domains in the same catalog. Owner death also affects every domain attached to that owner. Use separate owners, stores and backend processes for groups that require independent control-plane latency or failure scope. Application traffic continues to bypass these owners. This is not a distributed consensus or automatic authority-failover service.

The native backend uses normal ERTS mailboxes. The bounded `hls_mailbox` inside a source actor models finite hardware admission, but incoming messages can already be waiting in the actor's unbounded BEAM mailbox before that model examines them. The management processes likewise have ordinary BEAM mailboxes. `admit_cast/2` and bounded outstanding requests help the caller respect admission; they do not turn an ERTS simulation into a physical bandwidth or globally bounded-memory guarantee.

## Starting and using a domain

Create the store once. This example assumes `worker` is a supported `hls_statem` source actor and `Observer` is an external recipient:

```erlang
ok = hls_domain:create_store("deployment.activations"),
{ok, Backend} = hls_domain_erts:start_link(#{
    actors => #{worker => #{module => worker, mailbox_capacity => 4}},
    routes => #{worker => #{out => {external, Observer}}},
    startup => #{}
}),
{ok, Owner} = hls_domain:start_link(#{compute => manual}, #{
    module => hls_domain_erts,
    endpoints => #{compute => Backend},
    activation_file => "deployment.activations"
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

## OTP supervision

The catalog chooses `manual` or `automatic` replacement. Use `manual` when reset and reinitialization require application approval. For an explicitly automatic domain, an ordinary supervisor can own:

```erlang
#{id => compute,
  start => {hls_domain_instance, start_link, [Owner, compute]},
  restart => permanent,
  shutdown => 5000,
  type => worker}
```

The child starts promptly and observes readiness asynchronously. It then monitors the exact actor PIDs of its incarnation. Actor failure terminates the child; supervisor restart requests replacement through the surviving owner. Restarting only this representative attaches to the same incarnation if it is healthy. Supervisor intensity and subtree policy remain ordinary OTP policy. A readiness deadline reports an unknown outcome without cancelling or replaying the retained operation.

The generic lifecycle neither releases external reservations nor reconstructs previous application state. Initial support excludes arbitrary actor-local reset of shared state and distributed atomic replacement. Management progress still requires a running backend and working control transport.

See [initialization](initialization.md), [host transaction ownership](host-transactions.md) and [formal evidence labels](formal-contracts.md). Finite native/RTL histories do not establish unrestricted progress, physical reset correctness or external-device safety.
