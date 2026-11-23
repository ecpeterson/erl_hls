# Phi shell templates

These templates compose the decoder-specific gateway, scheduler RAM interfaces and debug ports. `phi_memory_debug_top_v` and `phi_decoder_profile_top_v` load them through this application's private directory. Generic FIFO, routing and backend storage support remains in `hls_lowering/priv/rtl`; board pins and clocks belong to `platforms/xc7`.
