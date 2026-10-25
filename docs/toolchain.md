# Standalone compiler toolchain

Use OTP 28 and rebar3 3.24 to build and package the compiler:

```sh
rebar3 release
_build/default/rel/erl_hls/bin/hlsc emit src/examples/regsvc/regsvc.erl --output /path/to/fresh-bundle
```

Move the whole `_build/default/rel/erl_hls/` directory to install it elsewhere with a compatible OTP runtime. The command uses packaged BEAM files, headers and support libraries; it needs neither rebar, Python nor this checkout at runtime. It does not start the compiler application or a distributed Erlang node. Rebar's standard `compile`, `eunit`, `dialyzer` and `release` commands remain the development interface; there is no custom provider or dependency-bootstrap script.

`hlsc emit SOURCE --output DIRECTORY` lowers one supported `hls_gs` or `hls_statem` actor through `hls_compile:actor/3` and the existing `xls_parse:to_xls/2` path. It writes `actor.x` and a source bundle. This command does not yet package communicating topologies; those compiler APIs remain available in [actor compilation](actor-compilation.md). Fabric placement, gateways, shared execution and application presets belong to downstream frontends.

Options take separate arguments:

- Repeat `-I DIRECTORY` for include paths, `-D NAME` or `-D 'NAME=TERM'` for macros, and `--dslx-path DIRECTORY` for application DSLX imports. Quote Erlang literal macro values for your shell.
- `--source-options FILE` reads one trusted Erlang list of [source options](source-context.md), including feature toggles. Its options precede command-line includes/macros; paths are relative to the invoking working directory, not the options file. The installed compiler's include directory is appended.
- `--direct-actor-debug` requests the existing dedicated state-machine observation interface.
- `--pipeline-stages N` selects the optional XLS recipe's positive stage count (default two, unit delay model). This is a scheduling choice, not a target frequency or physical result.

Later scalar options take precedence, including `--output`, `--pipeline-stages`, `--source-options` and `--diagnostics`. Flags may repeat. Include/import paths accumulate in command-line order; macros use the last definition of each name, with explicit `-D` overriding options-file defaults. Unknown options and missing values fail. `--diagnostics text|json` selects error output on standard error; the default is text. Owned diagnostics identify their `stage`, stable `code`, human `message` and structured `context`. Source preprocessing errors include each originating file, location, formatter module, raw reason and rendered message. For example, an oversized actor message reports its record, source/include location, actual width and the 96-bit limit. `HLS_DEBUG=1` adds the original stack, including as a `stack` field in JSON mode. Unexpected exceptions always expose their original class, reason and stack rather than being relabeled as invalid configuration. Existing output is rejected; later failures preserve partial output.

Compiler and downstream owners raise `hls_diagnostic:raise/4`; a caller can add defaults with `with_context/2`. Specific inner context wins, and the original stack is retained. The helper catches only tagged diagnostics: unrelated errors, throws and exits remain unchanged. JSON preserves numbers and UTF-8 binary text; every proper Erlang list remains an array, so numeric index lists never change schema based on their values. Owners use binaries for textual context; compound Erlang evidence uses explicit representations (`$tuple`, `$map` key/value pairs, `$binary_hex` for non-UTF-8 bytes, and `$term` for runtime-only values). This keeps actor identifiers and non-string map keys distinct from display text.

## Bundle contract

`hls_artifact_bundle` is the shared packaging API. Clients emit sources into a fresh directory, call `snapshot/2` for their support trees and `finish/3` with typed compilation units. `hls_compile:support/2` supplies this compiler's libraries and additional DSLX import trees; `support_layout/1` describes the same sources and bundle-relative import directories without copying them. A client chooses its own entry points, roles, schedules and RTL adapters; the compiler does not know fabric builder kinds or deployment policies.

Version 1 of `source-build.json` contains:

| Field | Meaning |
| --- | --- |
| `metadata` | Emitter-owned descriptive data, such as `kind`; cannot override schema fields |
| `units` | `role`, `directory`, `source`, `top`, `module`, `output`, `dslx_path`, literal `codegen_flags`, and complete `rtl` paths for each compilation unit |
| `rtl` | Ordered RTL file list per role, derived from units |
| `inputs` | Relative filename and SHA-256 for every emitted/copied input before the manifest is written |
| `eligible`, `native_measured` | Both false; emission grants neither admission nor physical qualification |

Paths stay inside the bundle; each unit has a distinct intermediate directory. Generated outputs appear in RTL lists before they exist. DSLX and RTL support files are copied with their relative hierarchy into `support/`. The bundle can move before external compilation. `request.erl` retains the original source/options for inspection; it is not a portable source-recompilation recipe. Input hashes bind emitted artifacts, not an exhaustive provenance inventory of original Erlang headers or the compiler binary. The manifest and source configuration are trusted local build records, not untrusted execution formats.

## Optional XLS invocation

Consume the manifest from another build system, or invoke the packaged standard-library Python driver:

```sh
_build/default/rel/erl_hls/bin/compile-source-build /path/to/xls /path/to/emitted-bundle
compiled=$(cd /path/to/emitted-bundle/compiled && pwd -P)
```

Add `--dry-run` to print a JSON preview without writing files or starting any XLS process:

```sh
_build/default/rel/erl_hls/bin/compile-source-build --dry-run /path/to/xls /path/to/emitted-bundle
```

The preview verifies frozen input hashes, resolved executable paths and their hashes, standard-library contents, source paths and import directories. It includes every unit's entry point, literal schedule flags and the same argument vectors consumed by execution. Relative arguments, outputs and logs refer to a future private source snapshot, not the caller's working directory. Preview also works after successful or failed compilation. It establishes the command plan, not XLS acceptance, successful scheduling or hardware behavior.

For detached use, copy both packaged `bin/compile-source-build` and `bin/compile_xls.py` into the same directory. The driver may be renamed; its companion must remain `compile_xls.py`. They require Python 3.12+ and XLS's `ir_converter_main`, `opt_main`, `codegen_main` and DSLX standard library, with no Erlang/rebar dependency. Each stage has a 300-second default deadline; `--timeout` changes it, and `--cache` selects a shared stage cache.

The driver leaves `source-build.json` and every frozen source input unchanged. It snapshots their relative hierarchy, runs or reuses conversion/optimization/codegen for every unit, then publishes one complete immutable release through the default `SOURCE/compiled` symlink. `--output` selects another managed symlink; the Python `compile_build(...)` API returns the resolved release path. Resolve the symlink once, as above, before consuming several files. The release retains frozen source metadata, inputs, per-unit IR/RTL and `commands.json`, logs, `compiled.json` and a `files.f` per role. Each `files.f` entry is relative to that listing's parent directory; `compiled.json` RTL paths are relative to the release root.

A later-unit failure leaves the previous release selected and retains the failed attempt's inputs, commands, logs and partial products. Retrying the same frozen bundle reuses completed stages after checking their hashes; an unchanged successful invocation keeps the same release. `<output>.run.json` beside the symlink records current cache hits and execution costs, separately from the immutable producing evidence. Source-bundle and prepared-flat-directory drivers share the [same stage executor and publication rules](incremental-xls-builds.md). They preserve their emitters' schedules and backend policies; a unified build-profile interface remains separate work.

The relocation tests use real Erlang lowering and mock external executables. They establish packaging/invocation behavior, not hardware semantics; RTL simulation and physical measurement remain separate evidence.
