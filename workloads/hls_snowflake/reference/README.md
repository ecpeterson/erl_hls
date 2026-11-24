# Snowflake reference witnesses

These fixtures follow **unchanged localuf 3.4.4**, commit [`daf81a10ed5d201c0bcaf6a1d5cdc6563a06b96c`](https://github.com/timchan0/localuf/tree/daf81a10ed5d201c0bcaf6a1d5cdc6563a06b96c), for a phenomenological repetition code: frugal window, commit height 1, buffer height `2*floor(d/2)`, fast merging, 2:1 growth and full unrooting. The reference and derived witnesses are MIT licensed; attribution is in `LICENSE.localuf`. The original algorithm is described in [Snowflake](https://arxiv.org/abs/2406.01701).

## Reproduce

From the umbrella repository root, use Python 3.13:

```sh
python3.13 -m venv _build/snowflake-reference/venv
_build/snowflake-reference/venv/bin/python -m pip install -r workloads/hls_snowflake/reference/requirements.lock
git clone https://github.com/timchan0/localuf.git _build/snowflake-reference/localuf
git -C _build/snowflake-reference/localuf checkout --detach daf81a10ed5d201c0bcaf6a1d5cdc6563a06b96c
_build/snowflake-reference/venv/bin/python workloads/hls_snowflake/reference/generate.py
```

`--reference` selects the checkout; `--output` selects an alternate output directory. The generator refuses a different revision or tracked source edits. Dependencies, upstream checkout and visualization cache stay under `_build/snowflake-reference/`; the application retains only scripts, compact fixtures and provenance.

## Stream and output meaning

Bit `q` of `data_fault_mask` is a new data error on qubit `q`; bit `j` of `measurement_fault_mask` is a measurement error at detector `j`. The detection-event mask is

```text
((data ^ (data >> 1)) & ((1 << (d-1)) - 1)) ^ measurement ^ previous_measurement
```

Input sheet `i` enters the top of the window. Before its drop, the decoder emits immutable corrections for sheet `i-window_height`; negative indices are initialization. Spatial bit `q` identifies edge `((q-1,0),(q,0))`; temporal bit `j` identifies edge `((j,0),(j,1))`. Sheets are emitted in order, including zero masks. This retirement frontier means past correction edges cannot change; it does **not** assert that every cluster originating in that sheet has already resolved. Clusters can persist across window raises.

Each case ends with `3*window_height+4` fault-free sheets. The reference continues normal grow/merge processing throughout this tail: it is not told to skip work. The generator checks that the window drains and the final residual data mask is either zero or a full logical string.

`named.json` contains d=3 and d=5 quiet streams, each spatial boundary, transient and repeated measurement faults, a burst and a seeded 96-sheet continuous stream. It retains states after every sheet. `enumerated.json` covers all 121 weight-0, weight-1 and weight-2 patterns in the 15 data/measurement fault locations across three d=3 sheets; it omits detailed states and phase telemetry. Deliberately uncorrectable patterns remain in both corpora. Matching these witnesses establishes agreement on these cases, not a decoder threshold or a general correctness guarantee.

## Timing and work

`reference_runtime_all` preserves localuf's `time_only='all'` result. `phases` records every executed whole-window drop, grow and merge pass, including merge passes which discover no busy nodes. At this revision, an empty sheet returns runtime 4 but executes five phases; the runtime is one less than the observed phase count throughout these fixtures. We retain both rather than silently changing the upstream counter. Neither is an FPGA cycle count or a timing estimate.

Phase `work` counts reference method invocations: node/edge drop visits, growth visits, merge visits, cluster-ID comparisons, grown checks and defect pushes. `changed_nodes`/`changed_edges` are net register changes, not memory writes. Hardware memory-port traffic, arbitration, reservations and network messages depend on the eventual mapping and must be measured separately. The generator wraps calls only to observe them and checks results, states and runtime against an untouched decoder instance after every sheet.

Node states use `node_fields`; coordinates and IDs come from the corresponding geometry. Edge states use `edge_fields` in geometry edge order. Pointer values are `C=0,W=1,E=2,D=3,U=4`. The provenance manifest records fixture hashes and the reference source hash.
