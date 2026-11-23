#!/usr/bin/env python3
"""Build only the final patched native GTX backend from verified local inputs.

Run under an external process-tree memory/time guard with no concurrent heavy job.
This script does not fetch inputs, rebuild the chip database, run tests, route a
design, or establish physical correctness. Existing output directories reject.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import posixpath
import shutil
import subprocess
import tarfile
import time
from pathlib import Path, PurePosixPath


PINNED_RECIPE = Path(__file__).with_name("offline-recipe.json")


def digest(path: Path) -> str:
    """Hash with bounded buffers instead of reading a whole artifact into RAM."""
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def record(path: Path, value: dict) -> None:
    """Write one compact evidence artifact without overwriting another phase."""
    with path.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def freeze(entry: dict, directory: Path) -> Path:
    """Copy a pinned input and verify the bytes that the build will consume."""
    target = directory / basename(entry["name"])
    if target.exists():
        raise ValueError(f"duplicate frozen input: {target.name}")
    shutil.copyfile(entry["path"], target)
    actual = digest(target)
    if actual != entry["sha256"]:
        raise ValueError(f"input mismatch: {entry['name']} {actual}")
    return target


def basename(name: str) -> str:
    """Reject output names that could escape or collide with a frozen input directory."""
    if (not isinstance(name, str) or not name or name in (".", "..") or
            Path(name).name != name or "/" in name or "\\" in name):
        raise ValueError(f"expected a plain input filename: {name!r}")
    return name


def load_recipe(path: Path) -> dict:
    """Resolve caller paths while requiring the qualified source pins and patch order."""
    manifest = json.loads(path.read_text())
    pinned = json.loads(PINNED_RECIPE.read_text())
    for key in ("schema", "upstream_revision", "source_directory", "patched_sources", "execution"):
        if manifest.get(key) != pinned[key]:
            raise ValueError(f"recipe differs from qualified settings: {key}")
    names = []
    for key in ("archives", "patches"):
        entries = manifest[key]
        expected = [(e["name"], e["sha256"]) for e in pinned[key]]
        if [(e["name"], e["sha256"]) for e in entries] != expected:
            raise ValueError(f"wrong {key} pins or order")
        for entry in entries:
            names.append(basename(entry["name"]))
            entry["path"] = str((path.parent / entry["path"]).resolve(strict=True))
    if len(names) != len(set(names)):
        raise ValueError("duplicate input basename")
    if set(manifest["tools"]) != set(pinned["tools"]):
        raise ValueError("unexpected native tool set")
    for key, value in manifest["tools"].items():
        manifest["tools"][key] = str((path.parent / value).resolve(strict=True))
    return manifest


def extract(archive: Path, root: str, directory: Path) -> Path:
    """Extract under one declared root, rejecting traversal and escaping archive links."""
    basename(root)
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle.getmembers():
            name = PurePosixPath(member.name)
            if name.is_absolute() or ".." in name.parts or not name.parts or name.parts[0] != root:
                raise ValueError(f"unexpected archive member: {member.name}")
            if member.issym() or member.islnk():
                target = (name.parent / member.linkname if member.issym()
                          else PurePosixPath(member.linkname))
                normalized = PurePosixPath(posixpath.normpath(str(target)))
                if normalized.is_absolute() or not normalized.parts or normalized.parts[0] != root:
                    raise ValueError(f"archive link escapes declared root: {member.name}")
            elif not (member.isfile() or member.isdir()):
                raise ValueError(f"unsupported archive member: {member.name}")
        bundle.extractall(directory, filter="data")
    source = directory / root
    if not source.is_dir() or source.is_symlink():
        raise ValueError(f"archive did not produce a directory: {root}")
    return source


def run_step(name: str, command: list[str], cwd: Path, output: Path,
             environment: dict[str, str]) -> dict:
    """Run serially in the guard's process group; the guard owns tree-wide timeouts."""
    started = time.monotonic()
    log = output / (name + ".log")
    print(json.dumps({"phase": name, "state": "starting"}), flush=True)
    with log.open("x") as stream:
        process = subprocess.run(command, cwd=cwd, env=environment, stdout=stream,
                                 stderr=subprocess.STDOUT, check=False)
    result = {"phase": name, "argv": command, "cwd": str(cwd),
              "elapsed_seconds": time.monotonic() - started,
              "returncode": process.returncode, "log": log.name}
    record(output / (name + ".json"), result)
    if process.returncode:
        raise RuntimeError(f"{name} failed with exit {process.returncode}; see {log}")
    print(json.dumps({"phase": name, "state": "finished",
                      "elapsed_seconds": result["elapsed_seconds"]}), flush=True)
    return result


