#!/usr/bin/env python3
"""Check window isolation and failure draining using the board's generated collector and actor fold."""
import argparse
import json
from pathlib import Path
import re

from backend_commands import digest, execute
from backend_paths import ROOT


def main() -> None:
    """Compile a small probe from a generated board source directory; retain its complete provenance."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('source', type=Path)
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    xls, source, stage = args.xls.resolve(), args.source.resolve(), args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=False)
    paths = list(source.glob('*.x')) + [ROOT/'apps/hls_fabric/test/xls/partition_reduction_probe.x',
        ROOT/'apps/hls_fabric/test/rtl/partition_reduction_tb.sv', Path(__file__)]
    paths += [xls/name for name in ('ir_converter_main', 'opt_main', 'codegen_main')]
    before = {str(p): digest(p) for p in paths}
    graph = (source/'device_0_graph.x').read_text()
    collector = re.search(r'proc (ReductionCollector\d+)<SLOT: u32> \{.*?^\}', graph, re.M | re.S)
    if collector is None or set(re.findall(r'frame_(\d+):', collector[0])) != {'0', '1', '2', '3'}:
        raise ValueError('expected a generated four-contributor collector')
    body = collector[0].replace(collector[1], 'ReductionCollector')
    probe = (ROOT/'apps/hls_fabric/test/xls/partition_reduction_probe.x').read_text().replace('// GENERATED_COLLECTOR', body)
    (stage/'reduction_probe.x').write_text(probe)
    execute([str(xls/'ir_converter_main'), '--top=Top', '--warnings_as_errors=false', f'--dslx_path={source}',
        f'--dslx_stdlib_path={xls/"xls/dslx/stdlib"}', 'reduction_probe.x'], stage, 'convert', output=stage/'probe.ir', timeout=120)
    execute([str(xls/'opt_main'), 'probe.ir'], stage, 'optimize', output=stage/'probe.opt.ir', timeout=120)
    execute([str(xls/'codegen_main'), '--pipeline_stages=2', '--delay_model=unit', '--flop_inputs=false',
        '--flop_outputs=true', '--use_system_verilog=false', '--reset=reset', '--fifo_module=',
        '--module_name=reduction_probe', 'probe.opt.ir'], stage, 'codegen', output=stage/'probe.v', timeout=120)
    execute(['iverilog', '-g2012', '-s', 'partition_reduction_tb', '-o', 'probe.vvp',
        str(ROOT/'apps/hls_fabric/test/rtl/partition_reduction_tb.sv'), 'probe.v'], stage, 'iverilog')
    execute(['vvp', 'probe.vvp'], stage, 'simulation')
    result = (stage/'simulation.log').read_text()
    if 'PASS:' not in result or before != {str(p): digest(p) for p in paths}:
        raise ValueError('probe failed or its inputs changed')
    (stage/'provenance.json').write_text(json.dumps({'inputs': before, 'rtl_sha256': digest(stage/'probe.v')}, indent=2)+'\n')
    print(result, end='')


if __name__ == '__main__':
    main()
