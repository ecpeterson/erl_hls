"""Lower a fresh source-network application boundary with the shared sampled-clock schedule."""
from pathlib import Path
import argparse
import json
from backend_paths import ROOT, PUBLIC
from compile_protocol_network import verify_network
from compile_protocol_transport import compile_clock, digest


def compile_boundary(xls: Path, directory: Path, imports: list[Path] | None = None) -> None:
    """Verify trusted generated inputs and retain exact compiler/RTL provenance; no admission implied."""
    network=verify_network(directory)
    stage=directory/'boundary';source=stage/'boundary.x'
    manifest=json.loads((stage/'manifest.json').read_text())
    if digest(source)!=manifest['dslx_sha256']:raise ValueError('changed boundary source')
    paths=[directory/'network',directory/'actors',directory/'dslx',ROOT/'priv/xls/lib',ROOT/'priv/xls/fabric',
           PUBLIC/'priv/xls/lib',PUBLIC/'priv/xls/fabric',*(imports or [])]
    compile_clock(xls,source,stage,'boundary_clock','protocol_boundary_core',paths)
    rtl=[stage/'core.v',stage/'protocol_boundary.sv']
    with (directory/'files.f').open('x') as handle:
        handle.write(''.join(str(p.resolve())+'\n' for p in rtl))
    manifest.update(network=network,rtl=[{'file':str(p),'sha256':digest(p)} for p in rtl],
        dslx_path=list(map(str,paths)),xls_tools={n:digest(xls/n) for n in ['ir_converter_main','opt_main','codegen_main']},
        schedule={'pipeline_stages':1,'flop_inputs':False,'flop_outputs':False,'channel_handshakes':'always_enabled_clock_samples'},
        native_measured=False)
    (stage/'compiled.json').write_text(json.dumps(manifest,indent=2)+'\n')


def main() -> None:
    """Use the caller's XLS distribution and ordinary provider search paths."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=Path);parser.add_argument('directory',type=Path)
    parser.add_argument('--dslx-path',type=Path,action='append',default=[])
    args=parser.parse_args()
    compile_boundary(args.xls.resolve(),args.directory.resolve(),[p.resolve() for p in args.dslx_path])


if __name__=='__main__':main()
