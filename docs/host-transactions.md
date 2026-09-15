# Host transaction ownership

An `hls_gs` hardware proxy and an `hls_debug` client each own one return route and a bounded set of outstanding transactions. The CPU `hls_gs` adapter still invokes callbacks directly. These are host-side rules: the FPGA frame layout and generated datapath are unchanged.

## Admission and completion

Application calls use IDs 0–254, allowing 255 outstanding calls per proxy. All application casts use ID 255 and occupy no call slot. Successful casts have no reply; a failed cast can emit an error, which the proxy counts as an ignored reply rather than delivering to an unrelated caller. Debug queries use all 256 IDs. Application and debug transports, and clients on different return routes, have independent capacities.

The allocator selects an unused slot, scanning cyclically from its previous position. A full client returns `{error, transaction_limit}` without transmitting the new request. It does not queue that request for later submission. `gen_server:call` and `gen_server:send_request` can both address an application proxy; application wrappers which destructure successful records must decide how to expose admission and transport errors.

A slot is released by its matching reply, by a broker rejection proving that the request was not sent, or by closing the client to further work. Reply matching checks the return route, transaction ID, and zero flags. Debug clients additionally require the expected reply tag or `DEBUG_ERROR`. An unknown tag, wrong debug reply kind, unowned ID, or wrong route/flags increments `ignored_replies` without consuming a pending request. A duplicate received while its old ID remains free is consequently ignored.

Application replies must decode to a declared record with no trailing payload, or to the remote-error result. Invalid record payloads and unknown tags leave the call pending. `hls_gs` does not yet declare a reply-record set for each request: a different valid declared record cannot be distinguished from a legitimate response by this client. Known debug replies retain their existing decoding-error results. Reply validation is not a general guarantee against a faulty endpoint inventing a plausible response.

## Timeout, caller death, and transport failure

A `gen_server:call` timeout ends the caller's wait; it does not cancel device work or notify the proxy that work has retired. A submitted request retains its slot unless the broker subsequently proves that it was not sent. A later reply releases that slot and is sent to the original reply alias, which modern ERTS has deactivated after timeout. If the caller dies, the proxy drops its reply handle and monitor but keeps the slot and decoding context until a matching reply arrives. A caller with several outstanding requests can leave several abandoned slots.

This deliberately permits exhaustion when the device never replies. Releasing slots on a host timer would permit late replies to satisfy newer callers. Increasing the timeout or using `infinity` changes only the caller's wait, not the ownership rule.

Broker death completes outstanding callers with `{error, {transport_down, Reason}}`. A send failure uses `{error, {transport_down, {send_failed, Reason}}}`. The client remains available for inspection but rejects further requests with the same failure and transmits no further casts. Neither error proves that an already submitted operation failed to execute. The client does not retry: retrying a non-idempotent operation after an ambiguous write can duplicate its effect. An actual FIFO write error stops the device broker because the shared stream may contain a partial frame, so all its sessions and routes lose the transport.

The persistent device broker has one linked raw writer and one linked raw reader. Opening a FIFO and transferring bytes happen in those workers. The broker and its application/debug clients continue processing replies, status queries, timers, and owner/worker death while either direction is blocked. A worker failure closes the shared transport. Starting the broker does not wait for a peer to open its FIFO; `writer_ready` in broker inspection distinguishes that opening stage.

## Transmit admission and deadlines

`hls_fabric:start_link(WritePath, ReadPath, Options)` accepts these positive frame limits:

| Option | Default | Bound |
| --- | ---: | --- |
| `tx_limit` | 1024 | Queued frames plus the active write, across the transport. |
| `tx_route_limit` | 512 | The same count for one outgoing `{Source, Destination}` route. |
| `rx_limit` | 64 | Delivered receive frames awaiting acknowledgement, across the transport. |
| `rx_route_limit` | 1 | The same count for one registered return route. |