def build(recipe: Path, output: Path) -> dict:
    """Verify, patch and build one final target; the external guard owns memory bounds."""
    manifest = load_recipe(recipe)
    # Existence rejects rather than resuming an uncertain or failed prior build.
    output.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    try:
        inputs = output / "inputs"
        inputs.mkdir()
        record(output / "recipe.json", manifest)
        shutil.copyfile(__file__, output / "build-script.py")
        source_identity = digest(Path(__file__))
        recipe_identity = digest(recipe)
        shutil.copyfile(PINNED_RECIPE, output / "pinned-recipe.json")
        pin_identity = digest(PINNED_RECIPE)
        archive_paths = {entry["name"]: freeze(entry, inputs)
                         for entry in manifest["archives"]}
        patch_paths = [freeze(entry, inputs) for entry in manifest["patches"]]
        source = extract(archive_paths["nextpnr.tar.gz"], manifest["source_directory"], output)
        eigen = extract(archive_paths["eigen.tar.gz"], "eigen-3.4.0", output)
        pkgconfig = output / "pkgconfig"
        pkgconfig.mkdir()
        (pkgconfig / "eigen3.pc").write_text(
            f"prefix={eigen}\nName: Eigen3\nDescription: Eigen headers\n"
            "Version: 3.4.0\nCflags: -I${prefix}\n")
        environment = os.environ.copy()
        environment.update({"PKG_CONFIG_PATH": str(pkgconfig), "MAKEFLAGS": "-j1",
                            "MFLAGS": "-j1", "CMAKE_BUILD_PARALLEL_LEVEL": "1"})
        tools = manifest["tools"]
        for tool in ("cmake", "make", "patch", "cc", "cxx", "pkg_config"):
            if not os.access(tools[tool], os.X_OK):
                raise ValueError(f"unavailable pinned tool: {tool}: {tools[tool]}")
        if not Path(tools["boost"]).is_dir():
            raise ValueError("unavailable pinned Boost installation")
        tool_identities = {name: digest(Path(tools[name]))
                           for name in ("cmake", "make", "patch", "cc", "cxx", "pkg_config")}
        phases = []
        for index, path in enumerate(patch_paths, 1):
            phases.append(run_step(f"patch-{index}",
                [tools["patch"], "-f", "-p1", "-i", str(path)], source, output,
                environment))
        patched = {name: digest(source / name) for name in manifest["patched_sources"]}
        record(output / "patched-sources.json", patched)
        native = output / "native-build"
        configure = [tools["cmake"], "-S", str(source), "-B", str(native),
            "-G", "Unix Makefiles", "-DARCH=xilinx", "-DBUILD_GUI=OFF",
            "-DBUILD_PYTHON=OFF", "-DBUILD_TESTS=OFF", "-DUSE_OPENMP=OFF",
            "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
            "-DCMAKE_POLICY_DEFAULT_CMP0167=OLD", f"-DBOOST_ROOT={tools['boost']}",
            f"-DCMAKE_MAKE_PROGRAM={tools['make']}", f"-DCMAKE_C_COMPILER={tools['cc']}",
            f"-DCMAKE_CXX_COMPILER={tools['cxx']}", f"-DPKG_CONFIG_EXECUTABLE={tools['pkg_config']}",
            "-DCURRENT_GIT_VERSION=68aeeb39-gtx-carry-head-offline"]
        phases.append(run_step("configure", configure, output, output, environment))
        phases.append(run_step("compile", [tools["cmake"], "--build", str(native),
            "--target", "nextpnr-xilinx", "--parallel", "1"], output, output,
            environment))
        binary = native / "nextpnr-xilinx"
        destination = output / "bin"
        destination.mkdir()
        published = destination / "nextpnr-gtx"
        shutil.copy2(binary, published)
        binary_hash = digest(binary)
        if digest(published) != binary_hash:
            raise ValueError("published binary mismatch")
        for entry in manifest["archives"] + manifest["patches"]:
            if digest(inputs / entry["name"]) != entry["sha256"]:
                raise ValueError(f"frozen input changed during build: {entry['name']}")
        if (digest(Path(__file__)) != source_identity or digest(recipe) != recipe_identity or
                digest(PINNED_RECIPE) != pin_identity or
                digest(output / "build-script.py") != source_identity or
                digest(output / "pinned-recipe.json") != pin_identity):
            raise ValueError("build controls changed during execution")
        if any(digest(Path(tools[name])) != value for name, value in tool_identities.items()):
            raise ValueError("native tool changed during build")
        result = {"success": True, "recipe_sha256": digest(output / "recipe.json"),
                  "script_sha256": digest(output / "build-script.py"), "phases": phases,
                  "pinned_recipe_sha256": pin_identity, "requested_recipe_sha256": recipe_identity,
                  "tool_sha256": tool_identities,
                  "elapsed_seconds": time.monotonic() - started,
                  "binary": str(published), "binary_bytes": published.stat().st_size,
                  "binary_sha256": binary_hash, "patched_sources": patched,
                  "parallel_compilers": 1, "tests_run": False,
                  "hardware_qualified": False, "timing_qualified": False,
                  "peak_memory_bytes": None,
                  "limits": "Fresh tool build only; guard supplies resource evidence. No historical binary identity, native semantics, image fit or physical behavior is claimed."}
        record(output / "result.json", result)
        return result
    except Exception as failure:
        record(output / "failure.json", {"success": False, "error": repr(failure),
            "elapsed_seconds": time.monotonic() - started,
            "policy": "Preserve this directory; do not silently resume or overwrite."})
        raise


def main() -> None:
    """Require an explicit fresh output directory; callers supply the outer resource guard."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    result = build(arguments.recipe.resolve(strict=True), arguments.output.resolve())
    print(json.dumps({key: result[key] for key in
        ("success", "binary", "binary_sha256", "elapsed_seconds")}), flush=True)


if __name__ == "__main__":
    main()
