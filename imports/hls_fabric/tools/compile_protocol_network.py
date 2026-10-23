"""Compile a fresh source-initialized network using the transport's sampled-clock schedule."""
from pathlib import Path
import argparse
import json

from backend_paths import ROOT, PUBLIC
from compile_protocol_transport import compile_clock, digest


def compile_network(xls: Path, directory: Path, imports: list[Path] | None = None) -> None:
    """Check direct source identities before lowering; preserve commands, products and provenance.

    Input manifests are trusted local build records, not untrusted deployment data.
    Extra imports resolve source-provider modules and must match the source build.
    The result is an executable RTL network, not application or device admission.
    """
    manifest = verify_network(directory)
    stage = directory/'network'
    source = stage/'network.x'
    paths = [stage, directory/'actors', directory/'dslx', ROOT/'priv/xls/lib', ROOT/'priv/xls/fabric',
             PUBLIC/'priv/xls/lib', PUBLIC/'priv/xls/fabric', *(imports or [])]
    compile_clock(xls, source, stage, 'network_clock', 'protocol_network_core', paths)
    rtl = [stage/'core.v', stage/'protocol_network.sv']
    with (directory/'files.f').open('x') as listing:
        listing.write(''.join(str(p.resolve())+'\n' for p in rtl))
    manifest['rtl'] = [{'file':str(p), 'sha256':digest(p)} for p in rtl]
    manifest['dslx_path'] = list(map(str, paths))
    manifest['xls_tools'] = {n:digest(xls/n) for n in ['ir_converter_main','opt_main','codegen_main']}
    manifest['schedule'] = {'pipeline_stages':1, 'flop_inputs':False, 'flop_outputs':False,
                            'channel_handshakes':'always_enabled_clock_samples'}
    manifest['native_measured'] = False
    (stage/'compiled.json').write_text(json.dumps(manifest, indent=2)+'\n')


def verify_network(directory: Path) -> dict:
    """Check this trusted generated network and all direct component identities before lowering."""
    stage = directory/'network'
    manifest = json.loads((stage/'manifest.json').read_text())
    source = stage/'network.x'
    if manifest['dslx_sha256'] != digest(source):
        raise ValueError('changed network source')
    for component in manifest['components']:
        if digest(directory/component['file']) != component['sha256']:
            raise ValueError('changed network component: '+component['file'])
    return manifest


def main() -> None:
    """Use the caller's XLS distribution and optional ordinary source-provider search paths."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--dslx-path', type=Path, action='append', default=[])
    args = parser.parse_args()
    compile_network(args.xls.resolve(), args.directory.resolve(), [p.resolve() for p in args.dslx_path])


if __name__ == '__main__':
    main()
