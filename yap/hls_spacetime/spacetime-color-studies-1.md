# S9 color studies

The scene's Color style selector now offers function, destination computation, direction, delay emphasis, and destination plus delay. These are alternate readings of the same retained geometry; selecting a style does not filter primitives or modify saved evidence. The optional flat footprint and static setup-path overlay retain their separate palettes.

## Meaning and boundaries

- Destination membership comes from the displayed write's resource and its selected native cones. The same resource keeps its hue across clocks, filtering and event ordering. Shared geometry is neutral gray, and missing contributing membership remains unknown. Twelve approximately equal-lightness Oklab hues are category hints, not unique IDs; the optional key shows exact resource names. Cache keys include cone-to-destination membership, including aliased destinations.
- Flow interpolates dark cool source to bright warm sink within each directed route span and from earlier to later on storage/dependency spans. The ramp restarts on every span, uses one GPU prism, and does not model electrical propagation or observed gate switching. Standalone points and unresolved route associations stay neutral. PIP connectivity is retained; site and inter-PIP connecting geometry remains schematic at tile resolution.
- Delay emphasis increases perceptual lightness on a fixed capture-wide scale. Every primitive inherits the maximum contributing cone bound in the selected timing scope; unknown contributors remain unknown. This is not incremental wire delay, slack, measured elapsed time, or a claim that every path was sensitized. Hybrid mode keeps the destination hue while changing lightness. Untimed storage retains a categorical hue in that mode and is neutral in delay-only mode.
- Selected access/write glyphs are pale neutral so selection does not masquerade as a semantic hue. Direction and timing styles disable face-lighting modulation; the existing depth buffer still occludes geometry. Role and categorical styles retain face shading for shape cues.

## Qualification

Serial local qualification under the 6 GiB process-group guard passed 231 JavaScript tests, 155 Erlang tests, Erlang formatting, Dialyzer and the source-contract audit (18 files, zero findings). The guard reported no violation and no remaining process-group members. Evidence: `hls_artifacts/runs/spacetime-2026-11-07/color-studies-1/qualification-1/`.

Focused cases cover endpoint tint packing/GPU attributes without segment splitting, equal categorical lightness and ordered scalar lightness, stable membership under aliases/filters/order changes, flat-window operation preservation, and unknown/shared membership aggregation. Browser comparison uses the existing routed N2 recording at C1852–1854, identical camera/spacing and wire-route detail; the RAM capture separately checks direction availability and disabled timing/membership choices without prepared native evidence. No new native job, decoder simulation or saved-data preparation is needed for these styles.

## Current judgment

Destination colors are the most useful general browsing view because they reveal spatial clusters and persist on the storage links. Direction is especially legible on inter-clock links; resetting its ramp on many tiny route spans is less helpful at a distant zoom. Delay-only is easier to interpret quantitatively than hybrid. Hybrid remains an option for comparison, but its mixed hue/lightness reading and untimed storage deserve care. Finer timing-impact claims would require more granular evidence, not a different color map.
