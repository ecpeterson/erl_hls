#!/usr/bin/env python3
"""Render link service causes and their relation to queued data on a cycle timeline."""
import argparse
from collections import Counter
import csv
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

COLORS = {'data_header': '#147d92', 'payload': '#147d92', 'credit_header': '#72b7b2',
          'arbitration_idle': '#ee9753', 'credit_idle': '#d45663', 'no_offer_idle': '#e6eaef'}
LABELS = {'payload': 'Data words', 'credit_header': 'Credit words', 'arbitration_idle': 'Arbitration idle',
          'credit_idle': 'Credit-starved idle', 'no_offer_idle': 'No offered work'}


def render(stage: Path, output: Path, start: int, duration: int) -> None:
    """Show exact per-direction accounting and D0 north/south production over a chosen ns interval."""
    report = json.loads((stage/'transport.json').read_text())
    periods = json.loads((stage/'profile-inputs.json').read_text())['device_periods_ns']
    with (stage/'transport-timeline.csv').open() as stream:
        rows = list(csv.DictReader(stream))
    # The pre-edge clock phase is retained explicitly rather than inferred from app events.
    initial = next(r['reset_release_ns'] for r in report['links'] if r['device'] == 0)
    fig, axes = plt.subplots(3, 1, figsize=(13, 7), gridspec_kw={'height_ratios': [1.2, 0.7, 1]}, constrained_layout=True)
    directions = ('north', 'south', 'east', 'west')
    totals = {direction: Counter() for direction in directions}
    for link in report['links']: totals[link['direction']].update(link['counts'])
    left = [0.0]*4
    for reason in LABELS:
        counts = [totals[d][reason]+(totals[d]['data_header'] if reason == 'payload' else 0) for d in directions]
        values = [100*n/sum(l['cycles'] for l in report['links'] if l['direction'] == d) for n, d in zip(counts, directions)]
        axes[0].barh(directions, values, left=left, color=COLORS[reason], label=LABELS[reason])
        left = [a+b for a, b in zip(left, values)]
    axes[0].invert_yaxis()
    axes[0].set(xlim=(0, 100), xlabel='Packetizer cycles (%)', title='D6: most unused link capacity has no offered frame or return credit')
    selected = {l['link']: l for l in report['links'] if l['device'] == 0 and l['direction'] in ('north', 'south')}
    for row in rows:
        link, cycle = int(row['link']), int(row['cycle'])
        if link not in selected: continue
        time = initial+cycle*periods[0]
        if not start <= time < start+duration: continue
        y = 0 if selected[link]['direction'] == 'north' else 1
        axes[1].broken_barh([(time-start, periods[0])], (y-.3, .6), facecolors=COLORS[row['reason']], linewidth=0)
    for link, info in selected.items():
        samples = [(initial+int(r['cycle'])*periods[0]-start, int(r['offered'])) for r in rows if int(r['link']) == link
                   and start <= initial+int(r['cycle'])*periods[0] < start+duration]
        axes[2].step([t for t, _ in samples], [v for _, v in samples], where='post', label=info['direction'])
    axes[1].set(yticks=[0, 1], yticklabels=['D0 north', 'D0 south'], xlim=(0, duration),
                title=f'Packetizer decisions from {start:,} ns (physical word follows one 8 ns cycle later)')
    axes[2].set(xlim=(0, duration), xlabel='Elapsed time (ns)', ylabel='Offered data lanes', ylim=(-.1, 4.1))
    axes[2].legend(loc='upper right', frameon=False)
    axes[0].legend(handles=[Patch(color=COLORS[r], label=LABELS[r]) for r in LABELS],
                   ncol=3, loc='lower right', fontsize=8)
    for ax in axes:
        ax.spines[['top', 'right']].set_visible(False)
    output.parent.mkdir(parents=True, exist_ok=True)
    for suffix in ('.svg', '.png'):
        fig.savefig(output.with_suffix(suffix), dpi=160, metadata={'Date': None} if suffix == '.svg' else None)
    plt.close(fig)
    svg = output.with_suffix('.svg')
    svg.write_text('\n'.join(line.rstrip() for line in svg.read_text().splitlines())+'\n')


def main() -> None:
    """Choose an existing checked recording and the timeline range in nanoseconds."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--start', type=int, default=45500)
    parser.add_argument('--duration', type=int, default=1200)
    args = parser.parse_args()
    render(args.stage, args.output, args.start, args.duration)


if __name__ == '__main__':
    main()
