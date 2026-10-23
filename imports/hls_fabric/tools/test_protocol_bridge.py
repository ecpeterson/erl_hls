"""Qualify the public framed source builder with two RTL roles and the production bounded relay."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import time
from backend_paths import ROOT, erlang_paths
from compile_protocol_bridge import compile_bridge
from compile_protocol_transport import digest
from test_local_protocol import run


def build(xls: Path, stage: Path) -> list[Path]:
    """Build complementary roles freshly; global identities and per-sender endpoints remain intact."""
    roles=[]
    for i,actors in enumerate(['[left,sink]','[right]']):
        config=stage/f'role{i}.config'
        config.write_text('#{sources=>[{"test/hls_protocol_network_fixture.erl",[]},'
            '{"test/hls_protocol_inbox_fixture.erl",[]}],topology=>{hls_protocol_network_fixture,framed,[]},'
            'actor_limit=>3,control=>rectangle,activation=>explicit_start,native_actors=>'+actors+',host=>1,service=>'+str(7+10*i)+'}.\n')
        role=stage/f'role{i}'
        run(['escript','tools/emit_protocol_bridge.escript',config,role],stage,f'emit-{i}')
        compile_bridge(xls,role);roles.append(role)
    return roles


def pair(roles: list[Path], stage: Path) -> tuple[Path,list[Path]]:
    """Rename independent compiled modules only for one simulator; wire their public AXIS ports."""
    rtl=[];instances=[];ports=['input clk,reset,retire','output fault','output [1:0] running'];wires=[]
    for i,role in enumerate(roles):
        for name in ['core.v','protocol_bridge_top.sv']:
            s=(role/'bridge'/name).read_text()
            s=re.sub(r'\bprotocol_bridge_core\b',f'role{i}_core',s)
            s=re.sub(r'\bprotocol_bridge_top\b',f'role{i}',s)
            target=stage/f'role{i}-{name}';target.write_text(s);rtl.append(target)
        ports.extend([f'input [31:0] s{i}_data',f'input s{i}_last,s{i}_valid,m{i}_ready',
            f'output s{i}_ready,m{i}_last,m{i}_valid',f'output [31:0] m{i}_data'])
        wires.append(f'wire fault{i};')
        pins=['.clk(clk)','.reset(reset)','.retire(retire)',f'.fault(fault{i})',f'.running(running[{i}])']
        for direction in ['s','m']:
            for field in ['data','last','valid','ready']:
                pins.append(f'.{direction}_app_t{field}({direction}{i}_{field})')
        instances.append(f'role{i} role_{i}('+','.join(pins)+');')
    wrapper=stage/'pair.sv'
    wrapper.write_text('// Test-only mechanical composition of independently compiled roles.\n'
        'module protocol_bridge_pair('+','.join(ports)+');\n'+'\n'.join(wires+instances)+
        '\nassign fault=fault0 || fault1;\nendmodule\n')
    return wrapper,rtl


def witness(build_root: Path, binary: Path, ebin: Path, stage: Path, incarnation: int) -> None:
    """Run actual brokers/relay, then require both FIFO leases closed and exact finite readout."""
    stage.mkdir()
    with (stage/'simulation.log').open('x') as log:
        sim=subprocess.Popen([binary,stage],stdout=log,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+10
            while not (stage/'role1_rx').exists():
                if sim.poll() is not None or time.monotonic()>deadline:raise RuntimeError('pair simulator startup')
                time.sleep(.02)
            expression='[B,S,I]=init:get_plain_arguments(),ok=hls_protocol_bridge_live:run(B,S,list_to_integer(I)),halt().'
            run(['erl','+S','2:2','-noshell','-pa',*erlang_paths(),ebin,'-eval',expression,
                '-extra',build_root,stage,str(incarnation)],stage,'host')
            assert sim.wait(timeout=10)==0,(stage/'simulation.log').read_text()
        finally:
            if sim.poll() is None:sim.terminate();sim.wait(timeout=5)
    assert 'PASS framed pair' in (stage/'simulation.log').read_text()
    assert json.loads((stage/'result.json').read_text())['frames']==39


def qualify(roles: list[Path], stage: Path) -> tuple[Path,list[Path]]:
    """Compile once and exercise two fresh reset-owned incarnations through real host routes."""
    ebin=stage/'ebin';ebin.mkdir()
    run(['erlc',*[v for p in erlang_paths() for v in ('-pa',p)],'+debug_info','-Werror','-o',ebin,
         ROOT/'test/hls_protocol_network_fixture.erl',ROOT/'test/hls_protocol_bridge_live.erl'],stage,'host-compile')
    wrapper,rtl=pair(roles,stage)
    run(['verilator','--cc','--exe','--build','--top-module','protocol_bridge_pair',
        '--Mdir',stage/'obj_dir','-j','1','-Wno-fatal','-CFLAGS','-std=c++17','-o','simulation',
        wrapper,*rtl,ROOT/'test/rtl/protocol_bridge_sim.cpp'],stage,'verilator')
    for i in [1,2]:witness(roles[0].parent,stage/'obj_dir/simulation',ebin,stage/f'live-{i}',100+i)
    return wrapper,rtl


def reset_witness(role: Path, stage: Path) -> None:
    """Interrupt public framing and ownership; reject stale sessions and mismatched identities."""
    m=json.loads((role/'bridge/manifest.json').read_text());identity=bytes.fromhex(m['identity'])
    incoming=next(l for l in m['links'] if l['direction']=='incoming');c=incoming['classes'][0]
    source=(ROOT/'test/rtl/protocol_bridge_reset_tb.sv').read_text()
    replacements={'IDENTITY':'\n'.join(f"identity[{i}]=32'h{int.from_bytes(identity[i*4:i*4+4],'little'):08x};" for i in range(8)),
        'LINK':str(incoming['index']),'SLOT':str(c['slot']),'FRAME':str(c['codec']['value'])}
    for key,value in replacements.items():source=source.replace('@@'+key+'@@',value)
    bench=stage/'reset.sv';bench.write_text(source)
    run(['iverilog','-g2012','-s','tb','-o',stage/'reset-sim',bench,role/'bridge/core.v',role/'bridge/protocol_bridge_top.sv'],stage,'reset-compile')
    run(['vvp',stage/'reset-sim'],stage,'reset-simulate')
    assert 'PROTOCOL_BRIDGE_RESET_PASS' in (stage/'reset-simulate.log').read_text()


def properties(xls: Path, stage: Path) -> None:
    """Quantify all finite component state/input bits; no reachable-state or progress claim."""
    from types import SimpleNamespace
    from test_local_protocol import prove
    source=ROOT/'test/rtl/protocol_bridge_properties.x';raw=stage/'properties.ir'
    run([xls/'ir_converter_main','--warnings_as_errors=false','--dslx_path='+str(ROOT/'priv/xls/lib'),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],stage,'properties-convert',raw)
    args=SimpleNamespace(xls=xls,yosys='yosys')
    results=[prove(args,stage,raw,'protocol_bridge_properties',name,positive) for name,positive in
        [('retained',True),('reset',True),('credit',True),('early_ack',True),('terminal',True),('wrong_accept_all',False)]]
    (stage/'proofs.json').write_text(json.dumps({'results':results,'domain':'All finite bits at I=1,C=2,O=1,E=1.',
        'assumptions':'Native observations fixed at the old-state boundary for retained-output cut.',
        'trust':['DSLX/XLS','Yosys/ABC/SAT'],'limits':'Combinational component properties, not temporal liveness/source refinement.'},indent=2)+'\n')


def area(wrapper: Path, rtl: list[Path], stage: Path) -> None:
    """Screen the complete pair and all framing/access logic against preregistered XC7 caps."""
    script=stage/'map.ys';netlist=stage/'mapped.json'
    script.write_text('read_verilog -sv '+' '.join('"'+str(p)+'"' for p in [wrapper,*rtl])+ '\n'
        'synth_xilinx -family xc7 -top protocol_bridge_pair -flatten -nowidelut\nwrite_json "'+str(netlist)+'"\n')
    run(['yosys','-Q','-T','-s',script],stage,'map')
    types=[c['type'] for c in json.loads(netlist.read_text())['modules']['protocol_bridge_pair']['cells'].values()]
    counts={k:sum(t.startswith(v) for t in types) for k,v in [('lut','LUT'),('ff','FD'),('bram','RAMB'),('dsp','DSP')]}
    limits={'lut':28000,'ff':16000,'bram':0,'dsp':0}
    (stage/'area.json').write_text(json.dumps({'counts':counts,'limits':limits,
        'within_budget':all(counts[k]<=limits[k] for k in counts),
        'evidence':'Complete local XC7 diagnostic; not routed timing or native device admission.'},indent=2)+'\n')
    assert all(counts[k]<=limits[k] for k in counts),counts


def component(xls: Path, stage: Path) -> None:
    """Measure the preregistered controller population including its selection/access logic."""
    from compile_protocol_transport import compile_clock
    source=ROOT/'test/rtl/protocol_bridge_component.x'
    compile_clock(xls,source,stage,'bridge_component_clock','bridge_component',[ROOT/'priv/xls/lib'])
    script=stage/'map.ys';netlist=stage/'mapped.json'
    script.write_text('read_verilog "'+str(stage/'core.v')+'"\n'
        'synth_xilinx -family xc7 -top bridge_component -flatten -nowidelut\nwrite_json "'+str(netlist)+'"\n')
    run(['yosys','-Q','-T','-s',script],stage,'map')
    types=[c['type'] for c in json.loads(netlist.read_text())['modules']['bridge_component']['cells'].values()]
    counts={k:sum(t.startswith(v) for t in types) for k,v in [('lut','LUT'),('ff','FD'),('bram','RAMB'),('dsp','DSP')]}
    limits={'lut':8000,'ff':4096,'bram':0,'dsp':0}
    (stage/'area.json').write_text(json.dumps({'counts':counts,'limits':limits,
        'within_budget':all(counts[k]<=limits[k] for k in counts),
        'state_bits':862,'population':{'incoming':1,'classes':3,'outgoing':1,'externals':3},
        'evidence':'Local controller state/access diagnostic, not native timing.'},indent=2)+'\n')
    assert all(counts[k]<=limits[k] for k in counts),counts


def main() -> None:
    """Keep every failed stage, exact generated input and new witness outside source control."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args();args.stage.mkdir()
    roles=build(args.xls,args.stage);wrapper,rtl=qualify(roles,args.stage)
    reset_witness(roles[0],args.stage);properties(args.xls,args.stage);area(wrapper,rtl,args.stage)
    part=args.stage/'component';part.mkdir();component(args.xls,part)
    (args.stage/'result.json').write_text(json.dumps({'passed':True,'incarnations':2,'frames_each':39,
        'forwarded_each':27,'inputs':{str(r/'bridge/core.v'):digest(r/'bridge/core.v') for r in roles},
        'evidence':'Finite actual-source, broker and two-role RTL witness; no native or progress admission.'},indent=2)+'\n')


if __name__=='__main__':main()
