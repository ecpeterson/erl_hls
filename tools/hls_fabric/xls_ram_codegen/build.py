#!/usr/bin/env python3
"""Rebuild the pinned Linux code generator and exercise its RAM-response fixes."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import urllib.request

HERE = Path(__file__).resolve().parent


def sha(path: Path) -> str:
    """Fingerprint an input or produced artifact."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch(url: str, path: Path, expected: str) -> None:
    """Reuse verified downloads and reject changed or incomplete files."""
    if not path.exists():
        temporary = path.with_suffix('.download')
        with urllib.request.urlopen(url, timeout=180) as response, temporary.open('wb') as stream:
            shutil.copyfileobj(response, stream)
        temporary.replace(path)
    if sha(path) != expected:
        raise ValueError(f'input digest differs: {path}')


def main() -> None:
    """Use a dedicated work directory; cache dependencies without editing installed tools."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('work', type=lambda p: Path(p).resolve())
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--memory-mb', type=int, default=18000)
    args = parser.parse_args()
    if args.jobs < 1 or args.memory_mb < 1024:
        parser.error('positive jobs and at least 1024 MiB required')
    pin = json.loads((HERE / 'manifest.json').read_text())
    inputs = {key: pin[key] for key in ('upstream_revision', 'source_sha256',
                                       'patch_sha256', 'bazel_sha256')}
    patch = HERE / 'ram-response.patch'
    if sha(patch) != pin['patch_sha256']:
        raise ValueError('patch digest differs')
    args.work.mkdir(parents=True, exist_ok=True)
    receipt = args.work / 'source-inputs.json'
    source = args.work / 'source'
    if receipt.exists():
        if json.loads(receipt.read_text()) != inputs:
            raise ValueError('work directory belongs to different source inputs')
    else:
        archive = args.work / 'source.tar.gz'
        fetch(pin['source_url'], archive, pin['source_sha256'])
        source.mkdir()
        # Extraction is restricted to a fresh directory and an exact trusted archive.
        subprocess.run(['tar', 'xzf', str(archive), '--strip-components=1', '-C', str(source)], check=True)
        with patch.open('rb') as stream:
            subprocess.run(['patch', '-p1', '--batch'], cwd=source, stdin=stream, check=True)
        receipt.write_text(json.dumps(inputs, indent=2) + '\n')
    bazel = args.work / 'bazel'
    fetch(pin['bazel_url'], bazel, pin['bazel_sha256'])
    bazel.chmod(0o755)
    flags = ['-c', 'opt', f'--jobs={args.jobs}', f'--local_ram_resources={args.memory_mb}']
    build = [str(bazel), 'build', *flags, '//xls/tools:codegen_main']
    tests = [str(bazel), 'test', *flags, '--test_output=errors',
             '--test_filter=*ReservesNextCycleRamResponse:*HeldReadIssuesOnceAfterResponseStall:'
             '*Held1RWRequestIssuesOnceAfterResponseStall:*PreservesTransactionsDuringOutputStalls*',
             '//xls/codegen:block_conversion_test', '//xls/codegen:ram_rewrite_pass_test']
    for name, command in (('build', build), ('test', tests)):
        with (args.work / f'{name}.log').open('w') as log:
            subprocess.run(command, cwd=source, stdout=log, stderr=subprocess.STDOUT, check=True)
    binary = source / 'bazel-bin/xls/tools/codegen_main'
    asset = args.work / pin['asset_name']
    asset.write_bytes(gzip.compress(binary.read_bytes(), mtime=0))
    result = inputs | {'commands': [build, tests], 'asset_sha256': sha(asset),
                       'codegen_sha256': sha(binary), 'recipe_sha256': sha(Path(__file__)),
                       'dependency_lock_sha256': sha(source / 'MODULE.bazel.lock')}
    (args.work / 'build.json').write_text(json.dumps(result, indent=2) + '\n')
    shutil.copy2(source / 'LICENSE', args.work / 'LICENSE.xls')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
