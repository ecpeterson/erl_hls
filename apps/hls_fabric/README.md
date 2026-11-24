# Communication synthesis

`hls_fabric` owns process-free communication synthesis: logical protocol projection, finite wait-graph analysis, host-codec planning and communication-topology rendering. Its planners consume checked logical and compiler facts and return retained values. They do not start virtual nodes, assign physical layouts, invoke target tools or revise system-level placement policy.

The application contains three related boundaries:

- `src/planning/protocol/` derives capture, transaction, codec and link facts without opening a transport.
- `src/planning/scheduler/` derives communication effect windows for scheduled actors.
- `priv/xls/fabric/` contains installed logical-router DSLX used by later target materialization.

`hls_compile` supplies source-derived computation facts. `hls_target` consumes Fabric results when it chooses physical bindings and emits target source. `hls_runtime` owns live routes, queues, wire codecs, device sessions and the virtual-node supervisor; those modules do not depend on this synthesis application. `hls_spacetime` may propose placement and scheduler requests through core contracts, but Fabric never calls the optimizer.

The `hls-fabric` CLI remains in the [`erl_hls` facade](../erl_hls/src/README.md) because one command coordinates computation, communication and target products. The retained build and execution contracts are described in the [Fabric documentation](../../docs/hls_fabric/README.md); package ownership is summarized in the [system model](../../docs/system-model.md).

Run the isolated communication boundary tests through the umbrella projection:

```sh
bash tools/test_umbrella_eunit.sh boundaries
python3 tools/check_package_boundaries.py
```

These checks establish the application dependency boundary and finite planner behavior. They do not establish generated-hardware correctness, physical timing or deployed progress.
