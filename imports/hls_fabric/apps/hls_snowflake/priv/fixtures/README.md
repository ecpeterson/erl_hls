# Finite reference fixtures

`named.json` and `enumerated.json` retain repetition-code streams from the pinned localuf reference; the `surface-` counterparts cover planar surface-code windows. The provenance documents record the reference identity and retained input hashes. `d3-p005-seed0-first128.json` is the fixed finite noise cohort used by the local-advance checks.

The [reference guide](../../reference/README.md) defines coordinates, mask ordering, retirement semantics and each corpus's quantified domain, and explains regeneration from the pinned source. [Application tests](../../test/README.md) load these files through the installed private directory. Their results establish agreement on the selected inputs, not a decoder threshold or a hardware timing result. Keep changed corpora and their provenance together; do not replace reference outputs with the implementation under test.
