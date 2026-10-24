"""Select one compiled Erlang profile without changing the process environment."""
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def erlang_paths(profile: str, root: Path = ROOT) -> list[Path]:
    """Return one built profile, preferring checkout beams over dependency beams.

    Require hls_fabric in that profile; never fall back to another build. Include
    fixture modules only for the test profile. Paths may contain spaces.
    """
    if not re.fullmatch(r"[A-Za-z0-9_-]+", profile):
        raise ValueError(f"invalid rebar profile: {profile!r}")
    base = root.absolute() / "_build" / profile
    if not (base / "lib/hls_fabric/ebin").is_dir():
        command = "rebar3 compile" if profile == "default" else f"rebar3 as {profile} compile"
        raise FileNotFoundError(f"missing {profile} backend build in {root}; run {command}")
    applications = {}
    for kind in ("lib", "checkouts"):
        for path in sorted((base / kind).glob("*/ebin")):
            applications[path.parent.name] = path
    tests = base / "lib/hls_fabric/test"
    return [*applications.values(), *([tests] if profile == "test" and tests.is_dir() else [])]


def erlang_environment(profile: str, root: Path = ROOT) -> dict[str, str]:
    """Copy the environment with ERL_AFLAGS bound to this profile for one child.

    Replace inherited ERL_AFLAGS to avoid carrying another profile's code paths.
    Set VM options through ERL_FLAGS. The parent environment is unchanged.
    """
    paths = erlang_paths(profile, root)
    # ERTS parses backslash escapes outside quotes, unlike shell double quoting.
    escaped = ["".join("\\" + c if c.isspace() or c in "\\'\"" else c for c in str(path))
               for path in paths]
    return {**os.environ, "ERL_AFLAGS": "-pa " + " ".join(escaped)}


def erl_command(public: Path, expression: str, *arguments: str | Path, profile: str) -> list[str]:
    """Build a two-scheduler VM command for one profile and optional built compiler override."""
    paths = erlang_paths(profile)
    if (public / "ebin").is_dir():
        paths = [public / "ebin", *paths]
    return ["erl", "+S", "2:2", "-noshell", "-pa", *map(str, paths),
            "-eval", expression, "-extra", *map(str, arguments)]
