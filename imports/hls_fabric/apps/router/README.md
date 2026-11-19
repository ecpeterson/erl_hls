# Rectangular multicast

`router` is an OTP library application. Its only dependencies are Kernel and STDLIB. The owner starts one registered root with `router:start_link(MinX, MinY, MaxX, MaxY, Routes)` under its supervisor, after its endpoints are ready. Omit `Routes` for an Erlang-only tree. Coordinates are inclusive and can be negative.

For a native target module, implement `whereis({X,Y}) -> pid() | undefined`. Empty sites are skipped. Leaves send ordinary casts unless the target implements `deliver(Site, Pid, Message)`. For a managed bank, supply enrolled sites, an extent, cast tags and a request builder in a `router:fabric_route()`. The deployment owns address translation and endpoint lifetimes.

- `broadcast/3` queues a send at the root.
- `submit/3` confirms native forwarding or reports managed admission.
- `barrier/3` collects the expected replies from selected sites. A managed bank can use consumption of an inert marker when that is sufficient to acknowledge the request. An empty selection succeeds. Failure or timeout can follow partial delivery.

A routed barrier follows earlier routed sends from the same caller. A barrier addressed directly to a PID follows that caller’s direct signals to the PID. Switching between a router and a direct sender introduces a second sender with its own ordering.
