#!/usr/bin/env python3
"""Execute explicit XLS stages with checked caches and atomic artifact publication.

The flat DSLX command is one recipe adapter. Multi-unit clients supply exact
commands and dependencies to execute(); the executor never chooses a schedule.
"""
from collections.abc import Callable, Iterator, Mapping, Sequence
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
from typing import Any, TypedDict, Union

TOOLS = ("ir_converter_main", "opt_main", "codegen_main")
RECIPE_VERSION = 1

# Dependency names remain caller-owned cache-key structure; leaves name snapshot files.
Dependency = Union[str, dict[str, "Dependency"]]


class StageSpec(TypedDict):
    """An ordered direct tool invocation with explicit inputs and one stdout product.

    id identifies diagnostics within this build; cache selects a shared stage
    family. Arguments and dependency leaves use paths relative to the snapshot.
    Earlier products may appear as inputs. No shell interpretation occurs.
    """
    id: str
    cache: str
    tool: str
    arguments: list[str]
    output: str
    inputs: dict[str, Dependency]


class StageRun(TypedDict):
    """Checked artifact provenance, separating current execution from reused work."""
    key: str
    reused: bool
    adopted: bool
    execution_time: dict[str, Any] | None
    original_time: dict[str, Any]
    directory: Path
    command: list[str]
    planned_command: list[str]
    output: str
    sha256: str
    exit: int


class Publication(TypedDict):
    """A finalized manifest and release-relative files selected from the snapshot.

    The executor hashes the files after finalization and owns publication. The
    manifest filename and completed.json are reserved, and stage logs are added
    automatically under <stage id>.{stderr.log,time.json,command.json}.
    """
    manifest_name: str
    manifest: dict[str, Any]
    files: dict[str, str]


def sha(path: Path | str) -> str:
    """Hash file contents without loading a large compiler or artifact into memory."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def identity(value: Any) -> str:
    """Identify a JSON-compatible recipe independently of dictionary insertion order."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def save(path: Path | str, value: Any) -> None:
    """Replace one JSON record atomically beside its destination."""
    path = Path(path)
    pending = path.with_name(path.name + ".new")
    pending.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    os.replace(pending, path)


def duration(value: str | float) -> float:
    """Parse positive finite seconds or a duration such as 5m or 2h."""
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([smh]?)", str(value))
    if not match or not math.isfinite(float(match[1])) or float(match[1]) <= 0:
        raise argparse.ArgumentTypeError("timeout must be positive seconds or a duration such as 5m or 2h")
    return float(match[1]) * {"": 1, "s": 1, "m": 60, "h": 3600}[match[2]]


@contextmanager
def locked(path: Path, wait: bool = False) -> Iterator[None]:
    """Own one output promptly, or wait only for a cache-publication lock."""
    with path.open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | (0 if wait else fcntl.LOCK_NB))
        except BlockingIOError:
            raise ValueError(f"build already active: {path}; use a separate output directory") from None
        yield


def checked(directory: Path, inputs: Any) -> bool:
    """Trust a completed entry only when its identity and every retained file hash match."""
    try:
        result = json.loads((directory / "completed.json").read_text())
        return (result["inputs"] == inputs and isinstance(result["outputs"], dict) and bool(result["outputs"]) and
                all(sha(directory / name) == digest for name, digest in result["outputs"].items()))
    except (OSError, ValueError, KeyError, TypeError):
        return False


def cached_artifact(directory: Path) -> Path:
    """Locate a cached stdout product independently of its caller's destination name."""
    outputs = json.loads((directory / "completed.json").read_text())["outputs"]
    artifact, = outputs.keys() - {"stderr.log", "time.json", "command.json"}
    return directory / artifact


