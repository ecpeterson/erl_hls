"""Exercise source-network cuts with canonical frames, sparse host masks and real feedback."""
from pathlib import Path
from types import SimpleNamespace
import argparse
import json
import re
import subprocess

from backend_paths import ROOT, erlang_environment
from compiler_paths import compiler_root
from protocol_test_build import compile_build, emit_command
from backend_commands import run
from test_local_protocol import prove


def build(xls: Path, stage: Path, index: int, actors: str) -> Path:
    """Build each independent role from current sources through the public network entry point."""
    config=stage/f'role{index}.config'
    config.write_text('#{sources => [{"test/hls_protocol_network_fixture.erl",[]},'
        '{"test/hls_protocol_inbox_fixture.erl",[]}],topology => '
        '{hls_protocol_network_fixture,partitioned,[]},actor_limit => 3,'
        'activation => explicit_start,native_actors => '+actors+'}.\n')
    role=stage/f'role{index}'
    run(emit_command('network', config, role),stage,f'emit-{index}', env=erlang_environment("test"))
    compile_build(xls,role,profile='test')
    return role


def pair(roles: list[Path], stage: Path) -> tuple[Path,list[Path]]:
    """Wire public pins through two test-only one-frame carriers; no generated behavior is edited.

    Mechanical module renaming only permits independently compiled roles in one simulator.
    Carriers share clock/reset and independently stall source acceptance; they do not model
    framing, CDC, packet loss or independent incarnations.
    """
    manifests=[json.loads((r/'network/manifest.json').read_text()) for r in roles]
    assert [m['native_indices'] for m in manifests]==[[0,2],[1]]
    assert [m['crossing_state_bits'] for m in manifests]==[1,1]
    assert all(m['ingress']['actors']==3 and not m['eligible'] for m in manifests)
    rtl=[];wires=[];instances=[];faults=[];cross={};boundaries=[]
    for j,(role,m) in enumerate(zip(roles,manifests)):
        for name in ['core.v','protocol_network.sv']:
            original=(role/'network'/name).read_text()
            renamed=re.sub(r'\bprotocol_network_core\b',f'role{j}_core',original)
            renamed=re.sub(r'\bprotocol_network\b',f'role{j}',renamed)
            target=stage/f'role{j}-{name}';target.write_text(renamed);rtl.append(target)
        connections=['.clk(clk)']
        for p in m['inputs']+m['outputs']:
            n,w=p['name'],p['width'];key=f'r{j}_{n}'
            wires.append(f'wire [{w-1}:0] {key};');connections.append(f'.{n}({key})')
            if n in ['reset','ingress_data']:wires.append(f'assign {key}={n};')
            elif n=='ingress_valid':wires.append(f'assign {key}=ingress_valid[{j}];')
            elif n=='start_valid':wires.append(f"assign {key}=1'b1;")
            elif n=='ingress_ready':wires.append(f'assign ingress_ready[{j}]={key};')
            if n.endswith(('_fault','_failure')):faults.append(key)
        instances.append(f'role{j} role_{j}('+','.join(connections)+');')
        for b in m['boundaries']:
            name=b['name'];i=b['source_index'];boundaries.append(i)
            wires.extend([f'assign r{j}_{name}_ready=ready[{i}];',f'assign valid[{i}]=r{j}_{name}_valid;',
                f'assign data_{i}=r{j}_{name}_data;'])
        for c in m['crossings']:cross.setdefault(c['index'],{})[c['direction']]=(j,c)
    assert sorted(boundaries)==[0,1,2] and len(cross)==2
    for k,(i,ends) in enumerate(sorted(cross.items())):
        (a,ac),(b,bc)=ends['outgoing'],ends['incoming']
        assert ac['classes']==bc['classes']
        out=f'r{a}_remote_{i}';inc=f'r{b}_remote_{i}'
        wires.extend([f'reg held_{i}=0; reg [7:0] slot_{i}=0; reg [127:0] frame_{i}=0;',
            f'assign {out}_ready=!reset && !held_{i} && crossing_ready[{k}];',
            f'assign {inc}_valid=!reset && held_{i};',
            f'assign {inc}_slot=slot_{i}; assign {inc}_frame=frame_{i};',
            f'always @(posedge clk) if(reset) held_{i}<=0; else begin',
            f' if({inc}_valid && {inc}_ready) held_{i}<=0;',
            f' if({out}_valid && {out}_ready) begin held_{i}<=1; slot_{i}<={out}_slot; frame_{i}<={out}_frame; end end'])
    wrapper=stage/'pair.sv'
    wrapper.write_text('module partition_pair(input clk,reset,input [2:0] ready, input [1:0] crossing_ready,\n'
        'input [1:0] ingress_valid,input [193:0] ingress_data,output [1:0] ingress_ready,\n'
        'output [2:0] valid,output [127:0] data_0,data_1,data_2,output fault);\n'+
        '\n'.join(wires+instances)+ '\nassign fault=|{'+','.join(faults)+'};\nendmodule\n')
    return wrapper,rtl


