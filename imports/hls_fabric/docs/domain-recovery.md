# Closed source-protocol recovery domains

`hls_protocol_domain:write/2` compiles one complete source-protocol network behind an incarnation boundary. It takes the ordinary network configuration and writes a portable source bundle for the existing external XLS driver. A domain is the fixed group of actors, private links, pending publications and host ingress that are reset together; a domain incarnation is one lifetime of that group. Separate emitted core instances have independent lifecycle and network state.

The control transition is the Erlang `hls_domain_lifecycle` kernel, compiled through its own small service adapter. The wrapper supplies physical observations: it acknowledges fencing only after the external ingress and egress gates close, acknowledges reset on the edge that resets every network component, and acknowledges initialization only after all source receivers have completed entry/internal callbacks successfully. `startup_done` alone is insufficient for readiness.

Erlang represents lifecycle commands, phases, dispositions, actions and causes as atom unions. The composer resolves their record fields through the ordinary `hls_type` machinery, retains the resulting codecs in `domain/interface.etf`, and generates `domain/domain_codes.x` and the port widths from those descriptors. A host transport packs and unpacks these atoms with the retained codecs; it needs neither compiler source nor a separately maintained numeric table. Numeric source-site failure codes remain a separate diagnostic field. Atom declaration order defines the wire encoding, so a bridge must use the interface from its matching hardware bundle.

Management and application traffic are separate interfaces. Only management requests, inspection, abort and an explicit owner-disconnect indication enter from the backend; physical completion opcodes are internal. The owner supplies non-reused 64-bit incarnation and transition identities. Application envelopes carry an incarnation; a stale or unready envelope is rejected without reaching the actor inbox. Outbound records carry the current incarnation at their acceptance boundary. Neither a replacement nor its fence revokes an output that an external consumer already accepted.

The first boundary supports a closed whole-network placement, rectangle ingress, automatic internal execution, no declared startup messages and silent initialization. A source initializer/entry failure closes admission. An initialization publication attempt also fails closed; it is not released to the application. Source failures retain actor index and full finite failure code separately from the domain cause. The generated control adapter currently requires ten frame payload words, so the builder selects at least that capacity. This is an internal composition constraint, not a promise that every deployment frame is ten words.

The backend must connect every application ingress and egress through the gates and keep management available independently of application backpressure. A dead physical backend does not establish a successful fence or reset; its owner must retain uncertainty. No distributed reset protocol or crossing-link ownership policy is implied by this single-clock composition.

## Stop and supervised lifetime

The shared lifecycle accepts incarnation-specific `stop`. It closes admission and reaches `stopped` only after the fence acknowledgement, without pulsing reset, running initialization or allocating a successor. A repeated stop is idempotent; a stale command cannot stop a newer incarnation. Replacement from stopped starts a fresh lifetime through the ordinary reset and initialization sequence.

For an OTP child that owns the domain's lifetime, use `hls_domain_instance:start_link(Owner, Domain, #{lifetime => supervised})`. Its surviving deployment owner records retirement intent before a replacement child may claim the domain. Ordinary supervisor shutdown waits for confirmed retirement; killing the representative does not cancel that intent. The default observing representative and transport-only disconnection preserve healthy actors. Keep the deployment owner and backend outside the controlled subtree. Owner/host loss does not persist the representative's shutdown intent, and remote uncertainty must not be reported as successful device retirement.

The framed backend also requires its promised prior-output frontier and actual endpoint termination before exposing `stopped`. Healthy intentional retirement reports `shutdown`; an already observed source failure keeps its cause. New admission is closed while earlier replies and effects drain. An accepted call which has not produced a reply need not complete, and no application work is replayed. Missing transport or output evidence remains uncertainty.

The lifecycle is an Erlang transition kernel usable by host or compiled controllers. The static composition below adds FPGA-local restart policy above independent child domains. Crossing-link ownership and physical clock/reset isolation remain separate contracts.

## Static supervisors on FPGA

`hls_protocol_supervisor:write/2` elaborates a checked subset of an ordinary OTP supervisor declaration and composes its fixed children as independently resettable source-protocol networks. The callback runs at build time; the FPGA does not interpret Erlang child specifications or dynamically allocate circuitry. The same declaration can start native domain representatives under an ordinary ERTS supervisor for comparison.

```erlang
Config = #{
    supervisor => {SupervisorModule, {deployment_owner, Flags}},
    children => #{a => NetworkA, b => NetworkB},
    clock_hz => 100000000
},
Bundle = hls_protocol_supervisor:write(Config, "build/supervised").
```

