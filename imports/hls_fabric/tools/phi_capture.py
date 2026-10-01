"""Bound the disk footprint of cycle captures without discarding observations."""
from collections.abc import Iterator
from contextlib import contextmanager
import json
import os
from pathlib import Path
import subprocess

from test_actor_rtl import digest


@contextmanager
def compressed_capture(path: Path, enabled: bool = True) -> Iterator[None]:
    """Stream a producer's FIFO into gzip; publish the recording only after successful completion.

    The caller must close its producer before leaving the context. Failed runs retain
    a .partial file for diagnosis; readers never mistake it for a complete capture.
    """
    if not enabled:
        yield
        return
    output = path.with_suffix(path.suffix+'.gz')
    partial = output.with_suffix(output.suffix+'.partial')
    if path.exists() or output.exists() or partial.exists():
        raise FileExistsError(f'capture already exists: {path}')
    os.mkfifo(path)
    reader = keeper = None
    process = None
    try:
        reader = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        keeper = os.open(path, os.O_WRONLY | os.O_NONBLOCK)
        os.set_blocking(reader, True)
        with partial.open('xb') as stream:
            process = subprocess.Popen(['gzip', '-1', '-n', '-c'], stdin=reader, stdout=stream)
        os.close(reader)
        reader = None
        yield
        os.close(keeper)
        keeper = None
        if process.wait(timeout=30):
            raise RuntimeError('cycle capture compression failed')
        partial.rename(output)
    finally:
        for descriptor in (reader, keeper):
            if descriptor is not None:
                os.close(descriptor)
        if process is not None and process.poll() is None:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        path.unlink()


def prune_simulation(stage: Path) -> None:
    """Discard a successful capture's checked simulation executable and payload-observer RTL.

    Preserve recordings, manifests, provenance, logs and the independently compiled
    device cache. Call only after the simulation and its witness checks have passed.
    """
    inputs = json.loads((stage/'profile-inputs.json').read_text())
    selected = {stage/'profile.vvp': inputs['vvp_sha256']}
    for name, expected in inputs['hardware_sources'].items():
        path = Path(name)
        if path.parent.parent == stage/'message-rtl' and path.name == 'instrumented.v':
            selected[path] = expected
    for path, expected in selected.items():
        if path.is_symlink() or digest(path) != expected:
            raise ValueError(f'simulation intermediate changed: {path}')
    record = {str(path.relative_to(stage)): expected for path, expected in selected.items()}
    (stage/'discarded-intermediates.json').write_text(json.dumps(record, indent=2)+'\n')
    for path in selected:
        path.unlink()
