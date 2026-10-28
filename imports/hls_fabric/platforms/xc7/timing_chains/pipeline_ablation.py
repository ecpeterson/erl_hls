#!/usr/bin/env python3
"""Remove scheduler boundaries from a captured candidate and check RTL against BEAM."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / "apps/hls_phi/tools"))
from backend_commands import logged_command
from decoder_profile_witness import rtl_events, sequences
from compile_phi_decoder_profile import INPUTS, BUILD_PROFILE, checked_inputs
from backend_build_profile import emit as emit_build_profile

CUTS = ('loader', 'completion', 'request', 'committed')


def replace(source: str, old: str, new: str) -> str:
    """Replace exactly one whitespace-insensitive fragment, rejecting source drift."""
    pattern = r'\s+'.join(re.escape(part) for part in old.split())
    source, count = re.subn(pattern, lambda _: new, source)
    if count != 1:
        raise ValueError(f'expected one match, got {count}: {old[:100]}')
    return source


def completion(source: str) -> str:
    """Permit an empty completion slot to bypass, retaining stalled or replacing results."""
    source = replace(source,
        'let result = state.completed; let retire_valid = buffered_can_retire;',
        '''let result = if state.completed_valid { state.completed } else { incoming_result };
        let retire_valid = buffered_can_retire || (!state.completed_valid && incoming_valid &&
          (!incoming_result.effects_valid || !credit_busy));''')
    return replace(source,
        '''let completed_valid = if accept_executor_result { incoming_valid }
          else { state.completed_valid };''',
        '''let completed_valid = if accept_executor_result {
          incoming_valid && (state.completed_valid || !retire_valid)
        } else { state.completed_valid };''')


def request(source: str) -> str:
    """Connect the loader directly to the existing executor input FIFO."""
    source = replace(source,
        'let (loaded_request_p, loaded_request_c) = chan<SharedExecutorRequest, u32:0>("loaded_request");', '')
    source = replace(source, 'spawn SharedRequestStage(loaded_request_c, executor_request_p);', '')
    return replace(source, 'SharedLoader<INSTANCE_ID>(dispatch_c, loaded_request_p,',
                   'SharedLoader<INSTANCE_ID>(dispatch_c, executor_request_p,')


def loader(source: str, request_removed: bool) -> str:
    """Return RAM reads to the metadata service while preserving ownership and write fences."""
    output = 'executor_request_p' if request_removed else 'loaded_request_p'
    source = replace(source, 'dispatch_out: chan<SharedDispatchTicket> out;',
        '''ram_read_req_out: chan<MachineRamReadReq> out;
  ram_read_resp_in: chan<MachineRamReadResp> in;
  mailbox_read_req_out: chan<MailboxRamReadReq> out;
  mailbox_read_resp_in: chan<MailboxRamReadResp> in;
  dispatch_out: chan<SharedExecutorRequest> out;''')
    source = replace(source,
        'let (dispatch_p, dispatch_c) = chan<SharedDispatchTicket, u32:1>("dispatch_ticket");', '')
    source = replace(source,
        f'''spawn SharedLoader<INSTANCE_ID>(dispatch_c, {output},
          ram_read_req_out, ram_read_resp_in, mailbox_read_req_out, mailbox_read_resp_in);''', '')
    source = replace(source, 'dispatch_p, executor_result_c,',
        f'''ram_read_req_out, ram_read_resp_in, mailbox_read_req_out, mailbox_read_resp_in,
        {output}, executor_result_c,''')
    # Reuse the exact loader payload assembly, including optional reduction fields.
    template = source[source.index('proc SharedLoader<'):source.index('proc SharedRequestStage')]
    payload = re.search(r'let request = SharedExecutorRequest \{.*?\n\s*\};', template, re.S)
    if payload is None:
        raise ValueError('missing loader payload')
    source = replace(source,
        '''let dispatch_tok = send_if(
          join(memory_tok, state_completion_tok, mailbox_completion_tok),
          dispatch_out, issue_valid, ticket);''',
        '''// With reads back in this atomic activation, prior-write tokens
        // order them; write acknowledgements still gate the activation itself.
        let read_fence = memory_tok;
        let read_state = send_if(read_fence, ram_read_req_out, issue_valid, machine_read(ticket.slot));
        let read_mail = send_if(read_fence, mailbox_read_req_out, issue_valid && ticket.received,
          mailbox::read(ticket.slot, ticket.mailbox_index, MAILBOX_DEPTH));
        let (state_done, machine) = recv_if(read_state, ram_read_resp_in, issue_valid,
          zero!<MachineRamReadResp>());
        let (mail_done, message) = recv_if(read_mail, mailbox_read_resp_in,
          issue_valid && ticket.received, zero!<MailboxRamReadResp>());
        ''' + payload[0] + '''
        let dispatch_tok = send_if(join(state_done, mail_done), dispatch_out, issue_valid, request);''')
    source = replace(source, 'join(memory_tok, egress_tok), ram_write_req_out,',
                     'join(read_state, egress_tok), ram_write_req_out,')
    return replace(source, 'join(memory_tok, egress_tok), mailbox_write_req_out,',
                   'join(read_mail, egress_tok), mailbox_write_req_out,')


def committed(source: str) -> str:
    """Forward captures/retirement into selection without reissuing an uncommitted actor."""
    # The original in-flight set deliberately excludes this cycle's retiring actor.
    source, count = re.subn(
        r'((?:reduction_)?ready_selection)\(state, state.cursor, state.in_flight\)',
        r'\1(retired, state.cursor, state.in_flight)', source)
    if count != 1:
        raise ValueError('missing committed selection')
    start = source.index('let (ready, read_slot)')
    end = source.index('let (state_completion_tok', start)
    section = source[start:end]
    for field in ('internal_candidates', 'aggregate_pending_valid', 'entry_probes',
                  'egress_waiters', 'mail_candidates', 'order', 'occupied', 'postponed'):
        section = section.replace('state.' + field, 'retired.' + field)
    source = source[:start] + section + source[end:]
    source = replace(source,
        '''state.occupied, state.order, state.admission_cursor,
          state.pending, state.pending_valid, false, u32:0, false, u32:0''',
        '''retired.occupied, retired.order, state.admission_cursor,
          captured_pending, credit_pending_valid, false, u32:0, false, u32:0''')
    # Keep credit capture registered. A credit may acknowledge a just-published
    # empty batch in this very activation; consuming it before setting busy would
    # leave a phantom outstanding batch. Selection itself still sees current
    # captures and retirement, so this removes their metadata visibility edge.
    if 'aggregate_pending[read_slot]' in source:
        # An old held value wins a simultaneous duplicate. Otherwise consume the
        # newly captured value once, rather than preserving it as its own replacement.
        source = replace(source, 'aggregate_request: state.aggregate_pending[read_slot],',
            '''aggregate_request: if state.aggregate_pending_valid[read_slot] {
              state.aggregate_pending[read_slot]
            } else { retired.aggregate_pending[read_slot] },''')
        source = replace(source, 'incoming_aggregate_valid, aggregate_slot),',
            'incoming_aggregate_valid && state.aggregate_pending_valid[read_slot], aggregate_slot),')
    return source


def transform(source: str, removed: set[str]) -> str:
    """Compose only the requested boundary removals on one generated shared actor."""
    if not removed <= set(CUTS):
        raise ValueError('unknown boundary')
    if 'completion' in removed:
        source = completion(source)
    if 'committed' in removed:
        source = committed(source)
    if 'request' in removed:
        source = request(source)
    if 'loader' in removed:
        source = loader(source, 'request' in removed)
    return source


def sha(path: Path) -> str:
    """Fingerprint inputs without retaining large duplicate artifacts."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_sources(reference: Path, stage: Path, removed: set[str]) -> dict:
    """Derive an explicitly experimental contract from checked captured inputs.

    The parent contract must already exist and match every bound file. Only
    parent-bound shared actors may be transformed; all copied support inputs and
    the exact transformation remain fingerprinted in the returned evidence.
    """
    parent_bytes = (reference / INPUTS).read_bytes()
    parent = checked_inputs(reference, assets=reference)
    if json.loads(parent_bytes) != parent:
        raise ValueError('parent input manifest changed while preparing ablation')
    sources, transformed = {}, {}
    for path in reference.iterdir():
        if not path.is_file() or not (path.suffix in ('.x', '.v', '.sh', '.term') or
                path.name in ('oracle.json', 'phi-actors.json', 'phi_decoder_profile.json', BUILD_PROFILE)):
            continue
        content = path.read_bytes()
        before = hashlib.sha256(content).hexdigest()
        if path.name in parent['inputs'] and parent['inputs'][path.name] != before:
            raise ValueError(f'parent input changed while preparing ablation: {path.name}')
        if path.suffix == '.x' and b'pub proc SharedService<' in content:
            if path.name not in parent['inputs']:
                raise ValueError(f'ablation actor is not bound by parent inputs: {path.name}')
            content = transform(content.decode(), removed).encode()
            transformed[path.name] = sorted(removed)
        (stage / path.name).write_bytes(content)
        sources[path.name] = {'before': before, 'after': hashlib.sha256(content).hexdigest()}
    if removed and not transformed:
        raise ValueError('no parent-bound shared actors found for requested ablation')
    derivation = {'kind': 'scheduler-boundary-ablation',
                  'parent_manifest_sha256': hashlib.sha256(parent_bytes).hexdigest(),
                  'parent_manifest': parent,
                  'script_sha256': sha(Path(__file__)),
                  'removed_boundaries': sorted(removed),
                  'transformed_inputs': {name: {**sources[name], 'removed_boundaries': cuts}
                                         for name, cuts in transformed.items()}}
    derived = {**parent, 'inputs': {name: sources[name]['after'] for name in parent['inputs']},
               'derivation': derivation}
    (stage / INPUTS).write_text(json.dumps(derived, indent=2) + '\n')
    checked_inputs(stage, assets=stage)
    return sources


