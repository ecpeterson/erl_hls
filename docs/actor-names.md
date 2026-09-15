# Actor names and encodings

Hardware translation checks actor record, tag, phase, output-port, and reduction namespaces before invoking XLS. The same checks run when inferring a state-machine interface from source. A collision reports the emitted symbol and both source declarations, including the file and line; a conflict with the compiler's own declarations identifies the generated name instead.

Record types retain the established spelling: remove the first underscore, then titlecase the result. The packer and unpacker use the lowercase form of that type name. For example, `#phi_fold{}` becomes `Phifold`, with `bits_from_phifold` and `phifold_from_bits`; `#'Input_Value'{}` becomes `InputValue`, with `bits_from_inputvalue` and `inputvalue_from_bits`. Enum members uppercase their Erlang atoms. Field names retain their spelling, including case.

Every declaration and reference uses these rules, including typed helpers, record patterns and updates, private reduction accumulators, and topology scheduler codec calls. This is an artifact naming convention; wire tags and field layout still follow the Erlang declarations. Renaming a source declaration to resolve a collision does not reorder its tag or fields.

The generated module has one namespace for record types and their two codec functions. Distinct records such as `foo_bar` and `foobar` therefore cannot coexist, nor can `a_b` and `a_B`, whose type names differ but whose codecs coincide. Even a single record named `bits` is ambiguous: both codecs would be named `bits_from_bits`. Actor runtime types, constants, codec names, and the `XLS_FAILURE_SITE_` prefix are reserved. Fixed parameters are reserved too: `N` for record codecs, plus `COUNT`, `ACTOR_COUNT`, `PRODUCER_COUNT`, `STARTUP_COUNT`, and `INSTANCE_ID` for state-machine services. DSLX value parameters can shadow record types. State-machine runtime names are reserved across service modes so enabling reductions or instrumentation does not change their availability.

Generated identifiers must use ASCII letters, digits, and underscores, beginning with a letter or underscore. Fields cannot use DSLX keywords or the bare `_` wildcard. Quoted Erlang names such as `'Value'` work; names containing punctuation or non-ASCII characters are rejected with their source origin. The check applies to records actually emitted by the actor, including its private accumulator; unrelated records in an included header do not occupy the actor's namespace.

This preflight covers actor declarations and fixed compiler names. Imported-provider aliases, deployment identifiers, and value/type shadowing by source-derived local bindings remain subject to XLS's own scope checks.

Tags, phases, ports, and reducer names have separate enum scopes. Reusing `value` as a message tag, phase, output port, and field is valid. Distinct atoms that uppercase to the same member, such as `ready` and `'Ready'`, cannot share an enum. Phase atoms `repeat_phase`, `reduce`, `terminate`, `consume`, `postpone`, `fail`, `true`, and `false` are reserved by callback or expression lowering.

| Encoding | Capacity |
| --- | --- |
| Public wire tags | 253, or 252 when an actor has a private reduction accumulator |
| Phases | 256 |
| Output ports | 255; ordered effect counts also occupy a byte |
| Reducer names | 256 distinct names, regardless of how many phases open them |

Wire tag zero denotes no message, one denotes an error, and two denotes actor data. Public tags start at three in include-expanded `hls_tags` order; an accumulator takes the next tag. `none`, `error`, and the data-record name cannot also be public tags. These wire-identity checks apply to BEAM's generated packing functions too. DSLX spelling restrictions do not apply to CPU-only packing.

`rebar3 eunit` covers collisions, include origins, reserved names, and encoding boundaries. `tools/test_names.sh XLS_ROOT` checks mixed-case records through BEAM, DSLX interpretation/JIT, serialized IR optimization, and RTL. It also checks ordinary and aggregate reduction artifacts and `hls_gs` service conversion. Existing generated DSLX goldens check that established application names retain their artifact spelling.
