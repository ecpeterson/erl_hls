#!/usr/bin/env python3
"""Render arithmetic samples and covered baseline control delay from campaign data."""
import argparse
import json
from pathlib import Path
import statistics

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def render(root: Path) -> None:
    """Write a PNG/SVG comparison without treating partial paths as clock closure."""
    rows = json.loads((root / 'microprobes.json').read_text())
    core = json.loads((root / 'cores.json').read_text())
    path = core['board-route-baseline']['paths']['decoder.aclk']
    plt.rcParams.update({'font.size': 12, 'svg.fonttype': 'none'})
    fig, axes = plt.subplots(2, 1, figsize=(11, 6.4), gridspec_kw={'height_ratios': [2, 1]})
    fig.subplots_adjust(left=.16, right=.97, top=.85, bottom=.18, hspace=.75)
    fig.suptitle('Arithmetic and routed control timing', x=.16, y=.96, ha='left', weight='bold', fontsize=19)
    means = {}
    maximum_sample = 0.0
    for index, (case, color) in enumerate((('baseline', '#54749a'),
                                         ('reciprocal', '#168274'))):
        samples = [row['period_ns'] for row in rows if row['case'].startswith(case+'/bulk-')
                   and row['stages'] == 2 and row['lut_only'] and row['delay_model'] == 'unit']
        if len(samples) != 3:
            raise ValueError(f'expected three matched two-stage samples for {case}')
        mean = statistics.mean(samples)
        means[case] = mean
        maximum_sample = max(maximum_sample, max(samples))
        axes[0].barh(index, mean, height=.48, color=color, alpha=.85)
        axes[0].errorbar(mean, index, xerr=[[mean-min(samples)], [max(samples)-mean]],
                         color='#15212b', capsize=6, linewidth=1.4)
        axes[0].scatter(samples, [index]*3, color='white', edgecolor='#15212b', s=23, zorder=4)
        axes[0].text(max(samples)+.8, index, f'{mean:.2f} ns', va='center', weight='bold')
    axes[0].set(yticks=[0, 1], yticklabels=['Original', 'Reciprocal'], xlim=(0, maximum_sample*1.22),
                title=f"Existing two-stage arithmetic · mean period falls {1-means['reciprocal']/means['baseline']:.1%}")
    axes[0].invert_yaxis()
    axes[0].text(0, -.36, 'Dots: placement seeds 1–3. Whiskers: best–worst; bar: mean.',
                 transform=axes[0].transAxes, fontsize=10, color='#48545f')
    logic, routing = path['logic_ns'], path['routing_ns']
    axes[1].barh(0, logic, height=.45, color='#cb8147', label=f'Logic: {logic:.1f} ns')
    axes[1].barh(0, routing, left=logic, height=.45, color='#8b647f', label=f'Routing: {routing:.1f} ns')
    axes[1].text(logic+routing/2, 0, f'{routing:.1f} ns routing', ha='center', va='center', color='white', weight='bold')
    axes[1].set(yticks=[0], yticklabels=['Baseline core'], xlim=(0, (logic+routing)*1.09),
                title=f'Covered control path · {logic+routing:.1f} ns total', xlabel='Delay / period (ns)')
    axes[1].text(logic/2, 0, f'{logic:.1f} ns\nlogic', ha='center', va='center', fontsize=10)
    for axis in axes:
        axis.set_axisbelow(True)
        axis.grid(axis='x', alpha=.2)
        for side in ('top', 'right', 'left'):
            axis.spines[side].set_visible(False)
        axis.tick_params(axis='y', length=0)
    fig.text(.16, .035, 'Native estimates: LUT-only arithmetic, three seeds; full-core control, one seed.\nRAM/DSP timing is incomplete. These are not whole-design clock guarantees.', fontsize=10, color='#48545f')
    for extension in ('png', 'svg'):
        output = root / ('timing-comparison.'+extension)
        fig.savefig(output, dpi=160, facecolor='white')
        if extension == 'svg':
            output.write_text('\n'.join(line.rstrip() for line in output.read_text().splitlines())+'\n')
    plt.close(fig)


def main() -> None:
    """Render a retained campaign directory; requires Matplotlib."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    render(parser.parse_args().results)


if __name__ == '__main__':
    main()
