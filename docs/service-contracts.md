# Service reply contracts

An `hls_gs` module declares the public records permitted in replies to each call:

```erlang
-hls_tags([set, get, ping, bulk_get, ack, read, bulk_read]).
-hls_replies([{ping, [ack]}, {get, [read]}, {bulk_get, [bulk_read]}]).
-compile({parse_transform, hls_pack}).
```

Every record handled by `handle_call/2` (or `handle_call/3` for [retained replies](retained-replies.md)) must have exactly one nonempty reply set. Each member must be a unique public `hls_tags` record. State records and the reserved `error` tag are not reply-set members. Cast tags have no reply declaration: their successful completion is silent. A record may be both a request and a reply, but a request tag cannot select both `handle_call/2` and `handle_cast/2`. Declarations may be spread across attributes and included headers; duplicate request declarations are rejected, even when identical.

The sets describe the intended interface independently of the implementation. For example, `[{query, [small, large]}]` permits either record, including records with different payload lengths. Separate source-ordered callback clauses can return different record types. Expression-level record choices still obey the compiler's [ordinary type-join constraints](control-flow.md); this declaration does not add general sum types.

The parse transform and XLS lowerer validate the same source contract. `hls_pack` embeds the normalized call and cast sets as module metadata; the host needs neither the source files nor compiler analysis when starting a proxy. A fabric proxy refuses a module without this metadata before registering its route. CPU-only adapters without `hls_pack` retain ordinary direct-callback behavior.

## Execution and failures

These are explicit HLS interface contracts, stronger than ordinary Erlang message passing. Erlang normally lets the caller interpret a reply and fail when it does not match the caller’s expectations; an `hls_gs` contract instead makes the declared reply kinds part of the service boundary and checks them before completion. The annotation is intended for a finite hardware interface, not as a general requirement on Erlang processes.

The CPU adapter checks each callback reply before committing the returned state. A reply outside the set raises `{reply_contract, RequestTag, Reply, AllowedTags}`, terminating the adapter like an ordinary callback exception. This checks the record kind; the [numeric representation contract](numeric-contract.md) still governs field values.

Generated hardware checks the reply tag after evaluating the selected body. An ordinary body failure takes precedence. A contract violation returns the one-word `ERROR` code 15, decoded by the proxy as `{error, {remote_error, reply_contract}}`. For immediate servers it follows the existing `hls_gs` callback-failure rule: zero callback state, rather than committing the invalid result's proposed state. A request-length error occurs before the callback and preserves state. See [control flow and failures](control-flow.md).

For constant record constructors, XLS can fold the membership check away. A declaration is not a static proof that the implementation always honors it; an erroneous callback remains executable and reports its violation. Constructors returned through typed helpers, local aliases, and branches receive the same check.

Both adapters reject a call using a cast-only or non-request tag with `{error, {invalid_request, call, Tag}}`. The fabric proxy sends nothing and reserves no transaction slot. An invalid cast raises `{invalid_request, cast, Tag}`: casts have no reply handle, so the adapter terminates rather than silently accepting a command it cannot execute. Internal inspection calls retain their existing handling.

## Host reply matching

Each submitted application call retains its allowed set until completion, including after caller timeout or death. A received record must belong to that set and decode without missing or trailing payload bytes. Error replies are permitted for every call but must contain exactly one 32-bit error code. Wrong kinds, unknown tags, invalid record payloads, and malformed error frames increment `ignored_replies` and leave ownership intact. A subsequent valid reply may still complete the call. An endpoint that emits only invalid replies can consequently exhaust the client's slots; host timeouts do not make those slots reusable.

Allowed sets constrain reply kinds, not values or causality. They cannot distinguish a fabricated response of the right type or an old duplicate delivered after transaction-ID reuse. The existing [host transaction contract](host-transactions.md) and transport assumptions still apply. Host codecs, declarations, and loaded hardware must belong to the same application build; these checks do not negotiate ABI versions or make live code replacement safe.

## Validation

`rebar3 eunit` checks declaration errors, CPU behavior, mixed pending request types, alternative reply sizes, malformed errors, admission, and late replies to timed-out/dead callers. `bash tools/test_service_contracts.sh XLS_ROOT` simulates generated hardware at three pipeline schedules. It checks alternative records, helper and branch results, deliberate contract violations, preceding body failures, state effects, casts, backpressure, and transaction-ID wrap through the external word-stream ports. Routine CI also retains the live routed-service/debug regression and complete D3 decoder coverage.
