# Phi inspection witness

`hls_phi_debug_live_tb.sv` drives the generated instrumented application through its public application and debug streams. It compares application handshakes and accepted payloads against the uninstrumented `phi_memory_top` under the same input schedule and external stalls. Separate sink controls exercise blocked application output and blocked debug output.

The [debug driver](../../../tools/test_phi_debug.py) assembles generated RTL and connects the Erlang inspection client. This bench witnesses public behavior for that finite run; it does not expose internal registers as a substitute for the runtime debug protocol or establish unrestricted noninterference.
