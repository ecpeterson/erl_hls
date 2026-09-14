#!/usr/bin/env python3
"""Compile a prepared flat DSLX stage, reusing checked intermediates.

The output is a symlink to a complete immutable release. Resolve it once before
reading several artifacts. Failed attempts leave the previous release in place.
"""
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
import time

TOOLS = ("ir_converter_main", "opt_main", "codegen_main")
RECIPE_VERSION = 1


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def identity(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def save(path, value):
    path = Path(path)
    pending = path.with_name(path.name + ".new")
    pending.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    os.replace(pending, path)


def duration(value):
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([smh]?)", str(value))
    if not match or not math.isfinite(float(match[1])) or float(match[1]) <= 0:
        raise argparse.ArgumentTypeError("timeout must be positive seconds or a duration such as 5m or 2h")
    return float(match[1]) * {"": 1, "s": 1, "m": 60, "h": 3600}[match[2]]


@contextmanager
def locked(path, wait=False):
    with path.open("a") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | (0 if wait else fcntl.LOCK_NB))
        except BlockingIOError:
            raise ValueError(f"build already active: {path}; use a separate output directory") from None
        yield


def checked(directory, inputs):
    try:
        result = json.loads((directory / "completed.json").read_text())
        return (result["inputs"] == inputs and isinstance(result["outputs"], dict) and bool(result["outputs"]) and
                all(sha(directory / name) == digest for name, digest in result["outputs"].items()))
    except (OSError, ValueError, KeyError, TypeError):
        return False



def cached_artifact(directory):
    # The stdout file is the one compiler product; its destination basename
    # does not affect conversion and may differ between callers sharing a cache.
    outputs = json.loads((directory / "completed.json").read_text())["outputs"]
    artifact, = outputs.keys() - {"stderr.log", "time.json", "command.json"}
    return directory / artifact


