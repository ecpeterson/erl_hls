"""Exercise the production transport compiler against ordinary effect decoders and finite RTL schedules."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess

from test_protocol_inbox import lower_receivers

ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str | Path], stage: Path, name: str, output: Path | None = None, accepted: bool = True, timeout: int = 120) -> None:
    """Retain one bounded command and its diagnostics, including expected rejection."""
    with (stage / (name + '.log')).open('x') as log:
        if output is None:
            result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        else:
            with output.open('x') as target:
                result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=target, stderr=log, timeout=timeout)
    if (result.returncode == 0) != accepted:
        raise AssertionError((command, (stage / (name + '.log')).read_text()[-4000:]))


def bench(plan: dict) -> str:
    """Model queues and leases independently; ordinary compiler RTL supplies expected message frames."""
    declarations = ['reg clk=0,reset=1; always #5 clk=~clk;', 'integer cycle=0,accepted=0,captured=0,consumed=0,bypassed=0;',
                    'reg [31:0] rng=32\'h12345678;', 'wire draining=(cycle>=800);']
    ports = ['.clk(clk)', '.reset(reset)']
    enqueue, observe, reset, drive, stable = [], [], [], [], []
    queues: dict[tuple[int, int], str] = {}
    for link in plan['links']:
        queues[link['source_index'], link['output_index']] = 'q' + str(link['index'])
    for boundary in plan['boundaries']:
        queues[boundary['source'], boundary['output']] = f"b{boundary['source']}_{boundary['output']}"
    for q in queues.values():
        declarations += [f'reg [127:0] {q}_frames[0:4095]; integer {q}_slots[0:4095]; integer {q}_head=0,{q}_tail=0;']
        reset += [f'{q}_head=0; {q}_tail=0;']
    for source in plan['sources']:
        i, width = source['index'], source['payload_width']
        p = f'source_{i}'
        declarations += [f'reg {p}_valid=0; reg [7:0] {p}_layout=0; reg [{width-1}:0] {p}_payload=0;',
                         f'wire {p}_ready,{p}_fault; reg {p}_accepted=0;']
        ports += [f'.{p}_{n}({p}_{n})' for n in ['valid', 'ready', 'fault', 'layout', 'payload']]
        observe += [f'if(({{{p}_ready,{p}_fault}} ^ {{{p}_ready,{p}_fault}})!==2\'b0) $fatal(1,"unknown source {i} cycle=%0d",cycle); if({p}_fault) $fatal(1,"source fault {i}"); {p}_accepted={p}_valid && {p}_ready;']
        reset += [f'{p}_accepted=0;']
        layouts = [m['layout'] for m in source['masks']]
        choices = ''.join(f'{n}: {p}_layout=8\'d{layout};' for n, layout in enumerate(layouts))
        drive += [f'if(reset || (draining && ({p}_accepted || !{p}_valid))) {p}_valid=0; else if({p}_accepted || !{p}_valid) begin '
                  f'{p}_valid=(cycle%{i+4}!=0); case((cycle+{i})%{len(layouts)}) {choices} endcase '
                  f'for(integer bitno=0;bitno<{width};bitno=bitno+1) {p}_payload[bitno]=rng[bitno%32] ^ (bitno%3==0); end']
        for output in source['outputs']:
            q = queues[i, output['index']]
            for j, row in enumerate(output['rows']):
                ref = f'ref_{i}_{output["index"]}_{j}'
                declarations += [f'wire [135:0] {ref}; reference_effect {ref}_decoder(.layout({p}_layout),'
                                 f'.payload({p}_payload),.index(8\'d{row["source_order"]}),.out({ref}));']
                enqueue += [f'if({p}_accepted && {p}_layout==8\'d{row["layout"]}) begin '
                            f'if({q}_tail==4096) $fatal(1,"scoreboard full"); '
                            f'{q}_frames[{q}_tail]={ref}[127:0]; {q}_slots[{q}_tail]={row["capture_slot"]}; {q}_tail={q}_tail+1; end']
    for pair in plan['pairs']:
        i, count, bits = pair['index'], pair['slots'], pair['payload_bits']
        p, q = f'link_{i}', f'q{i}'
        declarations += [f'reg {p}_take=0; reg [{count-1}:0] {p}_eligible=0,{p}_release_valid=0;',
                         f'wire [{count-1}:0] {p}_selected,{p}_available,{p}_leased; wire [{bits-1}:0] {p}_payloads;',
                         f'wire {p}_capture; wire [7:0] {p}_capture_slot;',
                         f'integer {p}_state[0:{count-1}],{p}_age[0:{count-1}],{p}_oldest,{p}_oldage; '
                         f'reg [127:0] {p}_expected[0:{count-1}]; reg [{count-1}:0] {p}_pick;']
        ports += [f'.{p}_{n}({p}_{n})' for n in ['take','eligible','release_valid','selected','available','leased','payloads','capture','capture_slot']]
        reset += [f'for(integer k=0;k<{count};k=k+1) begin {p}_state[k]=0; {p}_age[k]=0; end']
        drive += [f'{p}_take=draining || (cycle%{i+3}!=0); '
                  f'for(integer k=0;k<{count};k=k+1) begin {p}_eligible[k]=draining || ((cycle+k+{i})%7<4); '
                  f'{p}_release_valid[k]=draining || ((cycle+k*3+{i})%11==0); end']
        observe += [f'{p}_oldest=-1; {p}_oldage=2147483647; {p}_pick=0; '
                    f'for(integer k=0;k<{count};k=k+1) if({p}_state[k]==1 && {p}_eligible[k] && {p}_age[k]<{p}_oldage) '
                    f'begin {p}_oldest=k; {p}_oldage={p}_age[k]; end '
                    f'if({p}_oldest>=0) {p}_pick[{p}_oldest]=1; '
                    f'if({p}_selected!=={p}_pick) $fatal(1,"sender order {i}"); '
                    f'for(integer k=0;k<{count};k=k+1) case({p}_state[k]) '
                    f'1:if({p}_selected[k] && {p}_take) begin {p}_state[k]=2; consumed=consumed+1; '
                    f'for(integer j=0;j<{count};j=j+1) if({p}_state[j]==1 && {p}_age[j]<{p}_age[k]) bypassed=bypassed+1; end '
                    f'2:if({p}_release_valid[k]) {p}_state[k]=0; endcase '
                    f'if({p}_capture) begin '
                    f'if({q}_head=={q}_tail || {p}_capture_slot!={q}_slots[{q}_head] || {p}_state[{p}_capture_slot]!=0) '
                    f'$fatal(1,"capture identity {i}"); '
                    f'{p}_expected[{p}_capture_slot]={q}_frames[{q}_head]; {p}_state[{p}_capture_slot]=1; '
                    f'{p}_age[{p}_capture_slot]=cycle; {q}_head={q}_head+1; captured=captured+1; end']
        offset = 0
        for slot in pair['classes']:
            k, width = slot['index'], slot['width']
            inverse = {bit: n for n, bit in enumerate(slot['frame_positions'])}
            terms = [f'{p}_payloads[{offset+inverse[b]}]' if b in inverse else f"1'b{(slot['value']>>b)&1}" for b in range(127,-1,-1)]
            declarations += [f'wire [127:0] {p}_decoded_{k}={{'+','.join(terms)+'};']
            stable += [f'if({p}_available[{k}]!==({p}_state[{k}]==1) || {p}_leased[{k}]!==({p}_state[{k}]==2)) '
                       f'$fatal(1,"lease state {i}/{k}"); '
                       f'if({p}_state[{k}]!=0 && {p}_decoded_{k}!=={p}_expected[{k}]) $fatal(1,"payload {i}/{k}");']
            offset += width
    for boundary in plan['boundaries']:
        i, o = boundary['source'], boundary['output']
        p, q = f'boundary_{i}_{o}', f'b{i}_{o}'
        declarations += [f'reg {p}_ready=0; wire {p}_valid; wire [127:0] {p}_data;']
        ports += [f'.{p}_{n}({p}_{n})' for n in ['ready','valid','data']]
        drive += [f'{p}_ready=draining || (cycle%{i+5}==0);']
        observe += [f'if({p}_valid && {p}_ready) begin '
                    f'if({q}_head=={q}_tail || {p}_data!=={q}_frames[{q}_head]) $fatal(1,"boundary {i}/{o}"); '
                    f'{q}_head={q}_head+1; end']
    complete = ' && '.join(f'({q}_head=={q}_tail)' for q in queues.values())
    complete += ' && ' + ' && '.join(f'(source_{s["index"]}_valid==0 && source_{s["index"]}_ready==1)' for s in plan['sources'])
    complete += ' && ' + ' && '.join(f'(link_{p["index"]}_available==0 && link_{p["index"]}_leased==0)' for p in plan['pairs'])
    return '\n'.join(['module tb;', *declarations, 'protocol_fabric dut('+','.join(ports)+');',
        'always @(posedge clk) begin if(reset) begin', *reset, 'end else begin',
        *[x for x in observe if '_accepted=' in x], *enqueue,
        *[x for x in observe if '_accepted=' not in x],
        'accepted=accepted+'+'+'.join(f'source_{s["index"]}_accepted' for s in plan['sources'])+';', 'end end',
        'always @(negedge clk) begin if(!reset) begin', *stable, 'end cycle=cycle+1;',
        'reset=(cycle<3 || cycle==300 || cycle==301 || cycle==600 || cycle==601);',
        'rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};', *drive,
        f'if(cycle>820 && ({complete})) begin if((accepted^accepted)!==0 || accepted<30 || captured<60 || consumed<40 || bypassed==0) $fatal(1,"vacuous coverage"); '
        '$display("PASS transport cycles=%0d accepted=%0d captured=%0d consumed=%0d bypassed=%0d",cycle,accepted,captured,consumed,bypassed); $finish; end',
        'if(cycle==2000) $fatal(1,"drain timeout"); end endmodule'])


def invalid_layout_bench(plan: dict) -> str:
    """Check fail-closed layout handling and synchronous fault retirement on a generated source."""
    ports = ['.clk(clk)', '.reset(rst)']
    for source in plan['sources']:
        i, width = source['index'], source['payload_width']
        valid, layout = ('valid', 'layout') if i == 0 else ("1'b0", "8'b0")
        ports += [f'.source_{i}_valid({valid})',
                  f'.source_{i}_layout({layout})',
                  f'.source_{i}_payload({width}\'b0)']
        if i == 0:
            ports += ['.source_0_ready(ready)', '.source_0_fault(fault)']
    for pair in plan['pairs']:
        i, count = pair['index'], pair['slots']
        ports += [f'.link_{i}_take(1\'b1)', f'.link_{i}_eligible({count}\'b0)', f'.link_{i}_release_valid({count}\'b0)']
    ports += [f'.boundary_{b["source"]}_{b["output"]}_ready(1\'b1)' for b in plan['boundaries']]
    return """module tb;
