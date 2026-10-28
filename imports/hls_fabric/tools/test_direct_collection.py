#!/usr/bin/env python3
"""Exercise generated singleton collection with early input, stalls, reset and faults."""
import argparse
import json
import re
from pathlib import Path

from compiler_paths import compiler_root
from backend_paths import ROOT, erlang_paths
from backend_commands import execute


def state_paths(dslx: str) -> dict[int, str]:
    """Map flattened state leaves, resolving imported records and parameterized aliases.

    Arrays remain one state identity; scalar records, including axis frames,
    flatten recursively. Missing imported layouts fail rather than shift indices.
    """
    result: dict[int, str] = {}
    sources: dict[str, str] = {'': dslx}

    def visit(kind: str, path: str, module: str = '', seen: tuple[str, ...] = ()) -> None:
        """Resolve one type in its declaring module and enumerate scalar leaves."""
        if '[' in kind:
            result[len(result)] = path
            return
        if '::' in kind:
            module, kind = kind.split('::', 1)
            if module not in sources:
                locations = [root/'priv/xls'/folder/(module+'.x')
                             for root in (ROOT, compiler_root("test")) for folder in ('lib', 'fabric')]
                found = next((p for p in locations if p.is_file()), None)
                if found is None:
                    raise ValueError(f'missing imported state layout: {module}')
                sources[module] = found.read_text()
        source = sources[module]
        name = kind.split('<', 1)[0]
        identity = module+'::'+name
        if identity in seen:
            raise ValueError('recursive collection state type')
        active = (*seen, identity)
        aliases = re.findall(r'(?:pub\s+)?type\s+'+re.escape(name)+r'\s*=\s*([^;]+);', source)
        if aliases:
            if len(aliases) != 1:
                raise ValueError(f'ambiguous state type: {identity}')
            visit(aliases[0].strip(), path, module, active)
            return
        records = re.findall(r'(?:pub\s+)?struct\s+'+re.escape(name)+
                             r'(?:<[^>]+>)?\s*\{([^}]+)\}', source)
        if not records:
            result[len(result)] = path
            return
        if len(records) != 1:
            raise ValueError(f'ambiguous state record: {identity}')
        for field, value in re.findall(r'^\s*(\w+)\s*:\s*([^,]+),', records[0], re.M):
            visit(value.strip(), path+'.'+field, module, active)

    if not re.search(r'\bstruct DirectCollectionState\b', dslx):
        raise ValueError('missing generated direct collection state')
    visit('DirectCollectionState', 'state')
    return result


