# Application examples

These applications exercise the same [actor/type API](../../apps/hls_runtime/src/api/README.md), [source preparation](../frontend/README.md) and [XLS backend](../backend/README.md) available to clients. They remain in this repository as compiler and runtime fixtures; they are not generic compiler policies.

- [regsvc](regsvc/README.md): server calls/casts, register updates and bounded list replies.
- [packed_samples](packed_samples/README.md): sub-byte fields, bitstrings and signed codec behavior.
- [phi_decoder](phi_decoder/README.md): state-machine actors, reductions, topology families, noise feedback and finite host closeout.

Checked-in `.x`/`.erl.x` files and example RTL are fixture/support artifacts beside their sources. Regenerate source outputs through the documented test workflow; extend generic lowering in `backend/`, not by adding application-specific branches there. Board deployment and larger experiment infrastructure live outside these examples.
