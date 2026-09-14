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

Broker death completes outstanding callers with `{error, {transport_down, Reason}}`. A send failure uses `{error, {transport_down, {send_failed, Reason}}}`. The client remains available for inspection but rejects further requests with the same failure and transmits no further casts. Neither error proves that an already submitted operation failed to execute. The client does not retry: retrying a non-idempotent operation after an ambiguous write can duplicate its effect. An actual FIFO write error stops the broker because the shared stream may contain a partial frame, so all its routes lose the transport.

The broker has one linked raw writer and one linked raw reader. Opening a FIFO and transferring bytes happen in those workers. The broker and its application/debug clients continue processing replies, status queries, timers, and owner/worker death while either direction is blocked. A worker failure closes the shared transport. Starting the broker does not wait for a peer to open its FIFO; `writer_ready` in broker inspection distinguishes that opening stage.

## Transmit admission and deadlines

`hls_fabric:start_link(WritePath, ReadPath, Options)` accepts these positive frame limits:

| Option | Default | Bound |
| --- | ---: | --- |
| `tx_limit` | 1024 | Queued frames plus the active write, across the transport. |
| `tx_route_limit` | 512 | The same count for one outgoing `{Source, Destination}` route. |
| `rx_limit` | 64 | Delivered receive frames awaiting acknowledgement, across the transport. |
| `rx_route_limit` | 1 | The same count for one registered return route. |

Accepted writes preserve submission order. A frame has at most 255 payload words plus its route and header, so transmit storage is bounded by the configured frame count and a 1028-byte maximum encoded frame. Counts include the active write; rejected and expired queue entries consume no capacity. The per-route cap limits how much one route can occupy, but the single ordered stream still permits head-of-line blocking. It is not a fair scheduler.

`hls_fabric:send/4` waits for host write completion with a five-second budget. `send/5` accepts a millisecond timeout, `infinity`, or `{abs, MonotonicMilliseconds}`. `send_request/5` accepts the same arguments and returns an OTP request identifier; use `gen_server:check_response/2` in an event loop, or `receive_response/2` when waiting is appropriate. The deadline is calculated before submission and covers admission, queue residence, and the active write. Brokers and their route-owning clients reside in the same Erlang node, so these absolute values share one monotonic clock. Other nodes can still call those proxy processes through ordinary Erlang messaging. Waiting on an OTP request with a shorter timeout only abandons that reply handle; it does not cancel the broker's operation.

These outcomes distinguish what the broker knows:

- `ok`: the host writer completed the frame. It does not establish device admission or operation completion.
- `{error, {not_sent, Reason}}`: this frame was never issued to the writer. Reasons include `tx_limit`, `{route_tx_limit, Route}`, `timeout`, invalid frame encoding, and transport closure while the frame was still queued. The application/debug proxy releases just this request's slot and remains usable if its broker is still up.
- An active write error or `{write_timeout, Route}`: transmission may have happened in whole or in part. The broker closes, and its clients fail their remaining callers without retrying.

When a submitting process dies, its unwritten queue entries are removed. An active write continues to own the physical stream until it completes or the transport closes. Killing its worker cannot undo an operating-system write already executing; it may finish as the worker shuts down. A blocked raw open or transfer can outlive the broker until its operating-system call returns, so releasing the old I/O is part of session teardown. A replacement must respect the session recovery rules below.

Each application/debug proxy additionally permits at most 1024 outstanding host send completions, including casts. This bounds its asynchronous submission handles separately from its transaction IDs. `gen_server:cast` supplies no caller to receive an admission error: rejecting a cast therefore closes that client with `{cast_not_sent, Reason}`, visible in client inspection and subsequent calls. It does not silently drop a command and continue. Previously accepted traffic may still execute. Applications needing an acknowledgement of admission must use a request/reply interface.

The phi runner passes one absolute experiment deadline to its first and subsequent commands. It completes those writes in order before consuming another event, while continuing to handle its timer and fabric monitor. Its budget starts before the initial command; stalled initial or later writes cannot hide the experiment timeout. A command rejected before writing is not retried automatically.

## Receive credits

The broker delivers `{'$hls_fabric_frame', Receipt, Route, Header, Payload}` as a cast. The registered owner calls `hls_fabric:ack(Broker, Receipt)` after processing the frame. A receipt is single-use and belongs to that owner; duplicate and wrong-owner acknowledgements grant no credit. The application/debug clients acknowledge after decoding, including ignored replies. The phi runner retains receipts for events waiting on a command write and acknowledges each event when consumed.

The reader performs one permitted frame read at a time. The broker can retain one additional complete frame when its route has exhausted its window. That frame blocks further reads on the shared FIFO until credit returns; an independent route behind it cannot overtake. When the global window is full, the broker stops permitting reads. Registered owners therefore receive at most their configured route windows, subject to the global bound. These delivery bounds do not include kernel FIFO/DMA buffering.

