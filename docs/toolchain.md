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

Unknown or duplicate scalar options fail. Source failures retain their compiler reason; `HLS_DEBUG=1` adds a stack trace. Existing output is rejected; later failures preserve partial output.

## Bundle contract

`hls_artifact_bundle` is the shared packaging API. Clients emit sources into a fresh directory, call `snapshot/2` for their support trees and `finish/3` with typed compilation units. `hls_compile:support/2` supplies this compiler's libraries and additional DSLX import trees. A client chooses its own entry points, roles, schedules and RTL adapters; the compiler does not know fabric builder kinds or deployment policies.

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
```

The script can be copied and used independently of Erlang/rebar. It requires Python 3.12+ and XLS's `ir_converter_main`, `opt_main`, `codegen_main` and DSLX standard library. Each stage has a 300-second deadline. It verifies input hashes, compiles every unit once, records tool hashes, commands, logs and products in `compiled.json`, and writes `files.f` per role. Failed/partial output is preserved and cannot be retried in place. This convenience driver supplies imports and required schedules; XLS remains an external tool. The older [incremental stage cache](incremental-xls-builds.md) remains a separate consumer for existing experiment drivers.

The relocation tests use real Erlang lowering and mock external executables. They establish packaging/invocation behavior, not hardware semantics; RTL simulation and physical measurement remain separate evidence.
