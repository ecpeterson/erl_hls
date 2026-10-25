"""Finite source startup/feedback RTL witnesses and exact ordered-head dependency checks."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
from types import SimpleNamespace

from backend_paths import ROOT, erlang_environment
from compiler_paths import compiler_root
from protocol_test_build import compile_build, compile_clock, emit_command
from test_protocol_network import area
from backend_commands import run
from test_local_protocol import prove


def configuration(path: Path, function: str) -> None:
    """Use fresh source fixtures through the production network build boundary."""
    path.write_text('#{sources => [{"test/hls_protocol_startup_fixture.erl",[]},'
        '{"test/hls_protocol_startup_peer.erl",[]}],topology => '
        '{hls_protocol_startup_fixture,'+function+',[]},actor_limit => 2}.\n')


def wiring(fixture: Path) -> str:
    """Connect independent public boundary streams; do not inspect private generated RTL names."""
    manifest=json.loads((fixture/'network/manifest.json').read_text())
    assert manifest['actors']==2 and manifest['links']==2 and not manifest['eligible']
    ports=manifest['inputs']+manifest['outputs'];lines=[];connections=['.clk(clk)']
    for port in ports:
        name,width=port['name'],port['width'];connections.append(f'.{name}({name})')
        if name!='reset': lines.append(f'wire [{width-1}:0] {name};')
    for boundary in manifest['boundaries']:
        name=boundary['name'];i=boundary['source_index']
        lines += [f'assign {name}_ready=ready[{i}];',f'assign valid[{i}]={name}_valid;',f'assign data[{i}]={name}_data;']
    faults=[p['name'] for p in manifest['outputs'] if p['name'].endswith(('_fault','_failure'))]
    lines.append('wire [33:0] faults={'+','.join(faults)+'};')
    lines.append('protocol_network dut('+','.join(connections)+');')
    return '\n'.join(lines)


def simulate(fixture: Path, stage: Path, core: Path | None = None, reject: bool = False, failure: bool = False) -> None:
    """Score ordered constant records, real feedback, stalls, reset replay and unconsumed source failure."""
    if failure:
        text="""module tb;
reg clk=0,reset=1;integer cycle=0,epoch;wire [1:0] valid,ready;wire [127:0] data[0:1];
assign ready=2'b11;
@@WIRING@@
initial begin
for(epoch=0;epoch<2;epoch=epoch+1) begin
 reset=1;#5;clk=1;#5;clk=0;#1;if(faults!==0 || startup_done!==0 || valid!==0) $fatal(1,"reset failure retirement");
 reset=0;
 for(cycle=0;cycle<100;cycle=cycle+1) begin
   #4;if(startup_done!==0) $fatal(1,"failed startup retired");clk=1;#5;clk=0;#1;
 end
 if(actor_0_failure==0 || actor_0_fault!=0 || actor_1_failure!=0 || actor_1_fault!=0) $fatal(1,"missing source failure");
