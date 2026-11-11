# Actor recovery qualification

The first recovery boundary is a fixed actor domain and a surviving deployment owner. [Actor domains](../docs/actor-domains.md) specifies the supported behavior. The lifecycle transition is ordinary Erlang shared by the native backend and downstream hardware composition; the compiler does not choose application retry policy.

- [x] Make immediate and retained server callback failures terminal, preserve prior state/effects, and report finite source identities through incarnation-specific endpoints.
- [x] Implement native domain incarnation/replacement, generation-specific handles, exclusive ownership and ordinary OTP supervision over actual source actors.
- [x] Qualify duplicate-controller rejection, immutable instance binding and packaged lifecycle source lookup across build-release relocation.

Local qualification uses OTP 28.0.2, rebar3 3.24.0 and the pinned XLS build `9f360fc89`. Evidence is retained under the sibling artifact archive at `runs/recovery-2026-11-10/`; failed attempts and their corrections remain there. No remote CI or native synthesis was requested.

The current compiler suite passes 1,205 EUnit tests, including finite atom unions, owner-alias rejection, packaged-source relocation and VM-local store ownership across registry failure. Focused RTL witnesses cover control failures, service contracts, deferred replies, state-machine replies, names and float services. The deferred case includes a terminal internal continuation after its last retained reply: notification must still occur without a new request. Final formatting, Dialyzer, the source-contract audit and package boundaries pass; the audit reports 3,305 inherited gaps and zero new/changed gaps, not whole-tree documentation completion.

Downstream qualification compiles the same lifecycle kernel and actual source actors into independently resettable networks. SAT checks quantify all finite input/state encodings for six combinational properties and all eight-command histories from cold state; completion inputs are assumed to mean the reported physical action completed. Those checks do not establish physical fence/reset correctness or unbounded progress. See the fabric recovery qualification for the public-port RTL witness.

Remaining deployment work includes physical reset/inhibition, clock-domain crossings and control-session exclusion over a real transport. Directory durability after host power loss is not established by the incarnation store. No transparent replay, historical deduplication, dynamic hardware supervision or external-resource release is implied by this implementation.

## Counter and atom review

The incarnation store is only an eight-byte monotone incarnation counter, not actor persistence. The revised domain guide distinguishes replacement, supervisor-child restart, owner reattachment and backend restart, describes management traffic, and names the shared-owner latency/failure scope. Store claims now use a VM-local registry; surviving claims remain exclusive across a registry crash without Erlang's distributed `global` namespace.

Lifecycle phase, operation, disposition, action and cause are ordinary atom unions. Generic source-union resolution uses `hls_enum` through the existing type-provider and codec machinery; the hardware boundary retains compact codes and rejects unsupported coercions. A finite XLS interpreter/JIT witness exercises all three modes of the enum fixture, including the same atom occupying different positions in two codebooks. Host codecs reject unused codes; the downstream controller separately checks raw invalid hardware values. `atom-review-1.json` retains the successful checks and earlier failures. No application work log or new retry semantics were introduced.

## Incarnation terminology

The fixed actor group is a domain; one lifetime is a domain incarnation, identified by a non-reused incarnation ID. Runtime types, counter configuration and diagnostics now use that vocabulary. `activate/2` remains the operation that creates the first incarnation. This is a naming change with unchanged lifecycle rules and counter format. The 32 focused recovery tests, Dialyzer, formatting and source contracts pass; earlier broad compiler and finite enum checks remain retained.