The callback must return `one_for_one`, an intensity from zero through sixteen, a positive 32-bit period in seconds, and `auto_shutdown => never` when supplied. Each child must be a permanent worker whose start function is `hls_domain_instance:start_link/3` with `#{lifetime => supervised}` and the same domain name as its child ID. Brutal-kill shutdown and unsupported strategies or child kinds reject during elaboration. The deployment-owner argument is a placeholder at build time and an actual owner PID in the native declaration. The `children` map supplies exactly the networks named by that declaration; it does not select application recovery meaning.

The compiled Erlang supervisor policy lives outside its children's reset regions. It alone issues their lifecycle commands; host requests address the parent boundary rather than competing with it for child ownership. Child source faults close that child's admission independently. Management visits one child per edge, while the other networks and their independent application interfaces continue advancing. This serializes bounded recovery decisions, not ordinary actor messages.

Restart intensity counts replacement attempts within the declared sliding window, excluding initial startup. The generated local divider produces whole-second ticks from `clock_hz`; disconnected or stalled host management does not stop that clock. The deployment must supply the declared hardware frequency. This is neither a physical timing measurement nor an externally synchronized clock. Exhausted restart intensity or incarnation allocation closes the subtree and retires its children before reporting terminal parent failure. An unrelated domain outside that subtree is unaffected.

The parent uses the existing domain lifecycle interface. Its initialization remains pending until an identity grant is accepted and every child is ready. An orderly parent stop disables local recovery, retires its children and waits for completion. Existing lifecycle rules still apply to an already accepted initialization or replacement: stop cannot erase its reserved transition, and a busy response or timeout is not cancellation. Host connection loss alone neither stops the subtree nor resets healthy children. A host supervisor can control this parent through a backend adapter without occupying the local child-recovery path.

### Delegated identities

Before autonomous operation, the deployment durably reserves a finite, non-reused incarnation interval and presents `grant_valid`, `grant_epoch`, `grant_first` and `grant_last` through the public pins. The epoch must match the initializing parent's incarnation; the interval must lie above the controller's retained allocation high-water mark, and its inclusive upper bound must be below the largest 64-bit value. The supervisor consumes a fresh identity before each initial start or replacement; exhausted space fails closed instead of wrapping.

An exact repeated grant observes the same allocation and cannot rewind its cursor. Parent replacement resets child and supervisor execution state while retaining the allocation high-water mark, so a new parent incarnation needs a new interval. Full hardware reset loses that state. The deployment must then establish old-traffic exclusion and supply a fresh durably reserved interval; replaying an old grant is not recovery from lost allocation state. These grants retain no application work history.

### Public boundary and limitations

This composition emits raw parent management, grant and per-child application ports. It does not publish autonomous child incarnations as individual virtual Erlang PIDs through `hls_domain_fabric`. Several local replacements can occur between host observations; the ordinary framed backend's single retirement frontier cannot by itself represent every unseen child lifetime. Extending that publication path requires an explicit ordering and retirement contract rather than silently reusing the host-driven replacement assumption.

The native reference uses ordinary OTP supervision over actual counter/relay source domains. Its public outcomes cover independent progress, fresh source state and identities, intensity exhaustion, window expiry and explicit shutdown. Generated public-pin witnesses compare those outcomes; they do not equate ERTS scheduling with hardware clock counts or establish physical reset isolation. FPGA-to-host supervision and bounded temporary children remain follow-on work. Temporary children will need finite slot admission, retirement before slot reuse and fresh incarnation identities; fixed circuitry does not require every slot to be permanently occupied.

## Framed hardware backend

`hls_protocol_domain:write_stream(Config, Directory)` emits the same closed network behind two independently backpressured word streams. Compile its source bundle with the ordinary external XLS driver. The selected top is `domain_stream`, with separate management and application input/output channels. Each channel carries the existing route/header/payload words. `domain/interface.etf` retains actor schemas, call contracts, port identities, control enum codecs and the matching routes. The runtime does not need source modules or compiler applications.

Attach `hls_domain_fabric` to two deployment-owned `hls_fabric` brokers and that interface, with external output recipients keyed by `{ActorId, Port}`. Configure the domain owner with `module => hls_domain_fabric`; its policies, incarnation counter, supervisor child and `hls_node` service declaration are otherwise the same as for `hls_domain_erts`. The generated interface fixes the routes; incompatible host overrides reject before route acquisition. The backend does not close brokers owned by its deployment.

