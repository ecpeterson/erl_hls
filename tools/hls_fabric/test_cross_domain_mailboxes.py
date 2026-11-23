"""Witness source-domain retirement using only generated public RTL pins."""
import argparse
from collections import deque
import json
import re
from pathlib import Path
import subprocess

from backend_commands import digest, run
from backend_paths import ROOT, erlang_environment
from protocol_test_build import compile_build


def adapter(metadata: dict) -> str:
    """Render a test-only hex pin adapter; no hardware state is read or changed privately."""
    setters, getters, initialize = [], [], []
    for port in metadata['inputs']:
        name, width = port['name'], port['width']
        initialize.extend(f'd.{name}' + (f'[{i}]' if width > 64 else '') + '=0;'
                          for i in range((width + 31)//32 if width > 64 else 1))
        if width <= 64:
            assign = f'd.{name}=std::stoull(value,nullptr,16);'
        else:
            assign = ''.join(f'd.{name}[{i}]=word(value,{i});' for i in range((width+31)//32))
        setters.append(f'if(name=="{name}"){{{assign}return;}}')
    for port in metadata['outputs']:
        name, width = port['name'], port['width']
        expr = (f'hex(d.{name})' if width <= 64 else
                f'wide(d.{name},{(width+31)//32})')
        getters.append(f'out << "{name}=" << {expr} << " ";')
    return '''// Generated test adapter: named public pins, old-edge sample, then one clock.
#include "Vprotocol_domains.h"
#include "verilated.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <stdexcept>
static uint32_t word(const std::string& text,unsigned index) {
  if(text.size()<=index*8)return 0;
  size_t end=text.size()-index*8,start=end>8?end-8:0;
  return std::stoul(text.substr(start,end-start),nullptr,16);
}
static std::string hex(uint64_t value) {std::ostringstream s;s<<std::hex<<value;return s.str();}
template<class W>static std::string wide(const W& words,int count) {
  std::ostringstream s;s<<std::hex;
  for(int i=count-1;i>=0;--i)s<<std::setw(8)<<std::setfill('0')<<words[i];
  return s.str();
}
static void set(Vprotocol_domains& d,const std::string& name,const std::string& value) {
''' + '\n'.join(setters) + '''
  throw std::runtime_error("unknown public input: "+name);
}
int main(int argc,char** argv) {
  Verilated::commandArgs(argc,argv); Vprotocol_domains d;
''' + '\n'.join(initialize) + '''
  d.clk=0;d.eval();
  std::string line;
  while(std::getline(std::cin,line)) {
    std::istringstream input(line);std::string token;
    while(input>>token) {auto p=token.find('=');set(d,token.substr(0,p),token.substr(p+1));}
    d.clk=0;d.eval();std::ostringstream out;
''' + '\n'.join(getters) + '''
    d.clk=1;d.eval();d.clk=0;d.eval();
    std::cout<<out.str()<<std::endl;
  }
  d.final();return 0;
}
'''


def build(xls: Path, stage: Path, native: Path) -> tuple[Path, dict]:
    """Emit through the Erlang composer and compile its four immutable source units."""
    stage.mkdir()
    bundle = stage/'source'
    expression = ('[Bundle,Native]=init:get_plain_arguments(),'
                  '[code:ensure_loaded(M)||M<-[hls_cross_domain_native,hls_cross_domain_producer,'
                  'hls_cross_domain_consumer,hls_domain_counter]],'
                  'hls_cross_domain_build:write(Bundle,Native),halt().')
    run(['erl','-noshell','-eval',expression,'-extra',bundle,native],stage,'emit',
        env=erlang_environment('test'))
    compiled = compile_build(xls,bundle,profile='test')
    return compile_adapter(bundle, compiled, stage)


def compile_adapter(bundle: Path, compiled: Path, stage: Path) -> tuple[Path, dict]:
    """Build the public-pin test executable from the resolved production RTL."""
    metadata = json.loads((bundle/'fixture.json').read_text())
    manifest = json.loads((bundle/'source-build.json').read_text())
    account_state(bundle,compiled,metadata,stage)
    source = stage/'public_pins.cpp'
    source.write_text(adapter(metadata))
    rtl = list(dict.fromkeys(path for unit in manifest['units'] for path in unit['rtl']))
    run(['verilator','--cc','--exe','--build','--top-module','protocol_domains',
         '--Mdir',stage/'obj_dir','-j','1','-Wno-fatal','-CFLAGS','-std=c++17',
         '-o','simulation',*[compiled/path for path in rtl],source],stage,'verilator',timeout=None)
    return stage/'obj_dir/simulation',metadata


def account_state(bundle: Path, compiled: Path, metadata: dict, stage: Path) -> dict:
    """Enforce preregistered fixture state bounds on complete optimized proc signatures."""
    manifest = json.loads((bundle/'source-build.json').read_text())
    rows = []
    for unit in manifest['units']:
        path = compiled/unit['directory']/'optimized.ir'
        headers = [line for line in path.read_text().splitlines() if line.startswith('top proc ')]
        header, = headers
        parameters = header.split('out>(',1)[1].split(', init=',1)[0]
        fields = re.findall(r'(__state_\d+): bits\[(\d+)\](?= pos=|,|$)',parameters)
        # This fixture's optimized state is scalarized. Reject unknown aggregate state types.
        assert fields and [name for name,_ in fields] == re.findall(r'\b([A-Za-z_][A-Za-z0-9_]*):',parameters)
        rows.append({'unit':unit['directory'],'state_elements':len(fields),
                     'state_bits':sum(int(width) for _,width in fields),'sha256':digest(path)})
    total = sum(row['state_bits'] for row in rows)
    frame_bits = metadata['frame_bits']
    source_bits = metadata['channel']['storage_bits']
    assert source_bits-frame_bits-8 <= 384
    channel, = [row for row in rows if row['unit']=='channel']
    assert channel['state_bits'] <= source_bits <= frame_bits+8+384
    assert total <= 24000
    result = {'passed':True,'units':rows,'optimized_state_bits':total,'budget_bits':24000,
              'channel_source_bits':source_bits,'channel_source_budget_bits':frame_bits+8+384,
              'access':'One retained payload, one capture writer, one transmit reader, one in-flight credit per directed crossing.',
              'limits':'Source/optimized IR state only; not mapped area or physical timing.'}
    (stage/'state-budget.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


class Witness:
    """Bounded delayed transport and public management; all ownership decisions remain RTL."""

    def __init__(self, binary: Path, metadata: dict, directory: Path):
        """Start one simulator with empty test transport queues and a retained edge trace."""
        directory.mkdir()
        self.meta,self.directory = metadata,directory
        self.log = (directory/'edges.jsonl').open('x')
        self.errors = (directory/'simulation.log').open('x')
        self.child = subprocess.Popen([binary],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                                      stderr=self.errors,text=True,bufsize=1)
        self.inputs = {p['name']:0 for p in metadata['inputs']}
        self.channel = metadata['channel']['prefix']
        self.domains = metadata['domains']
        self.incarnations = {name:1 for name in self.domains}
        self.reports = {name:deque() for name in self.domains}
        self.data,self.credits = deque(),deque()
        self.transmitted,self.acknowledged = [],[]
        self.hold_tx,self.hold_data,self.hold_ack,self.hold_credit = False,False,False,False
        self.cycle,self.data_drops,self.credit_drops = 0,0,0
        self.matched = []

    def tick(self, **overrides: int) -> dict:
        """Sample before one edge; queue latency forbids transport bypass on that edge."""
        assert self.cycle < 10000, 'finite witness exceeded 10000 clocks'
        io = dict(self.inputs)
        ch = self.channel
        # Independent finite stalls; a held offer keeps exactly the same payload.
        io[ch+'data_tx_ready'] = int(not self.hold_tx and len(self.data)<1 and self.cycle%5!=1)
        io[ch+'ack_tx_ready'] = int(not self.hold_ack and len(self.credits)<1 and self.cycle%7!=2)
        io[ch+'data_valid'] = int(bool(self.data) and not self.hold_data)
        if self.data:
            io.update({ch+'data_'+k:v for k,v in self.data[0].items()})
        io[ch+'credit_valid'] = int(bool(self.credits) and not self.hold_credit)
        if self.credits:
            io.update({ch+'credit_'+k:v for k,v in self.credits[0].items()})
        for domain in self.domains.values():
            io[domain['report']['ready']] = int(self.cycle%3!=0)
        io.update(overrides)
        assert io.keys()==self.inputs.keys(), 'driver attempted a nonpublic pin'
        self.child.stdin.write(' '.join(f'{k}={v:x}' for k,v in io.items())+'\n')
        self.child.stdin.flush()
        line = self.child.stdout.readline()
        assert line, f'simulator terminated at edge {self.cycle}'
        out = {k:int(v,16) for k,v in (part.split('=') for part in line.split())}
        self.log.write(json.dumps({'cycle':self.cycle,'inputs':io,'outputs':out})+'\n')
        assert not out[ch+'fault'], 'compiled channel service failed'
        if io[ch+'data_valid'] and out[ch+'data_ready']:
            self.data.popleft()
            self.data_drops += out[ch+'data_drop']
        if io[ch+'credit_valid'] and out[ch+'credit_ready']:
            self.credits.popleft()
            self.credit_drops += out[ch+'credit_drop']
        if out[ch+'tx_valid'] and io[ch+'data_tx_ready']:
            packet = {k:out[ch+'tx_'+k] for k in ('generation','sequence','slot','frame')}
            self.data.append(packet)
            self.transmitted.append(packet.copy())
        if out[ch+'ack_valid'] and io[ch+'ack_tx_ready']:
            credit = {k:out[ch+'ack_'+k] for k in ('generation','sequence')}
            self.credits.append(credit)
            self.acknowledged.append(credit.copy())
        assert len(self.data)<=1 and len(self.credits)<=1
        for name,domain in self.domains.items():
            report = domain['report']
            if out[report['valid']] and io[report['ready']]:
                self.reports[name].append(out[report['data']])
        self.cycle += 1
        self.last = out
        return out

    def until(self, predicate, limit: int = 1000) -> dict:
        """Wait for an observed public condition, never a predicted internal completion."""
        for _ in range(limit):
            out = self.tick()
            if predicate(out): return out
        raise AssertionError(f'public observation timeout at {self.cycle}: {self.last}')

    def phase(self, name: str, phase: str) -> None:
        """Wait for the compiled domain's retained lifecycle observation."""
        expected = self.meta['domain_codecs']['phase']['values'][phase]
        prefix = self.domains[name]['prefix']
        self.until(lambda out:out[prefix+'domain_phase']==expected)

    def management(self, name: str, op: str, expected: int, target: int, transition: int) -> None:
        """Submit one exact lifecycle request through the ordinary raw management pins."""
        prefix = self.domains[name]['prefix']
        values = {'management_valid':1,'management_op':self.meta['domain_codecs']['operation']['values'][op],
                  'expected':expected,'target':target,'transition':transition}
        self.inputs.update({prefix+k:v for k,v in values.items()})
        out = self.until(lambda out:bool(out[prefix+'management_response_valid']))
        self.inputs[prefix+'management_valid']=0
        assert out[prefix+'domain_status']==self.meta['domain_codecs']['status']['values']['accepted'], out

    def bind(self, generation: int, accepted: bool = True) -> None:
        """Explicitly bind the observed endpoint pair; no host-to-hardware identity override exists."""
        out = self.tick(**{self.channel+'bind_request':1,self.channel+'expected_generation':generation})
        status = self.meta['channel_codecs']['status']['values']
        assert out[self.channel+'active']==int(accepted), out
        assert out[self.channel+'generation']==generation+int(accepted), out
        assert out[self.channel+'status']==status['accepted' if accepted else 'stale'], out

    def send(self, command: str) -> None:
        """Deliver a source message using the codec-derived spatial ingress packet."""
        stimulus = self.meta['stimuli'][command]
        name = stimulus['actor']; prefix = self.domains[name]['prefix']
        self.inputs.update({prefix+'ingress_valid':1,prefix+'ingress_data':stimulus['spatial'],
                            prefix+'incarnation':self.incarnations[name]})
        out = self.until(lambda out:bool(out[prefix+'app_ingress_ready']))
        assert not out[prefix+'domain_rejected']
        self.inputs[prefix+'ingress_valid']=0

    def expect(self, row: dict) -> None:
        """Match the next report from its logical actor; do not skip unexpected outputs."""
        name = row['actor']
        self.until(lambda _:bool(self.reports[name]))
        observed = self.reports[name].popleft()
        assert observed==row['frame'], (self.cycle,row,observed)
        self.matched.append(row)

    def command(self, command: str, expected: dict) -> None:
        """Submit one public request and match its native reference result."""
        self.send(command); self.expect(expected)

    def run(self) -> dict:
        """Witness ordered transfer, blocked-old work, dependent replacement and independent progress."""
        expected = self.meta['expected']
        for _ in range(3): self.tick(reset=1)
        for name in ('a','b','c'):
            self.management(name,'activate',0,1,1); self.phase(name,'ready')
        self.bind(0)
        for name in ('a','b','c'):
            self.command('initial_'+name,expected['initial'][name])
        self.send('before_burst')
        for row in expected['before_burst']: self.expect(row)
        for name in ('a','b','c'):
            self.command('before_'+name,expected['before_readouts'][name])
        self.until(lambda _:not self.data and not self.credits)
        old_credit = self.acknowledged[0].copy()
        # A real source continuation holds more old work behind the retained first packet.
        self.hold_data=True
        self.send('held_burst')
        self.until(lambda _:bool(self.data))
        old_data = self.data[0].copy()
        for _ in range(17): self.tick()
        assert self.data[0]==old_data
        self.command('before_c',expected['before_readouts']['c'])
        self.send('explode_b'); self.phase('b','failed')
        assert not self.last[self.channel+'active']
        # The receiving endpoint alone cannot rebind an old source's retained publication.
        self.management('b','replace',1,2,2); self.phase('b','ready')
        self.incarnations['b']=2
        self.bind(1,accepted=False)
        self.management('a','stop',1,1,2); self.phase('a','stopped')
        self.management('a','replace',1,2,3); self.phase('a','ready')
        self.incarnations['a']=2
        self.bind(1)
        self.credits.append(old_credit)
        self.hold_data=False
        self.until(lambda _:not self.data and not self.credits)
        assert self.data_drops>=1 and self.credit_drops>=1
        for name in ('a','b','c'):
            self.command('after_'+name,expected['after_reset'][name])
        # Old credits while a new packet is retained cannot release it or issue a second packet.
        self.hold_tx=True
        count = len(self.transmitted)
        self.send('after_burst')
        held = self.until(lambda out:bool(out[self.channel+'tx_valid']))
        identity = tuple(held[self.channel+'tx_'+k] for k in ('generation','sequence','slot','frame'))
        self.credits.append(old_credit)
        for _ in range(19):
            out = self.tick()
            assert out[self.channel+'tx_valid']
            assert identity==tuple(out[self.channel+'tx_'+k] for k in ('generation','sequence','slot','frame'))
        assert len(self.transmitted)==count
        self.hold_data=True
        self.hold_ack=True
        self.hold_credit=True
        self.hold_tx=False
        self.until(lambda _:bool(self.data))
        fresh_data=self.data.popleft()
        stale_data=self.transmitted[0].copy()
        assert fresh_data['sequence']==stale_data['sequence']==1
        assert fresh_data['generation']!=stale_data['generation']
        self.data.append(stale_data)
        drops=self.data_drops
        self.hold_data=False
        self.until(lambda _:not self.data)
        assert self.data_drops==drops+1 and not self.last[self.channel+'ack_valid']
        assert not self.reports['b']
        self.data.append(fresh_data)
        # Hold the actual acknowledgement while C runs; subsequent credits remain distinct edges.
        self.until(lambda out:bool(out[self.channel+'ack_valid']))
        self.command('c_add',expected['independent_c'][0])
        self.command('c_read',expected['independent_c'][1])
        self.hold_ack=False
        self.until(lambda _:bool(self.credits))
        fresh_credit=self.credits.popleft()
        assert fresh_credit['sequence']==old_credit['sequence']==1
        assert fresh_credit['generation']!=old_credit['generation']
        self.credits.append(old_credit)
        drops=self.credit_drops
        count=len(self.transmitted)
        self.hold_credit=False
        self.until(lambda _:not self.credits)
        assert self.credit_drops==drops+1
        for _ in range(13): self.tick()
        assert len(self.transmitted)==count, 'old credit released current source ownership'
        self.credits.append(fresh_credit)
        for row in expected['after_burst']: self.expect(row)
        self.command('final_a',expected['final']['a'])
        self.command('final_b',expected['final']['b'])
        self.until(lambda _:not self.data and not self.credits)
        # Simultaneous explicit endpoint reset must gate an already visible held transmit.
        self.hold_tx=True
        self.send('held_burst')
        self.until(lambda out:bool(out[self.channel+'tx_valid']))
        out = self.tick(**{self.domains['b']['prefix']+'reset':1,
                          self.channel+'data_tx_ready':1})
        assert not out[self.channel+'tx_valid'] and not out[self.channel+'ack_valid']
        assert not out[self.channel+'data_ready'] and not out[self.channel+'credit_ready']
        assert not out[self.channel+'active']
        for _ in range(30): self.tick()
        assert all(not rows for rows in self.reports.values()), self.reports
        self.command('c_read',expected['independent_c'][1])
        assert self.last[self.domains['c']['prefix']+'domain_current']==1
        return {'passed':True,'cycles':self.cycle,'matched_reports':len(self.matched),
                'data_drops':self.data_drops,'credit_drops':self.credit_drops,
                'transmitted':self.transmitted,'acknowledged':self.acknowledged,
                'evidence':'Finite native-history/public-pin RTL witness; same clock, delayed data/credit replay.',
                'limits':'No native equivalence, CDC, physical fence, framed deployment, board or general progress claim.'}

    def close(self) -> None:
        """Finish the one simulator even after an assertion; retain every observed edge."""
        self.child.stdin.close()
        try:
            code = self.child.wait(timeout=5)
            assert code==0, code
        finally:
            if self.child.poll() is None:
                self.child.kill(); self.child.wait()
            self.child.stdout.close();self.log.close();self.errors.close()


def witness(binary: Path, metadata: dict, directory: Path) -> dict:
    """Keep failed traces and publish a result only after the entire finite schedule passes."""
    test = Witness(binary,metadata,directory)
    try:
        result = test.run()
    finally:
        test.close()
    (directory/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('transmitted','acknowledged')}),flush=True)
    return result


def main() -> None:
    """Run the native reference and production bundle once, then the finite RTL transport schedule."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda value:Path(value).resolve())
    parser.add_argument('stage',type=lambda value:Path(value).resolve())
    args=parser.parse_args();args.stage.mkdir()
    native=args.stage/'native'
    run(['erl','-noshell','-eval','[D]=init:get_plain_arguments(),ok=hls_cross_domain_native:native(D),halt().',
         '-extra',native],args.stage,'native',env=erlang_environment('test'))
    binary,metadata=build(args.xls,args.stage/'build',native)
    witness(binary,metadata,args.stage/'witness')


if __name__=='__main__':
    main()
