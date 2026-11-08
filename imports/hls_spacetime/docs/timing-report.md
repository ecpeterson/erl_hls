# Explain recorded-computation timing

The offline report answers “which source-to-sink chains contribute the largest static bounds to these recorded writes, and where does their delay accumulate?” It consumes the same complete computation publication as the viewer, without running Vivado, a simulator or an application compiler. The report reads the original native graph and SDF annotations, including when its input directory also contains prepared rendering indexes.

```sh
node scripts/report-timing.mjs \
  --input /path/to/computation-publication \
  --output /path/to/fresh-timing-report
```

Use `--capture RECORDING_FILE` when the publication contains several computation captures. `--scope registered` is the default: sources are sequential outputs, excluding clock-to-Q. `--scope static` also admits the supported external and constant frontiers. `--first-cycle C --end-cycle C` selects a half-open interval of recorded write timestamps within the capture. `--event ID` selects a write or the explicit writes associated with a producer; the interval still applies. Repeated scalar options use the last value. An unknown event or invalid interval fails; a valid selection with no writes produces an explicitly empty report.

The output directory must not exist. `report.json` contains every selected write and shared cone; `report.md` gives a short ranked preview with direct native pin names. `manifest.json`, written last, binds both output files and the exact input recording, publication index and computation manifest. Existing loaders verify every original part's byte count and digest before analysis. File paths stay within the publication, including through symbolic links; hard-linked retained source files are supported. Input limits remain 128 MiB for the recording and 512 MiB for complete graph parts, at most 32 MiB each. The JSON report is bounded to 32 MiB and its Markdown preview to 4 MiB; oversized results fail instead of truncating the selected population.

## Reading the report

Each cone corresponds to qualified native target pins for one role: data, enable or reset. Compact report-local cone numbers refer back to each retained source cone identity. Writes sharing a cone refer to the same report row, so repeated occurrences do not repeat the static analysis or multiply delay. Write rows retain their cycle, incarnation, actor, task, target resource/mask, producer associations and mapped/unknown bit counts. Unknown target bits have no invented native endpoints. A write without any qualified target remains in the report with no cone.

For a known cone, the report backtracks the existing latest-arrival calculation to a source, retaining an ordered chain of exact native arcs. Each row includes the original fast/slow timing annotations, local delay, cumulative delay, source/target pin and cell type, available tile coordinates, and routing disposition. Net and logic sums reconcile with the cone's existing bound. A second ordering points to the largest individual contributions without changing the source-to-sink order. Native net sink-pin counts and unique path logic-cell/net counts provide context; neither is a measurement of congestion or a whole-device area count.

Equal maxima use deterministic native-identifier tie-breaking. The report states how many sinks tie and whether the selected backtrack encountered alternative predecessors. It supplies one representative maximizing chain, not every tied path or a uniquely responsible cause. Reconstruction is bounded by the cone's pin population and never enumerates an exponential set of paths.

Unknown competing timing, unsupported frontiers and cycles retain their reasons and yield no purported maximum chain. Registered scope can instead be not applicable when no sequential-output path reaches the target. `maximumKnownPathNs` is the maximum among known selected cones: it does not bound unknown cones, unmapped bits, unselected writes or the complete implemented design. An incomplete capture and its observer gaps remain attached to the report.

## What the numbers establish

Each arc cost is the largest supplied fast/slow, transition and conditional delay annotation. Adding those independent maxima gives an envelope over the represented structural graph. Its maximizing chain need not be jointly sensitizable or match a single corner's STA path. Recorded write membership establishes an association with that circuitry; it does not prove that every arc switched on that execution.

The analysis excludes clock-to-Q, setup, clock skew, timing constraints/exceptions and runtime sensitization. It is not STA slack, an achieved clock period, a congestion diagnosis or a whole-step critical path. Net-versus-logic fractions identify candidates to investigate; they do not predict the improvement from a design change. Counts of writes or clocks do not scale a path's delay. Deriving elapsed physical time still requires a separately qualified period and a measured cycle interval.

## Known delay with unresolved geometry

The viewer's shelf can contain connections whose endpoint timing is completely known. The routed branch may have unresolved extra site-pin attachments, missing locations or incomplete connectivity, so a defensible sequence of intermediate arrival heights is unavailable. The report keeps the native routing disposition and gap records alongside the known SDF delay. Missing geometry never becomes zero delay and never erases independently known endpoint timing.

Even a resolved branch has only native tile/PIP locations and schematic chords in this exporter. SDF supplies end-to-end pin-pair delays, not per-wire or per-PIP delay. The viewer's interpolated intermediate heights are a display convention; this report accumulates costs only at the native graph's pin boundaries.
