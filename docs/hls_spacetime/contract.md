# Cycle execution and physical correspondence

`hls_spacetime` defines a backend-neutral artifact for observations of work and stored values across FPGA clocks. Erlang producers call `validate/1` before publication; `encode/1` validates and returns JSON iodata. Neither function starts simulation, writes files, extracts checkpoints or renders a picture. The storage and physical companion validators are internal parts of that contract.

This is a cycle-native companion to [compiler timing profiles](../profiling.md), with header `format: "spacetime", schema: 1, unit: "cycle"`. It does not change that format or imply a clock period. A later projection needs an evidenced period/origin, suitable precision and a definition of each duration. A target clock constraint does not establish elapsed physical time.

## Producer data

The exported types in [`hls_spacetime`](../../apps/hls_spacetime/src/hls_spacetime.erl) define the native representation: atom field/enum names, binary text and integer cycles. JSON encoding turns those names into strings. Cycle/sequence counts must be below `2^53`; write masks are native integers but encode as hexadecimal strings such as `"0xFFFFFFFFFFFFFFFF"`, preserving wide hardware masks in browser consumers. Callers retain original recordings and bound input size before constructing the artifact. Validation loads the tables and graph into memory; it is not a streaming collector or an untrusted Erlang-term parser.

| Table | Meaning |
| --- | --- |
| `build` | Exact source-bundle, compiled-RTL, observation-binding and realized-implementation identities. Recordings use content identities, not application names. |
| `capture` | One device, one clock, half-open cycle interval, reset incarnations, observer counters, scope, completeness and evidence. |
| `resources` | Semantic computation/storage resources. Storage declares width, depth, ports, read latency, collision behavior and reset policy. |
| `versions` | Unique values with a producer event or an explicit initial/carry-in/unknown root. Stored versions identify resource/address; transient values use `storage: null`. |
| `events` | Accepted actions with observer sequence, cycle, incarnation, actor, task, activation, operation, input/output version IDs, optional logical-resource associations and evidence. |
| `relations` | Additional required control dependencies or observed resource order, with evidence. |
| `activity` | Separate electrical-activity annotations, which cannot become dependency endpoints. |
| `physical` | A build-bound catalogue of generated objects, unique primitive cells, placement, net/pin connectivity and resource bindings, or `null`. |

IDs are independent of payload equality and signal spelling. Every event output has exactly one matching producer declaration. Inputs name existing versions in the same reset incarnation, with no future producer. An activation ID has one actor/task/incarnation identity. Tasks are producer-supplied grouping labels, not proof of ownership at every gate.

An event's optional `resources` list names the logical resources associated with its action, independently of actor and signal names. References must exist and cannot repeat; omitting the list declares no additional association. Storage events already associate `access.resource`, so they need not duplicate it in this list. These associations let consumers join computations and communication to physical bindings; they create no dependency edges, imply no exclusive ownership and do not establish value-sensitive gate causality. One event can involve several resources, and many events can use the same resource.

Version inputs imply required producer-to-consumer edges. Read requests also precede their results. `relations.kind = required` adds evidenced control prerequisites; `resource_order` describes this recording's arbitration/serialization and names the resource. Analyses must keep those categories separate. Both kinds, together with version ancestry, must form an acyclic, temporally consistent graph. Equal-cycle dependencies need evidence; observer sequence alone creates none. All tied predecessors remain recorded. A gap after prerequisites become ready remains unassigned unless observations explain it.

## Storage and reset

Cycle C samples old state and accepted operations at an edge. An ordinary write creates state available at C+1; same-edge reads follow the declared collision rule. These are cycle-binned observations, not within-cycle delay measurements.

- A committed write creates a fresh word version even when bits are unchanged. `access.before` identifies the replaced word; `after_version` names the new output. A bit mask selects written bits. Partial writes require the prior word among their inputs for the preserved bits. Full overwrites need not depend on old data; replacement order alone is not data ancestry.
- A hold produces no version and preserves the current word. It is passive and can coexist with a read. A simultaneous write to that word contradicts it.
- A read request identifies resource, port, address and selected word. Its result names the request, uses the same selection and arrives after exactly the declared latency. It produces a transient version that later computation can use after the address is overwritten. Ordinary inputs cannot bypass access checks by naming stale storage directly. Optional `read_mask` identifies the selected operational input bits in the encoded word; request and result must supply the same positive, in-width mask. Absence leaves the subset unknown. Read and write masks serialize as canonical hexadecimal strings to preserve wide integers. A selected mask is not evidence of electrical switching or a sensitized gate path.
- `read_first` and `write_first` define same-address collisions; `forbidden` rejects them. Ambiguous `no_change` behavior is unsupported in schema 1. A port accepts at most one operation per edge, while a pipelined response may coincide with a new request. Conflicting writes reject instead of depending on list order.
- FFs, internal registers, BRAM words and SRL positions have explicit histories. SRL shifts need observed per-position operations; primitive names do not imply them.

Reset incarnations partition the captured interval. Inputs, activation identities and relations cannot cross reset. Each accessed word needs an explicit root in its incarnation. `reset: retained` does not imply cleared RAM: use a carry-in or unknown root with evidence. Schema 1 ends ancestry there; it does not invent links to retired actors/requests. Initial roots are permitted for reinitialized storage. Collectors must substantiate those declarations.

A complete capture requires every read response due before its incarnation ends. Reads due at or beyond that boundary may remain pending or be reset-retired. Incomplete histories can use `complete: false`, which cannot pass a complete-interval gate. There is no unrestricted progress claim.

## Coverage and physical joins