Accepted writes preserve admission order at the device broker. Independent sessions can interleave submissions; they share the same limits and ordered writer. A frame has at most 255 payload words plus its route and header, so transmit storage is bounded by the configured frame count and a 1028-byte maximum encoded frame. Counts include the active write; rejected and expired queue entries consume no capacity. The per-route cap limits how much one route can occupy, but the single ordered stream still permits head-of-line blocking. It is not a fair scheduler.

`hls_fabric:send/4` waits for host write completion with a five-second budget. `send/5` accepts a millisecond timeout, `infinity`, or `{abs, MonotonicMilliseconds}`. `send_request/5` accepts the same arguments and returns an OTP request identifier; use `gen_server:check_response/2` in an event loop, or `receive_response/2` when waiting is appropriate. The deadline is calculated before submission and covers admission, queue residence, and the active write. Brokers and their route-owning clients reside in the same Erlang node, so these absolute values share one monotonic clock. Other nodes can still call those proxy processes through ordinary Erlang messaging. Waiting on an OTP request with a shorter timeout only abandons that reply handle; it does not cancel the broker's operation.

These outcomes distinguish what the broker knows:

- `ok`: the host writer completed the frame. It does not establish device admission or operation completion.
- `{error, {not_sent, Reason}}`: this frame was never issued to the writer. Reasons include `tx_limit`, `{route_tx_limit, Route}`, `timeout`, invalid frame encoding, and transport closure while the frame was still queued. The application/debug proxy releases just this request's slot and remains usable if its broker is still up.
- An active write error or `{write_timeout, Route}`: transmission may have happened in whole or in part. The broker closes, and its clients fail their remaining callers without retrying.

When a submitting process dies, its unwritten queue entries are removed. An active write continues to own the physical stream until it completes or the transport closes. A raw open or transfer may outlive its broker until the operating-system call returns. Workers finish an issued operation and close their descriptors normally after broker shutdown. Device reservations remain held until both workers explicitly confirm closure; killing a worker and observing its `DOWN` cannot substitute for that confirmation. A replacement must also respect the device recovery rules below.

Each application/debug proxy additionally permits at most 1024 outstanding host send completions, including casts. This bounds its asynchronous submission handles separately from its transaction IDs. `gen_server:cast` supplies no caller to receive an admission error: rejecting a cast therefore closes that client with `{cast_not_sent, Reason}`, visible in client inspection and subsequent calls. It does not silently drop a command and continue. Previously accepted traffic may still execute. Applications needing an acknowledgement of admission must use a request/reply interface.

The phi runner passes one absolute experiment deadline to its first and subsequent commands. It completes those writes in order before consuming another event, while continuing to handle its timer and fabric monitor. Its budget starts before the initial command; stalled initial or later writes cannot hide the experiment timeout. A command rejected before writing is not retried automatically.

## Receive credits

The broker delivers `{'$hls_fabric_frame', Receipt, Route, Header, Payload}` as a cast. The registered owner calls `hls_fabric:ack(Broker, Receipt)` after processing the frame. A receipt is single-use and belongs to that owner; duplicate and wrong-owner acknowledgements grant no credit. The application/debug clients acknowledge after decoding, including ignored replies. The phi runner retains receipts for events waiting on a command write and acknowledges each event when consumed.

The reader performs one permitted frame read at a time. The broker can retain one additional complete frame when its route has exhausted its window. That frame blocks further reads on the shared FIFO until credit returns; an independent route behind it cannot overtake. When the global window is full, the broker stops permitting reads. Registered owners therefore receive at most their configured route windows, subject to the global bound. These delivery bounds do not include kernel FIFO/DMA buffering.

Owner death retires its routes, releases their outstanding receipts, and discards a buffered frame for a retired route so other routes can progress. Unknown and retired routes are drained without delivery. There is no receive timer which silently drops an owned frame to restore credit.

The limits bound admitted transport state and broker-to-owner deliveries, not arbitrary messages other processes send directly to BEAM mailboxes. Producers must still control their calls and casts. The example-local CPU fabric implements the same receipt/send interface but remains a functional actor model with unbounded internal Erlang mailboxes; it does not emulate physical backpressure.

