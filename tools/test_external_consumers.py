#!/usr/bin/env python3
"""Build isolated runtime and compiler consumers from one umbrella Git revision."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
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
            raise RuntimeError("commit Stage 4 changes before qualifying same-revision consumers")
    return resolved


def dependency_config(root: Path, commit: str, applications: tuple[str, ...]) -> str:
    """Render Git-subdirectory dependencies that all resolve through one exact commit."""
    url = root.resolve().as_uri()
    rows = [
        f"    {{{name}, {{git_subdir, {json.dumps(url)}, "
        f"{{ref, {json.dumps(commit)}}}, {json.dumps(f'apps/{name}')}}}}}"
        for name in applications
    ]
    return "{erl_opts, [debug_info]}.\n{deps, [\n" + ",\n".join(rows) + "\n]}.\n"


def paths(project: Path) -> list[str]:
    """Return only the isolated consumer and dependency ebin directories."""
    directories = sorted((project / "_build" / "default" / "lib").glob("**/ebin"))
    if not directories:
        raise RuntimeError(f"consumer produced no application code paths: {project}")
    return [str(path) for path in directories]


def export_fixtures(stage: Path, root: Path, commit: str,
                    environment: dict[str, str]) -> Path:
    """Export consumer sources from the same immutable revision as their dependencies."""
    archive = stage / "external-consumers.tar"
    checked(
        ["git", "archive", "--format=tar", f"--output={archive}", commit,
         FIXTURE_PATH.as_posix()],
        root,
        environment,
    )
    exported = stage / "revision"
    exported.mkdir()
    with tarfile.open(archive) as bundle:
        base = exported.resolve()
        for member in bundle.getmembers():
            target = (exported / member.name).resolve()
            if not target.is_relative_to(base) or member.issym() or member.islnk():
                raise RuntimeError(f"unsafe consumer fixture archive entry: {member.name!r}")
        bundle.extractall(exported)
    return exported / FIXTURE_PATH


def qualify(kind: str, fixtures: Path, stage: Path, root: Path, commit: str,
            environment: dict[str, str]) -> None:
    """Compile and run one consumer with no umbrella build directory on its code path."""
    project = stage / kind
    shutil.copytree(fixtures / kind, project)
    (project / "rebar.config").write_text(
        dependency_config(root, commit, PROJECT_APPS[kind]), encoding="utf-8"
    )
    checked(["rebar3", "compile"], project, environment)
    code_paths = paths(project)
    forbidden = str((root / "_build").resolve())
    if any(Path(path).resolve().is_relative_to(forbidden) for path in code_paths):
        raise RuntimeError("consumer resolved an umbrella build-tree code path")
    module = f"stage4_{kind}_consumer"
    checked(
        ["erl", "+S", "2:2", "-noshell", "-pa", *code_paths, "-eval", f"ok={module}:witness(),halt(0)."],
        project,
        environment,
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
        environment.update(
            {
                "ERL_AFLAGS": "",
                "ERL_FLAGS": "+S 2:2",
                "ERL_LIBS": "",
                "REBAR_CACHE_DIR": str(stage / "rebar-cache"),
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "protocol.file.allow",
                "GIT_CONFIG_VALUE_0": "always",
            }
        )
        fixtures = export_fixtures(stage, root, commit, environment)
        for kind in ("runtime", "compile"):
            qualify(kind, fixtures, stage, root, commit, environment)
    print(f"Qualified runtime and compiler consumers at {commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
