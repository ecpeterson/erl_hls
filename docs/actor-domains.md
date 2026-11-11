# Actor domains and replacement

A domain is a fixed set of actors replaced together with their private mailboxes, retained calls and routes. Its deployment owner survives that replacement. Starting an owner attaches to existing backend state; it does not reset or initialize the actors. A source callback failure ends its incarnation. A normal typed rejection is still a normal reply.

`hls_domain_erts` executes real `hls_statem` source actors. A hardware backend must establish the same lifecycle observations through its own fenced/reset scope. The finite `hls_domain_lifecycle` transition function is ordinary Erlang used by both paths; its requests are not evidence that a physical action has completed. The compiler library contains no application recovery policy.

## Commissioning and use

Create an activation store once for a new deployment. Preserve it across owner restarts. Missing or corrupt metadata is an error, never an invitation to create a fresh counter for a running deployment. Counter exhaustion refuses another activation instead of wrapping. The owner excludes another store user in the same BEAM VM; the backend separately excludes conflicting control authorities. Multiple hosts require an independently established ownership handoff.

Allocation synchronizes the file before replacing it, but does not establish containing-directory durability across host power loss. After a host/storage failure, reconcile the retained identities with the backend before admitting work; recreating a missing store is not recovery.

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

Read `hls_domain:status(Owner, compute)` until its phase is `ready`, then obtain the immutable handle and endpoint:

```erlang
{ok, #{phase := ready, handle := Handle}} = hls_domain:status(Owner, compute),
{ok, Pid} = hls_domain:resolve(Owner, Handle, worker),
Reply = hls_statem:call(Pid, Request),
{ok, _Replacement} = hls_domain:replace(Owner, Handle).
```

Replacement compares against the supplied activation. Repeating that request retrieves its retained successor; it does not reset twice after a caller timeout. Older handles reject once another transition has replaced that retained record. Resolve with a handle never follows a stable name into a new incarnation; resolve with a domain name explicitly requests its currently ready endpoint. Previously returned PIDs never become replacement actors.

The first implementation starts actors disconnected, connects every declared route, runs silent initial entry and startup, then publishes readiness. Setup must not send returned effects, reply or leave postponed work. Application ingress remains closed until setup completes. Arbitrary Erlang I/O is outside the lowered callback contract and cannot be rolled back by this check. The ERTS adapter accepts per-actor startup messages; a particular hardware composer may impose a narrower startup contract.

## Lifecycle observations

| Phase | Admission and required completion |
| --- | --- |
| `unbound` | Closed; no incarnation has been initialized. |
| `closing` | Closed; the backend retires the old boundary and acknowledges its fence. |
| `isolated` | Closed; the backend resets the complete private domain state. |
| `initializing` | Closed; the target activation exists but setup has not completed. |
| `ready` | Admit only the current nonzero activation. |
| `failed` | Closed; retain the first fault and current transition for inspection. |

Completion acknowledgements identify the expected activation, target activation and transition. An elapsed timeout is never an acknowledgement. Reset installs a new activation but does not establish readiness. Source failure closes admission without claiming that every peer has stopped simultaneously. In the ERTS backend, actor loss retires the domain's other actors; independent domains keep their state.

`status` distinguishes the finite domain cause from its `detail`: native source exceptions retain their Erlang reason, while a hardware adapter can retain actor/site diagnostics. A disconnected backend returns an unavailable error instead of inventing a reset or failed phase. A failed initial activation before reset acknowledgement remains unresolved through the owner API; reconciliation is required, rather than automatically retrying with another identity.

## OTP supervision

The deployment catalog chooses `manual` or `automatic` replacement. Use `manual` when reset/reinitialization can itself require application approval. For an explicitly automatic domain, an ordinary supervisor can own this child:

```erlang
#{id => compute,
  start => {hls_domain_instance, start_link, [Owner, compute]},
  restart => permanent,
  shutdown => 5000,
  type => worker}
```

The child starts promptly and becomes ready asynchronously. It monitors the exact actor PIDs of its admitted incarnation. Actor failure terminates the child; supervisor restart requests replacement through the surviving owner. If only the representative dies and the domain remains healthy, its successor attaches to that same incarnation. Supervisor intensity/subtree policy remains ordinary OTP policy. Neither representative termination nor reconnection silently resets a domain. The child bounds its local readiness wait; expiration reports an unknown outcome without cancelling the retained operation.

## Message and effect boundaries

A failed callback/entry publishes none of its returned effects and commits no proposed state. Earlier accepted effects remain accepted; reset cannot reverse them. Pending calls fail with endpoint death. Calls or casts are never transparently replayed. Public hardware failure frames are terminal even when their transaction has timed out or the failure came from a cast; ordinary busy/format rejection remains nonterminal.

`hls_statem:admit_cast/2` acknowledges bounded private-mailbox admission and rejects when disconnected/full. Bridges must also bound their outstanding requests. Native ERTS mailboxes and unrestricted senders do not acquire a hardware throughput bound from this API. Management progress still requires a running backend and functioning control transport.

The generic lifecycle does not release external resource reservations, reconstruct previous state, or certify an external device's safety. Those decisions belong to the application and its device-specific controllers. Initial support excludes arbitrary actor-local reset of shared state and distributed atomic replacement.

See [initialization](initialization.md), [host transaction ownership](host-transactions.md) and [formal evidence labels](formal-contracts.md). Focused tests use real actors, ordinary OTP supervision, stale/lost management requests and independently running domains; simulation histories do not establish unrestricted progress or physical reset correctness.