def run(argv: list[str], work: Path, output: str, timeout: float, *,
        cwd: Path | None = None, allow_empty: bool = False,
        expect_failure: str | None = None) -> dict[str, Any]:
    """Retain child CPU/RSS and logs; stop its whole group on failure to wait.

    Defaults require successful nonempty compiler output. Regression callers may
    allow empty stdout or require a positive exit and a matching diagnostic;
    signals and timeouts never count as an expected rejection. cwd only changes
    the command's working directory, not the retained log/product location.
    """
    if expect_failure is not None:
        re.compile(expect_failure)
    started = time.monotonic()
    (work / "time.json").unlink(missing_ok=True)
    (work / output).parent.mkdir(parents=True, exist_ok=True)
    with (work / output).open("wb") as stdout, (work / "stderr.log").open("wb") as stderr:
        process = subprocess.Popen(argv, cwd=work if cwd is None else cwd, stdout=stdout, stderr=stderr,
                                   env=dict(os.environ, LC_ALL="C"), start_new_session=True)
        try:
            while True:
                pid, status, usage = os.wait4(process.pid, os.WNOHANG)
                if pid:
                    process.returncode = os.waitstatus_to_exitcode(status)
                    break
                if time.monotonic() - started >= timeout:
                    raise TimeoutError(f"stage exceeded {timeout:g} seconds")
                time.sleep(0.02)
        except BaseException as error:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            save(work / "time.json", {"elapsed_seconds": time.monotonic() - started,
                                       "error": str(error), "returncode": process.returncode})
            raise
    metrics = {"elapsed_seconds": time.monotonic() - started,
               "user_seconds": usage.ru_utime, "system_seconds": usage.ru_stime,
               "max_rss_bytes": usage.ru_maxrss * (1 if platform.system() == "Darwin" else 1024),
               "returncode": process.returncode}
    save(work / "time.json", metrics)
    if expect_failure is not None:
        diagnostics = (work / "stderr.log").read_text(errors="replace") + (work / output).read_text(errors="replace")
        if process.returncode <= 0 or re.search(expect_failure, diagnostics) is None:
            raise RuntimeError(f"expected rejection did not match (exit {process.returncode}): {work / 'stderr.log'}")
    elif process.returncode:
        raise RuntimeError(f"compiler exited {process.returncode}: {work / 'stderr.log'}")
    if not allow_empty and not (work / output).stat().st_size:
        raise ValueError(f"compiler produced empty {output}")
    return metrics


def relative(name: str, *, directory: bool = False) -> str:
    """Require a normalized snapshot-relative path rather than silently rebasing a recipe."""
    path = Path(name)
    if not name or path.is_absolute() or ".." in path.parts or str(path) != name or (name == "." and not directory):
        raise ValueError(f"expected normalized relative path: {name!r}")
    return name


def tree_files(root: Path | str, prefix: str = "", suffixes: Sequence[str] = (".x",)) -> dict[str, Path]:
    """Inventory a complete source/import tree conservatively, preserving its hierarchy.

    Separate ordered import roots need separate prefixes to preserve shadowing.
    Empty import directories are supplied separately to execute(directories=...).
    """
    root = Path(root).resolve()
    if not root.is_dir():
        raise ValueError(f"missing input directory: {root}")
    if prefix:
        relative(prefix, directory=True)
    def collect(directory: Path, ancestors: frozenset[Path]) -> dict[str, Path]:
        """Follow trusted directory links while rejecting cycles rather than dropping imports."""
        resolved = directory.resolve()
        if resolved in ancestors:
            raise ValueError(f"cyclic input directory: {directory}")
        result = {}
        for path in sorted(directory.iterdir()):
            if path.is_dir():
                result.update(collect(path, ancestors | {resolved}))
            elif path.is_file() and path.suffix in suffixes:
                result[str(Path(prefix) / path.relative_to(root))] = path
        return result

    return collect(root, frozenset())


