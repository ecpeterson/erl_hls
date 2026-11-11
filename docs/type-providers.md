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

Compiler provider dispatch, built-in companions and typed codec renderers live together in [backend/xls/types](../src/backend/xls/types/README.md); see the [backend directory map](../src/backend/xls/README.md) for their expression, actor and emission collaborators.

## Finite atom unions

Typed actor fields and concrete local helper signatures can use ordinary Erlang
unions such as `-type fault() :: none | actor | backend.`. These are native atom
values in co-simulation. The compiler resolves a finite union (including
zero-argument local aliases) to an `hls_enum` descriptor and lowers its atoms at
typed fields, helper calls/results, patterns and equality comparisons.

The source declaration order defines codes starting at zero; repeated union
members retain their first occurrence. The first atom is the zero/default value,
so `fault = none :: fault()` is a legal field default. Reordering a union changes
its wire encoding. Generated record descriptors retain this complete codebook;
consumers should use those descriptors with `hls_type:pack/2` and `unpack/2` rather
than repeat numerical assignments. An explicit host descriptor is
`hls_enum:enum([none, actor, backend])`.

Unlisted atoms and unused codes reject in host codecs. XLS fields use the minimum
positive bit width, retaining unused integer codes so hardware wildcard clauses
can reject malformed input without an invalid enum cast. A generated bits decoder
does not by itself validate an application protocol: validate external codes before
acting on them. Exact equality/inequality are supported. Bare enum-valued guards, arithmetic, and
passing enum values to providers without atom-domain argument contracts are rejected. Atom ordering is rejected
because lexical Erlang ordering differs from declaration-code ordering.

Two distinct codebooks cannot be used interchangeably even if their widths or
members overlap. This slice diagnoses such uses, including a variable consumed by
two codebooks; it does not insert implicit enum conversions. Boolean atoms retain their separate canonical `boolean()` / `hls_bool:bool()`
type; explicit finite unions containing `true` or `false` are rejected rather than
interpreting declaration order as truth. Enums nested under collection/provider types are rejected until those operations
carry enum type-flow contracts; nested record fields are supported. Parameterized aliases
and imported source helpers' local aliases remain outside this supported slice.