def run(args: argparse.Namespace) -> None:
    """Compile a captured source variant and compare both readiness patterns with BEAM."""
    args.stage.mkdir(parents=True, exist_ok=True)
    manifest_path = args.stage / 'ablation.json'
    if manifest_path.exists():
        raise ValueError('use a fresh stage to preserve previous evidence')
    phases = {}
    def timed(name: str, argv: list, cwd: Path, timeout: int = 1800) -> None:
        """Record completed phase wall times separately from simulated clocks."""
        start = time.monotonic()
        logged_command(argv, cwd, args.stage / (name+'.log'), timeout)
        phases[name] = time.monotonic()-start
        print(name, round(phases[name], 2), flush=True)
    sources = prepare_sources(args.reference, args.stage, set(args.remove))
    profile = json.loads((args.stage / 'phi_decoder_profile.json').read_text())
    width, height = profile['width'], profile['height']
    shards = profile['shards_per_plane']
    evidence = {'reference': str(args.reference), 'remove': args.remove, 'sources': sources,
                'script_sha256': sha(Path(__file__)), 'phases_seconds': phases,
                'support_sha256': {name: sha(ROOT / ('apps/hls_phi/tools' if name == 'decoder_profile_witness.py' else 'tools') / name) for name in
                                   ('backend_commands.py', 'decoder_profile_witness.py')},
                'derived_inputs_sha256': sha(args.stage / INPUTS)}
    manifest_path.write_text(json.dumps(evidence, indent=2)+'\n')
    selected = args.stage / 'ablation-build-profile.json'
    emit_build_profile(selected, profile='test', delay_model='xc7_7030')
    timed('compile', ['bash', ROOT/'apps/hls_phi/tools/compile_phi_decoder_profile.sh', args.stage,
          args.xls_root, '--timeout', '20m', '--build-profile', selected,
          '--delay-table', args.delay_table], ROOT, 3700)
    compiled = (args.stage/'compiled').resolve()
    expected = sequences(json.loads((args.stage/'oracle.json').read_text()))
    samples = []
    for stalled in (0, 1):
        work = args.stage / f'stalled-{stalled}'
        work.mkdir()
        parameters = dict(WIDTH=width, HEIGHT=height, X_ENABLED=int('x' in profile['planes']),
                          Z_ENABLED=int('z' in profile['planes']), STALL_OUTPUTS=stalled)
        timed(f'iverilog-{stalled}', ['iverilog', '-g2012', '-s', 'phi_decoder_profile_tb',
            '-o', work/'sim.vvp', *[f'-Pphi_decoder_profile_tb.{k}={v}' for k,v in parameters.items()],
            ROOT/'apps/hls_phi/test/rtl/phi_decoder_profile_tb.sv',
            *[compiled/f for f in ('phi_decoder_profile.v','phi_decoder_profile_top.v','hls_1r1w_ram.v')]], work)
        timed(f'simulate-{stalled}', ['vvp', work/'sim.vvp'], work)
        actual = sequences(rtl_events(work/'phi_decoder_profile.events'))
        if actual != expected:
            raise ValueError(f'BEAM mismatch: stalled={stalled}')
        log = (args.stage/f'simulate-{stalled}.log').read_text()
        if 'PASS: decoder-only' not in log:
            raise ValueError('simulation did not finish')
        samples.append({'stalled': bool(stalled), 'events': sum(map(len,actual.values())),
                        'metrics': [line for line in log.splitlines() if line.startswith('PROFILE_')]})
        (work/'sim.vvp').unlink()
    evidence['samples'] = samples
    evidence['compiled_manifest_sha256'] = sha(compiled/'phi_decoder_profile.build.json')
    manifest_path.write_text(json.dumps(evidence, indent=2)+'\n')
    print(json.dumps(samples), flush=True)


def main() -> None:
    """Require exact candidate sources, compiler and calibration for each ablation."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'stage', 'xls-root', 'delay-table'):
        parser.add_argument('--'+name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--remove', nargs='*', choices=CUTS, default=[])
    run(parser.parse_args())


if __name__ == '__main__':
    main()
