#!/usr/bin/env python3
"""Reproduce isolated architecture variants from a checked small-core source bundle."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent


def sha(path: Path) -> str:
    """Fingerprint an input or result without retaining duplicate build trees."""
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def dedicated_template(reduction: bool) -> str:
    """Bind the dedicated actor to generated ordinary or aggregate-only callbacks."""
    text = (HERE / 'dedicated_actor.template.x').read_text()
    values = dict(AGGREGATE_FIELD='', AGGREGATE_ARGUMENT='', AGGREGATE_VALUE='',
                  INTERNAL='false', RECEIVE_AGGREGATE='let aggregate_tok = join(); let aggregate_valid = false;',
                  AGGREGATE_REQUEST='', AGGREGATE_DEMUX='', AGGREGATE_CHANNELS='',
                  AGGREGATE_ZERO='', AGGREGATE_ONE='')
    if reduction:
        values.update(
            AGGREGATE_FIELD='aggregate: chan<ReductionAggregateRequest> in;',
            AGGREGATE_ARGUMENT=', aggregate: chan<ReductionAggregateRequest> in',
            AGGREGATE_VALUE=', aggregate',
            INTERNAL='state.machine.reduction.status == ReductionStatus::COMPLETE',
            RECEIVE_AGGREGATE='''let (aggregate_tok, aggregate_request, aggregate_valid) = recv_if_non_blocking(
      join(), aggregate, !failed && !internal && !entry, zero!<ReductionAggregateRequest>());''',
            AGGREGATE_REQUEST='internal, aggregate_request, aggregate_valid,',
            AGGREGATE_DEMUX='''// Preserve the original collector and dispatch each aggregate by its actor slot.
proc DedicatedAggregateIngress {
  input: chan<ReductionAggregateRequest> in;
  outputs: chan<ReductionAggregateRequest>[2] out;
  // Aggregate membership and values are unchanged by demultiplexing.
  config(input: chan<ReductionAggregateRequest> in,
         outputs: chan<ReductionAggregateRequest>[2] out) { (input, outputs) }
  // This adapter retains no application state.
  init { () }
  // A blocked destination retains the received aggregate until acceptance.
  next(state: ()) {
    let (tok, request) = recv(join(), input);
    let _done = unroll_for! (i, tok): (u32, token) in u32:0..u32:2 {
      send_if(tok, outputs[i], request.slot == i, request)
    }(tok);
    state
  }
}''',
            AGGREGATE_CHANNELS='''let (aggregate_p, aggregate_c) =
      chan<ReductionAggregateRequest, u32:1>[2]("dedicated_aggregate");
    spawn DedicatedAggregateIngress(aggregate, aggregate_p);''',
            AGGREGATE_ZERO=', aggregate_c[u32:0]',
            AGGREGATE_ONE=', aggregate_c[u32:1]')
    for key, value in values.items():
        text = text.replace('@' + key + '@', value)
    if '@' in text:
        raise ValueError('unbound template placeholder')
    return text


def replace_once(text: str, old: str, new: str) -> str:
    """Reject source drift rather than silently applying an incomplete experiment."""
    if text.count(old) != 1:
        raise ValueError(f'expected one occurrence: {old[:100]}')
    return text.replace(old, new)


def prepare(args: argparse.Namespace) -> None:
    """Copy source inputs, apply one explicit variant, and record their identities."""
    profile = json.loads((args.reference / 'phi_decoder_profile.json').read_text())
    if (profile['width'], profile['height'], profile['planes'], profile['scheduler_count']) != (2, 1, ['x', 'z'], 4):
        raise ValueError('this experiment requires the two-plane 2x1/four-group reference')
    args.stage.mkdir(parents=True, exist_ok=False)
    for source in args.reference.glob('*.x'):
        shutil.copyfile(source, args.stage / source.name)
    for name in ('phi_decoder_profile_top.v', 'hls_1r1w_ram.v', 'phi_decoder_profile.json'):
        shutil.copyfile(args.reference / name, args.stage / name)
    topology = args.stage / 'phi_decoder_profile_topology.x'
    if args.variant == 'dedicated':
        text = topology.read_text()
        # Memory channels are the only external interfaces removed. Keep every
        # original startup, reduction plane, router and effect-window instance.
        for i, module in enumerate(('phi_syndrome_replay_cell',) * 2 + ('phi_halo_cell',) * 2):
            pattern = rf'spawn {module}::SharedService<\s*u32:2, u32:2, u32:2, u32:{i}>\(.*?;'
            replacement = f'''spawn {module}::DedicatedGroup(
      scheduler_{i}_requests_c, scheduler_{i}_startup_c, scheduler_{i}_egress_p'''
            replacement += f', scheduler_{i}_aggregate_c);' if i >= 2 else ');'
            text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
            if count != 1:
                raise ValueError(f'missing shared group {i}')
        text = re.sub(r'^.*scheduler_\d+_(?:ram|mailbox)_(?:read|write)_(?:req_out|resp_in).*\n', '', text, flags=re.M)
        text = replace_once(text, '      z_decoder_events_out\n    );\n  }',
                            '      z_decoder_events_out\n    );\n    (x_decoder_events_out, z_decoder_events_out)\n  }')
        topology.write_text(text)
        for module, reduction in (('phi_halo_cell', True), ('phi_syndrome_replay_cell', False)):
            source = args.stage / (module + '.x')
            source.write_text(source.read_text() + '\n' + dedicated_template(reduction))
        wrapper = (args.stage / 'phi_decoder_profile_top.v').read_text()
        header = wrapper[:wrapper.index(');') + 2]
        body = '''
    wire [31:0] profile_source_state_reads = 0;
    wire [31:0] profile_source_mailbox_reads = 0;
    wire [31:0] profile_phi_state_reads = 0;
    wire [31:0] profile_phi_mailbox_reads = 0;
    __phi_decoder_profile_topology__Top_0_next application (
      .clk(aclk), .reset(!aresetn),
      ._x_decoder_events_out(x_decoder_event),
      ._x_decoder_events_out_vld(x_decoder_event_valid),
      ._x_decoder_events_out_rdy(x_decoder_event_ready),
      ._z_decoder_events_out(z_decoder_event),
      ._z_decoder_events_out_vld(z_decoder_event_valid),
      ._z_decoder_events_out_rdy(z_decoder_event_ready));
endmodule
'''
        (args.stage / 'phi_decoder_profile_top.v').write_text(header + body)
    elif args.variant == 'registered-selection':
        source = args.stage / 'phi_halo_cell.x'
        source.write_text(replace_once(source.read_text(),
            'let fast_issue = !prior_issue_valid &&\n          !completion_blocked && fast_ready;',
            'let fast_issue = false;'))
    elif args.variant == 'separate-entry':
        for module in ('phi_halo_cell', 'phi_syndrome_replay_cell'):
            source = args.stage / (module + '.x')
            source.write_text(replace_once(source.read_text(),
                'let entered = shared_machine_enter(\n    dispatched.machine, request.egress_ready);',
                '''let entered = if machine.enter_pending {
    shared_machine_enter(dispatched.machine, request.egress_ready)
  } else { SharedStep { machine: dispatched.machine, ..zero!<SharedStep>() } };'''))
    elif args.variant == 'magnitude-rounding':
        source = args.stage / 'hls_fixed.x'
        text = source.read_text()
        start = text.index('  if (DENOMINATOR &')
        end = text.index('\n}\n', start)
        original = '''  let negative = numerator < sN[WIDTH]:0;
  let widened = numerator as sN[MAG];
  let magnitude = (if negative { -widened } else { widened }) as uN[MAG];
  let rounded = magnitude + ((DENOMINATOR / u32:2) as uN[MAG]);
  let quotient = (rounded / (DENOMINATOR as uN[MAG])) as sN[MAG];
  (if negative { -quotient } else { quotient }) as sN[WIDTH]'''
        source.write_text(text[:start] + original + text[end:])
    elif args.variant == 'factored-bulk':
        # Reuse the arithmetic screen's exact expression; the application sum
        # is wider storage but still contains at most four signed-32 neighbors.
        from factor_rounding import source as bulk_source
        source = args.stage / 'phi_field.x'
        body = bulk_source(True).split(' -> s32 {\n', 1)[1].rsplit('\n}', 1)[0]
        names = {'a': 'phi0', 'b': 'phi1', 'sum': 'neighbor_sum'}
        body = re.sub(r'\b(a|b|sum)\b', lambda m: names[m[0]], body)
        pattern = r'(pub fn relax_bulk\([^\n]+\) -> Scalar \{\n).*?\n\}'
        text, count = re.subn(pattern, lambda m: m[1] + body + '\n}', source.read_text(), flags=re.S)
        if count != 1:
            raise ValueError('expected one bulk recurrence')
        source.write_text(text)
    elif args.variant == 'registered-egress':
        # Only the two phi batch channels change. Depth two permits accepting
        # the next batch while the previous registered head drains.
        text = topology.read_text()
        for i in (2, 3):
            text = replace_once(text,
                f'chan<phi_halo_cell::ScheduledEffects, CHANNEL_DEPTH>("scheduler_{i}_egress")',
                f'chan<phi_halo_cell::ScheduledEffects, u32:2>("scheduler_{i}_egress")')
        topology.write_text(text)
    elif args.variant != 'reference':
        raise ValueError(args.variant)
    evidence = {'variant': args.variant, 'reference': str(args.reference),
                'reference_sources': {p.name: sha(p) for p in args.reference.glob('*.x')},
                'sources': {p.name: sha(p) for p in args.stage.glob('*.x')},
                'template_sha256': sha(HERE / 'dedicated_actor.template.x')}
    (args.stage / 'experiment.json').write_text(json.dumps(evidence, indent=2) + '\n')


def build(args: argparse.Namespace) -> None:
    """Compile with the retained tools, model and FIFO candidate, recording commands."""
    stage = args.stage
    reference = args.reference / 'compiled'
    commands = []
    ir = json.loads((reference / 'ir.command.json').read_text())
    ir[0] = str(args.xls / 'ir_converter_main')
    ir = [s if not s.startswith('--dslx_stdlib_path=') else
          '--dslx_stdlib_path=' + str(args.xls / 'xls/dslx/stdlib') for s in ir]
    opt = [str(args.xls / 'opt_main'), 'phi_decoder_profile.ir']
    if args.keep_next_selects:
        opt.insert(1, '--split_next_value_selects=0')
    codegen = json.loads((reference / 'codegen.command.json').read_text())
    codegen[0] = str(args.codegen)
    codegen = [('--xc7_delay_table=' + str(args.table)) if s.startswith('--xc7_delay_table=') else s for s in codegen]
    if args.variant == 'dedicated':
        codegen = [s for s in codegen if not s.startswith('--ram_configurations=')]
    for label, command, output in [('ir', ir, 'phi_decoder_profile.ir'),
                                    ('opt', opt, 'phi_decoder_profile.opt.ir'),
                                    ('codegen', codegen, 'phi_decoder_profile.v')]:
        if ('ir', 'opt', 'codegen').index(label) < ('ir', 'opt', 'codegen').index(args.resume_from):
            previous = json.loads((stage / 'commands.json').read_text())
            record = next(r for r in previous if r['label'] == label)
            if record['command'] != command or record['exit'] != 0 or record['output_sha256'] != sha(stage / output):
                raise ValueError(f'cannot resume past changed or failed {label}')
            commands.append(record)
            continue
        start = time.monotonic()
        with (stage / output).open('w') as out, (stage / (label + '.log')).open('w') as err:
            result = subprocess.run(command, cwd=stage, stdout=out, stderr=err, timeout=1200)
        if result.returncode == 0 and label == 'opt' and args.variant == 'registered-egress':
            path = stage / 'phi_decoder_profile.opt.ir'
            text = path.read_text()
            text, count = re.subn(r'(chan _scheduler_[23]_egress\([^\n]*fifo_depth=2, )bypass=true',
                                  r'\1bypass=false', text)
            if count != 2:
                raise ValueError('expected exactly two phi egress FIFO configurations')
            path.write_text(text)
        commands.append({'label': label, 'command': command, 'seconds': time.monotonic() - start,
                         'exit': result.returncode, 'postprocess': ('register two phi egress FIFOs'
                         if label == 'opt' and args.variant == 'registered-egress' else None),
                         'output_sha256': sha(stage / output)})
        (stage / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
        if result.returncode:
            raise RuntimeError(f'{label} failed; see {stage / (label + ".log")}')
        print(label, 'complete', flush=True)
    original = json.loads((reference / 'phi_decoder_profile.build.json').read_text())
    manifest = {k: original[k] for k in ('schema', 'profile', 'tools', 'stdlib', 'ram_configuration')}
    manifest['profile'] = dict(manifest['profile'], architecture=args.variant,
                               split_next_value_selects=0 if args.keep_next_selects else 4)
    if args.variant == 'dedicated':
        manifest['profile'].update(scheduler_count=0, source_scheduler_count=0,
                                   retained_routing_groups=4)
        manifest['ram_configuration'] = None
    manifest['timing_model_sha256'] = sha(args.table)
    manifest['architecture_experiment'] = json.loads((stage / 'experiment.json').read_text())
    manifest['tools'] = dict(manifest['tools'], codegen_main=sha(args.codegen))
    manifest['rtl'] = {name: sha(stage / name) for name in
                      ('phi_decoder_profile.v', 'phi_decoder_profile_top.v', 'hls_1r1w_ram.v')}
    (stage / 'phi_decoder_profile.build.json').write_text(json.dumps(manifest, indent=2) + '\n')


def main() -> None:
    """Require explicit frozen sources, compiler, table and destination."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'stage', 'xls', 'codegen', 'table'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--variant', choices=('reference', 'dedicated', 'registered-selection',
                        'separate-entry', 'magnitude-rounding', 'factored-bulk', 'registered-egress'), required=True)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--keep-next-selects', action='store_true')
    parser.add_argument('--resume-from', choices=('ir', 'opt', 'codegen'), default='ir')
    args = parser.parse_args()
    if not args.build_only:
        prepare(args)
    build(args)


if __name__ == '__main__':
    main()