def check_output_boundary(rtl: str, dslx: str) -> list[dict]:
    """Reject actor-output readiness depending on held input or current commands.

    Trace continuous assignments to registered boundaries, whose ownership comes
    from the actual generated DSLX layout. This is a structural dependency check,
    not timing estimation or sequential equivalence. Unknown leaves fail closed.
    """
    rows, layout = [], state_paths(dslx)
    for match in re.finditer(r'^module (\w*CollectionService\w*)\(.*?^endmodule', rtl, re.M | re.S):
        body = match[0]
        assigns = {}
        for name, indices, value in re.findall(r'\bassign\s+(\w+)((?:\[[^]]+\])*)\s*=\s*([^;]+);', body):
            assigns[name] = assigns.get(name, '') + ' ' + indices + ' ' + value
        registers = set(re.findall(r'\breg(?:\s+\[[^]]+\])?\s+(\w+)', body))
        inputs = set(re.findall(r'input wire(?:\s+\[[^]]+\])?\s+(\w+)', body))
        functions = set()
        for definition in re.findall(r'\bfunction\b.*?\bendfunction\b', body, re.S):
            name, = re.findall(r'function automatic(?: \[[^]]+\])? (\w+)', definition)
            locals_ = set(re.findall(r'input reg(?: \[[^]]+\])? (\w+)', definition))
            text = re.sub(r'//[^\n]*', '', definition)
            text = re.sub(r"\b\d+'[sS]?[bBoOdDhH][0-9a-fA-FxXzZ_?]+", '', text)
            identifiers = set(re.findall(r'\b[A-Za-z_]\w*\b', text))
            keywords = {'function','automatic','input','reg','begin','end','endfunction','casez','endcase','default'}
            if identifiers - locals_ - keywords - {name}:
                raise ValueError(f'function {name} has nonlocal dependencies')
            functions.add(name)
        if 'active_outputs_ready_0' not in assigns:
            raise ValueError('missing collector activation readiness')
        pending, seen, leaves = ['active_outputs_ready_0'], set(), set()
        while pending:
            name = pending.pop()
            if name in seen:
                continue
            seen.add(name)
            if name in registers or name in inputs:
                leaves.add(name)
            elif name in functions:
                continue
            elif name in assigns:
                expression = re.sub(r"\b\d+'[sS]?[bBoOdDhH][0-9a-fA-FxXzZ_]+", '', assigns[name])
                pending.extend(re.findall(r'\b[A-Za-z_]\w*\b', expression))
            else:
                raise ValueError(f'unknown combinational leaf {name}')
        owners = {}
        for name in sorted(leaves):
            state = re.fullmatch(r'____state_(\d+)(?:_\w+)?', name)
            if state:
                path = layout[int(state[1])]
                if path != 'state.publish_valid' and (
                        not path.startswith(('state.machine.', 'state.collection.')) or
                        path.startswith('state.machine.slots')):
                    raise ValueError(f'{match[1]}: readiness crosses {path}')
                owners[name] = path
            elif name in ('___egress_out_already_done_reg', '___actor_debug_out_already_done_reg') or name.endswith('_rdy'):
                owners[name] = 'output handshake'
            else:
                raise ValueError(f'{match[1]}: unclassified readiness leaf {name}')
        rows.append({'module': match[1], 'registered_dependencies': owners})
    if not rows:
        raise ValueError('no generated collector service')
    return rows



def overlap_observer(rtl: str, dslx: str, bench: str) -> str:
    """Require committed consecutive bank folds across both actor phases in RTL.

    Bind the actual generated consumed predicate to the retained contribution
    validity field; fail closed if optimization changes that observable boundary.
    The observer never drives the DUT or changes the exercised histories.
    """
    name, body = re.findall(r'^module (\w*CollectionService\w*)\((.*?)^endmodule',
                            rtl, re.M | re.S)[0]
    instance, = re.findall(r'^\s*'+re.escape(name)+r'\s+(\w+)\s*\(', rtl, re.M)
    paths = {v: k for k, v in state_paths(dslx).items()}
    valid = '____state_'+str(paths['state.contribution_valid'])
    command = '____state_'+str(paths['state.command_valid'])
    expression, = re.findall(r'assign consumed = ([^;]+);', body)
    if not re.search(r'\b'+valid+r'\b', expression):
        raise ValueError('collector consumed predicate lost retained contribution validity')
    for signal in (valid, command):
        if not re.search(r'\breg '+signal+r';', body):
            raise ValueError(f'collector observation lost scalar register {signal}')
    stem = 'dut.'+instance
    observation = f"""
  integer last_fold_cycle=-2, collector_folds=0;
  reg fold_on_grant=0, fold_on_execute=0, consecutive_folds=0;
  always @(posedge clk) begin
    if(reset) last_fold_cycle=-2;
    else if({stem}.active_outputs_ready_0 && {stem}.consumed) begin
      collector_folds=collector_folds+1;
      if(cycles==last_fold_cycle+1) consecutive_folds=1;
      last_fold_cycle=cycles;
      if({stem}.{command}) fold_on_execute=1; else fold_on_grant=1;
    end
  end
"""
    checked = bench.replace('  initial begin\n', observation+'  initial begin\n', 1)
    needle = '    $display("PASS:'
    if checked.count(needle) != 1:
        raise ValueError('collector test lacks unique final success boundary')
    return checked.replace(needle, '    if(!fold_on_grant || !fold_on_execute || !consecutive_folds)\n'
                           '      $fatal(1,"collector did not overlap both actor phases");\n'
                           '    $display("FOLD_RATE: %0d folds, consecutive=1, both_actor_phases=1",collector_folds);\n'
                           +needle)


