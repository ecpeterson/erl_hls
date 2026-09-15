#!/usr/bin/env python3
"""Compare word-stream router mapping with the former two-port XLS fixture.

This isolates routing, fixes return destination zero, and ties payload keep to
full words, matching the old interface. It does not measure placed timing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from topology_debug import quote
from measure_topology_debug import cell_counts

ROOT = Path(__file__).resolve().parents[1]


def command(args, log):
    with log.open('w') as output:
        subprocess.run(list(map(str, args)), stdout=output, stderr=subprocess.STDOUT, check=True, timeout=180)


def wrapper(ports, old=False):
    text = f'''module router_area(input clk, reset,
    input [32:0] rx, input rx_valid, output rx_ready,
    output [{33*ports-1}:0] rx_payload, output [{ports-1}:0] rx_payload_valid,
    input [{ports-1}:0] rx_payload_ready,
    input [{33*ports-1}:0] tx_payload, input [{ports-1}:0] tx_payload_valid,
    output [{ports-1}:0] tx_payload_ready,
    output [32:0] tx, output tx_valid, input tx_ready);
'''
    if old:
        text += '''__hls_fabric_router__PairIngress_0_next ingress(
    .clk(clk),.reset(reset),._shared_in(rx),._shared_in_vld(rx_valid),._shared_in_rdy(rx_ready),
    ._endpoint_one_out(rx_payload[32:0]),._endpoint_one_out_vld(rx_payload_valid[0]),._endpoint_one_out_rdy(rx_payload_ready[0]),
    ._endpoint_two_out(rx_payload[65:33]),._endpoint_two_out_vld(rx_payload_valid[1]),._endpoint_two_out_rdy(rx_payload_ready[1]));
__hls_fabric_router__PairEgress_0_next egress(
    .clk(clk),.reset(reset),._shared_out(tx),._shared_out_vld(tx_valid),._shared_out_rdy(tx_ready),
    ._endpoint_one_in(tx_payload[32:0]),._endpoint_one_in_vld(tx_payload_valid[0]),._endpoint_one_in_rdy(tx_payload_ready[0]),
    ._endpoint_two_in(tx_payload[65:33]),._endpoint_two_in_vld(tx_payload_valid[1]),._endpoint_two_in_rdy(tx_payload_ready[1]));
'''
    else:
        ids = sum((p+1) << (16*p) for p in range(ports))
        text += f'''wire [32:0] received;
wire [{32*ports-1}:0] data;
wire [{ports-1}:0] last;
hls_fabric_ingress #(.PORTS({ports}),.ENDPOINTS({16*ports}'d{ids})) ingress(
    .clk(clk),.reset(reset),.s_data(rx[31:0]),.s_keep(4'hf),.s_last(rx[32]),.s_valid(rx_valid),.s_ready(rx_ready),
    .m_data(received[31:0]),.m_last(received[32]),.m_keep(),.m_source(),.route_error(),
    .m_valid(rx_payload_valid),.m_ready(rx_payload_ready));
hls_fabric_egress #(.PORTS({ports}),.ENDPOINTS({16*ports}'d{ids})) egress(
    .clk(clk),.reset(reset),.s_data(data),.s_keep({4*ports}'h{'f'*ports}),.s_last(last),
    .s_valid(tx_payload_valid),.s_ready(tx_payload_ready),.s_destination({16*ports}'d0),
    .m_data(tx[31:0]),.m_last(tx[32]),.m_keep(),.m_valid(tx_valid),.m_ready(tx_ready));
'''
        for p in range(ports):
            text += f'assign rx_payload[{33*p}+:33]=received;\nassign data[{32*p}+:32]=tx_payload[{33*p}+:32];\nassign last[{p}]=tx_payload[{33*p+32}];\n'
    return text + 'endmodule\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--yosys', required=True)
    parser.add_argument('--stage', type=Path, default=ROOT / '_build/frame-router/area')
    args = parser.parse_args()
    stage = args.stage.resolve(); stage.mkdir(parents=True, exist_ok=True)
    xls = args.xls.resolve()
    baseline = subprocess.check_output(['git', 'rev-parse', args.baseline], cwd=ROOT, text=True).strip()
    old = stage / 'baseline'; old.mkdir(exist_ok=True)
    for path in ('priv/xls/lib/axis.x', 'priv/xls/fabric/hls_fabric_router.x'):
        (old / Path(path).name).write_bytes(subprocess.check_output(['git', 'show', f'{baseline}:{path}'], cwd=ROOT))
    for top, name in (('PairIngress', 'ingress'), ('PairEgress', 'egress')):
        for invocation, target in (
            ([xls/'ir_converter_main', '--warnings_as_errors=false', f'--dslx_path={old}',
              f'--dslx_stdlib_path={xls}/xls/dslx/stdlib', f'--top={top}', old/'hls_fabric_router.x'], old/f'{name}.ir'),
            ([xls/'opt_main', old/f'{name}.ir'], old/f'{name}.opt.ir'),
            ([xls/'codegen_main', '--pipeline_stages=1', '--delay_model=unit', '--flop_inputs=false', '--flop_outputs=true',
              '--use_system_verilog=false', '--reset=reset', '--fifo_module=', old/f'{name}.opt.ir'], old/f'{name}.v')):
            with target.open('w') as output, target.with_suffix(target.suffix+'.stderr').open('w') as errors:
                subprocess.run(list(map(str, invocation)), stdout=output, stderr=errors, check=True, timeout=120)
    report = {'baseline': baseline, 'yosys': subprocess.check_output([args.yosys, '-V'], text=True).strip(), 'variants': {}}
    for name, ports, before in [('baseline-2', 2, True), ('current-1', 1, False), ('current-2', 2, False), ('current-3', 3, False), ('current-8', 8, False)]:
        directory = stage/name;directory.mkdir(exist_ok=True)
        top = directory/'router_area.v';top.write_text(wrapper(ports, before))
        inputs = [top, *([old/'ingress.v', old/'egress.v'] if before else sorted((ROOT/'priv/rtl/fabric').glob('*.v')))]
        script = 'read_verilog -sv ' + ' '.join(map(quote, inputs)) + '\n'
        script += f'synth_xilinx -family xc7 -top router_area -flatten -noiopad -noclkbuf\nwrite_json {quote(directory/"netlist.json")}\n'
        (directory/'synth.ys').write_text(script)
        command([args.yosys, '-Q', '-T', '-s', directory/'synth.ys'], directory/'synth.log')
        netlist = json.loads((directory/'netlist.json').read_text())['modules']['router_area']['cells']
        counts = {}
        for cell in netlist.values(): counts[cell['type']] = counts.get(cell['type'], 0) + 1
        result = {'ports': ports, 'cells': counts, 'counts': cell_counts(counts),
                  'inputs': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}}
        report['variants'][name] = result
        print(name, result['counts'], flush=True)
    report['tools'] = {name: hashlib.sha256((xls/name).read_bytes()).hexdigest() for name in ('ir_converter_main', 'opt_main', 'codegen_main')}
    (stage/'report.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__': main()
