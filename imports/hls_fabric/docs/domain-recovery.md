# Source-protocol recovery domains

`hls_protocol_domain:write/2` compiles one complete source-protocol network behind an incarnation boundary. It takes the ordinary network configuration and writes a portable source bundle for the existing external XLS driver. A domain is the fixed group of actors, private links, pending publications and host ingress that are reset together; a domain incarnation is one lifetime of that group. Separate emitted core instances have independent lifecycle and network state.

The control transition is the Erlang `hls_domain_lifecycle` kernel, compiled through its own small service adapter. The wrapper supplies physical observations: it acknowledges fencing only after the external ingress and egress gates close, acknowledges reset on the edge that resets every network component, and acknowledges initialization only after all source receivers have completed entry/internal callbacks successfully. `startup_done` alone is insufficient for readiness.

Erlang represents lifecycle commands, phases, dispositions, actions and causes as atom unions. The composer resolves their record fields through the ordinary `hls_type` machinery, retains the resulting codecs in `domain/interface.etf`, and generates `domain/domain_codes.x` and the port widths from those descriptors. A host transport packs and unpacks these atoms with the retained codecs; it needs neither compiler source nor a separately maintained numeric table. Numeric source-site failure codes remain a separate diagnostic field. Atom declaration order defines the wire encoding, so a bridge must use the interface from its matching hardware bundle.

Management and application traffic are separate interfaces. Only management requests, inspection, abort and an explicit owner-disconnect indication enter from the backend; physical completion opcodes are internal. The owner supplies non-reused 64-bit incarnation and transition identities. Application envelopes carry an incarnation; a stale or unready envelope is rejected without reaching the actor inbox. Outbound records carry the current incarnation at their acceptance boundary. Neither a replacement nor its fence revokes an output that an external consumer already accepted.

The first boundary supports a closed whole-network placement, rectangle ingress, automatic internal execution, no declared startup messages and silent initialization. A source initializer/entry failure closes admission. An initialization publication attempt also fails closed; it is not released to the application. Source failures retain actor index and full finite failure code separately from the domain cause. The generated control adapter currently requires ten frame payload words, so the builder selects at least that capacity. This is an internal composition constraint, not a promise that every deployment frame is ten words.

The backend must connect every application ingress and egress through the gates and keep management available independently of application backpressure. A dead physical backend does not establish a successful fence or reset; its owner must retain uncertainty. No distributed reset protocol or crossing-link ownership policy is implied by this single-clock composition.

## Mailboxes between reset domains

`hls_protocol_domains:emit/2` splits one source topology into independently resettable partitions and inserts an incarnation-bound channel at every directed cut. `write/3` writes the same composition as a portable XLS bundle. For the repository's three-actor fixture, run from the repository root with the test modules available:

```erlang
Source = #{
    sources => [{"test/hls_cross_domain_producer.erl", []},
                {"test/hls_cross_domain_consumer.erl", []},
                {"test/hls_domain_counter.erl", []}],
    topology => {hls_cross_domain_producer, topology, []},
    actor_limit => 3,
    control => rectangle
},
Placement = #{
    domains => [{a, [0]}, {b, [1]}, {c, [2]}],
    restart_groups => [[a, b], [c]]
},
#{files := Files, result := Interface} = hls_protocol_domains:emit(Source, Placement),
Bundle = hls_protocol_domains:write(Source, Placement, "build/cross-domain").
```

Actor indices follow the source topology. The builder prepares one source snapshot and invokes its trusted topology constructor once; all partitions render from that retained program. Domains must cover every actor exactly once; restart groups must partition domain IDs, and every crossing must stay within one group. The example routes A to B while C remains independent. The source constraints remain automatic execution, rectangle ingress, silent initialization and no declared startup messages. The channel controller raises the shared frame capacity to at least twenty payload words. The result retains domain membership, crossing schemas, enum codecs and pin widths; each `domain_N/domain/interface.etf` describes its local boundary. The RTL top is `protocol_domains`.