Every observer declares `first_sequence` and exclusive `next_sequence`, including an empty stream. Present sequences and explicit `gaps` must partition that range exactly. Missing interiors, overlapping sequences and absent counters reject. Known gaps require `complete: false` and a reason. Sequence order must be monotone in cycle time across resets.

This checks reported coverage consistency, not whether instrumentation observed every action. Omitting and renumbering records can produce a consistent artifact. The observer's declared `scope` and later observation/noninterference qualification remain part of the trust boundary. Sparse switching or inspection snapshots cannot be relabelled as complete semantic capture.

The physical catalogue must match all four build identities. Each primitive appears once with kind, native properties and placement. Placed cells have site/BEL and common tile-grid coordinates. Explicitly unplaced cells, including native constants without a site, retain `null` site/BEL/coordinates; consumers must not draw them at an invented location. Canonical nets retain cell/pin/direction connections, with optional full native pin identities. Top-level ports are distinct from primitive pins. Tile coordinates are not micrometres; connectivity is not routed geometry or measured delay.

Every semantic resource has one disposition: `direct`, `distributed`, `merged`, `replicated`, `folded`, `optimized_away`, `ambiguous` or `unmapped`. Bindings reference generated objects and physical cells. A `distributed` word spans at least two cells and must identify a supported physical output pin, with evidence, for every encoded bit. This differs from replicated copies. An optional per-bit attachment on other dispositions covers the word with supported endpoints or explicit unknowns. Resources may share a cell; ambiguous candidates do not count as established mappings. Optimized-away resources have no cell. Names and structural association establish neither value-sensitive causality nor native equivalence.

Coverage is derived. `catalogue_supplied: false` distinguishes absent evidence; its `physical_cells: 0` counts supplied objects, not measured zero area. Otherwise cell counts use unique catalogue entries, never repeated bindings or clock layers. A real recording uses `simulation_witness` with a `native_measurement` catalogue; invented examples use `synthetic_fixture` for both. Mixed labels reject. Identity agreement does not authenticate a claimed measurement.

See [native catalogue import](native.md) for extraction, checked sidecars and native timing limits.

## Standalone inspection boundary

A viewer should consume a validated execution bundle, its matching physical catalogue and the two hashed SDF sidecars without rerunning the compiler, simulator or implementation tools. Backend packages generate observation bindings; application packages define inputs, completion events and workload interpretation. Spacetime keeps generic validation, reconstruction and rendering together, while target-owned adapters validate physical catalogues and SDF. Spacetime modules do not invoke the application compiler.

The first view will stack chip tile coordinates across clock layers. Repeating a cell in several layers does not multiply installed area. Static delay annotations neither create execution dependencies nor add another delay to an interval already measured in clocks. Endpoint connectivity remains schematic until actual routed geometry is supplied.

## Saved example and checks

[`spacetime_example.term`](../../apps/hls_spacetime/test_data/spacetime_example.term) is a trusted synthetic producer fixture. Phi/data names illustrate correction feedback, but its cycles, identities, checkpoint label and coordinates are invented. It includes a register write/hold, masked RAM write, read-first collision, delayed result, tied join inputs, separate grant order, two tags folded into one primitive, an ambiguous mapping and reset retirement. It is not an N2 simulation result.

After `rebar3 as spacetime compile`, an Erlang caller can inspect or serialize it:

```erlang
{ok, [Bundle]} = file:consult("apps/hls_spacetime/test_data/spacetime_example.term"),
Summary = hls_spacetime:validate(Bundle),
Json = hls_spacetime:encode(Bundle).
```

The caller owns any file write. No decoder that interns arbitrary JSON names as atoms is supplied. The term fixture is for trusted tests; external consumers use the JSON representation and must preserve this contract.

From the umbrella root, run `rebar3 as spacetime eunit --module=hls_spacetime_tests,hls_spacetime_trace_tests,hls_spacetime_import_tests,hls_target_sdf_tests` for positive cases and deliberate corruptions. These are consistency tests, not hardware proofs. The import and target SDF tests use synthetic native-shaped tables and bounded sidecars, not a vendor measurement. Native extraction, trace-to-implementation qualification and visualization remain separate stages.

## Passive sample reader

`hls_spacetime_trace:read/1` reads a complete or explicitly incomplete [protocol-stream recorder file](trace-format.md); `fold/3` visits every pre-edge sample without expanding runs into a full table. Repeated equal active samples still visit every edge. The reader checks fixed public fields, tap identities/widths, consecutive cycle coverage, canonical integer values and exact footer accounting. It bounds raw and decoded size at 256 MiB, cycles at four million, rows at one million and internal taps at 4096. The canonical recorder emits LF; Erlang also accepts CRLF normalized to LF, with decoded accounting over normalized rows and the file-size cap over original bytes.

The raw format is `spacetime_cycle_trace` version 1: header and public-field rows, tap declarations, run-length samples, then one mandatory footer. Wide samples use hexadecimal text. A missing footer rejects; an explicitly incomplete prefix can be inspected but never certifies a complete interval. A valid footer checks the producer's reported scope, not the authenticity of its measurements.

The optional `hls_spacetime_observer` application owns `xls_protocol_spacetime`, `xls_protocol_spacetime_capture` and its Verilator recorder/exact-replay shell. It consumes exact compiler and target products without moving their ownership into Spacetime. The [source-protocol capture guide](../hls_fabric/spacetime-capture.md) describes the external tool boundary and observation limits. Phi's public completion/readout interpretation stays in the application test package. Numerical attribution and physical correspondence remain separate from raw sample coverage.

See [the optional RTL memory witness](memory-witness.md) for a localized real-RAM recording.
