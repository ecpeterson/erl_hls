#!/usr/bin/env python3
"""Archive completed measurements without bulky Vivado checkpoints or duplicate EDIF."""
import argparse
import io
import json
from pathlib import Path
import tarfile


def collect(corpus: Path, output: Path, operations: list[str] | None) -> None:
    """Require every selected probe to finish; preserve source and audit evidence."""
    manifest = json.loads((corpus / 'manifest.json').read_text())
    rows = [row for row in manifest['probes'] if operations is None or row.get('op') in operations]
    if not rows:
        raise ValueError('empty measurement selection')
    for row in rows:
        log = corpus / row['name'] / 'vivado/console.log'
        if not log.is_file() or 'CHARACTERIZATION_COMPLETE' not in log.read_text():
            raise ValueError(f"incomplete measurement: {row['name']}")
    manifest['probes'] = rows
    with tarfile.open(output, 'w:gz') as archive:
        content = (json.dumps(manifest, indent=2) + '\n').encode()
        info = tarfile.TarInfo('manifest.json')
        info.size = len(content)
        archive.addfile(info, io.BytesIO(content))
        for row in rows:
            root = corpus / row['name']
            for path in sorted(root.rglob('*')):
                if path.is_file() and path.suffix not in ('.dcp', '.edf') and '.Xil' not in path.parts:
                    archive.add(path, arcname=str(path.relative_to(corpus)))


def main() -> None:
    """Collect a full corpus or an explicitly selected pilot subset."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('corpus', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--ops', nargs='+')
    args = parser.parse_args()
    collect(args.corpus, args.output, args.ops)


if __name__ == '__main__':
    main()