A **domain incarnation** identifies an actor group's lifetime. A separate **channel generation** identifies one binding of two exact endpoint incarnations, and a packet sequence identifies the single retained packet within that binding. Binding requires both endpoints to be ready and both incarnation IDs to exceed those retained from the previous binding. Replacing only B cannot reconnect A: A's old, unversioned publication could otherwise be relabelled as work for the new B. Recovery must retire and replace both members of this dependency group before binding again. A group declaration checks that policy's static scope; it does not instantiate a supervisor, issue resets or retry work. The deployment coordinates lifecycle commands and exact-generation `ch_N_bind_request`/`ch_N_fence` requests. This is mailbox ownership, not Erlang `link/1` signaling.

The public `domain_N_` pins retain each domain's lifecycle, host ingress and external effects. Raw peer pins are private to the composer. Each `ch_N_` interface exposes outgoing data (`tx_valid`, `tx_generation`, `tx_sequence`, `tx_slot`, `tx_frame`), incoming data and readiness, outgoing acknowledgements, returned credits, and management/status. `generation` and `packet_sequence` report current channel ownership; packet lanes retain their own `tx_sequence`, `data_sequence`, `ack_sequence` and `credit_sequence` fields. The external transport preserves metadata and payload together and holds each offer stable until its ready/valid handshake. One source publication occupies the channel until the destination's actual capture accepts it, its acknowledgement is sent and its exact credit returns. Capture acceptance is not completion of the destination callback. Stale, duplicate and premature data/credits cannot grant a destination delivery or release current credit; an abandoned packet is not replayed. These checks assume payload integrity: matching tags cannot detect corrupted or forged current payloads.

Channel state lives outside the endpoint reset regions. Either endpoint losing readiness or changing incarnation closes the binding; explicit fencing has the same admission priority. `domain_N_reset` also closes that endpoint's channel handshakes on the reset edge. Global `reset` reaches every domain and channel, clearing channel tombstones, so cold reset requires the deployment to exclude the former transport namespace before admission. No delay or timeout establishes that exclusion. All interfaces use one clock; this builder supplies neither clock-domain crossing nor physical reset isolation.