## Logical sessions and route lifetime

`hls_fabric:start_link/2,3` starts the persistent device broker. `hls_fabric:open_session(Device)` starts a linked logical session accepting the same `register_route`, `send`, `send_request`, `ack`, and `info` interface. Pass that session PID to an `hls_gs`, `hls_debug`, or frame client in place of the device PID. Clients may still address the device broker directly when no separate lifetime is needed.

```erlang
{ok, Device} = hls_fabric:start_link(WritePath, ReadPath),
{ok, Session} = hls_fabric:open_session(Device),
{ok, Client} = hls_debug:start_link(undefined, {fabric, Session, 1}),
{ok, Counters} = hls_debug:get_counters(Client),
ok = hls_fabric:drain_session(Session, 5000),
ok = hls_debug:stop(Client).
```

The device owner should live under the supervisor responsible for the physical transport. Session supervisors can replace their own children independently. Sessions monitor the device; losing it closes every session. Losing one session leaves the device, its raw descriptors, and other sessions alive. The session forwards the original OTP reply alias to the device, adding no second admission queue or request-ID allocator. The device remains the authority for route reservations, transmit capacity, receipts, and deadlines.

`drain_session/2` stops admission and waits for that session's accepted host writes, delivered receive receipts, and any complete buffered frame on its routes. It then retires the routes and stops the session. Receive processing and acknowledgements continue during draining. New submissions receive `{error, {not_sent, session_closed}}`. The timeout uses ordinary `gen_server:call` semantics: it abandons the caller's wait while draining continues. Producers must stop submitting work before initiating a drain.

This is a **host-traffic drain**, not a device-work fence. It does not wait for an application reply that the device has not emitted yet, prove that a cast finished, or require an autonomous topology to become idle. Applications needing completion should establish it through their own protocol before closing the session. Remaining calls fail on session loss without retry; subsequent frames on its retired routes are discarded as complete frames. Returning a receipt only acknowledges host processing of that frame.

`stop(Session)` closes immediately: the device removes that session's unwritten submissions, releases its receipts, and retires its routes. An active physical write retains the stream and its original deadline until completion or transport failure. Other sessions cannot overtake it. A stale reply or a session crash never causes another reader to open or a partial incoming frame to be relabeled for a successor.

A route may be registered repeatedly by the same live owner in the same session. Another owner or session receives `{error, {route_in_use, Route, Owner}}`. Once its owner or session exits, the route is retired for the **device broker's lifetime**. Re-registration returns `{error, {route_retired, Route}}`, even from a newly opened session. This also applies to orderly proxy shutdown and a successful host drain. Other routes remain usable. Retirement records occupy host memory until the device broker stops.

Within a device lifetime, the protocol assumes that each accepted call/query emits exactly one reply and that the transport does not duplicate frames. An old duplicate arriving *after* its ID has been reused is indistinguishable from a new response with the same tag. The eight-bit transaction header carries no generation. Out-of-order legitimate replies are supported; arbitrary duplicate delivery, device reset during traffic, transparent same-route reconnection, and finite-generation reuse require a stronger endpoint protocol or a proven device-work drain/reset fence. Session PIDs and host bookkeeping cannot manufacture that proof.

## Physical device closure and recovery

`stop(Device)` stops the broker and asks its raw workers to finish and close. It does **not** wait for descriptor release. `close(Device, Timeout)` also waits for that release, returning `ok`, `{error, timeout}`, or `{error, {release_unconfirmed, Reason}}`. A timeout leaves the reservation held. Capture `#{io := #{lease := Lease}} = hls_fabric:info(Device)` before stopping if a subsequent `hls_fabric:await_closed(Lease, Timeout)` will be needed.

A VM-local lease registry rejects overlapping opens with `{error, {device_owned, Owner, Status}}`. It reserves both endpoint paths, recognizes existing filesystem aliases by device/inode, and retains ownership through broker death. Workers confirm release only after `file:close/1` returns successfully. A partial read needs the rest of its old frame or peer closure; a stalled write needs the peer to consume bytes; an outstanding FIFO open needs its counterpart to open. There is no timeout that turns an unconfirmed release into a reusable device.

