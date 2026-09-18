# Topology query wire format

Use this reference when implementing a transport or decoder. For setup and interpretation, see [topology queries](topology-debug.md). Hosts, manifests and RTL must use matching schemas.

## Packets: schema 5

Words are little-endian, request flags are zero, and all beats have full keep. Replies preserve the transaction ID. The single-endpoint wrapper accepts route `{source:16, destination:16}` and returns `{2:16, source:16}` before the inner reply.

| Operation | Request payload | Reply payload |
| --- | --- | --- |
| `INFO` `0x10` → `0x90` | Empty | Schema `5`, resource/channel/FIFO/actor counts, 32 fingerprint bytes: 13 words |
| `QUERY` `0x11` → `0x91` | Resource ID | ID, cycle low/high, 128-bit value in four low-to-high words: 7 words |
| Error `0xff` | — | `1`: malformed/unsupported request; `2`: resource ID out of range |

Malformed inner requests drain through actual `TLAST`, including beyond 255 beats, and return one error with the original transaction ID. Payload words cannot become headers. The standalone router drops malformed routes and wrong destinations through `TLAST`, retaining frame ownership until the response's accepted final beat. Missing `TLAST` requires reset. There are no state-mutating commands.

## Observation values

Channel bits 0/1 mean valid/ready. FIFO values contain stored occupancy. Actor fields are:

| Bits | Field |
| --- | --- |
| 0–7 | Phase |
| 8 | Entry pending |
| 9–24 | Failure code, zero for none |
| 25 | Actor state initialized |
| 26–31 | Zero |
| 32–39 | Mailbox depth, if enabled |
| 40–47 | Postponed count, if enabled |
| 48–54 | Placement-specific mailbox fields below |
| 55 | Mailbox initialized |
| 56 onward | Optional reduction metadata |

For direct actors, bit 48 is reserved admission and 49–54 are zero. For shared actors, bits 48–52 are in-flight, mail candidate, entry candidate, egress waiter and shared egress busy; bits 53–54 encode scheduler phase. Slot zero occupies the low 24 bits of a shared scheduler's mailbox publication. Absent mailbox observations leave 32–55 zero.

Projection schema 4 supplies source and observation offsets for reduction status (2 bits), site (1–8), key (32), remaining (1–8) and pending failure (16), packed consecutively from bit 56. Unused bits are zero. Populations, site names, phase codebooks and failure source maps come from the manifest; unknown codes are rejected.

RAM providers occupy `banks`, direct providers `direct`, with contiguous resource indices across both. The projection and source RTL are covered by the manifest fingerprint. Values are snapshots at the query edge; their publication and coherence limits remain those in the [query contract](topology-debug.md).
