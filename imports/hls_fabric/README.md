# hls_fabric

Private shared actor execution, device fabrics and timing experiments built on `erl_hls`. Start with [building](docs/building.md), then [execution backends](docs/execution/README.md) for placement.

Each configured device has a virtual node name and genuine external Erlang PIDs for standalone services and scheduled actors. One ordinary BEAM hosts the node adapters and physical fabric brokers; no second VM or per-actor proxy process is required.

See the [documentation guide](docs/README.md) for node, addressing and transport contracts.

```erlang
{ok, _} = application:ensure_all_started(hls_fabric),
%% AppBroker and DebugBroker are persistent, local hls_fabric brokers owned
%% by the deployment's physical transport supervisor.
{ok, Node} = hls_fabric_sup:start_node('fpga_a@host',
    #{application => AppBroker, debug => DebugBroker},
    [#{name => registers, module => regsvc, endpoint => 2}], #{}),
#{registers := #{application := Registers, debug := Debug}} = hls_node:services(Node),
'fpga_a@host' = node(Registers),
42 = regsvc:ping(Registers, 42),
{ok, Counters} = hls_debug:get_counters(Debug).
```

Use the actual host name in the virtual node name. EPMD must be running. The listener defaults to the IPv4 address resolved from that host name; `ip` overrides the bind address. The advertised name must resolve to an address served by the listener. The endpoint authenticates using the hosting BEAM's cookie. Client nodes need compatible record definitions and the usual matching distribution cookie. Publish the returned PIDs through ordinary application discovery; a standalone service's configured name is also available as a registered destination on the virtual node.

A caller can use the same PID after reconnecting. Connection loss retires its return routes and bookkeeping, while FPGA actor state remains intact. Restarting the virtual node obtains a new EPMD creation and new PIDs; old PIDs cannot address the replacement. Starting or stopping this adapter never resets hardware or reopens physical descriptors.

This is an executable distribution **endpoint prototype**, with a deliberately limited signal set. It supports PID/registered-name calls and casts, monitors/demonitors, alias replies and `net_adm:ping`. Links, exit propagation, remote spawn, RPC services, sequential tracing, and general BEAM introspection are not implemented. Unsupported signals close the affected connection. TCP distribution is the default. Start the hosting BEAM with `-proto_dist hls_local` to connect to locally hosted virtual nodes through an in-process distribution controller. Other ERTS nodes still use ordinary TCP, as do remote callers of the virtual nodes. ETF serialization remains; this is not zero-copy messaging. See [node semantics and architecture](docs/device-sessions.md).

## Local carrier

After compilation, make the private distribution module available before distribution starts:

```sh
ERL_LIBS=_build/default/lib:_build/default/checkouts erl -pa _build/default/lib/hls_fabric/ebin \
    -sname host -proto_dist hls_local
```

Start the application and attach nodes as above. Each virtual node manager reserves a module-qualified local registered name, such as `'hls_node:fpga_a@host'`. This namespace belongs to the adapter; an unrelated process registered as `'fpga_a@host'` is never contacted during discovery. Lookup does not create atoms and returns the exact manager PID for that connection attempt; process death automatically releases the registration. Its PID is only a control-plane lookup; requests travel directly between ERTS's distribution buffer and the existing connection adapter. A local connection is reported as `carrier => local` in `hls_node:info/1`; remote connections report `tcp`. Restart the hosting BEAM to change its configured distribution carrier.

Both carriers use the same cookie handshake, node creation, service PIDs, codecs, pending transactions and route retirement. The local adapter pauses ERTS distribution intake when its waiting queue fills; normal ERTS busy-buffer behavior then applies, including possible sender suspension. This also means an asynchronous request API need not return immediately under distribution saturation. The device-release/control process must not depend on that saturated sender making progress.

