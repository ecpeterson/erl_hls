# Host transaction ownership

An `hls_gs` hardware proxy and an `hls_debug` client each own one return route and a bounded set of outstanding transactions. The CPU `hls_gs` adapter still invokes callbacks directly. These are host-side rules: the FPGA frame layout and generated datapath are unchanged.

## Admission and completion

Application calls use IDs 0–254, allowing 255 outstanding calls per proxy. All application casts use ID 255 and occupy no call slot. Successful casts have no reply; a failed cast can emit an error, which the proxy counts as an ignored reply rather than delivering to an unrelated caller. Debug queries use all 256 IDs. Application and debug transports, and clients on different return routes, have independent capacities.

The allocator selects an unused slot, scanning cyclically from its previous position. A full client returns `{error, transaction_limit}` without transmitting the new request. It does not queue that request for later submission. `gen_server:call` and `gen_server:send_request` can both address an application proxy; application wrappers which destructure successful records must decide how to expose admission and transport errors.

A slot is released only by its matching reply or by closing the client to further work. Reply matching checks the return route, transaction ID, and zero flags. Debug clients additionally require the expected reply tag or `DEBUG_ERROR`. An unknown tag, wrong debug reply kind, unowned ID, or wrong route/flags increments `ignored_replies` without consuming a pending request. A duplicate received while its old ID remains free is consequently ignored.

Application replies must decode to a declared record with no trailing payload, or to the remote-error result. Invalid record payloads and unknown tags leave the call pending. `hls_gs` does not yet declare a reply-record set for each request: a different valid declared record cannot be distinguished from a legitimate response by this client. Known debug replies retain their existing decoding-error results. Reply validation is not a general guarantee against a faulty endpoint inventing a plausible response.

## Timeout, caller death, and transport failure

A `gen_server:call` timeout ends the caller's wait; it does not cancel device work or notify the proxy that work has retired. The request retains its slot. A later reply releases that slot and is sent to the original reply alias, which modern ERTS has deactivated after timeout. If the caller dies, the proxy drops its reply handle and monitor but keeps the slot and decoding context until a matching reply arrives. A caller with several outstanding requests can leave several abandoned slots.

This deliberately permits exhaustion when the device never replies. Releasing slots on a host timer would permit late replies to satisfy newer callers. Increasing the timeout or using `infinity` changes only the caller's wait, not the ownership rule.

Broker death completes outstanding callers with `{error, {transport_down, Reason}}`. A send failure uses `{error, {transport_down, {send_failed, Reason}}}`. The client remains available for inspection but rejects further requests with the same failure and transmits no further casts. Neither error proves that an already submitted operation failed to execute. The client does not retry: retrying a non-idempotent operation after an ambiguous write can duplicate its effect. An actual FIFO write error stops the broker because the shared stream may contain a partial frame, so all its routes lose the transport.

The FIFO broker still performs synchronous writes. While a send is blocked, its client cannot process replies or status queries; the fabric call has the existing five-second timeout. A send timeout closes that client, but does not cancel a write already executing in the broker. Transaction capacity bounds outstanding ownership, not the BEAM mailboxes, queued casts, or transport bytes. Bounded I/O admission, owner-demand receive credits, and end-to-end deadlines are separate work.

## Session and route lifetime

A route may be registered repeatedly by the same live owner. Another owner receives `{error, {route_in_use, Route, Owner}}`. Once the owner exits, `hls_fabric` permanently retires that route for the broker's lifetime. Re-registration returns `{error, {route_retired, Route}}`; late frames on it are discarded. This also applies to orderly proxy shutdown, since the broker cannot prove the absence of in-flight device work. Other routes remain usable. Retirement records occupy host memory until the broker stops.

Starting a new broker or proxy does not reset the FPGA or drain old FIFO bytes. Recovery requires a clean transport/device boundary: stop admission, drain outstanding work and bytes where that can be established, or reset the relevant device/transport and reopen fresh endpoints. The simulator uses a fresh run and fresh FIFOs after interrupted work. Restarting only a proxy on an existing broker is explicitly rejected; a supervisor must respect this session boundary. An already idle client and transport may stay open across a separately established quiescent hardware reset. Zero pending calls alone does not prove quiescence, since casts and other physical transfers may still be in flight.

Within a session, the protocol assumes that each accepted call/query emits exactly one reply and that the transport does not duplicate frames. An old duplicate arriving *after* its ID has been reused is indistinguishable from a new response with the same tag. These eight-bit headers carry no generation. Out-of-order legitimate replies are supported; arbitrary duplicate delivery, device reset during traffic, transparent reconnection, and finite-generation reuse require a stronger endpoint protocol or a proven drain/reset fence. Host bookkeeping cannot manufacture that proof.

## Inspection and tests

`hls_fabric:client_info(Proxy)` queries local client state without sending an FPGA request:

```erlang
#{route => {0, 1}, status => up, capacity => 255,
  pending => 12, abandoned => 2, available => 243,
  ignored_replies => 1}
```

`pending` includes abandoned slots. `abandoned` counts known caller deaths, not timeouts in still-live callers. `available` is zero for a closed client; `status` then contains `{down, Reason}`. `ignored_replies` includes application cast errors as well as rejected/unowned replies. A CPU `hls_gs` returns `none`. This is distinct from `hls_debug:info(Proxy, message_queue_len)`, which inspects the proxy's native BEAM mailbox, and from scoped hardware mailbox/credit queries.

`rebar3 eunit --module=hls_fabric_client_tests,hls_fabric_tests` exercises both client kinds through a controlled broker and tests real FIFO framing and route retirement. The ownership scenarios saturate every slot over three ID cycles, permute completions, interleave 900 casts, and retain timed-out/dead callers across exhaustion and late replies. The regular generated-RTL regression also runs 600 concurrent-batch calls interleaved with 600 casts, a failing cast, and concurrent debug queries through the public frame bridge. Boundary counters/traces and client status check the resulting traffic without reading private RTL state.