def main() -> None:
    """Compile the real actor backend and require a bounded RTL scoreboard to finish."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=lambda p: Path(p).resolve())
    parser.add_argument('--stage', type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--pipeline-stages', type=int, choices=(2, 3), default=2)
    args = parser.parse_args()
    stage, xls = args.stage, args.xls
    stage.mkdir(parents=True, exist_ok=False)
    expression = '''[Source, Target] = init:get_plain_arguments(),
      Body = xls_scheduler_actor:to_xls(Source, #{direct_collection => exclusive_epoch, direct_actor_debug => true}),
      ok = file:write_file(Target, Body), halt().'''
    execute(['erl', '-noshell', '-pa', *erlang_paths("test"), '-eval', expression, '-extra',
             str(ROOT/'test/hls_projection_reduction_fixture.erl'), str(stage/'collector.x')], stage, 'generate')
    with (stage/'collector.x').open('a') as output:
        output.write('''
// Expose two independent producers and the ordered startup source to the test.
pub proc CollectionTest {
  // The ordinary runtime, per-producer buffers and collector are all generated.
  config(inputs: chan<axis::Frame>[u32:2] in,
      startup: chan<axis::Frame> in, output: chan<Egress> out,
      observation: chan<ActorObservation> out) {
    spawn CollectionService<u32:2, u32:1>(inputs, startup, output, observation); ()
  }
  // No state is owned by the test wrapper.
  init { () }
  // All behavior belongs to the generated service.
  next(state: ()) { state }
}
''')
    commands = [
        ([str(xls/'ir_converter_main'), '--top=CollectionTest', '--warnings_as_errors=false',
          f'--dslx_path={ROOT/"priv/xls/lib"}:{compiler_root('test')/"priv/xls/lib"}:{compiler_root('test')/"priv/xls/fabric"}',
          f'--dslx_stdlib_path={xls/"xls/dslx/stdlib"}', str(stage/'collector.x')], 'convert', 'collector.ir'),
        ([str(xls/'opt_main'), str(stage/'collector.ir')], 'opt', 'collector.opt.ir'),
        ([str(xls/'codegen_main'), f'--pipeline_stages={args.pipeline_stages}', '--delay_model=unit',
          '--flop_inputs=false', '--flop_outputs=true', '--use_system_verilog=false',
          '--reset=reset', '--fifo_module=', '--module_name=collector', str(stage/'collector.opt.ir')],
         'codegen', 'collector.v')]
    for command, name, output in commands:
        execute(command, stage, name, output=stage/output)
    (stage/'output-boundary.json').write_text(json.dumps(
        check_output_boundary((stage/'collector.v').read_text(), (stage/'collector.x').read_text()), indent=2) + '\n')
    tags = dict(re.findall(r'^  (BEGIN_SET|PIECE|RESULT) = u8:(\d+),', (stage/'collector.x').read_text(), re.M))
    parameters = [f'-Pdirect_collection_tb.TAG_{name}={tags[name]}' for name in ('BEGIN_SET', 'PIECE', 'RESULT')]
    width, = re.findall(r'pub type ActorObservation = bits\[(\d+)\]', (stage/'collector.x').read_text())
    parameters.append(f'-Pdirect_collection_tb.OBSERVATION_BITS={width}')
    bench = overlap_observer((stage/'collector.v').read_text(), (stage/'collector.x').read_text(),
                             (ROOT/'test/rtl/direct_collection_tb.sv').read_text())
    (stage/'testbench.sv').write_text(bench)
    execute(['iverilog', '-g2012', '-s', 'direct_collection_tb', *parameters, '-o', str(stage/'test.vvp'),
             str(stage/'testbench.sv'), str(stage/'collector.v')], stage, 'test-compile')
    execute(['vvp', str(stage/'test.vvp')], stage, 'simulate')
    report = (stage/'simulate.log').read_text()
    if 'PASS:' not in report:
        raise ValueError('collector scoreboard did not finish')
    print(report, end='')


if __name__ == '__main__':
    main()
