# Actor PID qualification

## Regression fixture

`tools/hls_fabric/test_actor_rtl.py` lowers a private `hls_statem` fixture through the public compiler into real state/mailbox RAM and scheduler RTL. It drives application and debug FIFOs using the production brokers and checks both TCP and local distribution carriers. Expected reports are observed only at the public topology output. Actor state and waits are inspected through the production debug query protocol; VPI connects only external interfaces.

The fixture verifies logical/physical slot isolation, exact emitted values, malformed addressed envelopes, stalled-output diagnosis, remote ERTS casts and state/identity preservation across reconnect. Host tests separately cover shared-endpoint admission retries, debug transaction exhaustion and rollover, old-reply retirement and old-PID rejection after node restart. Build commands, tool/source hashes, debug manifests and decoded observations are retained with each run.