def snapshot_files(files: Mapping[str, Path | str], target: Path) -> dict[str, str]:
    """Copy exact named inputs, preserving hierarchy, and hash the private copies."""
    result = {}
    for name, source in files.items():
        destination = target / relative(name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        result[name] = sha(destination)
    return result


def stage(label: str, tool: Path, arguments: list[str], inputs: dict[str, Any], work: Path,
          output: str, cache: Path, timeout: float) -> dict[str, Any]:
    """Reuse or execute one exact stage, converging concurrent publishers on checked bytes."""
    key = {"recipe": RECIPE_VERSION, "host": [platform.system(), platform.machine()],
           "tool": sha(tool), "arguments": arguments, "inputs": inputs}
    entry = cache / label / identity(key)
    entry.parent.mkdir(parents=True, exist_ok=True)
    (work / output).parent.mkdir(parents=True, exist_ok=True)
    if checked(entry, key):
        print(f"{label}: reused {entry.name[:12]}", flush=True)
        shutil.copyfile(cached_artifact(entry), work / output)
        return {"key": entry.name, "reused": True, "adopted": False, "execution_time": None, "directory": entry}
    print(f"{label}: compiling {entry.name[:12]}", flush=True)
    save(work / "command.json", [str(tool), *arguments])
    metrics = run([str(tool), *arguments], work, output, timeout)
    if sha(tool) != key["tool"]:
        raise ValueError(f"compiler changed during {label}")
    adopted = False
    with locked(entry.parent / f"{entry.name}.lock", wait=True):
        if not checked(entry, key):
            pending = Path(tempfile.mkdtemp(prefix=".new-", dir=entry.parent))
            names = (output, "stderr.log", "time.json", "command.json")
            snapshot_files({name: work / name for name in names}, pending)
            save(pending / "completed.json", {"inputs": key, "outputs": {
                name: sha(pending / name) for name in names}})
            if entry.exists():
                entry.rename(entry.with_name(f"{entry.name}.damaged-{time.time_ns()}"))
            pending.rename(entry)
        elif sha(cached_artifact(entry)) != sha(work / output):
            # XLS can assign different node IDs. Every dependent stage consumes
            # the first checked winner, never the losing publisher's bytes.
            shutil.copyfile(cached_artifact(entry), work / output)
            adopted = True
            print(f"{label}: adopted concurrently published {entry.name[:12]}", flush=True)
    return {"key": entry.name, "reused": False, "adopted": adopted, "execution_time": metrics, "directory": entry}


def dependency_hashes(dependencies: Mapping[str, Dependency], snapshot: Path) -> dict[str, Any]:
    """Hash declared snapshot leaves using the client's stable nested cache-key names."""
    return {key: dependency_hashes(value, snapshot) if isinstance(value, dict)
            else sha(snapshot / relative(value)) for key, value in dependencies.items()}


def specifications(stages: Sequence[StageSpec], inputs: Mapping[str, str], tools: Mapping[str, Path]) -> list[StageSpec]:
    """Check unique stage/output ownership before running the first external tool."""
    result, ids, products = list(stages), set(), set(inputs)
    diagnostics = {f"{relative(spec['id'])}.{suffix}" for spec in result
                   for suffix in ("stderr.log", "time.json", "command.json")}
    if diagnostics & products:
        raise ValueError("stage diagnostics shadow a frozen input")
    for spec in result:
        label, output = relative(spec["id"]), relative(spec["output"])
        relative(spec["cache"])
        if label in ids or output in products or output in diagnostics or output in (
                "stderr.log", "time.json", "command.json", "execution-inputs.json"):
            raise ValueError(f"duplicate or reserved stage id/output: {label}, {output}")
        if spec["tool"] not in tools or not all(isinstance(arg, str) for arg in spec["arguments"]):
            raise ValueError(f"invalid stage tool or arguments: {label}")
        ids.add(label)
        products.add(output)
    if not result:
        raise ValueError("build requires at least one external stage")
    return result


@contextmanager
def cancellation() -> Iterator[None]:
    """Convert SIGTERM into cleanup while executing on the main thread, restoring prior policy."""
    if threading.current_thread() is not threading.main_thread():
        yield
        return
    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        yield
    finally:
        signal.signal(signal.SIGTERM, previous)


def execute(files: Mapping[str, Path | str], tools: Mapping[str, Path | str], output: Path | str, *,
            prepare: Callable[[Path], Sequence[StageSpec]],
            finalize: Callable[[Path, Mapping[str, StageRun]], Publication],
            name: str = "build", directories: Sequence[str] = (), timeout: float = 7200,
            cache: Path | str | None = None) -> Path:
    """Run a recipe against private input copies and publish all selected products together.

    prepare reads the snapshot and supplies exact ordered commands. finalize may
    transform products or write reports there, then selects files and a manifest;
    it does not publish. Input files remain unchanged. The executor owns cache
    checks, process-group cleanup, output locking, diagnostics and the final
    atomic symlink switch. Main-thread SIGTERM handling is scoped to this call;
    embedded worker threads retain the application's signal policy.
    """
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", name):
        raise ValueError("build name must be an identifier")
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError("timeout must be positive finite seconds")
    output = Path(output).absolute()
    output = output.parent.resolve() / output.name
    if output.is_symlink() and output.resolve().parent != output.parent / f".{output.name}-releases":
        raise ValueError(f"output is not a managed symlink: {output}")
    if output.exists() and not output.is_symlink():
        raise ValueError(f"output must be absent or a managed symlink: {output}")
    tools = {key: Path(path).absolute() for key, path in tools.items()}
    for tool in tools.values():
        if not tool.is_file() or not os.access(tool, os.X_OK):
            raise ValueError(f"missing executable: {tool}")
    for path in files:
        relative(path)
        if path in ("stderr.log", "time.json", "command.json", "execution-inputs.json"):
            raise ValueError(f"reserved snapshot input: {path}")
    for directory in directories:
        relative(directory, directory=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    cache = Path(cache or output.parent / ".xls-cache").resolve()
    attempts = cache / "attempts"
    attempts.mkdir(parents=True, exist_ok=True)
    with locked(output.parent / f".{output.name}.lock"), cancellation():
        attempt = Path(tempfile.mkdtemp(prefix=f"{name}-", dir=attempts))
        started = time.monotonic()
        runs: dict[str, StageRun] = {}
        run_report: dict[str, Any] = {"output": str(output), "attempt": str(attempt), "stages": {}}
        try:
            tool_hashes = {key: sha(path) for key, path in tools.items()}
            input_hashes = snapshot_files(files, attempt)
            for directory in directories:
                (attempt / directory).mkdir(parents=True, exist_ok=True)
            specs = specifications(prepare(attempt), input_hashes, tools)
            if any(sha(attempt / path) != digest for path, digest in input_hashes.items()):
                raise ValueError("recipe modified a frozen build input")
            save(attempt / "execution-inputs.json", {"files": input_hashes, "tools": tool_hashes, "stages": specs})
            logs = {}
            for spec in specs:
                label, artifact = spec["id"], spec["output"]
                run_report["active_stage"] = label
                result = stage(spec["cache"], tools[spec["tool"]], spec["arguments"],
                               dependency_hashes(spec["inputs"], attempt), attempt, artifact, cache, timeout)
                record: StageRun = {**result,
                    "original_time": json.loads((result["directory"] / "time.json").read_text()),
                    "command": json.loads((result["directory"] / "command.json").read_text()),
                    "planned_command": [str(tools[spec["tool"]]), *spec["arguments"]],
                    "output": artifact, "sha256": sha(attempt / artifact), "exit": 0}
                runs[label] = record
                run_report["stages"][label] = {key: str(value) if isinstance(value, Path) else value
                                                for key, value in record.items()}
                for suffix in ("stderr.log", "time.json", "command.json"):
                    path = f"{label}.{suffix}"
                    (attempt / path).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(result["directory"] / suffix, attempt / path)
                    logs[path] = path
            if {key: sha(path) for key, path in tools.items()} != tool_hashes:
                raise ValueError("compiler installation changed during build")
            run_report["active_stage"] = "finalize"
            publication = finalize(attempt, runs)
            if {key: sha(path) for key, path in tools.items()} != tool_hashes:
                raise ValueError("compiler installation changed during finalization")
            if any(sha(attempt / path) != digest for path, digest in input_hashes.items()):
                raise ValueError("recipe modified a frozen build input")
            manifest_name = relative(publication["manifest_name"])
            selected = {relative(destination): relative(source) for destination, source in publication["files"].items()}
            if (manifest_name in selected or manifest_name in logs or "completed.json" in selected or manifest_name == "completed.json"
                    or any(path in selected and selected[path] != source for path, source in logs.items())):
                raise ValueError("publication shadows its manifest, completion record or stage diagnostics")
            selected.update(logs)
            product_hashes = {destination: sha(attempt / source) for destination, source in selected.items() if destination not in logs}
            release_id = identity({"manifest": publication["manifest"], "files": product_hashes})
            releases = output.parent / f".{output.name}-releases"
            releases.mkdir(exist_ok=True)
            release = releases / release_id
            release_inputs = {"manifest": release_id}
            if not checked(release, release_inputs):
                pending = Path(tempfile.mkdtemp(prefix=".new-", dir=releases))
                snapshot_files({destination: attempt / source for destination, source in selected.items()}, pending)
                (pending / manifest_name).parent.mkdir(parents=True, exist_ok=True)
                save(pending / manifest_name, publication["manifest"])
                save(pending / "completed.json", {"inputs": release_inputs, "outputs": {
                    str(path.relative_to(pending)): sha(path) for path in pending.rglob("*") if path.is_file()}})
                if release.exists():
                    release.rename(release.with_name(f"{release.name}.damaged-{time.time_ns()}"))
                pending.rename(release)
            link = output.parent / f".{output.name}.publish-{os.getpid()}"
            try:
                link.symlink_to(os.path.relpath(release, output.parent))
                os.replace(link, output)
            finally:
                link.unlink(missing_ok=True)
            del run_report["active_stage"]
            del run_report["attempt"]
            run_report.update(status="complete", release=str(release))
            print(f"Published {output} -> {release_id[:12]}", flush=True)
            return release
        except BaseException as error:
            run_report.update(status="failed", error=str(error))
            print(f"Build failed; previous release retained. Diagnostics: {attempt}", flush=True)
            raise
        finally:
            run_report["elapsed_seconds"] = time.monotonic() - started
            save(output.parent / f"{output.name}.run.json", run_report)
            if run_report.get("status") == "complete":
                shutil.rmtree(attempt)



def checked_codegen_flags(value: Sequence[str]) -> list[str]:
    """Copy literal options without normalizing their order, repetitions or omitted schedule choices."""
    if isinstance(value, (str, bytes)) or not isinstance(value, Sequence):
        raise ValueError("codegen_flags must be a sequence of complete option strings")
    flags = list(value)
    if any(not isinstance(flag, str) or not flag.startswith("--") or "\0" in flag for flag in flags):
        raise ValueError("codegen_flags must be a sequence of complete option strings")
    owned = {"--ram_configurations", "--xc7_delay_table", "--module_name", "--output_verilog_path"}
    if any(flag.split("=", 1)[0] in owned for flag in flags):
        raise ValueError("codegen_flags contains compiler-owned RAM, table, module or output options")
    return flags


def with_delay_table(flags: list[str], table: bool) -> list[str]:
    """Bind the frozen table to the last selected model while preserving other literal option order."""
    models = [flag.split("=", 1)[1] for flag in flags if flag.startswith("--delay_model=")]
    model = models[-1] if models else None
    if (model == "xc7_7030") != table:
        raise ValueError("xc7_7030 requires a delay table; other models do not accept one")
    if not table:
        return flags
    # This is the flat adapter's historical position: before channel delays and II.
    position = next((index for index, flag in enumerate(flags)
                     if flag.startswith(("--additional_channel_delay_ps=", "--worst_case_throughput="))), len(flags))
    return [*flags[:position], "--xc7_delay_table=assets/xc7_delay_table.tsv", *flags[position:]]


def build(source: Path | str, xls_root: Path | str, output: Path | str, *,
          name: str | None = None, top: str = "Top", pipeline_stages: int = 1,
          initiation_interval: int | None = None,
          ram_configurations: str | Callable[[Path], str] | None = None,
          assets: Sequence[Path | str] = (), metadata: dict | Callable[[Path], dict] | None = None,
          timeout: float = 7200, cache: Path | str | None = None,
          delay_model: str = "unit", delay_table: Path | str | None = None,
          channel_delays: dict[str, int] | None = None,
          codegen_flags: Sequence[str] | Callable[[Path], Sequence[str]] | None = None,
          optimizer_pipeline: Path | str | None = None,
          finalize: Callable[[Path, dict[str, Any]], dict[str, Any]] | None = None) -> Path:
    """Adapt a prepared flat DSLX stage to the shared executor and familiar release layout.

    Without codegen_flags this adapter retains its input-flops-disabled,
    output-flops-enabled schedule. Literal flags (or a callback reading snapshot
    inputs) instead supply the entire schedule and cannot accompany nondefault
    legacy scheduling options. Their order, repetitions and omissions survive.
    RAM arguments and frozen delay-table paths remain adapter-owned. Optimizer
    pipelines and delay tables are snapshotted inputs of their consuming stages.
    finalize may transform products and add manifest metadata before publication;
    artifacts and RTL hashes are refreshed afterwards. Inputs remain frozen.
    """
    source, xls_root = Path(source).resolve(), Path(xls_root).resolve()
    if codegen_flags is not None:
        if pipeline_stages != 1 or initiation_interval is not None or delay_model != "unit" or channel_delays:
            raise ValueError("codegen_flags conflicts with legacy scheduling options")
        if not callable(codegen_flags):
            codegen_flags = checked_codegen_flags(codegen_flags)
    elif (delay_model == "xc7_7030") != (delay_table is not None):
        raise ValueError("xc7_7030 requires a delay table; other models do not accept one")
    name = name or source.stem
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise ValueError("output name must be an identifier")
    channel_delays = channel_delays or {}
    if any(not re.fullmatch(r"[A-Za-z_]\w*(?::(?:send|recv))?", channel)
           or type(value) is not int or value < 0 for channel, value in channel_delays.items()):
        raise ValueError("channel delays require channel[:send|recv] and a nonnegative integer")
    if pipeline_stages < 1 or (initiation_interval is not None and initiation_interval < 1):
        raise ValueError("pipeline stages and initiation interval must be positive")
    tools = {tool: xls_root / tool for tool in TOOLS}
    stdlib = xls_root / "xls/dslx/stdlib"
    if not (stdlib / "std.x").is_file():
        raise ValueError(f"missing XLS standard library: {stdlib}")
    sources = {path.name: path for path in sorted(source.parent.glob("*.x"))}
    if source.name not in sources:
        raise ValueError(f"missing DSLX source: {source}")
    stdlib_files = tree_files(stdlib, "_stdlib")
    asset_files = {Path(path).name: Path(path) for path in assets}
    if len(asset_files) != len(assets) or any(asset in sources for asset in asset_files):
        raise ValueError("duplicate asset names")
    if delay_table is not None:
        if "xc7_delay_table.tsv" in asset_files or "xc7_delay_table.tsv" in sources:
            raise ValueError("reserved delay table asset name")
        asset_files["xc7_delay_table.tsv"] = Path(delay_table).resolve()
    if optimizer_pipeline is not None:
        if "optimizer_pipeline.txtpb" in asset_files or "optimizer_pipeline.txtpb" in sources:
            raise ValueError("reserved optimizer pipeline asset name")
        asset_files["optimizer_pipeline.txtpb"] = Path(optimizer_pipeline).resolve()
    files = {**sources, **stdlib_files, **{f"assets/{asset}": path for asset, path in asset_files.items()}}
    prepared: dict[str, Any] = {}

    def prepare(snapshot: Path) -> list[StageSpec]:
        """Resolve options and metadata against frozen inputs before selecting stage dependencies."""
        source_hashes = {path: sha(snapshot / path) for path in sources}
        stdlib_hashes = {str(Path(path).relative_to("_stdlib")): sha(snapshot / path) for path in stdlib_files}
        asset_hashes = {asset: sha(snapshot / "assets" / asset) for asset in asset_files}
        extra = metadata(snapshot) if callable(metadata) else (metadata or {})
        convert = ["--warnings_as_errors=false", "--dslx_path=.", "--dslx_stdlib_path=_stdlib", f"--top={top}", source.name]
        if codegen_flags is None:
            codegen = [f"--pipeline_stages={pipeline_stages}", f"--delay_model={delay_model}", "--flop_inputs=false",
                       "--flop_outputs=true", "--use_system_verilog=false", "--reset=reset", "--fifo_module="]
            if channel_delays:
                codegen.append("--additional_channel_delay_ps=" + ",".join(
                    f"{channel}={value}" for channel, value in sorted(channel_delays.items())))
            if initiation_interval is not None:
                codegen.append(f"--worst_case_throughput={initiation_interval}")
        else:
            codegen = checked_codegen_flags(codegen_flags(snapshot) if callable(codegen_flags) else codegen_flags)
        codegen = with_delay_table(codegen, delay_table is not None)
        optimizer = ["--pipeline_textproto=assets/optimizer_pipeline.txtpb"] if optimizer_pipeline is not None else []
        rams = ram_configurations(snapshot) if callable(ram_configurations) else ram_configurations
        if rams is not None:
            codegen.append(f"--ram_configurations={rams}")
        prepared.update(sources=source_hashes, stdlib=stdlib_hashes, assets=asset_hashes, metadata=extra, codegen=codegen)
        if optimizer:
            prepared["optimizer"] = optimizer
        save(snapshot / "inputs.json", {**prepared, "tools": {tool: sha(path) for tool, path in tools.items()}, "convert": convert})
        optimization_inputs: dict[str, Dependency] = {f"{name}.ir": f"{name}.ir"}
        if optimizer_pipeline is not None:
            optimization_inputs["assets/optimizer_pipeline.txtpb"] = "assets/optimizer_pipeline.txtpb"
        dependencies: dict[str, Dependency] = {f"{name}.opt.ir": f"{name}.opt.ir"}
        if delay_table is not None:
            dependencies["assets/xc7_delay_table.tsv"] = "assets/xc7_delay_table.tsv"
        return [
            {"id": "ir", "cache": "ir", "tool": "ir_converter_main", "arguments": convert,
             "output": f"{name}.ir", "inputs": {"sources": {path: path for path in sources},
                "stdlib": {str(Path(path).relative_to("_stdlib")): path for path in stdlib_files}}},
            {"id": "opt", "cache": "opt", "tool": "opt_main", "arguments": [*optimizer, f"{name}.ir"],
             "output": f"{name}.opt.ir", "inputs": optimization_inputs},
            {"id": "codegen", "cache": "codegen", "tool": "codegen_main", "arguments": [*codegen, f"{name}.opt.ir"],
             "output": f"{name}.v", "inputs": dependencies}]

    def finish(snapshot: Path, runs: Mapping[str, StageRun]) -> Publication:
        """Retain the flat adapter's artifact schema without owning execution or publication."""
        artifacts = {run["output"]: sha(snapshot / run["output"]) for run in runs.values()}
        manifest = {"schema": 1, "recipe": RECIPE_VERSION, "tools": {tool: sha(path) for tool, path in tools.items()},
                    "sources": prepared["sources"], "stdlib": {f"xls/dslx/stdlib/{key}": value for key, value in prepared["stdlib"].items()},
                    "options": {"top": top, "codegen": prepared["codegen"]}, "assets": prepared["assets"],
                    "artifacts": artifacts, "rtl": {key: value for key, value in {**artifacts, **prepared["assets"]}.items() if key.endswith('.v')},
                    "stages": {label: run["key"] for label, run in runs.items()}}
        if "optimizer" in prepared:
            manifest["options"]["optimizer"] = prepared["optimizer"]
        if prepared["metadata"].keys() & manifest.keys():
            raise ValueError("application metadata shadows compiler manifest fields")
        manifest.update(prepared["metadata"])
        if finalize is not None:
            manifest = finalize(snapshot, manifest)
        manifest["artifacts"] = {artifact: sha(snapshot / artifact) for artifact in manifest["artifacts"]}
        manifest["assets"] = {asset: sha(snapshot / "assets" / asset) for asset in prepared["assets"]}
        manifest["rtl"] = {key: value for key, value in {**manifest["artifacts"], **manifest["assets"]}.items() if key.endswith('.v')}
        selected = {artifact: artifact for artifact in manifest["artifacts"]}
        for asset in prepared["assets"]:
            if asset in selected or asset == f"{name}.build.json":
                raise ValueError(f"asset shadows generated output: {asset}")
            selected[asset] = "assets/" + asset
        selected.update({"sources/" + path: path for path in sources})
        selected.update({"stdlib/" + str(Path(path).relative_to("_stdlib")): path for path in stdlib_files})
        return {"manifest_name": f"{name}.build.json", "manifest": manifest, "files": selected}

    return execute(files, tools, output, prepare=prepare, finalize=finish, name=name,
                   directories=("assets",), timeout=timeout, cache=cache)


def interrupted(signum: int, _frame: Any) -> None:
    """Turn handled process cancellation into the executor's cleanup path."""
    raise InterruptedError(f"build interrupted by signal {signum}")


def main() -> None:
    """Compile one prepared flat stage through the same executor used by bundle clients."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--name")
    parser.add_argument("--top", default="Top")
    parser.add_argument("--pipeline-stages", type=int, default=1)
    parser.add_argument("--initiation-interval", type=int)
    parser.add_argument("--ram-configurations")
    parser.add_argument("--delay-model", default="unit")
    parser.add_argument("--delay-table", type=Path)
    parser.add_argument("--optimizer-pipeline", type=Path)
    parser.add_argument("--asset", type=Path, action="append", default=[])
    parser.add_argument("--timeout", type=duration, default=7200)
    parser.add_argument("--cache", type=Path)
    args = vars(parser.parse_args())
    args["assets"] = args.pop("asset")
    build(**args)


if __name__ == "__main__":
    main()