def simulate(wrapper: Path, rtl: list[Path], stage: Path, reject: bool = False) -> None:
    """Check exact source outputs/order/readout across two completed common-reset incarnations."""
    source=(ROOT/'test/rtl/protocol_network_tb.sv').read_text()
    wiring='''wire faults;
reg [1:0] ingress_valid=0; wire [1:0] ingress_ready;
wire [193:0] ingress_data={16'd0,16'd0,16'd1,16'd0,2'd0,8'd1,8'd0,8'd0,8'd5,96'd0};
reg [1:0] host_sent=0;
wire [1:0] crossing_ready={cycle>35 && cycle%7!=epoch, cycle>10 && cycle%5!=epoch};
partition_pair dut(.clk(clk),.reset(reset),.ready(ready),.valid(valid),.data_0(data[0]),.data_1(data[1]),.data_2(data[2]),.fault(faults),
  .crossing_ready(crossing_ready),.ingress_valid(ingress_valid),.ingress_data(ingress_data),.ingress_ready(ingress_ready));'''
    source=source.replace('@@WIRING@@',wiring).replace('reset=0;last_stalled=0;', 'reset=0;host_sent=0;ingress_valid=0;last_stalled=0;')
    source=source.replace('      #4;', '      ingress_valid=cycle>=450 ? ~host_sent : 0;\n      #4;\n      host_sent=host_sent | (ingress_valid & ingress_ready);')
    source=source.replace('else if(counts[0]', 'else if(host_sent!=3 || ingress_ready!=3 || counts[0]')
    # A silent lost link must fail the very same finite output/readout scoreboard.
    if reject: source=source.replace('cycle>35 && cycle%7!=epoch', "1'b0")
    bench=stage/'bench.sv';bench.write_text(source)
    run(['iverilog','-g2012','-s','tb','-o',stage/'sim',bench,wrapper,*rtl],stage,'compile')
    with (stage/'simulate.log').open('x') as log:
        result=subprocess.run(['vvp',str(stage/'sim')],stdout=log,stderr=subprocess.STDOUT,timeout=30)
    output=(stage/'simulate.log').read_text()
    if reject: assert result.returncode!=0 and 'incomplete witness' in output,output
    else: assert result.returncode==0 and 'PROTOCOL_NETWORK_PASS' in output,output


