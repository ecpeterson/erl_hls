# Selection and stalled outputs

A priority scan over nonblocking XLS receives can change its candidate when another input becomes valid. The first implementation passed continuously sparse/saturated tests but violated the wire contract when a higher-priority lane appeared during an output stall. The complete memory test caught it at the public link boundary; the small regression now reproduces it without application internals.

`Transmit` places a two-beat shared FIFO between `Packetize` and the wire. Selection is committed by enqueue, and a blocking forwarding proc retains the FIFO head until the wire accepts it. This adds no per-lane payload buffer. Tests cover late data lanes, late return traffic, continuously saturated classes, opaque payloads and stable data/TLAST through stalls.

The `--flop_outputs=true` setting did not make this proc's directly assigned output stable. Treat the generated ready/valid behavior as the boundary contract to test; do not infer stability from that flag. Other exported combinational selectors merit the same delayed-arrival regression when reviewed.

The report includes only the corrected implementation. Earlier unbuffered profiles remain local under `_build/provisional-ready-report/`; they are not accepted measurements.