end
$display("PROTOCOL_STARTUP_FAILURE_PASS");$finish;
end
endmodule
"""
    else: text=(ROOT/'test/rtl/protocol_startup_tb.sv').read_text()
    bench=stage/'bench.sv';bench.write_text(text.replace('@@WIRING@@',wiring(fixture)))
    run(['iverilog','-g2012','-s','tb','-o',stage/'sim',bench,core or fixture/'network/core.v',
         fixture/'network/protocol_network.sv'],stage,'compile')
    with (stage/'simulate.log').open('x') as log:
        result=subprocess.run(['vvp',str(stage/'sim')],stdout=log,stderr=subprocess.STDOUT,timeout=30)
    diagnostic=(stage/'simulate.log').read_text()
    if reject:
        assert result.returncode!=0 and ('wrong startup order/data' in diagnostic or 'incomplete startup witness' in diagnostic),diagnostic
    else:
        assert result.returncode==0 and ('PROTOCOL_STARTUP_FAILURE_PASS' if failure else 'PROTOCOL_STARTUP_PASS') in diagnostic,diagnostic


def negative_wiring(xls: Path, fixture: Path, stage: Path) -> None:
    """Require premature retirement and reordered declared messages to fail the same scoreboard."""
    original=(fixture/'actors/receiver_0.x').read_text()
    metadata=json.loads((fixture/'actors/receiver_0.x.json').read_text())['inbox']['startup']
    at=metadata['offset'];a,b=metadata['frames'][0],metadata['frames'][2]
    early=original.replace('s.startup_consumed | ((take >> CAPTURE_SLOTS)',
        's.startup_consumed | (((if accepted { reservation } else { InboxMask:0 }) >> CAPTURE_SLOTS)')
    before=f'u32:{at} => bits[128]:0x{a:x},';after=f'u32:{at+2} => bits[128]:0x{b:x},'
    assert before in original and after in original
    reordered=original.replace(before,f'u32:{at} => bits[128]:0x{b:x},').replace(after,f'u32:{at+2} => bits[128]:0x{a:x},')
    for name,source in [('early-retire',early),('reorder-startup',reordered)]:
        assert source!=original;part=stage/name;part.mkdir()
        for receiver in (fixture/'actors').glob('receiver_*.x'): shutil.copy2(receiver,part/receiver.name)
        (part/'receiver_0.x').write_text(source)
        imports=[part,fixture/'dslx',ROOT/'priv/xls/lib',ROOT/'priv/xls/fabric',compiler_root('default')/'priv/xls/lib',compiler_root('default')/'priv/xls/fabric']
        # Deliberate test corruption bypasses the production direct-component hash check.
        compile_clock(xls,fixture/'network/network.x',part,'network_clock','protocol_network_core',imports)
        simulate(fixture,part,part/'core.v',reject=True)


def selection_checks(xls: Path, stage: Path) -> None:
    """Prove oldest eligible startup selection for every finite mask in three widths."""
    source=ROOT/'test/protocol_startup_properties.x';raw=stage/'selection.ir'
    run([xls/'ir_converter_main','--warnings_as_errors=false','--dslx_path='+str(ROOT/'priv/xls/lib'),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],stage,'selection-convert',raw)
    args=SimpleNamespace(xls=xls,yosys='yosys')
    results=[prove(args,stage,raw,'protocol_startup_properties',p,p!='wrong_eligibility')
             for p in ['selection1','selection4','selection8','wrong_eligibility']]
    (stage/'selection-result.json').write_text(json.dumps({'results':results,
        'domain':'All consumed, eligibility and valid masks at widths 1,4,8.',
        'property':'Exactly the oldest eligible unconsumed declared record is offered; none yields zero.',
        'trust':['DSLX/XLS','Yosys/ABC/SAT'],
        'limits':'Combinational selection only; no whole startup progress or arbitrary-program refinement.'},indent=2)+'\n')


def main() -> None:
    """Run the production path, source-failure variant, negative controls and local capacity screen."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve())
    parser.add_argument('stage',type=lambda p:Path(p).resolve())
    args=parser.parse_args();stage=args.stage;stage.mkdir()
    config=stage/'startup.config';configuration(config,'topology');fixture=stage/'fixture'
    run(['bash','tools/emit_protocol_network.sh',args.xls,config,fixture],stage,'public-build')
    fixture=(fixture/'compiled').resolve()
    assert json.loads((fixture/'network/manifest.json').read_text())['startup_messages']==4
    simulate(fixture,stage)
    negative_wiring(args.xls,fixture,stage)
    selection_checks(args.xls,stage)
    area(fixture,stage)
    failed=stage/'failed';failed.mkdir();configuration(failed/'config','failing')
    run(emit_command('network', failed/'config', failed/'fixture'),failed,'emit',
        env=erlang_environment('default'))
    failed_build=compile_build(args.xls,failed/'fixture');simulate(failed_build,failed,failure=True)
    (stage/'result.json').write_text(json.dumps({'passed':True,'complete_incarnations':2,
        'reset_interruptions':3,'outputs_per_complete_incarnation':10,'final_sum':8,'real_acknowledgments':4,
        'negative_wiring':2,'source_failure_incarnations':2,
        'evidence':'Finite RTL witnesses and finite-mask selection properties; no application admission/native claim.'},indent=2)+'\n')


if __name__ == '__main__':
    main()
