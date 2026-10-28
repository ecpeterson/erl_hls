# Type providers and compiler extensions

A descriptor `{hls_type, Module, Name, Arguments}` identifies a value representation. `hls_type` in the `hls_runtime` library owns host dispatch; `xls_type` in the `erl_hls` compiler owns DSLX rendering and operation lowering. The descriptor always names its original provider, including during compilation. Packaging does not replace it with a compiler-companion name.

## Host contract

A provider implements `hls_type`: `width/2`, `zero/2`, `pack/3` and `unpack/3`. Optional `value_width/2` distinguishes a logical value from its padded wire slot; omission uses `width/2`. Application constructor functions return descriptors, while ordinary operation functions implement their BEAM behavior.

`hls_type:pack/2` checks the provider's returned bitstring width. Providers own accepted values, normalization, bit order and padding. Their successful pack/unpack operations must obey the [numeric and codec laws](numeric-contract.md). Constructor names and arguments denote stable encodings across compatible code upgrades; incompatible formats use a distinct name or version argument. Retained codecs check availability and total width, not semantic compatibility or implementation identity.

Host codecs must be usable with the runtime library and the application's provider dependencies. They do not call `xls_type`, read actor source or require the compiler's implementation modules. Already compiled actor record codecs and retained `hls_record_codec` values use this same host boundary.

## Compiler contract

`xls_type` defines the optional callbacks used by compiler-capable providers:

| Callback | Used for |
| --- | --- |
| `print_type(Name, Arguments)` | DSLX value type for a descriptor. Required when that type reaches hardware. |
| `transpile(Function, Arguments, ClauseState)` | Source operation lowering. Arguments are lowered clause values, including static literals and phantom type descriptors. |
| `dslx_codec(Name, Arguments)` | Non-cast wire conversion, returning from-bits/to-bits renderer functions. Omission selects a bit cast. |
| `dslx_imports(Names)` or `dslx_imports()` | Direct DSLX companion dependencies. The named form takes precedence and receives the sorted names used by selected hardware source. |

Providers implement only the roles they support: an operation library need not define a type, and an internal type need not expose source operations. `transpile/3` returns a clause value, an updated clause state, or `{fallible, Kind, Expression}`. The fallible expression produces `(value, failed)`; the compiler attaches the source location and preserves first-selected-failure ordering. Unsupported operations remain errors rather than host evaluation shortcuts.

Use `xls_type:print_type/1`, `dslx_from_bits/2` and `dslx_to_bits/2` when composing descriptors. Use `xls_type:transpile/4` to delegate a source operation to another provider. These APIs preserve nested element codecs and wire padding. Return deferred `xls_dslx:value()` fragments; do not render them while composing an enclosing computation, because that would lose structured failure references.

The compiler has an explicit mapping from built-in runtime modules to `xls_provider_*` companions. It is an implementation dispatch table, with no provider registration or version registry. For custom modules, `xls_type:provider/1` returns the original module and calls its existing callbacks directly. A custom module can declare both `hls_type` and `xls_type` behaviours; adding an operation does not require editing the compiler's built-in mapping. Its compiler callbacks need compiler APIs only on compilation paths. Applications remain responsible for keeping their host operations independent of those callbacks when deploying without `erl_hls`.

Import discovery visits only the selected hardware source and nested type arguments. The provider declares direct DSLX imports; XLS resolves their transitive imports using the supplied search path. The callbacks do not discover files or package support assets themselves. See [source selection and compilation](actor-compilation.md) for preparation and [expression lowering](expression-ir.md) for the source/target representation boundary.

## Shared layouts

`hls_field_layout:layout/2` derives ordered widths and prefixes from runtime descriptors. `stream` prefixes count physical stream bits; `lsb` prefixes identify numeric low-bit slices. Zero-width fields remain present and do not advance the prefix. Callers supply checked unique field names.

`xls_struct_codec` renders those layouts using `xls_type` conversions. `hls_frame_layout` owns the ordinary header schema and host capacity checks; `xls_frame_layout` emits the matching per-build DSLX configuration. Neither renderer owns a second copy of the layout or host codec policy.
