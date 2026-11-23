#!/usr/bin/env python3
"""Prepare resumable operation probes over bounded width, fan-in and index dimensions."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import math
from pathlib import Path
import re
import time
from characterize import harness, operation, run, sha


def probe(op: str, width: int, count: int) -> tuple[str, list[tuple[str, int]], int]:
    """Return a canonical operation with explicit default/index/array semantics."""
    args, ports, result, extra = [], [], width, ''
    nested = re.fullmatch(r'array2_(s[0-9]+|c0)_(s[0-9]+|c0)_n([0-9]+)_n([0-9]+)', op)
    shift = re.fullmatch(r'(shll|shrl|shra)_s(\d+)', op)
    indexed = re.fullmatch(r'(sel_d|array_index_s|array_update_s)(\d+)', op)
    if nested:
        outer,inner=int(nested[3]),int(nested[4])
        args=[('a',f'bits[{width}][{inner}][{outer}]')]
        ports=[('a',width*inner*outer)];indices=[]
        for i,mode in enumerate((nested[1],nested[2])):
            name=f'i{i}';indices.append(name)
            if mode=='c0':extra+=f'  {name}: bits[32] = literal(value=0)\n'
            else:
                bits=int(mode[1:]);args.append((name,f'bits[{bits}]'));ports.append((name,bits))
        result_type=f'bits[{width}]';body=f'array_index(a, indices=[{", ".join(indices)}])'
    elif shift:
        args = [('a', f'bits[{width}]'), ('amount', f'bits[{shift[2]}]')]
        ports = [('a', width), ('amount', int(shift[2]))]
        result_type, body = f'bits[{width}]', f'{shift[1]}(a, amount)'
    elif indexed:
        kind, selector = indexed[1], int(indexed[2])
        args = [('index', f'bits[{selector}]')]
        ports = [('index', selector)]
        if kind == 'sel_d':
            args += [(f'v{i}', f'bits[{width}]') for i in range(count)]
            args += [('otherwise', f'bits[{width}]')]
            ports += [(name, width) for name, _ in args[1:]]
            body = f'sel(index, cases=[{", ".join(f"v{i}" for i in range(count))}], default=otherwise)'
            result_type = f'bits[{width}]'
        else:
            args += [('a', f'bits[{width}][{count}]')]
            ports += [('a', width*count)]
            if kind == 'array_index_s':
                body = 'array_index(a, indices=[index])'
                result_type = f'bits[{width}]'
            else:
                args += [('item', f'bits[{width}]')]
                ports += [('item', width)]
                body = 'array_update(a, item, indices=[index])'
                result_type = f'bits[{width}][{count}]'
                result = width*count
    elif op in ('and', 'or', 'xor', 'nand', 'nor'):
        args = [(f'a{i}', f'bits[{width}]') for i in range(count)]
        ports = [(name, width) for name, _ in args]
        body = f'{op}({", ".join(name for name, _ in args)})'
        result_type = f'bits[{width}]'
    elif op in ('ne', 'ule', 'ugt', 'uge', 'sle', 'sge'):
        args = [('a', f'bits[{width}]'), ('b', f'bits[{width}]')]
        ports, result, result_type = [('a', width), ('b', width)], 1, 'bits[1]'
        body = f'{op}(a, b)'
    elif op in ('one_hot_lsb', 'one_hot_msb'):
        args, ports = [('a', f'bits[{width}]')], [('a', width)]
        result, result_type = width+1, f'bits[{width+1}]'
        body = f'one_hot(a, lsb_prio={str(op.endswith("lsb")).lower()})'
    elif op == 'gate':
        args, ports = [('enable', 'bits[1]'), ('a', f'bits[{width}]')], [('enable', 1), ('a', width)]
        result_type, body = f'bits[{width}]', 'gate(enable, a)'
    else:
        return operation(op, width, count)
    signature = ', '.join(f'{name}: {kind}' for name, kind in args)
    return f'package probe\n\ntop fn main({signature}) -> {result_type} {{\n{extra}  ret result: {result_type} = {body}\n}}\n', ports, result


def prepare_one(spec: dict, root: Path, codegen: Path, yosys: Path, tools: dict) -> dict:
    """Map a probe once, preserving fabric boundaries and checked input fingerprints."""
    directory = root/spec['name']
    done = directory/'prepared.json'
    identity = dict(spec=spec, tools=tools)
    if done.exists():
        saved = json.loads(done.read_text())
        if saved['identity'] != identity or any(sha(directory/n) != v for n, v in saved['row']['files'].items()):
            raise ValueError(f'{directory}: changed prepared probe')
        return saved['row']
    directory.mkdir(exist_ok=False)
    ir, ports, result = probe(spec['op'], spec['width'], spec['count'])
    (directory/'probe.ir').write_text(ir)
    run([codegen, '--generator=combinational', '--use_system_verilog=false',
         '--module_name=operation', 'probe.ir'], directory, 'codegen', directory/'operation.v')
    (directory/'harness.v').write_text(harness('operation', ports, result))
    (directory/'map.ys').write_text(
        'read_verilog -sv operation.v harness.v\n'
        'synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top probe_top\n'
        'check -assert\nscc -expect 0\ndelete t:$scopeinfo\nwrite_json mapped.json\n')
    run([yosys, '-Q', '-q', '-s', 'map.ys'], directory, 'map', timeout=900)
    data = json.loads((directory/'mapped.json').read_text())
    top = data['modules']['probe_top']
    top['cells'] = {n:c for n,c in top['cells'].items() if c['type'] != '$scopeinfo'}
    data['modules'] = {'probe_top': top}
    (directory/'mapped.json').write_text(json.dumps(data,separators=(',',':'))+'\n')
    run([yosys, '-Q', '-q', '-p', 'read_verilog -lib +/xilinx/cells_sim.v; read_json mapped.json; write_edif -pvector bra mapped.edf'], directory, 'edif')
    cells = top['cells'].values()
    if sum(c['type']=='FDRE' for c in cells) != sum(w for _,w in ports)+result:
        raise ValueError(f'{directory}: fabric boundary changed')
    for cell in top['cells'].values():
        if cell['type']=='DSP48E1' and any(int(v,2) for k,v in cell['parameters'].items() if k.endswith('REG')):
            raise ValueError(f'{directory}: absorbed DSP register')
    row = dict(spec, files={name:sha(directory/name) for name in ('probe.ir','operation.v','harness.v','map.ys','mapped.json','mapped.edf')})
    done.write_text(json.dumps(dict(identity=identity,row=row),indent=2)+'\n')
    return row


def plan() -> list[dict]:
    """Cover planned scheduler/queue growth; reserve non-grid shapes for validation."""
    cases = {}
    def add(op: str, widths: list[int], counts: list[int], split: str = 'training') -> None:
        """Add independent shapes, rejecting conflicting training/validation roles."""
        for width in widths:
            for count in counts:
                key = op,width,count
                if key in cases and cases[key]['split'] != split:
                    raise ValueError(f'duplicate split {key}')
                cases[key] = dict(name=f'{op}_w{width}_n{count}',op=op,width=width,count=count,split=split)
    for op in ('sel','one_hot_sel','priority_sel'):
        add(op,[1,8,64,256,1024],[2,4,8,16,32])
        add(op,[24,384],[4,16],'validation')
        if op!='sel':
            add(op,[1,8,64,256,1024],[1])
            add(op,[24,384],[3,6,17],'validation')
    for selector in (1,2,3,4,5,6,8,16,32,64):
        counts=sorted({n for n in (1,2,4,8,16,32,min(32,2**selector-1)) if n < 2**selector})
        add(f'sel_d{selector}',[1,64,1024],counts)
    for op in ('and','or','xor','nand','nor'):
        add(op,[1,8,64,1024],[2,4,8,16,32])
        add(op,[24,384],[3,7],'validation')
    for op in ('ne','ule','ugt','uge','sle','sge','one_hot_lsb','one_hot_msb'):
        add(op,[1,8,32,64],[2])
        add(op,[24],[2],'validation')
    add('gate',[1,8,64,256,1024],[2])
    for op in ('eq','ne','ult','ule','ugt','uge','slt','sle','sgt','sge'):
        add(op,[128,256,1024],[2])
    for op in ('shll','shrl','shra'):
        add(op,[128,256,1024],[2])
        for selector in (4,8,16,32,64):
            add(f'{op}_s{selector}',[8,32,128,1024],[2])
    for op in ('array_index_s','array_update_s'):
        for selector in (2,3,8,32,64):
            counts=[n for n in (2,4,8,16,32) if n<=2**selector]
            add(f'{op}{selector}',[1,8,128,256,1024],counts)
        add(f'{op}32',[24],[3,5,17],'validation')
    for shape in ('s32_s8_n4_n5','s2_s8_n4_n5','s3_s1_n8_n2','s2_s1_n4_n2','s32_s8_n8_n8','s32_c0_n4_n5','c0_s8_n4_n5'):
        add(f'array2_{shape}',[1,8,128],[2],'composed_validation')
    # A partial selector just below its index range retains a default decoder;
    # a full selector of the same width does not measure that circuit.
    for selector, counts in [(2,[3]), (3,[3,5]), (4,[9]), (5,[17])]:
        add(f'sel_d{selector}', [24,384], counts, 'validation')
    for prefix in ('array_index_s','array_update_s'):
        for selector, counts in [(2,[3]), (3,[3,5,7]), (4,[9,15])]:
            add(f'{prefix}{selector}', [24,384], counts, 'validation')
    # Index rounding is a separate approximation: do not train on these widths.
    for selector in (7, 12, 24):
        for prefix in ('sel_d', 'array_index_s', 'array_update_s'):
            add(f'{prefix}{selector}', [24, 384], [3, 17], 'validation')
        for prefix in ('shll_s', 'shrl_s', 'shra_s'):
            add(f'{prefix}{selector}', [24, 384], [2], 'validation')
    # This full-width update exceeds this part's LUT capacity with a 32- or 64-bit
    # index. Keep the 32-entry boundary at a measurable 512-bit payload.
    for selector in (32,64):
        del cases[f'array_update_s{selector}',1024,32]
        add(f'array_update_s{selector}',[512],[32])
    return list(cases.values())


def main() -> None:
    """Prepare a bounded batch or emit its plan without touching tool outputs."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage',type=Path,required=True)
    parser.add_argument('--codegen',type=Path)
    parser.add_argument('--yosys',type=Path)
    parser.add_argument('--jobs',type=int,choices=(1,2,3,4),default=2)
    parser.add_argument('--plan-only',action='store_true')
    parser.add_argument('--plan',type=Path,help='replay a saved plan instead of the built-in grid')
    parser.add_argument('--existing-table',type=Path,help='omit training shapes already measured in this table')
    parser.add_argument('--names',nargs='+')
    args=parser.parse_args();args.stage=args.stage.resolve();args.stage.mkdir(parents=True,exist_ok=True)
    specs=json.loads(args.plan.read_text()) if args.plan else plan()
    for spec in specs:
        if (not isinstance(spec, dict) or spec.get('split') not in ('training','validation','composed_validation')
                or type(spec.get('width')) is not int or spec['width'] <= 0
                or type(spec.get('count')) is not int or spec['count'] <= 0
                or not re.fullmatch(r'[a-z][a-z0-9_]*', spec.get('op', ''))
                or spec.get('name') != f"{spec['op']}_w{spec['width']}_n{spec['count']}"):
            parser.error('invalid saved probe specification')
    if len({spec['name'] for spec in specs}) != len(specs):
        parser.error('duplicate saved probes')
    if args.existing_table:
        measured = {(parts[0], int(parts[1]), int(parts[2]))
                    for line in args.existing_table.read_text().splitlines()
                    if (parts := line.split()) and not parts[0].startswith('#')}
        specs = [spec for spec in specs if spec['split'] != 'training'
                 or (spec['op'],spec['width'],spec['count']) not in measured]
    if args.names:
        specs=[s for s in specs if s['name'] in args.names]
        if len(specs)!=len(set(args.names)):parser.error('unknown or duplicate probe names')
    (args.stage/'plan.json').write_text(json.dumps(specs,indent=2)+'\n')
    print(f'{len(specs)} probes',flush=True)
    if args.plan_only:return
    if args.codegen is None or args.yosys is None:parser.error('both tools required')
    args.codegen,args.yosys=args.codegen.resolve(),args.yosys.resolve()
    rows=[];start=time.monotonic()
    tools={str(p):sha(p) for p in (args.codegen,args.yosys,Path(__file__),Path(__file__).with_name('characterize.py'))}
    failures = []
    with ThreadPoolExecutor(max_workers=args.jobs) as workers:
        pending = {workers.submit(prepare_one, spec, args.stage, args.codegen, args.yosys, tools): spec
                   for spec in specs}
        for future in as_completed(pending):
            spec = pending[future]
            try:
                row = future.result()
            except Exception as error:
                failures.append({'name': spec['name'], 'error': str(error)})
                (args.stage/'failures.json').write_text(json.dumps(failures, indent=2)+'\n')
                print(spec['name'], str(error), flush=True)
                continue
            rows.append(row)
            manifest=dict(schema=1,part='xc7z030sbg485-1',flow='synth_xilinx -abc9',tools=tools,
                          probes=sorted(rows, key=lambda item: item['name']))
            (args.stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
            print(row['name'],round(time.monotonic()-start,1),flush=True)
    if failures:
        raise SystemExit(f'{len(failures)} failed probes; see failures.json')


if __name__=='__main__':
    main()