See [host-path measurements](docs/artifacts.md#historical-reports) (`experiments/results/carrier-measurements.md`) for latency, throughput and memory-pressure comparisons with TCP loopback and local fabric proxies. They exclude physical I/O and hardware execution.

## Scheduled actors

`hls_node_topology:normalize/3` derives logical actor identities, generated codecs and scheduler slots from the existing topology and scheduler plans. Supply a physical ingress endpoint for each scheduler group and a matching addressed gateway:

```erlang
Deployment = hls_node_topology:normalize(Plan, SchedulerSpecs, Endpoints),
{ok, Node} = hls_node:start_link('fpga_a@host', Brokers,
    [#{name => workers, topology => Deployment, debug_endpoint => 2}], #{}),
#{workers := #{actors := Actors, debug := Debug}} = hls_node:services(Node),
Actor = maps:get({family, cells, [0, 0]}, Actors),
ok = hls_statem:cast(Actor, {work, 42}),
{ok, Catalog} = hls_node_topology:bind_debug(Plan, SchedulerSpecs, Debug, Manifest),
{ok, Target} = hls_debug_catalog:actor(Catalog, {family, cells, [0, 0]}),
[{phase, Phase}, {message_queue_len, Depth}] =
    hls_debug:info(Target, [phase, message_queue_len]).
```

Actor PIDs accept casts; effects follow their declared topology routes. Their shared topology debug endpoint supplies fingerprint-checked actor observations. The executable gateway currently covers the four-actor fixture with two interleaved scheduler groups; creating a descriptor alone does not add ingress to an arbitrary topology. See [actor addressing and its current limits](docs/actor-pids.md).

## Device-to-device messages

The private partition backend expands a closed topology onto multiple devices and gives each cut source/recipient pair an independently credited lane. The bridge is written in static DSLX and moves complete actor frames over a full-duplex ready/valid word link without host forwarding. The executable phi experiment compares independently generated devices with BEAM, holds a link while querying public debug state, and verifies ordered recovery under asymmetric stalls. The devices and host debug transport have independent clocks; bounded asynchronous FIFOs preserve complete beats, and the regression diagnoses a stopped peer through the running device’s public debug port. See [clock domains, reset and implementation constraints](docs/clock-domains.md).

The [complete memory experiments](docs/distributed-memory.md) use checked application streams for correction delivery and final measurements. D3 covers two partitions; the D6 torus covers eighteen physical 4×2 patches with four distinct neighbor links each. Eligible [reductions](docs/partitioned-reductions.md) collect contributions outside actor state RAM; scheduler replication controls how many actors share an executor.

Placement supports register-backed actors and shared-RAM schedulers with independent actor outboxes. Physical Ethernet transport and independent device restart remain separate tasks. See [the device bridge contract and reproduction commands](docs/device-bridge.md).

The TE0715 experiment now carries an [N=6 repetition application](experiments/07-openxc7/docs/repetition-link.md) across two three-cell PL roles. Its bounded board demonstration exposes decoded corrections and complete local status rounds to the two host BEAMs; the cross-host logical-memory closeout remains to be qualified on hardware.

## Validation

```sh
rebar3 eunit
bash tools/test_local_dist.sh
bash tools/test_return_routes.sh
```

The Erlang tests use production fabric brokers, FIFO receive paths and a deterministic wire-level `regsvc` model. They exercise native external PIDs, an additional real ERTS caller, independent caller/actor lifetimes, reconnects, retired replies, transaction exhaustion, broker admission, aliases, node incarnation changes and supervised broker loss. The extra caller VM is a distribution test peer, not part of the device runtime. Local distribution sockets and EPMD must be permitted. OTP 28.0.2 is the CI baseline.

The generated-RTL test hosts two virtual FPGA nodes **in one BEAM**, backed by two Icarus simulations:

```sh
python3 tools/test_rtl.py /path/to/generated-rtl \
    --erl-hls /path/to/erl_hls \
    --stage _build/rtl-devices --carrier hls_local
```

Run EUnit first to compile the test modules. The RTL directory contains `regsvc.v`, `hls_debug_observer.v` and `hls_debug_server.v` from the pinned public regression. The runner verifies the maintained `regsvc` golden digest and records all input hashes. It checks independent state, 200 pings, casts, variable-length replies, complete debug traces, concurrent peer connections, and delayed-reply exclusion across reconnect. Public debug queries diagnose the stalled application output; VPI handles only the external AXI interfaces. No XLS rebuild or synthesis sweep is repeated.

The private routed shell preserves requester identity around the existing `regsvc` cores. Its context adapter is directly tested at capacities 1, 3, 16, 255 and 256. `tools/measure_return_routes.py` reproduces the isolated Xilinx 7-series area estimate. The public demonstration shell's fixed reply destination cannot be used unchanged.

The scheduled-actor regression generates fresh XLS RTL, binds real state/mailbox RAM, and checks both distribution carriers using public application and debug ports:

```sh
python3 tools/test_actor_rtl.py /path/to/xls --stage _build/actor-pids
```

CI runs this fixture with the same pinned XLS release as the public dependency and retains build provenance and decoded debug observations. The [ingress measurement](docs/artifacts.md#historical-reports) (`experiments/results/actor-pid-measurements.md`) compares the complete small fixture with direct and addressed ingress while preserving its RAM mapping attributes.

The [compiler dependency](docs/building.md) is pinned and prepared automatically. All virtual-node implementation and documentation remain private here.

[Source-protocol inspection and transport](docs/source-protocol.md) compiles current actors, inventories their exact channels and emits connected snapshot publishers and typed capture links. Actor scheduling and whole-application admission remain separate.
