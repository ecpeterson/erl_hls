# Erlang library

`hls_spacetime_plan` proposes and revises the shared `hls_implementation_plan`. `hls_spacetime_partition` supplies deterministic balanced placement over caller-supplied logical targets; `hls_spacetime_schedule` groups placed actors into process-free scheduler requests. Revision accepts an exact `hls_characterization` by value and delegates the decision to a caller-supplied pure policy. These modules assign no wire selectors, RAM rows, target source or runtime endpoints.

`hls_spacetime` also owns the cycle artifact and public validation/encoding entry points. `hls_spacetime_storage` checks its storage attachments, `hls_spacetime_import` imports bounded native tables through target-owned validation, and `hls_spacetime_trace` reads the protocol-stream capture dialect. `hls_target_physical`, `hls_target_native` and `hls_target_sdf` own physical and timing adapters.

The library has no application callback or supervision tree and never invokes a compiler, simulator or Vivado. Backend-specific signal meaning belongs to the producing toolchain. The optional `hls_spacetime_observer` application integrates compiler, target and saved-capture products without making any of those lower applications depend on Spacetime.
