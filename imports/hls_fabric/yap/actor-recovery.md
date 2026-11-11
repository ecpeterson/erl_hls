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

Final review is retained alongside the checks. Native board qualification and a production transport backend remain separate deployment work; no live-device admission is claimed.

## Atom boundary review

The composer derives all lifecycle codebooks and port widths from the kernel's resolved record types, retains the descriptors in `interface.etf`, and emits matching DSLX constants. The fixture's host and C++ adapters use those same descriptors; numeric source/site failures remain a separate namespace. Native lifecycle values use atoms throughout.

The first compact-code RTL witness exposed missing physical-stream padding before `axis::pack`: numeric widening of the 199-bit input shifted the partial-byte fault field, so the source fault was observed but its domain cause decoded as `none`. The wrapper now pads through `hls_bits::frame_payload`. New all-input framing and valid-first-fault closure properties prevent that failure from being hidden by other invariants. The corrected full RTL witness passes; failed attempts remain retained. Five profile tests, Dialyzer, formatting, source contracts, package boundaries and runtime release closure were rechecked with this interface. The earlier unchanged node-unit evidence remains retained, and the regenerated RTL witness again exercises the actual remote ERTS peer.

## Incarnation terminology

The fixed reset group is a domain; one lifetime is a domain incarnation. Recovery handles, application envelope fields, endpoint bindings and the durable incarnation counter use that vocabulary. `activate/2` remains the operation that starts the first incarnation. Network execution configuration still uses `activation` for automatic versus explicitly started execution; that is independent of recovery identity.

The terminology revision passes nine focused node/profile tests, regenerated normal and failed-initialization RTL witnesses in `recovery-incarnation-rtl-1`, Dialyzer, formatting and source contracts (zero new gaps). The earlier full node and finite formal evidence remains retained; naming does not change lifecycle transitions or wire values.
