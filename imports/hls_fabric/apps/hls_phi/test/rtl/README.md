# Phi RTL witnesses

These benches exercise generated application hardware: individual data/halo actors, closed and periodic topologies, repetition feedback, memory bridges and multi-device/profile compositions. The [application drivers](../../tools/README.md) select their generated modules, finite stimulus and completion conditions; the benches are not deployed hardware support.

The `.svh` files share simulation transport, profile and link-delay behavior. `phi_profile_trace.c` and `phi_service_trace.c` provide VPI diagnostics for retained internal activity; such recordings are observations, not a complete protocol proof. [debug](debug/README.md) contains the public-stream inspection and application-equivalence witness.

Application shell templates belong in [priv/rtl](../../priv/rtl/README.md). Board-independent component benches remain in the repository's `test/rtl`, while board pins, clocks and deployment checks belong to `platforms/xc7`. Passing simulation does not establish a routed clock or live-board operation.
