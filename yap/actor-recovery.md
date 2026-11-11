# Actor recovery qualification

The first recovery boundary is a fixed actor domain and a surviving deployment owner. [Actor domains](../docs/actor-domains.md) specifies the supported behavior. The lifecycle transition is ordinary Erlang shared by the native backend and downstream hardware composition; the compiler does not choose application retry policy.

- [x] Make immediate and retained server callback failures terminal, preserve prior state/effects, and report finite source identities through incarnation-specific endpoints.
- [x] Implement native domain activation/replacement, generation-specific handles, exclusive ownership and ordinary OTP supervision over actual source actors.
- [x] Qualify duplicate-controller rejection, immutable instance binding and packaged lifecycle source lookup across build-release relocation.

Local qualification uses OTP 28.0.2, rebar3 3.24.0 and the pinned XLS build `9f360fc89`. Evidence is retained under the sibling artifact archive at `runs/recovery-2026-11-10/`; failed attempts and their corrections remain there. No remote CI or native synthesis was requested.

The compiler suite passed 1,167 EUnit tests; the subsequent 12-test focused run covers the final owner-alias rejection and packaged-source relocation changes. Focused RTL witnesses cover control failures, service contracts, deferred replies, state-machine replies, names and float services. The deferred case includes a terminal internal continuation after its last retained reply: notification must still occur without a new request. Final formatting, Dialyzer, the source-contract audit and package boundaries pass; the audit reports 3,307 inherited gaps and zero new/changed gaps, not whole-tree documentation completion.

Downstream qualification compiles the same lifecycle kernel and actual source actors into independently resettable networks. SAT checks quantify all finite input/state encodings for three single-step properties and all eight-command histories from cold state; completion inputs are assumed to mean the reported physical action completed. Those checks do not establish physical fence/reset correctness or unbounded progress. See the fabric recovery qualification for the public-port RTL witness.

Remaining deployment work includes physical reset/inhibition, clock-domain crossings and control-session exclusion over a real transport. Directory durability after host power loss is not established by the activation store. No transparent replay, historical deduplication, dynamic hardware supervision or external-resource release is implied by this implementation.