Owner death retires its routes, releases their outstanding receipts, and discards a buffered frame for a retired route so other routes can progress. Unknown and retired routes are drained without delivery. There is no receive timer which silently drops an owned frame to restore credit.

The limits bound admitted transport state and broker-to-owner deliveries, not arbitrary messages other processes send directly to BEAM mailboxes. Producers must still control their calls and casts. The example-local CPU fabric implements the same receipt/send interface but remains a functional actor model with unbounded internal Erlang mailboxes; it does not emulate physical backpressure.

## Session and route lifetime

A route may be registered repeatedly by the same live owner. Another owner receives `{error, {route_in_use, Route, Owner}}`. Once the owner exits, `hls_fabric` permanently retires that route for the broker's lifetime. Re-registration returns `{error, {route_retired, Route}}`; late frames on it are discarded. This also applies to orderly proxy shutdown, since the broker cannot prove the absence of in-flight device work. Other routes remain usable. Retirement records occupy host memory until the broker stops.

Starting a new broker or proxy does not reset the FPGA or drain old FIFO bytes. Recovery requires a clean transport/device boundary: stop admission, drain outstanding work and bytes where that can be established, or reset the relevant device/transport and reopen fresh endpoints. The simulator uses a fresh run and fresh FIFOs after interrupted work. Restarting only a proxy on an existing broker is explicitly rejected; a supervisor must respect this session boundary. An already idle client and transport may stay open across a separately established quiescent hardware reset. Zero pending calls alone does not prove quiescence, since casts and other physical transfers may still be in flight.

Within a session, the protocol assumes that each accepted call/query emits exactly one reply and that the transport does not duplicate frames. An old duplicate arriving *after* its ID has been reused is indistinguishable from a new response with the same tag. These eight-bit headers carry no generation. Out-of-order legitimate replies are supported; arbitrary duplicate delivery, device reset during traffic, transparent reconnection, and finite-generation reuse require a stronger endpoint protocol or a proven drain/reset fence. Host bookkeeping cannot manufacture that proof.

## Inspection and tests

`hls_fabric:client_info(Proxy)` queries local client state without sending an FPGA request:

```erlang
#{route => {0, 1}, status => up, capacity => 255,
  pending => 12, abandoned => 2, available => 243,
  transmitting => 3, transmit_capacity => 1024,
  rejected_requests => 0, ignored_replies => 1}
```

`pending` includes both submitted calls waiting on a host write and calls waiting on a device reply, including abandoned slots. `transmitting` counts outstanding host send completions, including casts; a device reply can arrive before its host write completion is processed. `rejected_requests` counts calls known not to have been sent. `abandoned` counts known caller deaths, not timeouts in still-live callers. `available` is zero for a closed client; `status` then contains `{down, Reason}`. `ignored_replies` includes application cast errors as well as rejected/unowned replies. A CPU `hls_gs` returns `none`. This is distinct from `hls_debug:info(Proxy, message_queue_len)`, which inspects the proxy's native BEAM mailbox, and from scoped hardware mailbox/credit queries.

`hls_fabric:info(Broker)` inspects the local transport independently of those client and hardware queries. `tx` reports capacities, per-route occupancy, queued count, writer readiness, and the active write's route, byte count, and deadline. `rx` reports capacities, outstanding receipt count, whether a read is in progress, and the buffered route, if any. `routes` identifies owners and their outstanding receipts or marks a route `retired`; `counts` records written/delivered/discarded frames, rejections, expirations, and ignored acknowledgements. Neither this query nor client inspection sends device traffic. Use these observations alongside `hls_debug:info/2,3`, counters, and hardware queue probes to distinguish a host write stall, a slow host owner, and device backpressure.

`rebar3 eunit --module=hls_fabric_client_tests,hls_fabric_tests,hls_fabric_backpressure_tests,phi_memory_runner_tests` exercises both client kinds through a controlled broker and tests real FIFO framing and route retirement. The ownership scenarios saturate every slot over three ID cycles, permute completions, interleave 900 casts, and retain timed-out/dead callers across exhaustion and late replies. Real-FIFO tests fill a pipe to stop writes, withhold receive acknowledgements, exercise per-route/global limits, distinguish queued expiry from ambiguous active failure, and verify byte order, owner death, and recovery. They also complete an earlier debug reply while a later write is stalled. Runner tests cover stalled initial and later writes and broker death. The regular generated-RTL regression also runs 600 concurrent-batch calls interleaved with 600 casts, a failing cast, and concurrent debug queries through the public frame bridge. Boundary counters/traces and client status check the resulting traffic without reading private RTL state.