Each addressed host request selects one actor. Ordinary source calls reuse the compiler's bounded caller/reply machinery. Each declared reply port must have one external destination; internal calls, call-tag startup messages and dynamic internal reply routes reject. A reply keeps its caller identity while publication is blocked. Casts retain their ordinary zero transaction field; only the outer request envelope uses the no-call-slot sentinel.

Hardware owns incarnation admission, bounded request-to-call-slot correlation and the output sequence. Each receive/transmit direction retains one finite packet. A round-robin arbiter skips empty sources and advances only when it captures an application input or output; management has its own parser and response buffer. Persistent eligible sources share accepted transfers fairly, but receiver stalls can take arbitrarily long. One physical application stream still serializes packets: a blocked transmitter prevents new command admission, and a blocked receive head prevents later input packets from passing it. There is no retry history or transparent application replay. The 32-bit request and output counters do not wrap; exhaustion closes further admission instead of reusing an identity.

Host admission is bounded per actor. `pending_limit` bounds unacknowledged casts for each actor; its declared `pending_calls` separately bounds retained calls. A long call therefore does not consume the room needed for a release cast or another actor's request. Hardware and native endpoints implement the same admission notification and capacity-wait contract. The distribution bridge releases input credit on admission, retains bounded completion ownership per actor, and preserves sender order for operations awaiting admission. Only an explicitly unadmitted busy cast can wait and try admission again; uncertain writes and accepted operations are never replayed. Shared finite links and full ingress queues can still impose head-of-line blocking.

Management observations include the count of application outputs accepted by the generated transport. Those buffers and counters survive ordinary domain replacement. On source failure, the host backend waits for that frontier, sends prior replies and effects through the incarnation endpoint, and then retires it. The same endpoint sends effects to their recipient before its `DOWN` signal. A successor is not exposed while predecessor delivery or endpoint retirement remains pending. A missing frontier, malformed response, broker loss or cold-device identity regression produces `noconnection`, not evidence of a completed reset.

Connection loss does not reset the actor network or fault its lifecycle. By default, owner loss also preserves actors and revokes only that owner's authority; `owner_loss => fail` explicitly selects retirement instead. A backend failure terminates its disposable host proxies with `noconnection`. Accepted work may still finish. Existing monitors remain terminal, and interrupted calls are never transparently resumed or replayed.

To reconnect, the deployment must:

1. Stop the old brokers and isolate their physical paths. Confirm actual descriptor closure and prevent buffered old bytes from reaching a new parser. A host process `DOWN` alone does not establish this.
2. Drive a fresh, strictly greater nonzero `transport_session` and pulse `transport_reset`. Wait for `transport_attached` with matching `transport_session_observed`. These pins reset packet buffers, correlation counters and observers, while preserving actor/network state, lifecycle and incarnation. Cold `reset` remains a separate full reset. An equal session is idempotent; zero or a lower session cannot establish a connection.
3. Open independent fresh brokers and start `hls_domain_fabric` with `#{management => M, application => A, session => Session}`. Every payload begins with that 64-bit session; complete old-session packets are discarded before admission or sequence accounting. The deployment must not reuse sessions across cold resets unless all old transport paths have been irreversibly isolated. This identity check is not authentication. The deployment must bind the new backend to the same physical domain and matching emitted interface; a matching numeric incarnation alone cannot identify a different device.
4. Call `hls_domain:reattach(Owner, Handle, FreshBackend)` and, for a surviving virtual node, `hls_node:reattach_domain(Node, Service)`. Both check the same incarnation; the node retains its existing virtual PIDs. A different incarnation requires replacement and new PIDs. Callers establish fresh monitors and decide what new work to issue.

A partial packet cannot safely carry its own reset command, hence the separate sideband boundary. A disconnected call's hardware slot remains occupied until its actual source reply arrives; that abandoned reply is discarded and the slot then becomes reusable. A call that never replies can retain its bounded slot indefinitely. Casts and independent actors can still progress; selecting domain replacement is application policy, not automatic transport cleanup. Fresh host calls rotate slot choices after explicit pre-admission rejection; this never retries accepted or uncertain work. Effects emitted after reattachment may arise from work admitted before the disconnect.

This is a generated stream and host-runtime contract. Its finite simulations do not establish live-device admission, failure detection deadlines or physical reset isolation.

The maintained shared-application witness is:

```sh
rebar3 as test compile
python3 tools/test_domain_stream.py --xls /path/to/xls --work /fresh/artifact/directory
```

