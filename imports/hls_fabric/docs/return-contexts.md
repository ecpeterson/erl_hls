# Return contexts

`hls_return_routes` preserves each request's source and transaction ID while sharing a service across sessions. It substitutes a free context slot as the service transaction ID, then restores the original pair on reply. Application/debug tables are independent, defaulting to 16 slots each (`APP_CONTEXT_SLOTS`, `DEBUG_CONTEXT_SLOTS`).

## Ownership

Sessions may reuse the same original ID concurrently; service replies may complete out of order. A slot remains owned until the reply's final beat is accepted. A retired host session does not release it early: the eventual reply retains the retired route and is discarded there.

A full table backpressures request headers. A released slot becomes available next cycle; a stalled header retains its selected ID even if another slot becomes free. Available capacity adds no pipeline stage.

Application casts keep ID 255 and allocate no context because successful casts have no reply. Cast-failure and other unowned replies are drained. Debug uses all 256 transaction values. Busy-mask and dropped-reply outputs exist but are not yet connected to a host query service.

## Service and reset obligations

Requests must be complete valid frames. The service must preserve the assigned ID and reply exactly once per call/query, with its first reply beat after request-header acceptance on a clock edge. Same-cycle combinational replies are unsupported. A request that never replies can retain a slot indefinitely; arbitrary duplicate replies after reuse are outside the contract.

Reset must cover context tables, service work and buffered old output, followed by fresh host activation. Clearing tables alone is unsafe while old replies can emerge.

Service debug traces observe remapped IDs, so they cannot be equated directly with original host IDs. Counters remain useful. The adapter preserves return routes; autonomous actor-network routing is a separate contract.
