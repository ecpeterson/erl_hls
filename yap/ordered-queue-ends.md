# Ordered queues and logical boundary coordinates

The P3 SQM source appends monotonically ordered round requests and coalesces readers at the tail. `hls_ring:append/2`, `back/1` and `replace_back/2` keep that bookkeeping inside the shared native/DSLX storage provider. Append invalidates traversal; replacing the tail preserves it. Empty, full and unfinished-insertion misuse keeps the existing failure convention. No new queue metadata, implicit scheduling or stored predicates are introduced.

The T footprint also contains stabilizers at coordinate -1. Exact topology IDs are logical static names, not physical coordinates or family indices. Their integer components now permit either sign; hardware addressing remains separately validated and bounded. The SQM fixture shifts its rectangle ingress address while retaining its original actor identity. This introduces no signed hardware address.

Finite qualification: four native ring tests (including repeated fill/drain, tail replacement and rejection), 3,600 native/DSLX/JIT/RTL operation transitions at capacities 1/3/4/7, 36 enum/nested-record source histories, and 41 topology tests. Shared source-quality checks, formatting, Dialyzer and runtime package boundaries pass. The first signed-ID test accidentally renamed an output port; its corrected replacement changes actor identities only. A subsequent fixture declaration typo was corrected. Failed attempts remain in the P3 evidence, separately from passing checks.

These are finite functional witnesses, not all-input proofs or area/timing evidence. P3 application and offloader work remains owned by the master Notes roadmap; this file is an implementation record, not another task list.
