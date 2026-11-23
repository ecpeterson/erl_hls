# Independent recovery domains on two boards

This flow combines already compiled source-domain RTL with one independently clocked endpoint per directed crossing, a physical Ethernet carrier, and the TE0715 host DMA shell. It consumes ordinary compiler bundles; the platform does not reinterpret application source or generate decoder policy. The N8 repetition qualification assigns four data/phi/syndrome positions to each board. The application fixture and oracle remain in `apps/hls_phi/`.

## Boundaries

Each board owns its domain incarnation and the local half of each crossing. The host confirms a receiver binding before enabling its transmitter. Bindings include a deployment namespace, generation, both incarnations and a nonwrapping sequence; ordinary domain replacement does not clear carrier failure or replay old work. See [domain recovery](../../../docs/domain-recovery.md#independently-clocked-endpoints) for the generic ownership contract.

The physical application clock is 25 MHz. The existing MAC/PCS uses independent transmit/receive clocks, packet storage and CDC ownership. DATA carries the complete 672-bit application frame; ACK follows native destination capture. Endpoint management and application traffic are separate host lanes, so observing a failure does not require the failed Ethernet carrier to make progress.

The PS DMA banks carry complete existing route/header/payload frames:

| Bank | Route | Recipient |
| --- | --- | --- |
| 0 | 1 | Domain application transport |
| 1 | 0 | Domain management |
| 1 | 2 | Crossing endpoint management |
| 1 | 3 | Optional incarnation-checked process inspection |
| 1 | 4 | Board status and parser-session bootstrap |

`hls_domain_board_control` emits the bank-1 framing switch, session control and optional inspection in DSLX. Its generated RTL wrapper only wires the exact emitted interfaces. `application/te0715_domain_link_top.v` connects those signals to the physical PS/GTX/DMA implementation. The hash-bound `board_control/interface.json` fixes the physical role and source domain index; the image builder rejects mismatches.

## Bootstrap and failure

Before ESTABLISH, the deployment must quiesce both DMA banks, finish and acknowledge old packets, and exclude pending or newly arriving native responses throughout establishment. Empty host mailboxes alone do not establish that condition. Qualification uses startup or fully drained failed domains. This in-band control lane cannot cancel a partially transferred DMA packet; arbitrary host death in the middle of DMA is not qualified by this flow.

A new nonzero host session must exceed both observed parser sessions. An exact already-attached pair can acknowledge an idempotent request. Success is reported only after both parsers observe the requested session. The operation resets parsers, never actor state, endpoint ownership or carrier failure. `hls_domain_board_client` owns routes 3/4 on the existing management broker. It has one outstanding request and a finite deadline; a lost establishment reply requires a later ordered status observation, never an automatic retry.

Carrier loss includes directional readiness loss, malformed private packets, and exported MAC/frame-store loss events. CRC or preamble rejection can discard a complete frame without delivering any payload bytes, so direction-local sticky loss capture conveys those events explicitly. The domain receives a native transport fault, retains its incarnation and first fault, and leaves host management available. Only cold reset clears physical carrier failure. A stopped clock whose health indication incorrectly remains active has no new watchdog here.

The carrier admits traffic through an explicit startup handshake. Control requests arming after observing both directions ready; each direction acknowledges that request through its own synchronizer while locally active. Host admission waits for both acknowledgements. Readiness settling before local arming may recover harmlessly. Once a direction has armed, even an active-loss pulse while its clock is stopped is retained until cold reset.

Errors stop their producing byte interface locally. Fault levels then cross into the control clock through synchronizers; the opposite direction observes a synchronized stop request. With running ideal clocks, these stages take at most three control edges and three destination edges respectively. Work accepted before its local stop observation has ambiguous completion; the carrier does not promise an instantaneous global stop. Active recovery, parser-session changes and domain replacement never replay that work or rearm the carrier.

Active loss stops cursors without resetting the retained DMA ownership slots. Only whole-image cold reset invalidates those slots, with the old link namespace excluded and users quiescent. Before a fresh packet is published, its producer overwrites every byte declared by that packet; unused memory is not treated as initialized data. Cold reset asserts immediately and releases locally through the reset synchronizers. The carrier uses 82 framing/control bits in addition to its two 1024-bit buffers; the frontend loss capture and reset synchronizers use another 12 bits. Inherited DMA/CDC memory and control remain part of the whole-image budget.

## Board attachment and closure

`domain_board_transport.py` owns four authenticated relay commands: application and management DMA on each board. `application/domain_board_relay.c` keeps one bounded packet per direction. A TX acknowledgement means that the native write returned; it is not an actor admission receipt. Closing stops new native I/O and closes the device descriptor, but a response already captured by the relay is delivered and credited before its final close acknowledgement. This handles a close request crossing an unread response without enlarging the buffers or reconnecting.

Successful attachment tests require all four close acknowledgements and terminal local/remote owners. Those acknowledgements do not establish native DMA cancellation or drain. After ambiguous interruption, retain the uncertainty; a fresh qualification attachment uses quiescent/unbound DMA, whole-image cold reset and a new excluded-from-old-traffic namespace. It never replays the previous session. Linux FPGA Manager reload also requires an idle PCAP controller and Linux's normal unlocked SLCR ownership; the shared [boot preparation](te0715-boot.md) omits the optional vendor IDCODE readback that left PCAP work pending at handoff.

## Local qualification

Before preparing an image, emit the source domain and each independent endpoint network using the [domain build interfaces](../../../docs/domain-recovery.md#independently-clocked-endpoints). Add `hls_domain_board_control:emit/2` to that role's source bundle and compile the ordinary `source-build.json` through the external XLS driver. The image manifest selects compiled units, identifies the board-control bundle and binds their source/compiled manifests and RTL hashes. It also supplies the generated MAC sources and initialization files, platform source hashes, exact native tools, chip database, retained reference bitstream and offline assembly donors. `application/domain_board.py:prepare` is the manifest consumer; `test_domain_board_inputs.py` contains small contract fixtures.

The native backend input includes the successful `hls-native-gtx-offline-build-v1` receipt and its sibling `recipe.json` and `build-script.py`, not just an executable path. The separate platform repair supplies `gtx/build_offline.py` and its pinned recipe to produce this bundle serially from local archives; an existing reviewed bundle with the same receipt contract is also usable. Preparing an image neither builds nor downloads the backend.

`application/domain_board.py` consumes that frozen manifest and runs one phase at a time:

```sh
python3 platforms/xc7/application/domain_board.py prepare /fresh/image --manifest /path/to/inputs.json
python3 platforms/xc7/application/domain_board.py map /fresh/image
# Review complete-image and connected-link resource reports before routing.
python3 platforms/xc7/application/domain_board.py route /fresh/image
python3 platforms/xc7/application/domain_board.py assemble /fresh/image
```

Use a process-tree memory guard and serialize native tool jobs. Inputs bind compiler receipts and RTL, physical role, MAC initialization files, constraints, tools, database and offline donor data. Each phase owns a fresh directory; failure preserves evidence and does not cause a restart or reroute. The mapping gate keeps whole-image and link-component limits separate. Logic whose ownership is unknown is charged conservatively; missing evidence is not free hardware.

Routing resolves the five application/TX/RX clock selectors against mapped names, then requires complete packed clock targets and MMCM placement before starting implementation. Assembly requires the retained complete routed coverage and successful modeled timing; effective constraints and coverage reports are hash-bound to the route result.

`application/domain_board_continue.py` consumes an independently recorded exception to the component screen; it never creates that review or relaxes whole-image gates. The reviewer supplies JSON with schema `hls_board_route_disposition_v2`, a nonempty `user_instruction`, and `selected_images` entries containing the exact resolved absolute `path`, SHA-256 of `inputs.json` as `input_manifest_sha256`, and SHA-256 of `map/result.json` as `map_result_sha256`. Set `component_screen_override_only`, `routing_settings_unchanged` and `whole_image_budgets_unchanged` to `true`; set `component_cost_established`, `synthesis_repeat` and `physical_board_access_authorized_now` to `false`; set `route_attempts_per_role` to `1`. The consumer rejects name-only reviews, changed identities and any prior attempt. It creates one fresh derived continuation while retaining the original failed component screen.

The corrected native backend, LUT legality check, known-mask comparison and complete frame roundtrip are distinct checks. Native timing has incomplete BRAM, generated-clock and CDC coverage: meeting its modeled frequency targets is not complete timing signoff or proof of a live clock. Programming and execution on both boards remain separate qualification steps.

For full Vivado timing analysis, `vivado/domain_board_profile.tcl` is an explicit opt-in profile for an unconstrained synthesized `te0715_domain_link_top` on `xc7z030sbg485-1`. Set `$output` to an existing artifact directory, source the profile, and call `board_check_clocks synthesis $output`; repeat the check with `routed` after routing. The caller owns the complete RTL source set, implementation settings, resource/time guards and final admission. This profile does not run implementation or program a board. Unknown CDC entries stay timed and block admission; review the retained unresolved and bounded-crossing reports.

The accepted board experiment implemented frozen v4 clock/CDC declarations and then checked additional TX RAM write-enable bounds on its saved routed checkpoint. The promoted profile combines those declarations but has not driven a fresh implementation. Future images need their own complete timing/constraint review; the existing physical witness does not qualify a new placement or bitstream.

Focused fixtures cover endpoint ownership, packet routing, Ethernet loss, host client correlation and both board-control inspection profiles. The independent-clock application witness compares two incarnations against the native N8 oracle and rejects old DATA/ACK packets after replacement. Its simulated atomic carrier does not exercise physical Ethernet. Conversely, the board-control witness supplies controlled native observations; it does not prove those observations or native DMA quiescence. Keep these scopes separate in reports.

`python3 platforms/xc7/test_domain_link_packets.py /fresh/evidence` runs the carrier, direction-guard and loss-capture fixtures serially. `--test guard`, `--test carrier` and `--test loss` select narrower witnesses. The guard fixture includes stopped-clock startup settling, explicit arming, post-arm active loss and cold-only recovery. These are finite ideal-clock witnesses, not metastability, arbitrary-history or physical CDC qualification; implementation constraints must separately validate the exact synchronizer and reset chains.
