"""Resolve and load one explicitly selected compiler without changing import paths."""
import hashlib
import importlib
import importlib.util
from pathlib import Path
import re
import sys
from types import ModuleType

from backend_paths import ROOT, application_directory


def compiler_root(profile: str, override: Path | None = None, root: Path = ROOT) -> Path:
    """Select an explicit compiler or the named rebar profile; never probe another profile.

    Resolution happens only when called. Environment variables do not override
    the caller. The selected compiler must provide the packaged Python tools.
    """
    if re.fullmatch(r"[A-Za-z0-9_-]+", profile) is None:
        raise ValueError(f"invalid rebar profile: {profile!r}")
    public = (Path(override) if override is not None else
              application_directory("erl_hls", profile, root)).resolve()
    return compiler_source_root(public)


def compiler_source_root(public: Path) -> Path:
    """Resolve sources through the selected app's own projection, never an unrelated checkout.

    Umbrella builds link src/priv/include into an application build directory but
    omit arbitrary tool directories. Keep that build directory for BEAM selection;
    source/tool lookup follows its authoritative src link. BEAM selection checks
    that same link before using the fabric profile's compiled application.
    """
    public = public.resolve()
    candidates = [public]
    if (public / "src").is_symlink():
        candidates.append((public / "src").resolve().parent)
    for source in candidates:
        standalone = source / "tools/erl_hls_tools/__init__.py"
        umbrella = source.parents[1] / "tools/erl_hls_tools/__init__.py"
        if (standalone.is_file() or
                (source.name == "erl_hls" and source.parent.name == "apps" and
                 (source / "src").is_dir() and umbrella.is_file())):
            return source
    raise FileNotFoundError(f"missing compiler application sources in {public}")


def compiler_tools_root(public: Path) -> Path:
    """Return the repository that owns the selected compiler's Python package."""
    source = compiler_source_root(public)
    candidates = [source, source.parents[1] if source.parent.name == "apps" else source]
    for root in candidates:
        if (root / "tools/erl_hls_tools/__init__.py").is_file():
            return root
    raise FileNotFoundError(f"missing compiler Python package for {source}")


def compiler_application(public: Path, name: str) -> Path:
    """Return one source application owned by the selected compiler umbrella.

    Current umbrellas keep compiler, communication and target resources in separate
    applications. A legacy standalone compiler may still carry those resources in
    its selected root; retain that fallback only when no umbrella application exists.
    """
    if name not in {"erl_hls", "hls_compile", "hls_fabric", "hls_target"}:
        raise ValueError(f"unsupported compiler application: {name!r}")
    source = compiler_source_root(public)
    repository = compiler_tools_root(source)
    candidate = repository / "apps" / name
    if candidate.is_dir():
        return candidate.resolve()
    if name == "erl_hls":
        return source
    if repository == source:
        return source
    raise FileNotFoundError(f"missing {name} resources for compiler {source}")


def compiler_resource(public: Path, name: str, *parts: str) -> Path:
    """Resolve a relative resource below one selected compiler application."""
    if not parts or any(not part or Path(part).is_absolute() or ".." in Path(part).parts
                        for part in parts):
        raise ValueError(f"invalid compiler resource path: {parts!r}")
    return compiler_application(public, name).joinpath(*parts)


def compiler_source(public: Path, name: str) -> Path:
    """Return a named compiler tool's authoritative source for loading or provenance."""
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) is None:
        raise ValueError(f"invalid compiler tool name: {name!r}")
    source = compiler_tools_root(public) / "tools/erl_hls_tools" / (name + ".py")
    if not source.is_file():
        raise FileNotFoundError(f"missing compiler tool: {source}")
    return source


def compiler_tool(public: Path, name: str) -> ModuleType:
    """Load a tool and its relative imports in a namespace unique to the compiler root.

    Packages are cached like ordinary imports. Distinct roots cannot share sibling
    modules; neither sys.path nor the process environment is changed.
    """
    source = compiler_source(public, name)
    package = source.parent
    namespace = "_erl_hls_tools_" + hashlib.sha256(str(package).encode()).hexdigest()
    if namespace not in sys.modules:
        spec = importlib.util.spec_from_file_location(namespace, package / "__init__.py",
            submodule_search_locations=[str(package)])
        if spec is None or spec.loader is None:
            raise ImportError(f"cannot load compiler package: {package}")
        module = importlib.util.module_from_spec(spec)
        sys.modules[namespace] = module
        try:
            spec.loader.exec_module(module)
        except BaseException:
            del sys.modules[namespace]
            raise
    return importlib.import_module(namespace + "." + name)
