# Closed-domain recovery qualification

The implementation composes whole source-protocol networks around the shared Erlang lifecycle kernel and exposes incarnation-specific endpoints through the virtual node. [Domain recovery](../docs/domain-recovery.md) and [device sessions](../docs/device-sessions.md) specify the supported interfaces. The older scoped-recovery note is design history, not authority for additional work-history or replay guarantees.

- [x] Compile the lifecycle kernel around a complete source network with independent management, closed admission during replacement and successful-entry readiness.
- [x] Exercise actual local RTL against Erlang owners and a real second ERTS peer, including independent domains and failed initialization.
- [x] Add generic two-profile actuator/policy witnesses separating digital completion, logical result validity and retained resource reservations.
- [x] Qualify accepted-output ordering, stale profile identities and the runtime release; pin compiler/runtime [PR #41](https://github.com/ecpeterson/erl_hls/pull/41).

Evidence is retained in the sibling artifact archive at `runs/recovery-2026-11-10/`. All local work is serialized under a 6 GiB guard. Final atom-based qualification regenerates both normal and failed-initialization designs in `recovery-atoms-rtl-2`, with check logs under `atom-rtl-witness-2`. Native and RTL public histories match `[7,7,0]`. A is replaced six times while B is never replaced. The witness includes stale ingress/report/admission acknowledgements, a partial application frame, a lost actual replacement response, ownership reconciliation, remote virtual-PID retirement and initialization that remains closed on failure. The simulator uses only public ports, with independent application and management parsers; no internal actor state is forced.

Final review caught an output-ordering defect: fast management could retire a proxy before an already accepted report reached its application lane. The transport now includes a nonwrapping response sequence and management delivery frontier; the endpoint processes ordered retirement after earlier results. A deterministic stalled-delivery witness requires the accepted reply before source-failure `DOWN`. Missing frontier evidence terminates with `noconnection`, not an invented orderly source outcome. An initial negative trial accidentally used the source fixture's non-failing zero case; the corrected trial first adds 13 through the public application API. Both attempts are retained.

The node/peer suite passes 23 tests; the profile suite passes five, including reused request IDs with stale completion and query epochs. Final formatting, Dialyzer, application boundaries and runtime release package checks pass. Source contracts report 289 inherited gaps and zero new/changed gaps. Remote CI remains unused because Actions credits are exhausted.

`recovery-atoms-formal-1` checks the actual generated controller with six combinational SAT properties and every eight-command history from cold state, retaining a counterexample for an intentionally wrong admission rule. Toolchain, input and output hashes accompany the evidence. Reported backend completion meanings are assumptions; physical reset, arbitrary progress and native timing are outside these checks.

Requests in the RTL fixture use explicit source request-ID/cast/report messages. Stale acknowledgement checks cover that application protocol, not exhaustive private-credit behavior. The whole-network boundary resets private links together and rejects crossing placement; it is not a distributed reset implementation. The generic profile fixture supplies no real device safety schedule or logical-state recovery policy.

Final review is retained alongside the checks. At that stage the production transport backend remained separate; the reusable-backend follow-on below implements it. Native board qualification remains separate, and no live-device admission is claimed.

## Atom boundary review

The composer derives all lifecycle codebooks and port widths from the kernel's resolved record types, retains the descriptors in `interface.etf`, and emits matching DSLX constants. The fixture's host and C++ adapters use those same descriptors; numeric source/site failures remain a separate namespace. Native lifecycle values use atoms throughout.

The first compact-code RTL witness exposed missing physical-stream padding before `axis::pack`: numeric widening of the 199-bit input shifted the partial-byte fault field, so the source fault was observed but its domain cause decoded as `none`. The wrapper now pads through `hls_bits::frame_payload`. New all-input framing and valid-first-fault closure properties prevent that failure from being hidden by other invariants. The corrected full RTL witness passes; failed attempts remain retained. Five profile tests, Dialyzer, formatting, source contracts, package boundaries and runtime release closure were rechecked with this interface. The earlier unchanged node-unit evidence remains retained, and the regenerated RTL witness again exercises the actual remote ERTS peer.

## Incarnation terminology

The fixed reset group is a domain; one lifetime is a domain incarnation. Recovery handles, application envelope fields, endpoint bindings and the durable incarnation counter use that vocabulary. `activate/2` remains the operation that starts the first incarnation. Network execution configuration still uses `activation` for automatic versus explicitly started execution; that is independent of recovery identity.

The terminology revision passes nine focused node/profile tests, regenerated normal and failed-initialization RTL witnesses in `recovery-incarnation-rtl-1`, Dialyzer, formatting and source contracts (zero new gaps). The earlier full node and finite formal evidence remains retained; naming does not change lifecycle transitions or wire values.

## Reusable backend follow-on

- [x] Run the same supervised profile application on ERTS and source-protocol RTL through the custom distribution node.
- [x] Admit bounded calls using the existing shared reply-book and callback machinery.
- [x] Ship schema-derived host endpoints and hardware framing, request correlation and reply-retirement frontiers.
- [x] Keep an external device model alive across domain replacement and exercise adverse delivery schedules against independent public expectations.

Local implementation/evidence is retained under `runs/recovery-2026-11-11/`, serially bounded to 6 GiB. Management and application use independent streams; physical device deployment and cross-domain reset remain separate.

The reusable path is `write_stream/2` → the external XLS driver → `hls_domain_fabric` → `hls_domain_endpoint` → the existing `hls_node`. This initial follow-on reused distribution forwarding; the admission follow-on below consolidates that forwarding and removes completion-based blocking. The application uses ordinary typed calls/casts; bounded reply ownership reuses compiler machinery. Internal calls and dynamic internal reply destinations remain rejected.

`stream-witness-2` passes with the exact simulator and native expected history retained from the first attempt. Both deployments exercise the same source controller, host policy and OTP supervisor through a real remote ERTS node. Accepted/repeated/rejected profiles, stale commands, independent domains, fresh/stale virtual PIDs, representative reattachment and supervisor intensity exhaustion agree with explicit application expectations. An external model retains effects and reservations across controller replacement. The additional RTL delivery schedule holds B's application receipt at sequence 10 while hardware reaches 14 and then failure frontier 15. Its endpoint stays alive until release; the typed reply and external effect precede `DOWN`. Every FIFO descriptor lease closes. The first attempt passed these application assertions but exposed a teardown ordering error; that failed attempt remains retained.

All 52 focused EUnit tests, two DSLX reply witnesses and six stream checks pass. Host tests additionally exercise missing delivery frontiers, lost management responses without replay, and owner-loss exclusion until an actual device closure observation. The latter exercise malformed/partial framing, blocked-output stability, independent management, sticky transport failure and actual typed storage. Transport state is 2,995 bits against a 3,105-bit preregistered ceiling, with one selected application transfer per edge and independently owned management buffering; these are structural counts, not mapped area or throughput. All 96 final generated DSLX, RTL adapter, retained interface and support files are byte-identical to the tested bundle. Only four transient source-origin references in retained planning metadata and its manifest hash differ.

Local Dialyzer, formatting, source-contract and application/runtime package checks pass; there remain 289 inherited source-contract gaps and zero new gaps. No CI, Vivado or live-device test ran. The witness proves no physical quiescence, device safety, arbitrary progress, distributed reset or exhaustive source/RTL equivalence. Exclusive fresh attachment and external resource/recovery policy remain explicit deployment/application obligations.

## Admission and arbitration follow-on

- [x] Share queued/submitted/admitted request ownership between managed endpoints and legacy wire channels; keep framing adapters distinct.
- [x] Release connection admission credit before retained calls complete, with independent per-actor call/cast capacity and explicit capacity wakeups.
- [x] Replace the older RTL fixture endpoint with the production endpoint.
- [x] Skip idle stream producers without adding storage or selecting more than one application packet per edge.

Evidence is retained at `runs/recovery-serialization-2026-11-11/`. The native/RTL profile application again agrees through a real ERTS peer, including independent domains, retained external resources, stale identities, supervisor replacement and delayed reply/effect delivery before DOWN. Nine finite DSLX checks include sparse producers, round-robin accepted-transfer fairness, stalled output and same-edge final-beat refill. The preregistered hardware allowance adds no state or packet buffers. This is finite behavioral and structural evidence, not a mapped-area or throughput measurement.

Focused tests hold actor A’s calls while B and a release cast progress; exercise busy-cast capacity waits without replaying admitted work; scope ordinary-cast rejection to one peer binding; and keep management write ownership bounded even after logical timeouts. A full application attempt caught acknowledged casts being classified as ordinary calls; the corrected real-peer regression and matched RTL witness pass. An invalid DSLX parametric expression was also corrected; both failed attempts remain retained.

Remaining serialization is explicit: one application receive head and transmit packet per physical stream, one ordered output frontier per domain, codec work in a per-domain backend, and node publication transactions. A flood of unadmitted requests can still exhaust finite connection intake. The scheduler wire codec remains separate from the managed-domain codec, but both now use one request ledger. Domain admission is not yet mandatory for every deployment, and this change does not invent reset guarantees for legacy scheduled actors.

The final serialization follow-on passes 114 distinct focused EUnit cases across the two repositories, nine DSLX stream checks and the matched real-peer native/RTL application witness. Local Dialyzer, formatting, source contracts (289 inherited fabric gaps, zero new) and runtime release boundaries pass. The fabric pins compiler/runtime [PR #42](https://github.com/ecpeterson/erl_hls/pull/42). The release is a runtime closure, not an OTP hot-upgrade package.

A first successful arbitration build exposed an optimizer-retained extra cursor bit. Narrowing the already range-checked grant before increment restored the exact 65-element/4,167-bit optimized state layout. The final IR contains 1,870 nodes versus 1,879 before; its 21 preview-origin nodes contain no actor/receiver origins, while committed actor and receiver operation counts are unchanged. This supports pruning of the unused preview successor for this fixture; node counts are not cell counts. Final generated hardware, nine DSLX checks and the real-peer RTL witness were rebuilt after that correction.
