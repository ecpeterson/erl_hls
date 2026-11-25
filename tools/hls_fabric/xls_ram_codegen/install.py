#!/usr/bin/env python3
"""Install the pinned RAM-safe Linux code generator over its matching XLS release."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def digest(data: bytes) -> str:
    """Identify bytes independently of filenames or release labels."""
    return hashlib.sha256(data).hexdigest()


def replace(destination: Path, asset: Path, pin: dict) -> None:
    """Atomically replace only the expected upstream binary with verified bytes."""
    current = digest(destination.read_bytes())
    if current == pin['codegen_sha256']:
        return
    if current != pin['upstream_codegen_sha256']:
        raise ValueError('unexpected codegen_main; install the pinned upstream release first')
    compressed = asset.read_bytes()
    if digest(compressed) != pin['asset_sha256']:
        raise ValueError('RAM-safe codegen archive digest differs')
    binary = gzip.decompress(compressed)
    if digest(binary) != pin['codegen_sha256']:
        raise ValueError('RAM-safe codegen binary digest differs')
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(binary)
            stream.flush()
            temporary.chmod(0o755)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def main() -> None:
    """Install the verified code generator from its GitHub release or a supplied archive."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--asset', type=Path, help='use an already downloaded archive')
    args = parser.parse_args()
    pin = json.loads((HERE / 'manifest.json').read_text())
    if not pin['codegen_sha256'] or not pin['asset_sha256']:
        raise ValueError('toolchain build has not been pinned')
    destination = args.xls.resolve() / 'codegen_main'
    current = digest(destination.read_bytes())
    if current == pin['codegen_sha256']:
        print('RAM-safe XLS codegen already verified')
        return
    if current != pin['upstream_codegen_sha256']:
        raise ValueError('unexpected codegen_main; refusing to replace a different toolchain')
    with tempfile.TemporaryDirectory(prefix='xls-ram-codegen-') as stage:
        asset = args.asset
        if asset is None:
            subprocess.run(['gh', 'release', 'download', pin['asset_tag'],
                            '--repo', pin['asset_repository'], '--pattern', pin['asset_name'],
                            '--dir', stage], check=True, timeout=180)
            asset = Path(stage) / pin['asset_name']
        replace(destination, asset, pin)
    print('Installed verified XLS codegen with RAM-response reservation')


if __name__ == '__main__':
    main()
