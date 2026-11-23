"""Select one compiled Erlang profile without changing the process environment."""
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def erlang_paths(profile: str, root: Path = ROOT, *, compiler: Path | None = None) -> list[Path]:
    """Return one built profile, preferring checkout beams over dependency beams.

    Require hls_fabric in that profile; never fall back to another build. Include
    fixture modules only for the test profile. An explicit compiler replaces that
    application with its matching built beams. Paths may contain spaces.
    """
    if not re.fullmatch(r"[A-Za-z0-9_-]+", profile):
        raise ValueError(f"invalid rebar profile: {profile!r}")
    base = root.absolute() / "_build" / profile
    if not (base / "lib/hls_fabric/ebin").is_dir():
        command = "rebar3 compile" if profile == "default" else f"rebar3 as {profile} compile"
        raise FileNotFoundError(f"missing {profile} backend build in {root}; run {command}")
    applications = built_applications(profile, root)
    if compiler is not None:
        applications["erl_hls"] = compiler_ebin(compiler, profile, root)
        applications["hls_runtime"] = compiler_runtime_ebin(compiler, profile, root)
    tests = [path.parent / "test" for path in applications.values()]
    return [*applications.values(), *([path for path in tests if path.is_dir()] if profile == "test" else [])]


def built_applications(profile: str, root: Path) -> dict[str, Path]:
    """Index one profile's application projections, preferring checkouts over fetched dependencies."""
    applications = {}
    base = root.absolute() / "_build" / profile
    for kind in ("lib", "checkouts"):
        for dependency in sorted((base / kind).glob("*")):
            candidates = [dependency / "ebin", *sorted(dependency.glob("apps/*/ebin"))]
            for path in candidates:
                if path.is_dir():
                    applications[path.parent.name] = path
    return applications


def application_directory(name: str, profile: str, root: Path = ROOT) -> Path:
    """Find one resolved application's build directory, including its priv/source links."""
    for path in erlang_paths(profile, root):
        if path.name == "ebin" and path.parent.name == name:
            return path.parent
    raise FileNotFoundError(f"missing {name} in compiled {profile} profile")


def compiler_ebin(public: Path, profile: str, root: Path = ROOT) -> Path:
    """Find matching beams in an application directory or its explicit standalone profile.

    A source-only override is rejected rather than combined with unrelated beams
    from the fabric dependency. Standalone checkout overrides retain precedence.
    """
    if not re.fullmatch(r"[A-Za-z0-9_-]+", profile):
        raise ValueError(f"invalid rebar profile: {profile!r}")
    public = public.resolve()
    candidates = [public / "ebin"]
    selected = built_applications(profile, root).get("erl_hls")
    if selected is not None and (selected.parent / "src").is_symlink() and \
            (selected.parent / "src").resolve() == (public / "src").resolve():
        candidates.append(selected)
    candidates += [public / "_build" / profile / "checkouts/erl_hls/ebin",
                   public / "_build" / profile / "lib/erl_hls/ebin"]
    for path in candidates:
        if path.is_dir():
            return path
    raise FileNotFoundError(f"missing {profile} compiler beams in {public}")


def compiler_runtime_ebin(public: Path, profile: str, root: Path = ROOT) -> Path:
    """Select runtime beams belonging to the explicit compiler build or its installed siblings.

    A checkout override replaces both compiler-owned applications. Never combine
    its compiler with the fabric dependency's unrelated runtime provider code.
    """
    public = public.resolve()
    base = public / "_build" / profile
    compiler_app = compiler_ebin(public, profile, root).parent
    candidates = [compiler_app.parent / "hls_runtime/ebin",
        compiler_app.parent / "hls_runtime/apps/hls_runtime/ebin",
        base / "checkouts/hls_runtime/ebin", base / "lib/hls_runtime/ebin",
        base / "lib/hls_runtime/apps/hls_runtime/ebin",
        public.parent / "hls_runtime/ebin",
        public.parent / "hls_runtime/apps/hls_runtime/ebin"]
    if public.name.startswith("erl_hls-"):
        candidates.extend(sorted(public.parent.glob("hls_runtime-*/ebin")))
    for path in candidates:
        if path.is_dir():
            return path
    raise FileNotFoundError(f"missing {profile} runtime beams for compiler {public}")


def erlang_environment(profile: str, root: Path = ROOT, *, compiler: Path | None = None) -> dict[str, str]:
    """Copy the environment with ERL_AFLAGS bound to this profile for one child.

    Replace inherited ERL_AFLAGS to avoid carrying another profile's code paths.
    Set VM options through ERL_FLAGS. The parent environment is unchanged.
    """
    paths = erlang_paths(profile, root, compiler=compiler)
    # ERTS parses backslash escapes outside quotes, unlike shell double quoting.
    escaped = ["".join("\\" + c if c.isspace() or c in "\\'\"" else c for c in str(path))
               for path in paths]
    return {**os.environ, "ERL_AFLAGS": "-pa " + " ".join(escaped)}


def erl_command(public: Path, expression: str, *arguments: str | Path, profile: str) -> list[str]:
    """Build a two-scheduler VM command with the selected compiler's matching beams."""
    paths = erlang_paths(profile, compiler=public)
    return ["erl", "+S", "2:2", "-noshell", "-pa", *map(str, paths),
            "-eval", expression, "-extra", *map(str, arguments)]


def debug_rtl(public: Path) -> list[Path]:
    """Return the compiler-owned RTL files for the ordinary actor debug transport."""
    return [public / "priv/rtl/debug" / name for name in
            ("hls_debug_frame_rx.v", "hls_debug_route.v", "hls_topology_debug.v", "hls_actor_snapshot.v")]
