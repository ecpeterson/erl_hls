"""Compile a fresh source application, reusing the boundary and shared ordered gateway schedules."""
from pathlib import Path
import argparse
import json
import subprocess
from backend_paths import ROOT
from compiler_paths import PUBLIC
from compile_protocol_boundary import compile_boundary
from compile_protocol_transport import digest


def compile_application(xls: Path, directory: Path, imports: list[Path] | None = None) -> None:
    """Check emitted application inputs, compile once, and retain commands and exact RTL dependencies.

    Manifests/deployment are trusted local build records; attachment is not authentication.
    Boundary uses clock samples; the shared gateway uses its qualified two-stage channel schedule.
    """
    stage=directory/'application'
    manifest=json.loads((stage/'manifest.json').read_text())
    for row in manifest['inputs']:
        if digest(directory/row['file'])!=row['sha256']:
            raise ValueError('changed application input: '+row['file'])
    compile_boundary(xls,directory,imports)
    paths=[ROOT/'priv/xls',ROOT/'priv/xls/lib',PUBLIC/'priv/xls/lib',PUBLIC/'priv/xls/fabric',*(imports or [])]
    commands=[
        ('convert',[xls/'ir_converter_main','--top=Top','--warnings_as_errors=false',
            '--dslx_path='+':'.join(map(str,paths)), '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),stage/'gateway.x'],stage/'raw.ir'),
        ('opt',[xls/'opt_main',stage/'raw.ir'],stage/'optimized.ir'),
        ('codegen',[xls/'codegen_main','--pipeline_stages=2','--delay_model=unit','--flop_inputs=false',
            '--flop_outputs=true','--use_system_verilog=false','--reset=reset','--fifo_module=',
            '--module_name=application_gateway',stage/'optimized.ir'],stage/'gateway.v')]
    records=[]
    for label,command,output in commands:
        with (stage/(label+'.log')).open('x') as log, output.open('x') as target:
            result=subprocess.run(list(map(str,command)),stdout=target,stderr=log,timeout=300)
        records.append({'command':list(map(str,command)),'exit':result.returncode,'output':str(output),'sha256':digest(output)})
        (stage/'commands.json').write_text(json.dumps(records,indent=2)+'\n')
        if result.returncode:raise RuntimeError((stage/(label+'.log')).read_text()[-4000:])
    rtl=[stage/'gateway.v',stage/'protocol_application_top.sv',ROOT/'priv/rtl/hls_partition_activation.sv']
    if manifest['inspection'] != 'none':
        rtl += [PUBLIC/'priv/rtl/debug'/name for name in ['hls_debug_route.v','hls_debug_frame_rx.v','hls_topology_debug.v']]
    with (directory/'files.f').open('a') as listing:listing.write(''.join(str(p.resolve())+'\n' for p in rtl))
    all_rtl=[Path(p) for p in (directory/'files.f').read_text().splitlines()]
    manifest.update(rtl=[{'file':str(p),'sha256':digest(p)} for p in all_rtl],
        boundary={'file':str(directory/'boundary/compiled.json'),'sha256':digest(directory/'boundary/compiled.json')},
        gateway_dependencies=[{'file':str(p),'sha256':digest(p)} for p in
            [ROOT/'priv/xls/hls_partition_io.x',ROOT/'priv/xls/lib/protocol_framing.x',
             ROOT/'priv/xls/lib/protocol_rectangle.x',PUBLIC/'priv/xls/lib/axis.x',PUBLIC/'priv/xls/fabric/hls_spatial_router.x']],
        native_measured=False,eligible=False)
    (stage/'compiled.json').write_text(json.dumps(manifest,indent=2)+'\n')


def main() -> None:
    """Use the caller's XLS distribution and source-provider import directories."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=Path);parser.add_argument('directory',type=Path)
    parser.add_argument('--dslx-path',type=Path,action='append',default=[])
    args=parser.parse_args()
    compile_application(args.xls.resolve(),args.directory.resolve(),[p.resolve() for p in args.dslx_path])


if __name__=='__main__':main()
