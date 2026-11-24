# Shared physical support

These board-independent modules accompany emitted hardware bundles under `support/target/rtl`. `hls_build_support:layout/1` resolves this installed `hls_target` asset directory; source and scheduler builders retain the selected support files with their manifests.

- `hls_async_fifo.v` crosses bounded ready/valid words between two clock domains under one reset epoch.
- `hls_return_routes.v` retains bounded requester/transaction identities while services execute and replies stall.
- `hls_indexed_gather_ram.v` implements the scheduler's indexed collection RAM boundary.
- `hls_partition_activation.sv` orders partition setup before startup requests.

Application-specific adapters live with the application's assets. Board shells, constraints and drivers live under `platforms/`; test-only compositions such as the register-service routing shell live in `test/rtl`.
