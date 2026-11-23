#!/usr/bin/env python3
"""Run finite carrier, direction-guard and physical-loss pulse witnesses."""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/hls_fabric'))
from backend_commands import digest, run


def executable(name: str) -> Path:
    """Resolve the simulator executable whose exact bytes enter the evidence record."""
    path = Path(shutil.which(name) or name).resolve(strict=True)
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError('not an executable: ' + str(path))
    return path


def main() -> None:
    """Snapshot native sources and run selected bounded fixtures serially."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=lambda value: Path(value).resolve(), help='fresh evidence directory')
    parser.add_argument('--iverilog', default=os.environ.get('IVERILOG', 'iverilog'))
    parser.add_argument('--vvp', default=os.environ.get('VVP', 'vvp'))
    parser.add_argument('--test', action='append', choices=['guard', 'carrier', 'loss'],
                        help='run only selected finite witnesses; default runs all three')
    args = parser.parse_args()
    platform = ROOT / 'platforms/xc7'
    carrier_sources = [platform / 'zynq_ps_probe.v', platform / 'ethernet/cdc_slot.v',
                       platform / 'ethernet/dma_packets.v', platform / 'application/domain_link_packets.v',
                       platform / 'application/domain_link_packets_tb.sv']
    loss_sources = [platform / 'zynq_ps_probe.v', platform / 'ethernet/frame_store.v',
                    platform / 'ethernet/dma_endpoint.v',
                    platform / 'ethernet/packet_loss_tb.sv']
    guard_sources = [platform / 'zynq_ps_probe.v', platform / 'application/domain_link_packets.v',
                     platform / 'application/direction_guard_tb.sv']
    marker = ('DOMAIN_LINK_PACKETS_PASS good_pairs=3 malformed_rx=8 illegal_tx=1 '
              'directional_loss=2 physical_loss=1')
    loss_marker = ('ETHERNET_PACKET_LOSS_PASS zero_byte=2 store_drop=2 store_abort=2 '
                   'directions=2 cold_rearm=1')
    guard_marker = ('DOMAIN_DIRECTION_GUARD_PASS settling=1 stopped_clock=1 '
                    'local_fault=1 host_stop=1 cold_rearm=1')
    fixtures = [('guard', 'direction_guard_tb', guard_sources, guard_marker),
                ('carrier', 'domain_link_packets_tb', carrier_sources, marker),
                ('loss', 'ethernet_packet_loss_tb', loss_sources, loss_marker)]
    chosen = set(args.test or ['guard', 'carrier', 'loss'])
    fixtures = [row for row in fixtures if row[0] in chosen]
    sources = sorted({source for _, _, rows, _ in fixtures for source in rows})
    iverilog, vvp = executable(args.iverilog), executable(args.vvp)
    inputs = {path: digest(path) for path in [*sources, Path(__file__).resolve(),
              ROOT / 'tools/hls_fabric/backend_commands.py',
              ROOT / 'tools/hls_fabric/backend_paths.py', iverilog, vvp]}
    args.stage.mkdir(parents=True)
    snapshot = args.stage / 'sources'
    snapshot.mkdir()
    copied = {}
    for source in sources:
        target = snapshot / source.name
        shutil.copyfile(source, target)
        if digest(target) != inputs[source]:
            raise ValueError('source changed while snapshotting: ' + str(source))
        copied[source] = target
    completed = []
    for name, top, rows, verdict in fixtures:
        product = args.stage / (top + '.vvp')
        run([iverilog, '-g2012', '-s', top, '-o', product,
             *(copied[source] for source in rows)], args.stage, name + '-compile', timeout=120)
        run([vvp, product], args.stage, name + '-witness', timeout=60)
        if verdict not in (args.stage / (name + '-witness.log')).read_text():
            raise ValueError('missing finite witness verdict: ' + name)
        completed.append(name)
        print(verdict, flush=True)
    for path, expected in inputs.items():
        if digest(path) != expected:
            raise ValueError('input changed during witness: ' + str(path))
    result = {
        'passed': True,
        'evidence': 'Simulation witness',
        'kind': 'independent_domain_packet_carrier',
        'completed': completed,
        'inputs': {str(path): value for path, value in inputs.items()},
        'scenarios': {name: scenarios for name, scenarios in {
            'carrier': [
                'Independent host/TX/RX clocks with deterministic byte stalls',
                'DATA32 and ACK11 opaque equality in both directions',
                'Atomic local capture, held RX publication and canonical zero ACK high words',
                'Short, early-TLAST and oversized/missing-TLAST receive frames',
                'Bad magic, source role, destination, word count and protocol version',
                'Illegal local packet length rejects and latches fatal',
                'Mid-frame TX loss recovering between host edges remains fatal',
                'Mid-frame RX loss recovering after host edges remains fatal',
                'No acceptance or emission after each clock domain observes its local stop',
                'No retained DMA replay after active recovery or host-session changes',
                'Cold reset reinitializes ownership and permits fresh traffic',
                'Qualified physical_loss sets carrier fault bit6 and suppresses retained traffic',
            ],
            'guard': [
                'Pre-arm settling with a paused local clock is recoverable',
                'Local arm acknowledgement follows the synchronized host request',
                'Sub-cycle active loss after local arm is retained while the clock is stopped',
                'Local faults stop immediately; host stop crosses through its synchronizer',
                'Active/request recovery never rearms a stopped direction; cold reset does',
            ],
            'loss': [
                'Zero-byte CRC/preamble pulse capture, with inactive startup pulses ignored',
                'Real frame-store underlength/overflow drop and partial-abort/queued-flush pulses',
                'Independent TX/RX sticky capture survives directional reset until cold reset',
            ],
        }.items() if name in chosen},
        'parameters': {'role': 1, 'peer': 2, 'data_words': 32, 'ack_words': 11,
                       'data_frame_bytes': 152, 'ack_frame_bytes': 68,
                       'host_period_ns': 22, 'tx_period_ns': 8, 'rx_period_ns': 14,
                       'simulation_watchdog_ns': 2000000, 'loss_watchdog_ns': 100000},
        'declared_storage': {'packet_buffer_bits': 2048, 'framing_control_bits': 82,
                             'physical_loss_capture_synchronizer_and_reset_bits': 12,
                             'inherited_dma_cdc_memory_bits': 32768,
                             'inherited_control': 'Additional DMA/CDC/reset state remains charged to the whole image.'},
        'assumptions': 'Dedicated point-to-point private Ethernet envelope; MAC integrity checks '
                       'precede these bytes and exported error pulses enter cold-reset-only loss capture. '
                       'Whole-packet sources hold stable offers until acceptance. '
                       'Local admission waits explicit arm handoff; stop propagation assumes running clocks. '
                       'Already accepted work may complete before its direction observes stop. '
                       'Cold reset occurs with quiescent users and exclusion of the old namespace.',
        'trust': 'Handwritten carrier and inherited DMA/CDC/reset RTL, testbench assertions and Icarus.',
        'limits': 'Exactly these finite ideal-clock schedules. The loss fixture injects exported MAC '
                  'error pulses; it does not execute or validate the CRC/preamble decoder. '
                  'No formal or arbitrary-history claim, '
                  'physical CDC/reset qualification, routed timing, recovery progress or whole-image area measurement.',
        'artifacts': {str(path.relative_to(args.stage)): digest(path)
                      for path in args.stage.rglob('*') if path.is_file()},
    }
    (args.stage / 'result.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