reg clk=0,rst=1,valid=0; always #5 clk=~clk;
reg [7:0] layout=0; wire ready,fault;
protocol_fabric dut("""+','.join(ports)+""");
initial begin
 repeat(2) @(negedge clk); rst=0;
 #1; if(ready!==1 || fault!==0) $fatal(1,"constant initial layout");
 @(negedge clk); layout=255;valid=1;
 @(posedge clk); #1; if(ready!==0 || fault!==1) $fatal(1,"invalid layout accepted");
 @(negedge clk); valid=0; layout=0;
 @(posedge clk); #1; if(fault!==1) $fatal(1,"fault did not latch");
 @(negedge clk); rst=1;
 @(posedge clk); #1; if(fault!==0 || ready!==0) $fatal(1,"reset retirement");
 $display("PASS invalid layout and reset"); $finish;
end
initial begin #500; $fatal(1,"timeout"); end
endmodule"""


def main() -> None:
    """Run a connected finite witness and elaborate actual N2/N3/N6/D3 transport populations."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    parser.add_argument('stage', type=Path)
    args = parser.parse_args()
    stage = args.stage.resolve()
    stage.mkdir()
    config = stage / 'fixture.config'
    config.write_text('#{sources => [{"test/hls_protocol_capture_fixture.erl",[]},{"test/hls_protocol_transport_topology.erl",[]}],topology => {hls_protocol_transport_topology,topology,[]},actor_limit => 3}.\n')
    fixture = stage / 'fixture'
    run(['bash','tools/emit_protocol_transport.sh',args.xls,config,fixture], stage, 'emit-fixture', timeout=1000)
    run(['erl','-noshell','-eval','ok=hls_protocol_transport_validation:prepare(hd(init:get_plain_arguments())),halt().','-extra',fixture], stage, 'prepare-witness')
    compiler = Path(os.environ['ERL_HLS_ROOT'])
    paths = ':'.join(str(p) for p in [ROOT/'priv/xls/lib', ROOT/'priv/xls/fabric', compiler/'priv/xls/lib', compiler/'priv/xls/fabric'])
    run([args.xls/'ir_converter_main','--warnings_as_errors=false','--top=local_effect','--dslx_path='+paths,
         '--dslx_stdlib_path='+str(args.xls/'xls/dslx/stdlib'),fixture/'reference.x'],stage,'reference-convert',fixture/'reference.ir')
    run([args.xls/'opt_main',fixture/'reference.ir'],stage,'reference-opt',fixture/'reference.opt.ir')
    run([args.xls/'codegen_main','--generator=combinational','--use_system_verilog=false','--module_name=reference_effect',
         '--output_verilog_path='+str(fixture/'reference.sv'),fixture/'reference.opt.ir'],stage,'reference-codegen')
    (fixture/'tb.sv').write_text(bench(json.loads((fixture/'witness.json').read_text())))
    run(['iverilog','-g2012','-s','tb','-o',fixture/'run.vvp','-f',fixture/'files.f',fixture/'reference.sv',fixture/'tb.sv'],stage,'iverilog')
    run(['vvp',fixture/'run.vvp'],stage,'simulation')
    (fixture/'invalid-layout.sv').write_text(invalid_layout_bench(json.loads((fixture/'witness.json').read_text())))
    run(['iverilog','-g2012','-s','tb','-o',fixture/'invalid-layout.vvp','-f',fixture/'files.f',fixture/'invalid-layout.sv'],stage,'invalid-layout-compile')
    run(['vvp',fixture/'invalid-layout.vvp'],stage,'invalid-layout')
    # The public command must reject incomplete ownership before writing RTL.
    original_config = config.read_text()
    negatives = {
        'actor-limit': (original_config.replace('actor_limit => 3', 'actor_limit => 2'), 'actor_limit'),
        'missing-source': (original_config.replace('{"test/hls_protocol_capture_fixture.erl",[]},', ''), None),
        'duplicate-source': (original_config.replace('sources => [', 'sources => [{"test/hls_protocol_capture_fixture.erl",[]},'), 'duplicate_transport_source'),
        'coupled': (original_config.replace('topology,[]}', 'invalid,[coupled]}'), 'unsupported_transport_delivery'),
        'missing-route': (original_config.replace('topology,[]}', 'invalid,[missing_route]}'), 'unrouted_outputs'),
    }
    for name, (text, diagnostic) in negatives.items():
        path, target = stage/(name+'.config'), stage/name
        path.write_text(text)
        run(['bash','tools/emit_protocol_transport.sh',args.xls,path,target],stage,'reject-'+name,accepted=False)
        assert not target.exists(), name
        if diagnostic:
            assert diagnostic in (stage/('reject-'+name+'.log')).read_text(), name
    retained = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in fixture.rglob('*') if p.is_file()}
    run(['bash','tools/emit_protocol_transport.sh',args.xls,config,fixture],stage,'reject-existing',accepted=False)
    assert retained == {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in fixture.rglob('*') if p.is_file()}
    applications = []
    receiver_shapes: set[tuple] = set()
    receiver_lowerings = lower_receivers(args.xls, fixture, stage, receiver_shapes)
    for name, n, topology, expected in [('repetition',2,'phi_repetition_topology',6),('repetition',3,'phi_repetition_topology',9),('repetition',6,'phi_repetition_topology',18),('noise',3,'phi_noise_topology',54)]:
        key = f'{name}-{n}'
        modules = (['phi_line_cell','phenom_line_data_cell','phenom_line_syndrome_cell'] if name=='repetition'
                   else ['phi_halo_cell','phenom_data_cell','phenom_syndrome_cell'])+[topology]
        directory = compiler/'src/examples/phi_decoder'
        sources = ','.join('{'+json.dumps(str(directory/(m+'.erl')))+',[{i,'+json.dumps(str(compiler/'include'))+'},{i,'+json.dumps(str(directory))+'}]}' for m in modules)
        config = stage/(key+'.config')
        config.write_text('#{sources => ['+sources+'],topology => {'+topology+',topology,['+str(n)+',16#80000000]},actor_limit => 64}.\n')
        output = stage/key
        run(['bash','tools/emit_protocol_transport.sh',args.xls,config,output],stage,'emit-'+key,timeout=1000)
        run(['erl','-noshell','-eval','ok=hls_protocol_transport_validation:startup(hd(init:get_plain_arguments())),halt().','-extra',output],stage,'startup-reference-'+key)
        report = json.loads((output/'summary.json').read_text())
        assert report['actors']==expected and report['eligible'] is False
        run(['iverilog','-g2012','-s','protocol_fabric','-o',output/'elaborated.vvp','-f',output/'files.f'],stage,'elaborate-'+key)
        receiver_lowerings += lower_receivers(args.xls, output, stage, receiver_shapes)
        applications.append({'name':key,'actors':expected,'links':report['links']})
    (stage/'result.json').write_text(json.dumps({'passed':True,'applications':applications,
        'receiver_shapes_lowered':receiver_lowerings,
        'evidence':'finite_transport_witness_and_application_elaboration','negative_builds':len(negatives)+1,'application_admitted':False},indent=2)+'\n')
    print((stage/'simulation.log').read_text().strip())


if __name__ == '__main__':
    main()
