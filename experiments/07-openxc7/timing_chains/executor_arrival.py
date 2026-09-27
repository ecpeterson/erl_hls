#!/usr/bin/env python3
"""Reschedule one stateless executor with a measured channel-arrival allowance."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from architecture import sha
from egress_experiment import ports
from schedule_report import analyze


def prepare(args: argparse.Namespace) -> None:
    """Preserve the surrounding RTL and require identical executor ports/stage count."""
    reference = args.reference
    manifest = json.loads((reference / 'phi_decoder_profile.build.json').read_text())
    rtl_path = reference / 'phi_decoder_profile.v'
    if sha(rtl_path) != manifest['rtl'][rtl_path.name]:
        raise ValueError('reference RTL differs from build manifest')
    records = json.loads((reference / 'commands.json').read_text())
    opt = next(r for r in records if r['label'] == 'opt')
    ir_path = reference / 'phi_decoder_profile.opt.ir'
    if opt['exit'] != 0 or sha(ir_path) != opt['output_sha256']:
        raise ValueError('optimized IR differs from recorded compilation')
    text = ir_path.read_text()
    match = re.search(r'^proc ' + re.escape(args.executor) + r'[^\n]*\{\n.*?^}', text, re.M | re.S)
    if match is None or 'state_read(' in match[0] or 'next_value(' in match[0]:
        raise ValueError('require one stateless executor')
    rtl = rtl_path.read_text()
    pattern = r'^module ' + re.escape(args.executor) + r'\(.*?^endmodule'
    original = re.search(pattern, rtl, re.M | re.S)
    if original is None:
        raise ValueError('executor module not found')
    args.stage.mkdir(parents=True, exist_ok=False)
    stage = args.stage
    (stage / 'executor.ir').write_text(text.split('\nproc ', 1)[0] + '\n\n' + match[0] + '\n')
    allowance = ('--additional_input_delay_ps=' + str(args.delay_ps) if args.symmetric else
                 '--additional_channel_delay_ps=' + args.channel + ':recv=' + str(args.delay_ps))
    command = [str(args.codegen), '--top=' + args.executor, '--pipeline_stages=2',
               '--delay_model=xc7_7030', '--xc7_delay_table=' + str(args.table),
               '--xc7_routed_delays=' + ('false' if args.cell_only else 'true'),
               '--flop_inputs=false', '--flop_outputs=true', '--use_system_verilog=false',
               '--reset=reset', '--worst_case_throughput=1', '--module_name=' + args.executor,
               '--output_schedule_path=schedule.textproto', '--output_schedule_ir_path=scheduled.ir',
               '--output_block_ir_path=block.ir', allowance, 'executor.ir']
    (stage / 'command.json').write_text(json.dumps(command, indent=2) + '\n')
    with (stage / 'executor.v').open('w') as out, (stage / 'codegen.log').open('w') as log:
        subprocess.run(command, cwd=stage, stdout=out, stderr=log, check=True, timeout=300)
    replacement = re.search(pattern, (stage / 'executor.v').read_text(), re.M | re.S)
    if replacement is None or ports(original[0]) != ports(replacement[0]):
        raise ValueError('executor interface changed')
    executor = replacement[0]
    kept = []
    if args.keep_product_inputs:
        declarations = set(re.findall(r'^  reg (?:\[[^\]]+\] )?(\w+);$', executor, re.M))
        for arguments in re.findall(r'= [su]mul\w*\(([^()]+)\);', executor):
            kept += [a.strip() for a in arguments.split(',') if a.strip() in declarations]
        kept = sorted(set(kept))
        if not kept:
            raise ValueError('no direct registered product operands to preserve')
        for name in kept:
            executor, count = re.subn(r'^  (reg (?:\[[^\]]+\] )?' + re.escape(name) + ';)$',
                                      r'  (* keep *) \1', executor, flags=re.M)
            if count != 1:
                raise ValueError('ambiguous product register declaration')
        (stage / 'executor.v').write_text(executor + '\n')
    changed = rtl[:original.start()] + executor + rtl[original.end():]
    if changed[:original.start()] != rtl[:original.start()] or not changed.endswith(rtl[original.end():]):
        raise AssertionError('non-executor RTL changed')
    for name in ('phi_decoder_profile_top.v', 'hls_1r1w_ram.v', 'phi_decoder_profile.json'):
        shutil.copyfile(reference / name, stage / name)
    (stage / rtl_path.name).write_text(changed)
    result = {'schema': 1, 'additional_delay_ps': args.delay_ps, 'symmetric_allowance': args.symmetric,
              'cell_only': args.cell_only, 'channel': args.channel, 'executor': args.executor,
              'kept_product_inputs': kept,
              'unchanged_other_modules': True, 'unchanged_ports': True,
              'command': command, 'inputs': {str(p): sha(p) for p in (rtl_path, ir_path, args.codegen, args.table)},
              'schedule': analyze((stage / 'scheduled.ir').read_text(),
                                  (stage / 'schedule.textproto').read_text(), re.escape(args.executor)),
              'outputs': {name: sha(stage / name) for name in
                          ('executor.v', rtl_path.name, 'scheduled.ir', 'schedule.textproto', 'block.ir')}}
    manifest['executor_arrival_experiment'] = result
    manifest['rtl'][rtl_path.name] = sha(stage / rtl_path.name)
    (stage / 'phi_decoder_profile.build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (stage / 'arrival.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'products': [(p['name'], p['stage']) for p in result['schedule'][0]['products']],
                      'stage_delays_ps': result['schedule'][0]['stage_delays_ps']}), flush=True)


def main() -> None:
    """Require a verified application, explicit tool/table and an unused output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'stage', 'codegen', 'table'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--executor', default='__phi_halo_cell__SharedExecutor_0_next')
    parser.add_argument('--channel', default='_request_in')
    parser.add_argument('--delay-ps', type=int, required=True)
    parser.add_argument('--symmetric', action='store_true', help='control: allowance applies at both channel directions')
    parser.add_argument('--cell-only', action='store_true', help='schedule with calibrated cell-only operation costs')
    parser.add_argument('--keep-product-inputs', action='store_true',
                        help='preserve direct product input registers in fabric for native timing coverage')
    args = parser.parse_args()
    if args.delay_ps < 0:
        parser.error('arrival allowance must be nonnegative')
    prepare(args)


if __name__ == '__main__':
    main()
