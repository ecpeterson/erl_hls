# Closed source-protocol recovery domains

`hls_protocol_domain:write/2` compiles one complete source-protocol network behind an incarnation boundary. It takes the ordinary network configuration and writes a portable source bundle for the existing external XLS driver. A domain is the fixed group of actors, private links, pending publications and host ingress that are reset together; a domain incarnation is one lifetime of that group. Separate emitted core instances have independent lifecycle and network state.

The control transition is the Erlang `hls_domain_lifecycle` kernel, compiled through its own small service adapter. The wrapper supplies physical observations: it acknowledges fencing only after the external ingress and egress gates close, acknowledges reset on the edge that resets every network component, and acknowledges initialization only after all source receivers have completed entry/internal callbacks successfully. `startup_done` alone is insufficient for readiness.

Erlang represents lifecycle commands, phases, dispositions, actions and causes as atom unions. The composer resolves their record fields through the ordinary `hls_type` machinery, retains the resulting codecs in `domain/interface.etf`, and generates `domain/domain_codes.x` and the port widths from those descriptors. A host transport packs and unpacks these atoms with the retained codecs; it needs neither compiler source nor a separately maintained numeric table. Numeric source-site failure codes remain a separate diagnostic field. Atom declaration order defines the wire encoding, so a bridge must use the interface from its matching hardware bundle.

Management and application traffic are separate interfaces. Only management requests, inspection, abort and an explicit owner-disconnect indication enter from the backend; physical completion opcodes are internal. The owner supplies non-reused 64-bit incarnation and transition identities. Application envelopes carry an incarnation; a stale or unready envelope is rejected without reaching the actor inbox. Outbound records carry the current incarnation at their acceptance boundary. Neither a replacement nor its fence revokes an output that an external consumer already accepted.

The first boundary supports a closed whole-network placement, rectangle ingress, automatic internal execution, no declared startup messages and silent initialization. A source initializer/entry failure closes admission. An initialization publication attempt also fails closed; it is not released to the application. Source failures retain actor index and full finite failure code separately from the domain cause. The generated control adapter currently requires ten frame payload words, so the builder selects at least that capacity. This is an internal composition constraint, not a promise that every deployment frame is ten words.

The backend must connect every application ingress and egress through the gates and keep management available independently of application backpressure. A dead physical backend does not establish a successful fence or reset; its owner must retain uncertainty. No distributed reset protocol or crossing-link ownership policy is implied by this single-clock composition.

## Focused local witness

After compiling the test profile with the matching compiler checkout, run:

```sh
python3 tools/test_domain_recovery.py /path/to/xls /fresh/artifact/directory
```

The witness compiles two ordinary source actors, counter then relay, into a complete network; two independent instances communicate with actual Erlang owners and incarnation-specific actor endpoints through separate management/application FIFO pairs. A second build makes initial source entry fail. Test-only stale-wire injections are labeled separately from actual source-generated responses. The simulator touches only public clock, management, ingress and egress ports, and never forces internal actor state.

The fixture transport sequences application responses and puts the accepted-response frontier in each management snapshot. A fault closes admission immediately, but orderly endpoint termination waits until every promised prior response reaches the adapter. The endpoint processes those replies before its in-band retirement message. Missing, malformed or timed-out delivery evidence yields connection uncertainty instead of an invented orderly source failure. A deterministic witness stalls delivery after hardware acceptance, observes the fault independently, then checks the reply precedes `DOWN` when delivery resumes. This transport frontier belongs to the fixture adapter; a production bridge needs its own corresponding ordered lane or frontier contract.

This is finite simulation evidence. It establishes neither arbitrary progress nor board admission, physical timing or exhaustive source/RTL equivalence. The controller retains one lifecycle transition and first fault, not an application work history. Local test generation and simulation are serialized; neither Vivado nor a whole-application performance sweep is needed for this contract witness.

The fixture implements requests as source-level request-ID/cast/report messages. It does not add general synchronous calls to the source-protocol lowering. Its stale acknowledgement case covers application admission; it is not an exhaustive proof of private credit handling.

The compiled kernel can also be checked independently:

```sh
python3 tools/test_domain_formal.py /path/to/xls /emitted/source/bundle /fresh/formal/evidence
```

The checker consumes an already emitted source bundle. It checks exact command framing, admission consistency, preservation of state on stale requests and unused control encodings, first-fault closure, and completion requirements for readiness over every finite input/state encoding, plus all eight-command histories from cold state. An intentionally incorrect admission rule must produce a counterexample. These results trust the compiler, XLS and SAT toolchain; they verify controller decisions under the meanings assigned to backend completion signals, not the physical fence or reset wiring. See the compiler's evidence labels when reporting a run.

## Device-specific recovery policy

The generic profile fixture in `test/hls_recovery_profile_tests.erl` separates a finite actuator from its host policy. It has eight capability bits, two predeclared profiles, configuration epochs and one pending transition. Tests distinguish applied digital configuration from an unavailable logical result, keep reservations across controller replacement, and allow a selected branch to ignore an unused failed input. These are interface witnesses; a device library must supply real profiles, resource ownership rules and the meaning of a usable result. Neither compiler nor bridge interprets that meaning.
