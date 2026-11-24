#!/usr/bin/env python3
"""List the complete Erlang host-source payload for portable bridge execution."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOST_SOURCE_ROOTS = (
    Path("apps/hls_core/src"),
    Path("apps/hls_runtime/src/api"),
    Path("apps/hls_runtime/src/runtime"),
)
ADDITIONAL_SOURCES = (Path("apps/erl_hls/src/examples/regsvc/regsvc.erl"),)


def source_paths(root: Path = ROOT) -> list[Path]:
    """Return every core source plus the runtime layers used by the portable bridge."""
    paths = []
    for relative in HOST_SOURCE_ROOTS:
        directory = root / relative
        if not directory.is_dir():
            raise ValueError(f"missing portable host source root: {relative}")
        paths.extend(path.relative_to(root) for path in directory.rglob("*.erl"))
    for relative in ADDITIONAL_SOURCES:
        if not (root / relative).is_file():
            raise ValueError(f"missing portable host source: {relative}")
        paths.append(relative)
    result = sorted(paths)
    modules = [path.stem for path in result]
    if len(modules) != len(set(modules)):
        raise ValueError("duplicate module in portable host source payload")
    return result


def main() -> None:
    """Print repository-relative source paths for the shell bundle writer."""
    print("\n".join(map(str, source_paths())))


if __name__ == "__main__":
    main()
