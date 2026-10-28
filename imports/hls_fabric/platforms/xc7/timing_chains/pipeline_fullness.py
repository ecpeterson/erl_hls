#!/usr/bin/env python3
"""Observe candidate scheduler readiness and transfers without changing measured RTL."""
import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools'))
sys.path.insert(0, str(ROOT / "apps/hls_phi/tools"))
from backend_commands import logged_command
from decoder_profile_witness import rtl_events, sequences


def instrument(source: str) -> tuple[str, list[dict]]:
    """Bind checked selector expressions and executor ports, then append passive samplers."""
    bindings = []
    def module(match: re.Match) -> str:
        """Sample one service's real eligibility predicate rather than treating mail as work."""
        name, body = match[1], match[0]
        if '__SharedService_' not in name:
            return body
        selectors = re.findall(r'assign (selectable(?:__\d+)?) = (ready(?:__\d+)?) & ~(\w+(?:\[[^]]+\])?);', body)
        count_match = re.search(r'__SharedService_\d+__(\d+)_', name)
        if count_match is None or len(selectors) != int(count_match[1]):
            raise ValueError(f'{name}: incomplete readiness/ownership binding')
        count = int(count_match[1])
        for _, _, flight in selectors:
            base = flight.split('[')[0]
            if not re.search(r'\breg '+re.escape(base)+r'(?:\[0:'+str(count-1)+r'\])?;', body):
                raise ValueError(f'{name}: unknown in-flight state layout: {flight}')
        executor = re.search(r'\w+__SharedExecutor_\w+\s+\w+\s*\((.*?)\n\s*\);', body, re.S)
        if executor is None:
            raise ValueError('missing executor instance')
        ports = dict(re.findall(r'\.(\w+)\((\w+)\)', executor[1]))
        ready_mask = "{"+', '.join(row[1] for row in selectors)+"}"
        selectable_mask = "{"+', '.join(row[0] for row in selectors)+"}"
        flight_mask = "{"+', '.join(row[2] for row in selectors)+"}"
        signals = [ready_mask, selectable_mask, flight_mask,
            ports['_request_in_vld'], ports['_request_in_rdy'],
            ports['_result_out_vld'], ports['_result_out_rdy'], 'p0_stage_done', 'issue_valid',
            '_ram_read_req_out_vld', '_ram_read_req_out_rdy',
            '_ram_write_req_out_vld', '_ram_write_req_out_rdy', '_egress_out_vld', '_egress_out_rdy']
        for signal in signals[3:]:
            if not re.search(r'\b'+re.escape(signal)+r'\b', body):
                raise ValueError('missing signal: '+signal)
        ident = len(bindings)
        bindings.append({'id': ident, 'module': name, 'actors': count,
                         'selectors': selectors, 'signals': signals, 'executor_ports': ports})
        columns = ('time,ready,eligible,inflight,request_valid,request_ready,result_valid,result_ready,'
                   'metadata_advance,issue_valid,read_valid,read_ready,write_valid,write_ready,egress_valid,egress_ready')
        observer = f'''
  // Passive simulation observer; this file is never supplied to synthesis.
  integer fullness_file;
  initial begin
    fullness_file = $fopen("fullness-{ident}.csv", "w");
    $fdisplay(fullness_file, "{columns}");
  end
  always @(posedge clk) if (!reset) begin
    $fdisplay(fullness_file, "%0t{',%0d'*len(signals)}", $time, {', '.join(signals)});
  end
'''
        return body.removesuffix('endmodule')+observer+'endmodule'
    rewritten = re.sub(r'module (\w+)\(.*?\bendmodule', module, source, flags=re.S)
    if not bindings:
        raise ValueError('no scheduler bindings')
    return rewritten, bindings