def properties(xls: Path, role: Path, stage: Path) -> None:
    """Quantify canonical admission and the retained observation cut over every state/input bit."""
    m=json.loads((role/'network/manifest.json').read_text())
    incoming=next(c for c in m['crossings'] if c['direction']=='incoming');i=incoming['index']
    ports=json.loads((role/'dslx/ports.json').read_text())
    fields=ports['outputs']
    fixed=', '.join(p['name']+': io.'+p['name'] for p in ports['inputs'] if p['name'].endswith('_eligible'))
    observed=[p['name'] for p in fields if p['name'].endswith(('_selected','_available','_leased','_payloads'))
              or (p['name'].startswith('boundary_') and p['name'].endswith(('_valid','_data')))
              or (p['name'].startswith('remote_') and p['name'].endswith(('_valid','_slot','_frame')))]
    canonical=' || '.join(f'(io.remote_{i}_slot == u8:{c["slot"]} && '
        f'(io.remote_{i}_frame & bits[128]:{c["codec"]["mask"]}) == bits[128]:{c["codec"]["value"]})'
        for c in incoming['classes'])
    source=stage/'partition_properties.x';raw=stage/'properties.ir'
    source.write_text('import transport;\nimport protocol_partition as p;\n'
        '// Quantify retirement, offers and peer readiness at fixed old state/reset/eligibility.\n'
        'pub fn retained(s: transport::State, io: transport::Inputs, changed: transport::Inputs) -> bool {\n'
        'let a=transport::tick(s,io).output; let b=transport::tick(s,transport::Inputs { reset: io.reset, '+fixed+', ..changed }).output;\n'+
        ' && '.join('a.'+n+' == b.'+n for n in observed)+' }\n'
        '// Every invalid slot/header/padding/omitted constant faults without capture.\n'
        'pub fn canonical(s: transport::State, io: transport::Inputs) -> bool {\n'
        f'let valid={canonical}; let t=transport::tick(s,io);\n'
        f'(!t.output.link_{i}_capture || valid) && '
        f'(io.reset || !io.remote_{i}_valid || valid || t.state.remote_{i}.fault) && '
        f'(!io.reset || (!t.state.remote_{i}.fault && !t.output.remote_{i}_ready && !t.output.link_{i}_capture)) }}\n'
        '// The negative intentionally removes the admission precondition.\n'
        f'pub fn wrong_accepts_all(s: transport::State, io: transport::Inputs) -> bool {{\n'
        f'!io.remote_{i}_valid || transport::tick(s,io).output.link_{i}_capture }}\n')
    run([xls/'ir_converter_main','--warnings_as_errors=false',
        '--dslx_path='+':'.join(map(str,[role/'dslx',ROOT/'priv/xls/lib',compiler_root('test')/'priv/xls/lib'])),
        '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],stage,'properties-convert',raw)
    args=SimpleNamespace(xls=xls,yosys='yosys')
    results=[prove(args,stage,raw,'partition_properties',name,positive)
        for name,positive in [('retained',True),('canonical',True),('wrong_accepts_all',False)]]
    (stage/'proofs.json').write_text(json.dumps({'results':results,'domain':'All finite fixture transport state/input bits.',
        'trust':['fresh source/capture schema extraction','DSLX/XLS','Yosys/ABC/SAT'],
        'limits':'Combinational properties, not source refinement or temporal progress.'},indent=2)+'\n')


def area(wrapper: Path, rtl: list[Path], stage: Path) -> None:
    """Measure the connected role pair, including both test-carrier registers, with fixed XC7 caps."""
    script=stage/'map.ys';netlist=stage/'mapped.json'
    script.write_text('read_verilog -sv '+' '.join('"'+str(p)+'"' for p in [wrapper,*rtl])+'\n'
        'synth_xilinx -family xc7 -top partition_pair -flatten -nowidelut\nwrite_json "'+str(netlist)+'"\n')
    run(['yosys','-Q','-T','-s',script],stage,'map')
    cells=json.loads(netlist.read_text())['modules']['partition_pair']['cells'].values()
    types=[c['type'] for c in cells]
    counts={k:sum(t.startswith(v) for t in types) for k,v in [('lut','LUT'),('ff','FD'),('bram','RAMB'),('dsp','DSP')]}
    limits={'lut':14000,'ff':7000,'bram':0,'dsp':0}
    (stage/'area.json').write_text(json.dumps({'xc7_counts':counts,'limits':limits,
        'within_budget':all(counts[k]<=limits[k] for k in counts),
        'evidence':'Local connected synthesis diagnostic, including test carriers; not native timing/device admission.'},indent=2)+'\n')


def main() -> None:
    """Build only the new population; preserve each failed stage instead of retrying it silently."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve())
    parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args();stage=args.stage;stage.mkdir()
    roles=[build(args.xls,stage,i,actors) for i,actors in enumerate(['[left,sink]','[right]'])]
    wrapper,rtl=pair(roles,stage);simulate(wrapper,rtl,stage)
    negative=stage/'negative';negative.mkdir();simulate(wrapper,rtl,negative,reject=True)
    proof=stage/'proof';proof.mkdir();properties(args.xls,roles[0],proof)
    area(wrapper,rtl,stage)
    (stage/'result.json').write_text(json.dumps({'passed':True,'roles':2,'complete_incarnations':2,
        'interrupted_incarnations':1,'outputs_per_complete_incarnation':39,'final_sum':60,
        'sparse_native_indices':[0,2],'host_retirement':'both roles accept/consume, then return ready',
        'ordering':'source batch order and finite sink arithmetic; no imposed cross-sender chronology',
        'evidence':'Finite actual-source RTL witness, not multi-board/native admission.'},indent=2)+'\n')


if __name__=='__main__':
    main()
