#!/usr/bin/env python3
"""Measure dedicated-actor aggregate handoffs using unchanged RTL interface ports."""
import argparse
from collections import Counter, defaultdict, deque
import json
from pathlib import Path
import subprocess

from architecture import sha

ROOT = Path(__file__).resolve().parents[3]


def monitor() -> str:
    """Observe completed handshakes and blocked outputs at each active clock edge."""
    base = 'phi_decoder_profile_tb.dut.application.__phi_decoder_profile_topology__SchedulerGrid_0_next_inst'
    rows = ['module boundary_monitor;', 'integer cycle=0; integer file;',
            'initial file=$fopen("handoffs.txt","w");',
            'always @(posedge phi_decoder_profile_tb.clk) if(phi_decoder_profile_tb.resetn) begin']
    for plane, suffix in (('x', ''), ('z', '_1')):
        collector = base + f'.__phi_decoder_profile_topology__Phi_{plane}ReductionPlane_0_next_inst'
        data = collector + '._aggregate_out_0'
        rows += [f'if({data}_vld && {data}_rdy)',
                 f'  $fdisplay(file,"%0d collector {plane} %0d %h",cycle,{data}[217:186],{data});']
        for slot in (0, 1):
            group = base + f'.__phi_halo_cell__DedicatedGroup_0_next_inst{suffix}'
            actor = group + f'.__phi_halo_cell__DedicatedActor_0__{slot}_next_inst'
            for kind, port in (('actor', '_aggregate'), ('effect', '_output')):
                data = actor + '.' + port
                rows += [f'if({data}_vld && {data}_rdy)',
                         f'  $fdisplay(file,"%0d {kind} {plane} {slot} %h",cycle,{data});']
            rows += [f'if({actor}._output_vld && !{actor}._output_rdy)',
                     f'  $fdisplay(file,"%0d blocked {plane} {slot} 0",cycle);']
            data = group + f'.__phi_halo_cell__DedicatedEgress_0_next_inst._inputs__{slot}'
            rows += [f'if({data}_vld && {data}_rdy)',
                     f'  $fdisplay(file,"%0d egress {plane} {slot} %h",cycle,{data});']
    return '\n'.join(rows + ['cycle=cycle+1;', 'end', 'endmodule', ''])


def analyze(stage: Path) -> dict:
    """Match complete aggregate words in FIFO order; do not infer effect causality."""
    pending = defaultdict(deque)
    effects = defaultdict(deque)
    counts = Counter()
    latency = Counter()
    egress_latency = Counter()
    sites = Counter()
    effect_spacing = Counter()
    previous_effect = {}
    for line in (stage / 'handoffs.txt').read_text().splitlines():
        cycle, kind, plane, slot, word = line.split()
        cycle, slot = int(cycle), int(slot)
        actor = (plane, slot)
        counts[kind] += 1
        if kind == 'collector':
            pending[actor].append((cycle, word))
        elif kind == 'actor':
            if not pending[actor]:
                raise AssertionError('actor accepted an aggregate before collector acceptance')
            start, expected = pending[actor].popleft()
            if word != expected:
                raise AssertionError('aggregate changed or reordered')
            latency[cycle - start] += 1
            sites[((int(word, 16) >> 167) & 3, cycle - start)] += 1
        elif kind == 'effect':
            effects[actor].append((cycle, word))
            if actor in previous_effect:
                effect_spacing[cycle - previous_effect[actor]] += 1
            previous_effect[actor] = cycle
        elif kind == 'egress':
            if not effects[actor]:
                raise AssertionError('egress accepted a batch before actor publication')
            start, expected = effects[actor].popleft()
            if word != expected:
                raise AssertionError('effect batch changed or reordered')
            egress_latency[cycle - start] += 1
    return {'counts': dict(counts), 'handoff_cycles': dict(sorted(latency.items())),
            'handoff_by_site': [{'site': site, 'cycles': cycles, 'count': count}
                                for (site, cycles), count in sorted(sites.items())],
            'effect_egress_cycles': dict(sorted(egress_latency.items())),
            'effect_spacing_cycles': dict(sorted(effect_spacing.items())),
            'pending_at_finish': sum(map(len, pending.values())),
            'pending_effects_at_finish': sum(map(len, effects.values())),
            'blocked_actor_output_cycles': counts['blocked'],
            'effect_spacing_is_causality': False}


def measure(rtl: Path, stage: Path) -> None:
    """Run the normal profile with passive monitors and retain checked payload matches."""
    stage.mkdir(parents=True, exist_ok=False)
    (stage / 'monitor.v').write_text(monitor())
    files = [rtl / name for name in ('phi_decoder_profile.v', 'phi_decoder_profile_top.v', 'hls_1r1w_ram.v')]
    command = ['iverilog', '-g2012', '-s', 'phi_decoder_profile_tb', '-s', 'boundary_monitor',
               '-Pphi_decoder_profile_tb.WIDTH=2', '-Pphi_decoder_profile_tb.HEIGHT=1',
               '-o', 'simulation.vvp', str(ROOT / 'test/rtl/phi_decoder_profile_tb.sv'),
               *map(str, files), 'monitor.v']
    with (stage / 'compile.log').open('w') as log:
        subprocess.run(command, cwd=stage, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
    with (stage / 'simulation.log').open('w') as log:
        subprocess.run(['vvp', 'simulation.vvp'], cwd=stage, stdout=log, stderr=subprocess.STDOUT,
                       check=True, timeout=300)
    if 'PASS: decoder-only' not in (stage / 'simulation.log').read_text():
        raise AssertionError('incomplete profile')
    summary = analyze(stage)
    summary.update(inputs={str(p): sha(p) for p in files}, command=command,
                   trace_sha256=sha(stage / 'handoffs.txt'), monitor_sha256=sha(stage / 'monitor.v'))
    (stage / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    (stage / 'simulation.vvp').unlink()
    print(json.dumps(summary['counts']), summary['handoff_cycles'], flush=True)


def main() -> None:
    """Require the dedicated fixture and a fresh trace directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('rtl', 'stage'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    args = parser.parse_args()
    measure(args.rtl, args.stage)


if __name__ == '__main__':
    main()
