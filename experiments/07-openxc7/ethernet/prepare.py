"""Provide hash-checked HDL generator sources without installing Python packages."""

import hashlib
import io
import json
import os
import tarfile
import tempfile
import urllib.request
from pathlib import Path


def digest(path: Path) -> str:
    """Return a file's SHA-256 identity."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def environment(cache: Path, unpacked: Path) -> dict[str, str]:
    """Download about 4 MB once and return an isolated generator import path.

    Archives are rechecked and unpacked afresh on each invocation; edited cached
    source trees cannot silently change the generated circuit. Python 3.12+
    supplies the safe tar extraction filter. No pip, venv or global install.
    """
    lock = json.loads(Path(__file__).with_name("sources.lock.json").read_text())
    cache.mkdir(parents=True, exist_ok=True)
    roots = []
    for name, pin in lock.items():
        archive = cache / f"{name}.tar.gz"
        if not archive.exists():
            with urllib.request.urlopen(pin["url"], timeout=45) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != pin["sha256"]:
                raise ValueError(f"archive SHA-256 mismatch: {name}")
            with tempfile.NamedTemporaryFile(dir=cache, delete=False) as temporary:
                temporary.write(data)
                temporary_path = Path(temporary.name)
            temporary_path.replace(archive)
        if digest(archive) != pin["sha256"]:
            raise ValueError(f"cached archive SHA-256 mismatch: {name}")
        # A fresh directory also avoids stale Python bytecode after source edits.
        target = unpacked / name
        target.mkdir(parents=True, exist_ok=False)
        with tarfile.open(fileobj=io.BytesIO(archive.read_bytes())) as source:
            # This helper extracts only regular source files, never links/devices.
            for member in source.getmembers():
                if member.isfile():
                    source.extract(member, target, filter="data")
        roots.append(target / f"{name}-{pin['revision']}")
    return {**os.environ, "PYTHONPATH": os.pathsep.join(map(str, roots)), "PYTHONDONTWRITEBYTECODE": "1"}