`hls_protocol_domain:emit_partition/1` and `write_partition/2` are the lower-level escape hatch for another checked crossing owner. They require explicit `native_actors` and an external owner that excludes old data and credits; connecting their bare wires does not support independent reset. The single-domain entry points continue to reject partition selection. The checked multi-domain builder supplies the [framed composition](#framed-crossing-management) below.

The raw native test uses real source actors under an ordinary OTP `one_for_all` supervisor for A/B, with independent C. Its generated-RTL counterpart drives the public lifecycle and transport pins directly, including delayed old packets and credits. Those checks witness source behavior and hardware ownership; exercising host supervision through the framed bridge is a separate integration check. Neither establishes board operation, physical timing or unrestricted progress.

Run the finite native/public-pin witness and the separate compiled-channel checks locally:

```sh
rebar3 as test compile
python3 tools/test_cross_domain_mailboxes.py /path/to/xls /fresh/mailbox-evidence
python3 tools/test_domain_channel_formal.py /path/to/xls /fresh/mailbox-evidence/build/source /fresh/channel-evidence --yosys /path/to/yosys
```

The RTL schedule retains old data across replacement, replays old data and credits against a fresh packet with the same sequence number, stalls acknowledgements while C advances, and checks same-edge endpoint reset. The channel checker runs six finite schedules, two single-edge finite-state propositions and a rejecting stale-generation negative control. The state-budget check measures source/optimized-IR storage; it does not infer mapped area or timing.

### Framed crossing management

`hls_protocol_domains:write_stream(Source, Placement, Directory)` uses the same placement and channel kernel, adding independent management/application streams around each domain and one shared management stream for the declared channels. `emit_stream/2` returns these generated files without writing them. The top is `protocol_domains_stream`. Each `domain_N/domain/interface.etf` supplies its own `hls_domain_fabric` interface; `channel_management/interface.etf` supplies the channel adapter. Application payloads and returned credits still use the crossing's separate ready/valid lanes. They never travel through the channel-management parser or a host management process.

Establish each domain's transport session and the independent channel-management session before attaching brokers. `hls_domain_channel_fabric:start_link(#{management => Broker, session => Session}, Interface, Options)` registers the latter route. It has one receive/transmit exchange and a bounded queue, with a separate owner capability for each declared channel. The stream accepts only inspection, exact-pair binding and exact-generation fencing. A successful bind acknowledges channel ownership, not execution or completion of a source callback. The optional `name => crossing_control` registers an ordinary local OTP name suitable for a supervisor child specification that must survive replacement of this adapter.

An ordinary host OTP supervisor coordinates the dependent restart group. Keep domain owners, transport brokers and the channel backend outside that subtree. Put the supervised domain representatives before their channel worker in startup order; OTP then stops the channel worker first during subtree shutdown. For the A/B example, a supervisor callback can return:

```erlang
init({OwnerA, OwnerB, ChannelIndex}) ->
    Domains = [
        #{id => Id,
          start => {hls_domain_instance, start_link,
                    [Owner, Id, #{lifetime => supervised}]},
          restart => permanent, shutdown => 5000, type => worker}
        || {Id, Owner} <- [{a, OwnerA}, {b, OwnerB}]
    ],
    Channel = #{id => crossing,
        start => {hls_domain_channel_instance, start_link,
                  [crossing_control, ChannelIndex, {OwnerA, a}, {OwnerB, b}, #{}]},
        restart => permanent, shutdown => 5000, type => worker},
    {ok, {#{strategy => one_for_all, intensity => 3, period => 60},
          Domains ++ [Channel]}}.
```

Child startup is asynchronous: a successful `start_link` is not domain or channel readiness. `hls_domain_channel_instance:status/1` reports `phase => ready` only after the device confirms an active binding of the two observed ready incarnations. The worker resolves its adapter name at startup and pins that exact process; it does not automatically follow later registration changes. It observes domain owners and manages the binding, neither forwarding application messages nor replacing actors itself. Actual member failure terminates its supervised representative, and OTP's `one_for_all` policy retires and replaces the dependent group. Unrelated C belongs outside this subtree. A placement's `restart_groups` field checks static membership; it does not construct this supervisor or enforce the deployment's chosen OTP declaration.

A timed-out binding request has an unknown outcome. The worker retains the requested pair and inspects the channel to determine whether that binding exists. If ordered evidence proves the prior inactive binding is unchanged, it may retry that exact management request once after fresh owner observations; a second uncertain attempt stays unavailable. A timeout alone never authorizes another actor incarnation or application replay. Owner death revokes channel authority and leaves a fencing obligation in the surviving channel backend. A successor cannot acquire the channel while that obligation is unresolved. Fencing cancels retained crossing ownership without waiting for a failed peer's credit; it does not retract a destination effect or waive either domain backend's promised-output retirement frontier.

Transport replacement remains separate from actor replacement. A fresh channel-management session clears only its framing state; it preserves channel generation, endpoint bindings and retained data/credit ownership. Domain session replacement likewise preserves actors and their incarnations. After isolating the old transport, explicitly reattach the surviving channel worker to a fresh backend and reconcile the observed binding. A lost connection is not permission to restart healthy actors, silently adopt a changed pair or replay application work. Cold reset, session non-reuse, correct physical-device identity and exclusion of old transport paths retain the [deployment obligations](#framed-hardware-backend) below.

This composition is host-managed and single-clock. The separately generated FPGA supervisor supports its documented closed-child composition; the two builders do not imply arbitrary combinations of local supervision and crossing topology. Physical reset isolation, clock-domain crossing and live-device qualification remain separate work.

### Independently clocked endpoints

The common-clock channel has one controller for both ends. A physical board crossing instead uses `hls_domain_channel_tx` and `hls_domain_channel_rx`, compiled from their Erlang kernels by `hls_domain_endpoint_build`. Each endpoint sees only its local domain's readiness and incarnation. There is no asynchronous wire that samples the other board's lifecycle.

One binding contains a deployment namespace, a generation, and both domain incarnations. The transmitter retains one accepted publication until its exact acknowledgment arrives; the receiver acknowledges only after native destination capture. Packet identity includes the complete binding and a nonwrapping sequence. Well-formed stale packets drain without affecting a new binding. Invalid current traffic fails closed. Neither endpoint stores a retry history or replays an application operation.

Place one `hls_domain_endpoint_pair` child per directed crossing after both domain-instance children under an ordinary `one_for_all` supervisor. Management adapters and deployment owners outlive that subtree. The worker retires old endpoint ownership, requires both current domain incarnations to exceed both endpoints' retained histories, chooses a generation above both retained generations, and confirms RX before admitting TX. Generation gaps are necessary when a previous attempt reached RX but not TX. A lost mutation reply triggers ordered inspection; one exact management retry is allowed only when that inspection establishes the unchanged pre-state. This is not permission to retry application work.

The worker carries only management requests. Its `status/1` is a last-observed readiness record, not a continuously true guarantee about a remote peer. Failed ordered reads quarantine that transport for the worker's lifetime and fence the reachable peer. Recovery requires explicit deployment reconciliation and a fresh supervised worker; a replacement registered process is not silently adopted. Surviving adapters fence a dead worker's owned endpoints independently.

`hls_domain_endpoint_role` mechanically connects a source partition to its local endpoints. `hls_domain_endpoint_packets` uses the retained source crossing classes to validate and route complete packets, and `hls_domain_endpoints_stream` supplies metadata-only host management. `hls_domain_endpoint_network` joins these components without adding state. Its physical carrier/router fault input reaches the domain's native failure transition, preserving incarnation and fault history while leaving host management available. A host parser/session fault remains a connection failure and does not become an actor-network failure.

Cold reset is a separate deployment boundary: it forgets endpoint identity history. The deployment must exclude the old namespace before admitting a fresh one. Domain replacement and host-session changes must not reset endpoints or the carrier. The current physical packet emitter supports twenty application payload words, carries all identity fields, and requires a bounded atomic packet carrier; the board-specific carrier owns its clock crossings and integrity checks. Finite kernel and RTL witnesses establish only their tested histories, not physical CDC safety or unbounded distributed progress.

### Casting to a rectangle

A framed endpoint also accepts `hls_domain_fabric:cast_rectangle(Endpoint, {X0,Y0,X1,Y1}, Message)`. The endpoint identifies the incarnation and the ingress target used by this cast tag. The rectangle can include other actors and can exclude the submitting endpoint. The compiler enables this operation only when all recipients of the target accept that record as a cast. The emitted address gives the target's width and height. Both the encoder and hardware check inclusive bounds. Existing point commands retain their encoding.

Each request consumes one cast credit at the submitting endpoint. `hls_domain_fabric:cast_rectangle(Endpoint, Bounds, Message, admitted)` acknowledges capture in the shared ingress register. The three-argument form selects this mode. With `consumed`, the same cast returns one `ok` after the last selected inbox commits its take. An empty selection has no takes to await. The bridge retains the request identity in its existing input packet and one waiting bit. A later continuation, publication, or readout can still be pending. A router can use `rectangle_request/3` with OTP request IDs to keep serving other senders while collecting the receipt.

A held inbox selection keeps its reservation. Fresh eligible host and actor heads compete by rotating priority after sender-local ordering. An actor that postpones the broadcast keeps its pending bit even while peers finish. Put every prerequisite on the ingress before the dependent broadcast, or arrange an independent actor or management path that can make progress. Keep draining external outputs while waiting. A late host release behind a postponed broadcast on the same port creates a circular wait that fair arbitration cannot resolve. Timeout, disconnect or retirement can leave a partially consumed rectangle. Replay requires application-level recovery.

Each receipt belongs to one managed domain and incarnation. The [partition stream](source-protocol.md) already fans global rectangle commands out to device roles in order. A distributed consumption fence would need a correlated receipt from each selected role and a failure outcome when any role is lost after partial delivery.

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

The callback must return `one_for_one`, an intensity from zero through sixteen, a positive 32-bit period in seconds, and `auto_shutdown => never` when supplied. Each child must be a permanent or temporary worker whose start function is `hls_domain_instance:start_link/3` with `#{lifetime => supervised}` and the same domain name as its child ID. Brutal-kill shutdown and unsupported strategies or child kinds reject during elaboration. The deployment-owner argument is a placeholder at build time and an actual owner PID in the native declaration. The `children` map supplies exactly the networks named by that declaration and any explicit temporary templates; it does not select application recovery meaning.

The compiled Erlang supervisor policy lives outside its children's reset regions. It alone issues their lifecycle commands; host requests address the parent boundary rather than competing with it for child ownership. Child source faults close that child's admission independently. Management visits one child per edge, while the other networks and their independent application interfaces continue advancing. This serializes bounded recovery decisions, not ordinary actor messages.

Restart intensity counts replacement attempts within the declared sliding window, excluding initial startup and explicit temporary-child admission. The generated local divider produces whole-second ticks from `clock_hz`; disconnected or stalled host management does not stop that clock. The deployment must supply the declared hardware frequency. This is neither a physical timing measurement nor an externally synchronized clock. Exhausted restart intensity, initial-start identity allocation or permanent-replacement identity allocation closes the subtree and retires its children before reporting terminal parent failure. An unrelated domain outside that subtree is unaffected.

The parent uses the existing domain lifecycle interface. Its initialization remains pending until an identity grant is accepted and every initially declared child is ready and every dormant template has been registered. An orderly parent stop disables local recovery, retires its children and waits for hardware fence completion. Each child's host backend drains its independently accepted output and retires its host endpoints separately; return from parent stop does not establish delivery on every child connection. Consumers needing that boundary wait for the child monitors or observed child endpoint retirement. Existing lifecycle rules still apply to an already accepted initialization or replacement: stop cannot erase its reserved transition, and a busy response or timeout is not cancellation. Host connection loss alone neither stops the subtree nor resets healthy children. A host supervisor can control this parent through a backend adapter without occupying the local child-recovery path.

### Delegated identities

Before autonomous operation, the deployment durably reserves a finite, non-reused incarnation interval and presents `grant_valid`, `grant_epoch`, `grant_first` and `grant_last` through the public pins. The epoch must match the initializing parent's incarnation; the interval must lie above the controller's retained allocation high-water mark, and its inclusive upper bound must be below the largest 64-bit value. The supervisor consumes a fresh identity before each initial start or replacement; exhausted space fails closed instead of wrapping.

An exact repeated grant observes the same allocation and cannot rewind its cursor. Parent replacement resets child and supervisor execution state while retaining the allocation high-water mark, so a new parent incarnation needs a new interval. Full hardware reset loses that state. The deployment must then establish old-traffic exclusion and supply a fresh durably reserved interval; replaying an old grant is not recovery from lost allocation state. These grants retain no application work history.

### Framed parent and child publication

`hls_protocol_supervisor:write/2` retains the raw-pin composition. `hls_protocol_supervisor:write_stream(Config, Directory)` emits parent management/grant framing and separate management/application streams for each child. Compile that portable bundle with the usual external XLS driver. The enclosing `interface.etf` contains the parent interface; each `child_N/domain/interface.etf` contains that child's retained actor schemas and marks its supervision as local.

Use `hls_supervisor_fabric:start_link/3` for the parent, with one deployment-owned management broker, an established nonzero transport session and an already durably reserved `grant => {First, Last}`. An ordinary `hls_domain` owner and host OTP representative control the parent through that backend. The adapter submits the grant for the initializing parent incarnation; it neither allocates identities nor retries uncertain writes. Each child uses the existing `hls_domain_fabric` backend with its own management/application brokers. No child application packet passes through the parent adapter. Child backend attachments grant observation and application access only: lifecycle requests and `owner_loss => fail` reject because the compiled supervisor owns recovery.

A child backend first asks hardware to watch one exact ready incarnation. Until that acknowledgement is observed, it returns `publication_pending` rather than exposing new endpoints. Independent application delivery may precede the management acknowledgement: the backend retains at most one broker-owned effect frame and withholds its delivery acknowledgement until the matching endpoint exists. Keep the application broker’s per-route receipt limit at its default of one; additional delivery before acknowledgement exceeds this boundary and closes with uncertainty. A missing watch response times out with connection uncertainty. If the watched lifetime already ended, private closing endpoints deliver its promised effects and retire without publishing a dead lifetime as ready. Hardware retains the watched identity and, when it departs, one immutable record containing its terminal cause, source actor and final accepted-output frontier. That record survives later child restarts and parent-owned child resets. The local supervisor can continue replacing permanent children while host output is stalled; it does not wait for publication or retain an application work history.

The backend drains the watched lifetime's promised outputs, sends its terminal notification through those same endpoints and waits for their actual process deaths. It then acknowledges that exact retirement record. Only afterward can it watch the latest ready incarnation and expose its endpoints. `hls_node:publish_domain/2` allocates fresh virtual PIDs after the distribution connections acknowledge predecessor retirement. Intermediate incarnations which were never watched are not published retroactively, and their failure histories are not reconstructed. A missing or changed record yields `noconnection`, never an invented orderly failure. A parent-owned reset can temporarily expose an unbound child; the backend retains the greatest observed identity and rejects reuse after that reset. A raw child which still reports its old ready state during parent closure cannot regain a watch after that incarnation was retired.

Transport loss terminates old endpoint monitors with `noconnection`. A fresh session discards the previous session's observation record and framing state, preserving the independently running child. Establish that session using the [deployment exclusion procedure](#framed-hardware-backend), then read the fresh backend's authoritative current incarnation before choosing whether to resume observation:

- If it still equals the previous handle, call `hls_domain:reattach(Owner, Handle, FreshBackend)`, wait for watched readiness and use `hls_node:reattach_domain/2` to preserve the surviving virtual PIDs.
- If it is newer and the application accepts that new lifetime, supply the independently observed exact handle to `hls_domain:reattach(Owner, {Domain, Candidate}, FreshBackend)`. This binds observation; it does not request replacement. After watched readiness, call `hls_node:publish_domain/2` for fresh PIDs. Never reattach the old virtual PID to the new incarnation.

`reattach/3` checks the supplied exact incarnation both before and after attachment and refuses a still-live old backend. A changed candidate returns `incarnation_not_ready`; an unsuccessful final confirmation can leave the new binding installed, so inspect owner status to reconcile it. In particular, `publication_pending` means attachment succeeded while its watch handshake is unfinished: wait on owner status for the exact ready handle instead of repeating attachment. These checks do not establish physical device identity: the deployment must bind the candidate to the same child and matching interface. Old monitors remain terminal in both cases. Callers establish fresh monitors and choose new work; accepted or uncertain operations are never replayed.

### Bounded temporary children

`restart => temporary` has its ordinary OTP meaning: a child declared by `supervisor:init/1` starts during initial startup and is never automatically restarted. To reserve initially empty capacity, supply an additional `templates => [ChildSpec, ...]` in the build configuration. Every template must be a temporary domain child of the same supported shape; IDs across initial children and templates must be unique and exactly match `children` bindings. Empty initial declarations are allowed when templates reserve at least one slot. A native program passes these ordinary templates to `supervisor:start_child/2` when it needs an occupant. Hardware retains the compiled template after the occupant retires; OTP removes the terminated temporary child specification.

Resolve the parent’s `supervisor` endpoint through the existing owner, then use its incarnation-bound management API:

```erlang
{ok, Supervisor} = hls_domain:resolve(ParentOwner, ParentHandle, supervisor),
{ok, #{phase := vacant, incarnation := Previous}} =
    hls_supervisor_fabric:child_status(Supervisor, Slot),
{ok, #{incarnation := New}} =
    hls_supervisor_fabric:start_child(Supervisor, Slot, Previous).
```

An accepted start reserves exactly `New`; it does not promise successful initialization or endpoint publication. Observe the child owner until that exact incarnation is ready before sending work. A fixed slot which is occupied or retiring returns `busy`; unknown slots reject. Concurrent starts cannot share one admission. Starting an empty slot requires its last-occupant identity (zero before first use), so an old request cannot start a later vacancy. If the finite grant is exhausted, optional admission returns `exhausted` and existing occupants continue. No failed or uncertain operation is automatically retried; after an unknown result, inspect the slot and reconcile it with application policy.

After the application completes its work, call `hls_supervisor_fabric:terminate_child(Supervisor, Slot, New)`. Its acceptance is retirement intent. A source fault also retires a temporary occupant, without automatic replacement or restart-intensity accounting. The source callback language currently has no normal-exit directive; explicit termination represents completion here. Initial startup failure still closes the initial subtree; failure of a later explicit admission does not create another attempt.

A slot becomes `vacant` only after the child controller establishes retirement and its transport has acknowledged the old incarnation’s output frontier and endpoint termination. An old output held by the host therefore blocks reuse of that slot, while other occupied slots continue. Old identities remain invalid after reuse. A raw-pin deployment must supply the corresponding `child_N_observed_reusable` evidence; elapsed time or a dead host proxy is insufficient. A failed pre-reset initialization whose old lifetime has not been fenced remains unavailable, rather than reporting a false vacancy. Parent shutdown preserves and retires already accepted starts. One autonomous scan turn follows each accepted targeted mutation, so continuous raw control cannot starve retirement or permanent-child recovery.

Only management requests pass through the parent. Application packets, reply ownership and retirement records remain per child. The framed parent retains one in-flight exchange and eight waiting requests; its endpoint stays responsive to parent retirement during outstanding requests. Parent connection loss yields uncertainty and never resets the autonomous supervisor. Possession of the resolved supervisor endpoint grants access to these operations, like possession of an ordinary OTP supervisor PID; a stale endpoint cannot control its successor.

### Limits and evidence

The native reference uses ordinary OTP supervision over actual source domains. Generated public-pin witnesses compare finite application and lifecycle outcomes; they do not equate ERTS scheduling with hardware clock counts or establish physical reset isolation. FPGA-to-host supervision remains follow-on work. Temporary admission instantiates a logical lifetime in existing circuitry; it does not allocate circuitry or select arbitrary runtime initialization arguments.

## Framed hardware backend

`hls_protocol_domain:write_stream(Config, Directory)` emits the same closed network behind two independently backpressured word streams. Compile its source bundle with the ordinary external XLS driver. The selected top is `domain_stream`, with separate management and application input/output channels. Each channel carries the existing route/header/payload words. `domain/interface.etf` retains actor schemas, call contracts, port identities, control enum codecs and the matching routes. The runtime does not need source modules or compiler applications.

Attach `hls_domain_fabric` to two deployment-owned `hls_fabric` brokers and that interface, with external output recipients keyed by `{ActorId, Port}`. Configure the domain owner with `module => hls_domain_fabric`; its policies, incarnation counter, supervisor child and `hls_node` service declaration are otherwise the same as for `hls_domain_erts`. The generated interface fixes the routes; incompatible host overrides reject before route acquisition. The backend does not close brokers owned by its deployment.

Point requests select one actor. Rectangle casts select all matching members of their declared target. Ordinary source calls reuse the compiler's bounded caller/reply machinery. Each declared reply port must have one external destination; internal calls, call-tag startup messages and dynamic internal reply routes reject. A reply keeps its caller identity while publication is blocked. Casts retain their ordinary zero transaction field; only the outer request envelope uses the no-call-slot sentinel.

Hardware owns incarnation admission, bounded request-to-call-slot correlation and the output sequence. Each receive/transmit direction retains one finite packet. A round-robin arbiter skips empty sources and advances only when it captures an application input or output; management has its own parser and response buffer. Persistent eligible sources share accepted transfers fairly, but receiver stalls can take arbitrarily long. One physical application stream still serializes packets: a blocked transmitter prevents new command admission, and a blocked receive head prevents later input packets from passing it. There is no retry history or transparent application replay. The 32-bit request and output counters do not wrap; exhaustion closes further admission instead of reusing an identity.

Host admission is bounded per actor. `pending_limit` bounds unacknowledged casts for each actor; its declared `pending_calls` separately bounds retained calls. A long call therefore does not consume the room needed for a release cast or another actor's request. Hardware and native endpoints implement the same admission notification and capacity-wait contract. The distribution bridge releases input credit on admission, retains bounded completion ownership per actor, and preserves sender order for operations awaiting admission. Only an explicitly unadmitted busy cast can wait and try admission again; uncertain writes and accepted operations are never replayed. Shared finite links and full ingress queues can still impose head-of-line blocking.

Management observations include the count of application outputs accepted by the generated transport. Those buffers and counters survive ordinary domain replacement. On source failure, the host backend waits for that frontier, sends prior replies and effects through the incarnation endpoint, and then retires it. The same endpoint sends effects to their recipient before its `DOWN` signal. A successor is not exposed while predecessor delivery or endpoint retirement remains pending. A missing frontier, malformed response, broker loss or cold-device identity regression produces `noconnection`, not evidence of a completed reset.

Connection loss does not reset the actor network or fault its lifecycle. By default, owner loss also preserves actors and revokes only that owner's authority; `owner_loss => fail` explicitly selects retirement instead. A backend failure terminates its disposable host proxies with `noconnection`. Accepted work may still finish. Existing monitors remain terminal, and interrupted calls are never transparently resumed or replayed.

To reconnect, the deployment must:

1. Stop the old brokers and isolate their physical paths. Confirm actual descriptor closure and prevent buffered old bytes from reaching a new parser. A host process `DOWN` alone does not establish this.
2. Drive a fresh, strictly greater nonzero `transport_session` and pulse `transport_reset`. Wait for `transport_attached` with matching `transport_session_observed`. These pins reset packet buffers, correlation counters and observers, while preserving actor/network state, lifecycle and incarnation. Cold `reset` remains a separate full reset. An equal session is idempotent; zero or a lower session cannot establish a connection.
3. Open independent fresh brokers and start `hls_domain_fabric` with `#{management => M, application => A, session => Session}`. Every payload begins with that 64-bit session; complete old-session packets are discarded before admission or sequence accounting. The deployment must not reuse sessions across cold resets unless all old transport paths have been irreversibly isolated. This identity check is not authentication. The deployment must bind the new backend to the same physical domain and matching emitted interface; a matching numeric incarnation alone cannot identify a different device.
4. For an unchanged incarnation, call `hls_domain:reattach(Owner, Handle, FreshBackend)` and, for a surviving virtual node, `hls_node:reattach_domain(Node, Service)`. Both check the same incarnation; the node retains its existing virtual PIDs. A different incarnation requires an explicit application decision and fresh PIDs, using the [autonomous-child publication flow](#framed-parent-and-child-publication) when local supervision already replaced it. Callers establish fresh monitors and decide what new work to issue.

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

The autonomous-supervisor witness exercises the production parent and child adapters together:

```sh
rebar3 as test compile
python3 tools/test_supervisor_stream.py --xls /path/to/xls --stage /fresh/artifact/directory
```

An ordinary host OTP parent controls a generated FPGA supervisor and two independently resettable source actors. A real ERTS peer uses the published child PIDs. The witness compares native replacement histories, holds an accepted reply while local restart finishes, requires that reply before the old PID's `DOWN`, and checks sibling progress. It also loses observation during a source failure, isolates the old descriptors, establishes a new session, explicitly adopts the independently observed successor and shuts down the parent. These are finite transport/lifecycle witnesses, not physical reset or board qualification.

The temporary-child variant uses two initially empty templates and the same typed source actors:

```sh
python3 tools/test_supervisor_stream.py --scenario temporary --xls /path/to/xls --stage /fresh/artifact/directory
```

It compares concurrent admission, capacity rejection, source failure without restart, explicit completion, fresh identity/state, stale-operation rejection and unaffected sibling state against ordinary OTP temporary children. The RTL extension holds accepted output across retirement and requires reply-before-`DOWN` before slot reuse. Focused kernel/controller tests additionally exercise parent shutdown during startup, failed initialization and finite identity exhaustion.

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
