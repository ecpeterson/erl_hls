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

## Admission and independent management

- [x] Separate native actor admission from call completion, sharing bounded capacity observations with downstream hardware endpoints.
- [x] Keep one ordered management lane per domain, with asynchronous backend waits and one durable incarnation allocator in the actual owner process.

The serialization follow-on is retained at `runs/recovery-serialization-2026-11-11/`. Its 58 focused runtime tests cover held calls, capacity notification, dead observers, independently stalled domain inspection/resolution/submission, queue bounds, backend loss, abandoned responses and timeout reconciliation. Native admission acknowledges private-queue acceptance before any effects or final reply; it does not promise successful dispatch. Only explicit pre-admission rejection permits resubmission. Capacity wakeups reserve nothing.

Formatting, Dialyzer, source contracts and runtime package boundaries pass. The contract audit reports 3,303 remaining gaps and zero new/changed gaps. Backend waits no longer block other domains; initial attachment and counter persistence remain shared operations. Ordinary ERTS mailboxes remain unbounded. The implementation introduces no work history or transparent replay.

## Connection loss and same-incarnation reattachment

- [x] Preserve native actors and accepted lifecycle work after management-owner loss by default; `owner_loss => fail` retains explicit owner-coupled retirement.
- [x] Reattach a dead local backend adapter through the owner's existing asynchronous domain lane, checking the same ready incarnation before attachment and after binding. Reject live takeover and duplicate candidate reservations across domains.
- [x] Keep an incarnation representative unavailable after proxy `noconnection`, then re-monitor confirmed same-incarnation endpoints after explicit reattachment. Polling does not reconnect, reset or replay work.

Local evidence is retained at `runs/recovery-reattach-2026-11-11/`. Six focused runtime modules passed 45 tests; the five-test reattachment module then passed after adding the concurrent candidate-reservation witness. These finite native/host witnesses cover actor state and pending-call survival, explicit fail policy, same-owner authority, other-domain progress, mismatched identity rejection, lost final confirmation and same-incarnation representative recovery. The fixture's retained controller snapshot models the hardware boundary; it does not prove physical persistence or session exclusion.

Formatting, Dialyzer and runtime package boundaries pass. Source contracts report 3,303 inherited/current gaps and zero new/changed gaps. A connection failure remains an unknown application outcome; old reply/monitor contexts do not resume, accepted work is not replayed, and hardware continuity must be established by its backend. A native backend restart still starts `unbound`; only management-owner restart preserves its actors. No remote CI, synthesis or hardware run was performed for this change.

The availability watcher also survives its own five-second owner-call timeout while already disconnected. A deterministic witness withholds backend status and suspends the owner until that deadline, then confirms the representative stays unavailable and later reattaches to the same incarnation without allocating an identity. That single witness passed; the changed observer passed formatting, source contracts and incremental Dialyzer. Other owner exits and actual actor failures retain their existing terminal behavior.

## Supervised shutdown and mixed placement

- [x] Complete an incarnation-specific stop operation and explicitly supervised domain lifetimes; exercise healthy shutdown, dependent OTP subtree restarts, stale commands and interrupted retirement on native actors and generated RTL.
- [x] Run an Erlang-defined static supervisor on FPGA over two independent reset-safe child domains. Exercise local one-for-one recovery during host disconnection, fresh delegated incarnation identities, bounded restart intensity and reconciliation after reconnect.
- [ ] Connect autonomous supervisors to the production framed bridge with bounded retirement acknowledgement before publishing independently replaced child PIDs; preserve prior replies and distinguish connection uncertainty across unseen child incarnations.
- [ ] Support bounded temporary children early in application work: static slots and supported child templates, runtime occupancy, explicit capacity exhaustion, no automatic restart for `restart => temporary`, and slot reuse only after confirmed retirement, old-traffic exclusion and a fresh incarnation. No dynamic circuit allocation is implied.
- [ ] Extend independent hardware-domain communication and dependent restart groups together; exercise asymmetric reset with outstanding data and credits and an unaffected third domain.
- [ ] Qualify deployment recovery over a real transport, including physical exclusion, acknowledgements and device identity. Keep digital restart separate from external-resource recovery.

Host-to-FPGA supervision is the priority. FPGA-to-host supervision is deferred until a concrete use case needs it or the supported mechanism makes it straightforward. A compiled supervisor should accept a checked static subset of ordinary OTP declarations rather than a separate policy language; native OTP traces supply the behavioral reference. Restart bookkeeping is bounded management state, not application work history.

Shutdown evidence is retained at `runs/recovery-shutdown-2026-11-11/`. Updated lifecycle/shutdown checks passed 18 tests, two added reconnection scenarios passed, and the final affected owner regression passed 23 tests. The original 47-test pre-review run and corrected assertions remain retained separately; these counts overlap. Dialyzer, formatting, source-contract and package checks pass, with 3,303 inherited contract gaps and zero new gaps. The downstream matched native/three-core RTL witness exercises healthy termination, one-for-all/rest-for-one, fresh identities, an unaffected third domain and prior-reply delivery before shutdown. Eight finite lifecycle properties pass, including an eight-input history bound; a deliberately wrong admission rule produces its expected counterexample. These do not establish physical isolation, unbounded progress, or FPGA-resident restart policy.

Static-supervisor implementation is in progress in the `codex/fpga-supervisor` worktree, stacked above explicit shutdown. The shared Erlang kernel and durable grant reservation have focused native witnesses; generated RTL qualification remains pending. Initial hardware startup follows synchronous OTP child initialization, while existing host domain representatives retain their documented asynchronous readiness. The finite timestamp ring supports at most sixteen restarts per declared period. Host-to-FPGA control is the next boundary; individually distributed child endpoint retirement, FPGA-to-host supervision and physical deployment remain separate.

Static-supervisor evidence is retained at `runs/recovery-fpga-supervisor-2026-11-11/`. The ordinary native OTP reference and public-pin RTL witness agree on fresh child state/identities, independent sibling progress, two permitted restarts followed by intensity exhaustion, window expiry and whole-subtree shutdown. The generated two-child composition ran 34,094 clocks. An ordinary host OTP parent drove the existing domain API through a witness adapter, lost its adapter while local recovery continued, and explicitly reattached to the same parent incarnation. The witness also rejects stale application identities and old grants, retains the allocation cursor on repeated grant input, and retires all children on identity exhaustion. Individually published child virtual PIDs and physical deployment remain separate work.

Fourteen finite supervisor cases, eleven owner cases and fourteen declaration/port checks pass across retained runs. Six finite compiled-kernel propositions pass, with a deliberately incorrect readiness rule producing a counterexample. The first-allocation proposition composes two source transitions; the other propositions are single-step checks under their stated finite-domain assumptions. They do not prove arbitrary execution histories or physical fencing. The proved generated kernel and codebook are byte-identical to the final RTL bundle.

The supervisor declares 2,411 control-state bits for two children. XLS retains 2,267 state bits in 36 elements and 2,850 IR nodes; each unchanged child domain retains 1,317 bits in 48 elements. These fit the preregistered management-state allowance, with no new child application buffers or reply slots. They are not mapped-area or clock-rate measurements. Local formatting, Dialyzer, source-contract and package checks pass; inherited gaps remain 3,303 in the compiler and 289 in fabric, with zero new gaps. No Actions, EC2 or live-device test ran. All failed check/build attempts remain in the evidence.