If a raw worker dies without confirming closure, the reservation remains quarantined. The registry retains its reservations across its own unexpected restart and treats those reservations as unconfirmed too. Successful explicit closure can release them; otherwise recovery requires ending that BEAM operating-system process. The registry is a small Erlang process started on first device use; there is no native helper executable. Its reservation changes are infrequent lifecycle operations, outside the frame path. This protects cooperating owners in one BEAM VM, not other OS processes. Endpoint pathnames and their aliases must remain stable while reserved.

Confirmed descriptor closure proves that old raw workers cannot steal bytes from a successor. It does **not** drain FIFO/DMA buffers or prove that device work has stopped. Reusing routes with a new device broker additionally requires an application-specific drain acknowledgement or a reset covering old work and output. The simulator uses fresh runs and FIFOs after interrupted work. An already idle client and transport may stay open across a separately established quiescent hardware reset; zero pending calls alone does not establish quiescence.

## Inspection and tests

`hls_fabric:client_info(Proxy)` queries local client state without sending an FPGA request:

```erlang
#{route => {0, 1}, status => up, capacity => 255,
  pending => 12, abandoned => 2, available => 243,
  transmitting => 3, transmit_capacity => 1024,
  rejected_requests => 0, ignored_replies => 1}
```

`pending` includes both submitted calls waiting on a host write and calls waiting on a device reply, including abandoned slots. `transmitting` counts outstanding host send completions, including casts; a device reply can arrive before its host write completion is processed. `rejected_requests` counts calls known not to have been sent. `abandoned` counts known caller deaths, not timeouts in still-live callers. `available` is zero for a closed client; `status` then contains `{down, Reason}`. `ignored_replies` includes application cast errors as well as rejected/unowned replies. A CPU `hls_gs` returns `none`. This is distinct from `hls_debug:info(Proxy, message_queue_len)`, which inspects the proxy's native BEAM mailbox, and from scoped hardware mailbox/credit queries.

`hls_fabric:info(Broker)` inspects the local transport independently of those client and hardware queries. `tx` reports capacities, per-route occupancy, queued count, writer readiness, and the active write's route, byte count, and deadline. `rx` reports capacities, outstanding receipt count, whether a read is in progress, and the buffered route, if any. `device` identifies the persistent owner, `session` identifies the queried session (`none` for a direct device query), `sessions` lists open/draining sessions, and `io` exposes the lease and worker PIDs. `routes` identifies owners and their outstanding receipts or marks a route `retired`; `counts` records written/delivered/discarded frames, rejections, expirations, and ignored acknowledgements. Neither this query nor client inspection sends device traffic. Use these observations alongside `hls_debug:info/2,3`, counters, and hardware queue probes to distinguish a host write stall, a slow host owner, and device backpressure.

`rebar3 eunit --module=hls_fabric_client_tests,hls_fabric_tests,hls_fabric_backpressure_tests,phi_memory_runner_tests` exercises both client kinds through a controlled broker and tests real FIFO framing and route retirement. The ownership scenarios saturate every slot over three ID cycles, permute completions, interleave 900 casts, and retain timed-out/dead callers across exhaustion and late replies. Real-FIFO tests exercise session replacement across a partial frame, draining writes and receipts, late replies, independent sessions, duplicate device opens, and confirmed versus unconfirmed descriptor release. They also fill a pipe to stop writes, withhold receive acknowledgements, exercise per-route/global limits, distinguish queued expiry from ambiguous active failure, and verify byte order, owner death, and recovery. They also complete an earlier debug reply while a later write is stalled. Runner tests cover stalled initial and later writes and broker death. The regular generated-RTL regression also runs 600 concurrent-batch calls interleaved with 600 casts, a failing cast, and concurrent debug queries through logical sessions and the public frame bridge. Boundary counters/traces and client status check the resulting traffic without reading private RTL state.
