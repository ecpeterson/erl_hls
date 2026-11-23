# Erlang library

`hls_spacetime` owns the cycle artifact and public validation/encoding entry points. `hls_spacetime_storage`, `hls_spacetime_physical` and `hls_spacetime_native` check its storage and physical attachments. `hls_spacetime_import` imports bounded native tables; `hls_spacetime_sdf` preserves checked SDF sidecars. `hls_spacetime_trace` reads the current protocol-stream capture dialect.

The library uses OTP only, has no application callback or supervision tree, and never invokes a compiler, simulator or Vivado. Backend-specific signal meaning belongs to the producing toolchain.
