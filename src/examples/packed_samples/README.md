# Packed-sample server

`packed_samples.erl` is a small `hls_gs` application whose callbacks accumulate a signed delta from a 24-bit input and return bounded receipts. It exercises typed bitstrings, sub-byte fields and generated record codecs through `hls_pack` and the ordinary XLS actor frontend.

The callback module is the application; tests supply its client and transport. Keep fixture-specific records and behavior here, and keep generic packing/type semantics in `api/` and lowering in `backend/`.