def run(argv, work, output, timeout):
    """Wait for this child specifically, retaining its own CPU and peak RSS."""
    started = time.monotonic()
    (work / "time.json").unlink(missing_ok=True)
    with (work / output).open("wb") as stdout, (work / "stderr.log").open("wb") as stderr:
        process = subprocess.Popen(argv, cwd=work, stdout=stdout, stderr=stderr,
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
            # Kill the process group, including compiler helpers, before returning
            # ownership of this attempt's files to a retry.
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
    if process.returncode:
        raise RuntimeError(f"compiler exited {process.returncode}: {work / 'stderr.log'}")
    if not (work / output).stat().st_size:
        raise ValueError(f"compiler produced empty {output}")
    return metrics


def snapshot_files(files, target):
    result = {}
    for name, source in files.items():
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        result[name] = sha(destination)
    return result


def stage(label, tool, arguments, inputs, work, output, cache, timeout):
    key = {"recipe": RECIPE_VERSION, "host": [platform.system(), platform.machine()],
           "tool": sha(tool), "arguments": arguments, "inputs": inputs}
    entry = cache / label / identity(key)
    entry.parent.mkdir(parents=True, exist_ok=True)
    if checked(entry, key):
        print(f"{label}: reused {entry.name[:12]}", flush=True)
        shutil.copyfile(cached_artifact(entry), work / output)
        return {"key": entry.name, "reused": True, "adopted": False, "execution_time": None, "directory": entry}
    print(f"{label}: compiling {entry.name[:12]}", flush=True)
    save(work / "command.json", [str(tool), *arguments])
    metrics = run([str(tool), *arguments], work, output, timeout)
    if sha(tool) != key["tool"]:
        raise ValueError(f"compiler changed during {label}")
    # Two independent outputs may compute the same cache entry. Serialize only
    # publication; complete entries are never partially overwritten.
    adopted = False
    with locked(entry.parent / f"{entry.name}.lock", wait=True):
        if not checked(entry, key):
            pending = Path(tempfile.mkdtemp(prefix=".new-", dir=entry.parent))
            for name in (output, "stderr.log", "time.json", "command.json"):
                shutil.copyfile(work / name, pending / name)
            save(pending / "completed.json", {"inputs": key, "outputs": {
                name: sha(pending / name) for name in (output, "stderr.log", "time.json", "command.json")}})
            if entry.exists():
                # Preserve a damaged entry for diagnosis; never trust a stamp
                # whose output hashes no longer match.
                entry.rename(entry.with_name(f"{entry.name}.damaged-{time.time_ns()}"))
            pending.rename(entry)
        elif sha(cached_artifact(entry)) != sha(work / output):
            # XLS can choose different internal node IDs on identical inputs.
            # Pin the first completed result and feed those exact bytes to the
            # next stage; never mix a losing output with the winner's provenance.
            shutil.copyfile(cached_artifact(entry), work / output)
            adopted = True
            print(f"{label}: adopted concurrently published {entry.name[:12]}", flush=True)
    return {"key": entry.name, "reused": False, "adopted": adopted, "execution_time": metrics, "directory": entry}


def build(source, xls_root, output, *, name=None, top="Top", pipeline_stages=1,
          initiation_interval=None, ram_configurations=None, assets=(), metadata=None,
          timeout=7200, cache=None):
    source, xls_root = Path(source).resolve(), Path(xls_root).resolve()
    # Resolve the parent, not the published symlink itself.
    output = Path(output).absolute()
    output = output.parent.resolve() / output.name
    name = name or source.stem
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise ValueError("output name must be an identifier")
    if pipeline_stages < 1 or (initiation_interval is not None and initiation_interval < 1):
        raise ValueError("pipeline stages and initiation interval must be positive")
    if output.is_symlink() and output.resolve().parent != output.parent / f".{output.name}-releases":
        raise ValueError(f"output is not a managed symlink: {output}")
    if output.exists() and not output.is_symlink():
        raise ValueError(f"output must be absent or a managed symlink: {output}")
    tools = {tool: xls_root / tool for tool in TOOLS}
    for tool in tools.values():
        if not tool.is_file() or not os.access(tool, os.X_OK):
            raise ValueError(f"missing executable: {tool}")
    stdlib = xls_root / "xls/dslx/stdlib"
    if not (stdlib / "std.x").is_file():
        raise ValueError(f"missing XLS standard library: {stdlib}")
    output.parent.mkdir(parents=True, exist_ok=True)
    cache = Path(cache or output.parent / ".xls-cache").resolve()
    attempts = cache / "attempts"
    attempts.mkdir(parents=True, exist_ok=True)
    with locked(output.parent / f".{output.name}.lock"):
        attempt = Path(tempfile.mkdtemp(prefix=f"{name}-", dir=attempts))
        started = time.monotonic()
        runs = {}
        run_report = {"output": str(output), "attempt": str(attempt), "stages": runs}
        try:
            sources = {p.name: p for p in sorted(source.parent.glob("*.x"))}
            if source.name not in sources:
                raise ValueError(f"missing DSLX source: {source}")
            source_hashes = snapshot_files(sources, attempt)
            stdlib_files = {str(p.relative_to(stdlib)): p for p in sorted(stdlib.rglob("*.x"))}
            stdlib_hashes = snapshot_files(stdlib_files, attempt / "_stdlib")
            asset_files = {Path(p).name: Path(p) for p in assets}
            if len(asset_files) != len(assets) or any(n in sources for n in asset_files):
                raise ValueError("duplicate asset names")
            asset_hashes = snapshot_files(asset_files, attempt / "assets")
            tool_hashes = {tool: sha(path) for tool, path in tools.items()}
            extra = metadata(attempt) if callable(metadata) else (metadata or {})
            convert = ["--warnings_as_errors=false", "--dslx_path=.", "--dslx_stdlib_path=_stdlib",
                       f"--top={top}", source.name]
            codegen = [f"--pipeline_stages={pipeline_stages}", "--delay_model=unit", "--flop_inputs=false",
                       "--flop_outputs=true", "--use_system_verilog=false", "--reset=reset", "--fifo_module="]
            if initiation_interval is not None:
                codegen.append(f"--worst_case_throughput={initiation_interval}")
            if callable(ram_configurations):
                ram_configurations = ram_configurations(attempt)
            if ram_configurations is not None:
                codegen.append(f"--ram_configurations={ram_configurations}")
            save(attempt / "inputs.json", {"sources": source_hashes, "stdlib": stdlib_hashes,
                 "tools": tool_hashes, "convert": convert, "codegen": codegen,
                 "assets": asset_hashes, "metadata": extra})
            specifications = [
                ("ir", "ir_converter_main", convert, f"{name}.ir"),
                ("opt", "opt_main", [f"{name}.ir"], f"{name}.opt.ir"),
                ("codegen", "codegen_main", [*codegen, f"{name}.opt.ir"], f"{name}.v")]
            inputs = {"sources": source_hashes, "stdlib": stdlib_hashes}
            for label, tool, arguments, artifact in specifications:
                run_report["active_stage"] = label
                result = stage(label, tools[tool], arguments, inputs, attempt, artifact, cache, timeout)
                runs[label] = {"key": result["key"], "reused": result["reused"],
                               "execution_time": result["execution_time"], "adopted": result["adopted"],
                               "original_time": json.loads((result["directory"] / "time.json").read_text())}
                for filename in ("stderr.log", "time.json", "command.json"):
                    shutil.copyfile(result["directory"] / filename, attempt / f"{label}.{filename}")
                inputs = {artifact: sha(attempt / artifact)}
            if {tool: sha(path) for tool, path in tools.items()} != tool_hashes:
                raise ValueError("compiler installation changed during build")
            artifacts = {artifact: sha(attempt / artifact) for _, _, _, artifact in specifications}
            manifest = {"schema": 1, "recipe": RECIPE_VERSION, "tools": tool_hashes,
                        "sources": source_hashes, "stdlib": {f"xls/dslx/stdlib/{n}": h for n, h in stdlib_hashes.items()},
                        "options": {"top": top, "codegen": codegen}, "assets": asset_hashes,
                        "artifacts": artifacts, "rtl": {n: h for n, h in {**artifacts, **asset_hashes}.items() if n.endswith('.v')},
                        "stages": {label: r["key"] for label, r in runs.items()}}
            if extra.keys() & manifest.keys():
                raise ValueError("application metadata shadows compiler manifest fields")
            manifest.update(extra)
            release_id = identity(manifest)
            releases = output.parent / f".{output.name}-releases"
            releases.mkdir(exist_ok=True)
            release = releases / release_id
            release_inputs = {"manifest": release_id}
            if not checked(release, release_inputs):
                pending = Path(tempfile.mkdtemp(prefix=".new-", dir=releases))
                for artifact in artifacts:
                    shutil.copyfile(attempt / artifact, pending / artifact)
                for asset in asset_hashes:
                    if asset in artifacts or asset == f"{name}.build.json":
                        raise ValueError(f"asset shadows generated output: {asset}")
                    shutil.copyfile(attempt / "assets" / asset, pending / asset)
                snapshot_files({n: attempt / n for n in sources}, pending / "sources")
                shutil.copytree(attempt / "_stdlib", pending / "stdlib")
                for label in runs:
                    for suffix in ("stderr.log", "time.json", "command.json"):
                        shutil.copyfile(attempt / f"{label}.{suffix}", pending / f"{label}.{suffix}")
                save(pending / f"{name}.build.json", manifest)
                save(pending / "completed.json", {"inputs": release_inputs, "outputs": {
                    str(p.relative_to(pending)): sha(p) for p in pending.rglob("*") if p.is_file()}})
                if release.exists():
                    release.rename(release.with_name(f"{release.name}.damaged-{time.time_ns()}"))
                pending.rename(release)
            # Keep the temporary link beside its destination: --cache may be
            # on another filesystem, where renaming a link would fail.
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


def interrupted(signum, _frame):
    raise InterruptedError(f"build interrupted by signal {signum}")


def main():
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--name")
    parser.add_argument("--top", default="Top")
    parser.add_argument("--pipeline-stages", type=int, default=1)
    parser.add_argument("--initiation-interval", type=int)
    parser.add_argument("--ram-configurations")
    parser.add_argument("--asset", type=Path, action="append", default=[])
    parser.add_argument("--timeout", type=duration, default=7200)
    parser.add_argument("--cache", type=Path)
    args = vars(parser.parse_args())
    args["assets"] = args.pop("asset")
    build(**args)


if __name__ == "__main__":
    main()
