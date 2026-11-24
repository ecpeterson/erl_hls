#!/usr/bin/env python3
"""Build isolated runtime and compiler consumers from exact umbrella releases."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_PATH = Path("tools/fixtures/external_consumers")
PROJECT_APPS = {
    "runtime": ("hls_core", "hls_runtime"),
    "compile": (
        "hls_core",
        "hls_runtime",
        "hls_compile",
        "hls_fabric",
        "hls_target",
        "erl_hls",
    ),
}
RELEASES = {"runtime": "hls_runtime", "compile": "erl_hls"}
CONSUMERS = {"runtime": "hls_runtime_consumer", "compile": "erl_hls_compile_consumer"}


def checked(command: list[str], cwd: Path, environment: dict[str, str]) -> str:
    """Run one bounded consumer command and retain complete diagnostics on failure."""
    result = subprocess.run(
        command,
        cwd=cwd,
        env=environment,
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode:
        raise RuntimeError(
            f"consumer command failed ({result.returncode}): {command!r}\n"
            f"{result.stdout}{result.stderr}"
        )
    return result.stdout


def revision(root: Path, requested: str | None) -> str:
    """Resolve an immutable commit; a symbolic or dirty working tree is never packaged."""
    value = requested or checked(
        ["git", "rev-parse", "HEAD"], root, os.environ.copy()
    ).strip()
    resolved = checked(
        ["git", "rev-parse", f"{value}^{{commit}}"], root, os.environ.copy()
    ).strip()
    if requested is None:
        dirty = checked(
            ["git", "status", "--porcelain", "--untracked-files=no"],
            root,
            os.environ.copy(),
        )
        if dirty:
            raise RuntimeError("commit changes before qualifying same-revision consumers")
    return resolved


def consumer_paths(project: Path) -> list[str]:
    """Return only the isolated consumer application's ebin directory."""
    directories = sorted((project / "_build" / "default" / "lib").glob("*/ebin"))
    if not directories:
        raise RuntimeError(f"consumer produced no application code paths: {project}")
    return [str(path) for path in directories]


def release_paths(release: Path) -> list[str]:
    """Return the installed release closure without consulting a development build tree."""
    directories = sorted((release / "lib").glob("*/ebin"))
    if not directories:
        raise RuntimeError(f"release produced no application code paths: {release}")
    return [str(path) for path in directories]


def checkout(stage: Path, root: Path, commit: str,
             environment: dict[str, str]) -> Path:
    """Create one detached clean checkout at the exact requested revision."""
    exported = stage / "revision"
    checked(
        ["git", "clone", "--quiet", "--no-checkout", str(root), str(exported)],
        stage,
        environment,
    )
    checked(["git", "checkout", "--quiet", "--detach", commit], exported, environment)
    actual = checked(["git", "rev-parse", "HEAD^{commit}"], exported, environment).strip()
    if actual != commit:
        raise RuntimeError(f"revision checkout mismatch: {actual} != {commit}")
    if checked(["git", "status", "--porcelain"], exported, environment):
        raise RuntimeError("exact revision checkout is unexpectedly dirty")
    return exported


def project_applications(release: Path, known: set[str]) -> set[str]:
    """Read project application identities from installed application resources."""
    applications = []
    for ebin in (release / "lib").glob("*/ebin"):
        applications.extend(path.stem for path in ebin.glob("*.app"))
    project = [name for name in applications if name in known]
    if len(project) != len(set(project)):
        raise RuntimeError(f"release contains duplicate project applications: {sorted(project)}")
    return set(project)


def build_releases(source: Path, environment: dict[str, str]) -> dict[str, Path]:
    """Build both canonical consumption closures once from the clean exact checkout."""
    known = {
        path.parent.parent.name
        for path in (source / "apps").glob("*/src/*.app.src")
    }
    for name in ("erl_hls", "hls_runtime"):
        checked(["rebar3", "release", "-n", name], source, environment)
    releases = {
        kind: source / "_build" / "default" / "rel" / name
        for kind, name in RELEASES.items()
    }
    for kind, release in releases.items():
        paths = release_paths(release)
        if any(Path(path).is_relative_to(ROOT / "_build") for path in paths):
            raise RuntimeError("release resolved the invoking checkout's build tree")
        actual = project_applications(release, known)
        expected = set(PROJECT_APPS[kind])
        if actual != expected:
            raise RuntimeError(
                f"{kind} release project closure mismatch: {sorted(actual)} != {sorted(expected)}"
            )
    return releases


def qualify(kind: str, fixtures: Path, release: Path, stage: Path, root: Path,
            environment: dict[str, str]) -> None:
    """Compile and run one consumer using only its exact installed release closure."""
    project = stage / "consumers" / kind
    shutil.copytree(fixtures / kind, project)
    consumer_environment = environment | {"ERL_LIBS": str(release / "lib")}
    checked(["rebar3", "compile"], project, consumer_environment)
    code_paths = consumer_paths(project) + release_paths(release)
    forbidden = str((root / "_build").resolve())
    if any(Path(path).resolve().is_relative_to(forbidden) for path in code_paths):
        raise RuntimeError("consumer resolved an umbrella build-tree code path")
    checked(
        ["erl", "+S", "2:2", "-noshell", "-pa", *code_paths, "-eval",
         f"ok={CONSUMERS[kind]}:witness(),halt(0)."],
        project,
        consumer_environment,
    )


def main() -> int:
    """Qualify both external package shapes at one immutable umbrella commit."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--revision", help="exact commit or ref; permits an unrelated dirty checkout")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    commit = revision(root, arguments.revision)
    with tempfile.TemporaryDirectory(prefix="erl-hls-external-consumers-") as temporary:
        stage = Path(temporary)
        environment = os.environ.copy()
        environment.update({
            "ERL_AFLAGS": "",
            "ERL_FLAGS": "+S 2:2",
            "ERL_LIBS": "",
            "REBAR_CACHE_DIR": str(stage / "rebar-cache"),
        })
        source = checkout(stage, root, commit, environment)
        releases = build_releases(source, environment)
        fixtures = source / FIXTURE_PATH
        for kind in ("runtime", "compile"):
            qualify(kind, fixtures, releases[kind], stage, root, environment)
    print(f"Qualified runtime and compiler release consumers at {commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
