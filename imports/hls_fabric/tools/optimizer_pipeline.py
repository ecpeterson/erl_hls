"""Freeze an explicit XLS optimization pipeline without editing its tool installation."""
from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile

from compiler_paths import compiler_root, compiler_source, compiler_tool


def prepare(xls: Path, pipeline: Path, cache: Path, *, public: Path | None = None,
            profile: str = "default") -> tuple[Path, Path, dict[str, str]]:
    """Return a checked tool overlay, retained pipeline and provenance for one configuration.

    The original optimizer must support --pipeline_textproto. No default policy is
    inferred, and modified cached tools/configurations are rejected before reuse.
    Compiler helpers come from public or the explicitly named rebar profile.
    """
    public = compiler_root(profile, public)
    compiler = compiler_tool(public, "compile_xls")
    xls = xls.resolve()
    cache = cache.resolve()
    if (xls / "optimizer_pipeline.txtpb").exists():
        raise ValueError("optimizer pipeline overlays cannot be nested")
    optimizer = (xls / "opt_main").resolve()
    data = pipeline.read_bytes()
    policy = {"optimizer_pipeline_sha256": hashlib.sha256(data).hexdigest(),
              "optimizer_executable_sha256": compiler.sha(optimizer)}
    wrapper = "\n".join([
        "#!/usr/bin/env python3",
        '"""Execute the recorded optimizer and pipeline only while their bytes match."""',
        "import hashlib, os, sys",
        "from pathlib import Path",
        f"optimizer = Path({str(optimizer)!r})",
        "pipeline = Path(__file__).resolve().with_name('optimizer_pipeline.txtpb')",
        f"pins = [(optimizer, {policy['optimizer_executable_sha256']!r}),",
        f"        (pipeline, {policy['optimizer_pipeline_sha256']!r})]",
        "for path, expected in pins:",
        "    with path.open('rb') as stream:",
        "        if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:",
        "            raise SystemExit('optimizer input changed: ' + str(path))",
        "os.execv(str(optimizer), [str(optimizer), '--pipeline_textproto=' + str(pipeline), *sys.argv[1:]])",
        "",
    ])
    links = {name: (xls / name).resolve() for name in ("ir_converter_main", "codegen_main", "xls")}
    if any(not path.exists() for path in links.values()):
        raise ValueError("incomplete XLS tool bundle")
    signature = {"wrapper": wrapper, "links": {name: str(path) for name, path in links.items()},
                 "cache_helpers": compiler.sha(compiler_source(public, "compile_xls"))}
    cache.mkdir(parents=True, exist_ok=True)
    output = cache / compiler.identity(signature)
    with compiler.locked(cache / (output.name + ".lock")):
        if not output.exists():
            with tempfile.TemporaryDirectory(prefix="pipeline-", dir=cache) as temporary:
                staged = Path(temporary) / "content"
                staged.mkdir()
                (staged / "optimizer_pipeline.txtpb").write_bytes(data)
                executable = staged / "opt_main"
                executable.write_text(wrapper)
                executable.chmod(0o755)
                for name, target in links.items():
                    (staged / name).symlink_to(target)
                staged.rename(output)
        if (output / "opt_main").read_text() != wrapper or (output / "optimizer_pipeline.txtpb").read_bytes() != data:
            raise ValueError("cached optimizer pipeline changed; preserve it and use a fresh cache")
        if any(not (output / name).is_symlink() or (output / name).resolve() != target
               for name, target in links.items()):
            raise ValueError("cached optimizer tool links changed")
    return output, output / "optimizer_pipeline.txtpb", policy