def summarize(stage: Path, bindings: list[dict], start: int, end: int) -> list[dict]:
    """Count disjoint executor states and independent ready/in-flight population histograms."""
    results = []
    for binding in bindings:
        histograms = {name: Counter() for name in ('ready','eligible','inflight','executor')}
        counts = Counter()
        for raw in csv.DictReader((stage/f'fullness-{binding["id"]}.csv').read_text().splitlines()):
            row = {key: int(value) for key,value in raw.items()}
            if not start <= row['time'] < end:
                continue
            counts['cycles'] += 1
            for name in ('ready','eligible','inflight'):
                histograms[name][row[name].bit_count()] += 1
            accepted = row['request_valid'] and row['request_ready']
            if accepted:
                state = 'accepted'
            elif row['request_valid']:
                state = 'request blocked'
            elif row['eligible']:
                state = 'no request; eligible actor exists'
            elif row['inflight']:
                state = 'no request; outstanding actors, none eligible'
            else:
                state = 'no request; no outstanding or eligible actor'
            histograms['executor'][state] += 1
            for key, value in {'requests': accepted,
                'results': row['result_valid'] and row['result_ready'],
                'result_stalls': row['result_valid'] and not row['result_ready'],
                'metadata_advance': row['metadata_advance'],
                'metadata_issue': row['metadata_advance'] and row['issue_valid'],
                'reads': row['read_valid'] and row['read_ready'],
                'writes': row['write_valid'] and row['write_ready'],
                'egress_stalls': row['egress_valid'] and not row['egress_ready']}.items():
                counts[key] += int(value)
        results.append({**binding, 'counts': dict(counts),
                        'histograms': {k: dict(v) for k,v in histograms.items()}})
    return results


def run(args: argparse.Namespace) -> None:
    """Rerun the normal oracle with a separate passive RTL copy and retain a steady-state census."""
    args.stage.mkdir(parents=True, exist_ok=False)
    compiled = (args.fixture/'compiled').resolve()
    rtl = (compiled/'phi_decoder_profile.v').read_text()
    observed, bindings = instrument(rtl)
    (args.stage/'observed.v').write_text(observed)
    tb = (ROOT/'apps/hls_phi/test/rtl/phi_decoder_profile_tb.sv').read_text()
    for boundary in ('warmup', 'target'):
        old = f'{boundary}_cycle = cycle_count;'
        if tb.count(old) != 1:
            raise ValueError('testbench timing markers changed')
        tb = tb.replace(old, old+f'\n        $display("FULLNESS_{boundary.upper()} %0t", $time);')
    (args.stage/'bench.sv').write_text(tb)
    profile = json.loads((args.fixture/'phi_decoder_profile.json').read_text())
    parameters = {'WIDTH':profile['width'],'HEIGHT':profile['height'],
                  'X_ENABLED':int('x' in profile['planes']),'Z_ENABLED':int('z' in profile['planes'])}
    logged_command(['iverilog','-g2012','-s','phi_decoder_profile_tb','-o',args.stage/'sim.vvp',
        *[f'-Pphi_decoder_profile_tb.{k}={v}' for k,v in parameters.items()],
        args.stage/'bench.sv', args.stage/'observed.v', compiled/'phi_decoder_profile_top.v',
        compiled/'hls_1r1w_ram.v'], args.stage, args.stage/'compile.log')
    logged_command(['vvp',args.stage/'sim.vvp'],args.stage,args.stage/'simulate.log')
    if sequences(rtl_events(args.stage/'phi_decoder_profile.events')) != sequences(json.loads((args.fixture/'oracle.json').read_text())):
        raise ValueError('observer run differs from BEAM')
    log = (args.stage/'simulate.log').read_text()
    start, = re.findall(r'FULLNESS_WARMUP (\d+)',log)
    end, = re.findall(r'FULLNESS_TARGET (\d+)',log)
    report = {'rtl_sha256': hashlib.sha256(rtl.encode()).hexdigest(),
              'observer_sha256': hashlib.sha256(observed.encode()).hexdigest(),
              'support_sha256': {name: hashlib.sha256((ROOT / ('apps/hls_phi/tools' if name == 'decoder_profile_witness.py' else 'tools') / name).read_bytes()).hexdigest()
                                 for name in ('backend_commands.py', 'decoder_profile_witness.py')},
              'interval_ps': [int(start),int(end)],
              'schedulers': summarize(args.stage, bindings, int(start),int(end))}
    (args.stage/'fullness.json').write_text(json.dumps(report,indent=2)+'\n')
    (args.stage/'sim.vvp').unlink()
    print(json.dumps([{'module':s['module'],'counts':s['counts'],'executor':s['histograms']['executor']}
                      for s in report['schedulers']],indent=2))


def main() -> None:
    """Require the exact fixture and a fresh output directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('fixture','stage'):
        parser.add_argument('--'+name,required=True,type=lambda p:Path(p).resolve())
    run(parser.parse_args())


if __name__ == '__main__':
    main()
