# Shared runtime records

Headers here define finite contracts shared by native runtime code, tests and source compilation. They do not select hardware placement or contain generated wire encodings.

`hls_domain_channel.hrl` declares the mailbox channel's state, per-edge observations and decisions. The [runtime kernel](../src/runtime/domain/hls_domain_channel.erl) is their behavioral authority; [lowering](../../hls_lowering/src/backend/xls/protocol/README.md) derives hardware types and atom codecs from these declarations. Payload storage remains in the enclosing transport wrapper. Keep source-visible tags as atom unions and widths as named runtime integer types.