It runs the same profile actuator, host policy, ordinary OTP supervisor and surviving device model on ERTS and on two independent generated cores. Both use the custom distribution node and a real second ERTS node for typed calls, casts, monitors and fresh virtual PIDs. The C++ simulator moves public word beats only; it neither interprets recovery commands nor manufactures replies, acknowledgements or frontiers. Native and RTL histories are checked against explicit application expectations. Device effect history and resource reservations live in the application-side model and deliberately survive controller replacement.

The transport replacement witness uses the same generated actuator core:

```sh
python3 tools/test_domain_stream.py --scenario reattach --xls /path/to/xls --work /fresh/artifact/directory
```

It withholds an actual reply, kills the host backend, checks remote call/monitor uncertainty and independent-domain progress, rotates the FIFO descriptors, and establishes a new session through sampled public RTL pins. It checks preserved state/incarnation/virtual PID, stale-session rejection, fresh monitoring and subsequent actual source failure. An incomplete old packet is checked against accepted-word traces; focused DSLX tests separately exercise abandoned calls whose source reply has not yet arrived. These are bounded witnesses, not exhaustive native/RTL equivalence.

The shutdown scenario runs the same three-domain application on ERTS and generated RTL through a real distribution peer:

```sh
python3 tools/test_domain_stream.py --scenario shutdown --xls /path/to/xls --work /fresh/artifact/directory
```

It exercises healthy child termination, `one_for_all`, `rest_for_one`, fresh identities, duplicate/stale stop requests and an unaffected third domain. An additional RTL schedule withholds already-produced output and requires the earlier reply before orderly shutdown becomes visible. These are finite histories; asynchronous child readiness and physical reset completion remain separate contracts.

## Focused local witness

After compiling the test profile with the matching compiler checkout, run:

```sh
python3 tools/test_domain_recovery.py /path/to/xls /fresh/artifact/directory
```

The witness compiles two ordinary source actors, counter then relay, into a complete network; two independent instances communicate with actual Erlang owners and incarnation-specific actor endpoints through separate management/application FIFO pairs. A second build makes initial source entry fail. Test-only stale-wire injections are labeled separately from actual source-generated responses. The simulator touches only public clock, management, ingress and egress ports, and never forces internal actor state.

The fixture transport sequences application responses and puts the accepted-response frontier in each management snapshot. A fault closes admission immediately, but orderly endpoint termination waits until every promised prior response reaches the adapter. The endpoint processes those replies before its in-band retirement message. Missing, malformed or timed-out delivery evidence yields connection uncertainty instead of an invented orderly source failure. A deterministic witness stalls delivery after hardware acceptance, observes the fault independently, then checks the reply precedes `DOWN` when delivery resumes. This older witness puts the frontier in its fixture adapter; `write_stream/2` above implements that responsibility in generated hardware.

This is finite simulation evidence. It establishes neither arbitrary progress nor board admission, physical timing or exhaustive source/RTL equivalence. The controller retains one lifecycle transition and first fault, not an application work history. Local test generation and simulation are serialized; neither Vivado nor a whole-application performance sweep is needed for this contract witness.

The fixture implements requests as source-level request-ID/cast/report messages. It predates the bounded host-call support used by the framed endpoint above. Its stale acknowledgement case covers application admission; it is not an exhaustive proof of private credit handling.

The compiled kernel can also be checked independently:

```sh
python3 tools/test_domain_formal.py /path/to/xls /emitted/source/bundle /fresh/formal/evidence
```

The checker consumes an already emitted source bundle. It checks exact command framing, admission consistency, preservation of state on stale requests and unused control encodings, first-fault closure, completion requirements for readiness, and stopped-state exclusion of implicit replacement over every finite input/state encoding, plus all eight-command histories from cold state. An intentionally incorrect admission rule must produce a counterexample. These results trust the compiler, XLS and SAT toolchain; they verify controller decisions under the meanings assigned to backend completion signals, not the physical fence or reset wiring. See the compiler's evidence labels when reporting a run.

## Device-specific recovery policy

The generic profile fixture in `test/hls_recovery_profile_tests.erl` separates a finite actuator from its host policy. It has eight capability bits, two predeclared profiles, configuration epochs and one pending transition. Tests distinguish applied digital configuration from an unavailable logical result, keep reservations across controller replacement, and allow a selected branch to ignore an unused failed input. These are interface witnesses; a device library must supply real profiles, resource ownership rules and the meaning of a usable result. Neither compiler nor bridge interprets that meaning.
