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


def fix_config_pulses(source: Path) -> None:
    """Require fresh received configuration words for each PCS negotiation event.

    The pinned PCS latches both PulseSynchronizer inputs high until reset. Clear
    them each cycle before the conditional assignments, so link loss cannot
    renegotiate using events left over from the previous connection.
    """
    old = "        self.sync.eth_rx += [\n            If(self.rx.seen_config_reg,"
    new = ("        self.sync.eth_rx += [\n"
           "            rx_config_reg_abi.i.eq(0),\n"
           "            rx_config_reg_ack.i.eq(0),\n"
           "            If(self.rx.seen_config_reg,")
    text = source.read_text()
    if text.count(old) != 1:
        raise ValueError("pinned PCS configuration-event source changed; review the local fix")
    source.write_text(text.replace(old, new))


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
        source_root = target / f"{name}-{pin['revision']}"
        if name == "liteeth":
            fix_config_pulses(source_root / "liteeth/phy/pcs_1000basex.py")
        roots.append(source_root)
    return {**os.environ, "PYTHONPATH": os.pathsep.join(map(str, roots)), "PYTHONDONTWRITEBYTECODE": "1"}
