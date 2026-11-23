#!/usr/bin/env python3
"""Measure the exact staged reciprocal inside an otherwise frozen phi executor."""
import argparse
import difflib
import json
from pathlib import Path
import shutil

from architecture import sha
from completion_experiment import build
from executor_arrival import prepare as compile_executor


def prepare(args: argparse.Namespace) -> Path:
    """Specialize only the measured signed-37-bit divide-by-twelve operation."""
    source = args.stage / 'sources'
    source.mkdir(parents=True, exist_ok=False)
    for path in args.reference.glob('*.x'):
        shutil.copyfile(path, source / path.name)
    for name in ('phi_decoder_profile.v', 'phi_decoder_profile_top.v', 'hls_1r1w_ram.v',
                 'phi_decoder_profile.json', 'phi_decoder_profile.build.json'):
        shutil.copyfile(args.rtl_reference / name, source / name)
    if args.library:
        inputs = [*args.reference.glob('*.x'), *args.library.glob('*.x')]
        for name in ('hls_fixed.x', 'hls_multiply.x'):
            shutil.copyfile(args.library / name, source / name)
        field = source / 'phi_field.x'
        old = field.read_text()
        field.write_text(old.replace('hls_fixed::round_ratio<u32:12>',
                                    'hls_fixed::round_ratio_chunked<u32:12, u32:24, u32:17>'))
        (args.stage / 'inputs.json').write_text(json.dumps({str(p): sha(p) for p in inputs}, indent=2) + '\n')
        return source
    kernel = Path(__file__).with_name('staged_reciprocal.x')
    text = kernel.read_text()
    text = text[text.index('// Six independent'):]
    text += ('\n// Exact composition; XLS selects the register boundaries.\n'
             'pub fn divide(n: sN[37]) -> sN[37] { finish(reduce(products(n))) }\n')
    (source / 'reciprocal_kernel.x').write_text(text)
    library = source / 'hls_fixed.x'
    before = library.read_text()
    old = '  if (DENOMINATOR & (DENOMINATOR - u32:1)) == u32:0 {'
    new = ('  if WIDTH == u32:37 && DENOMINATOR == u32:12 {\n'
           '    reciprocal_kernel::divide(numerator as sN[37]) as sN[WIDTH]\n'
           '  } else if (DENOMINATOR & (DENOMINATOR - u32:1)) == u32:0 {')
    if before.count(old) != 1:
        raise ValueError('unexpected fixed-point library')
    after = 'import reciprocal_kernel;\n' + before.replace(old, new)
    library.write_text(after)
    (args.stage / 'source.patch').write_text(''.join(difflib.unified_diff(
        before.splitlines(True), after.splitlines(True), fromfile='hls_fixed.x', tofile='hls_fixed.x')))
    inputs = {str(p): sha(p) for p in [*args.reference.glob('*.x'), kernel]}
    (args.stage / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    return source


def main() -> None:
    """Compile once, then retain isolated executor substitutions for explicit stage budgets."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'rtl-reference', 'stage', 'codegen', 'table'):
        parser.add_argument('--' + name, type=lambda p: Path(p).resolve(), required=True)
    parser.add_argument('--pipeline-stages', type=int, nargs='+', default=[2])
    parser.add_argument('--library', type=lambda p: Path(p).resolve(),
                        help='use the reusable chunked implementation instead of the initial fixed kernel')
    args = parser.parse_args()
    source = prepare(args)
    build(source, args.reference)
    for stages in args.pipeline_stages:
        compile_executor(argparse.Namespace(
            reference=source, stage=args.stage / f'compiled-{stages}', codegen=args.codegen,
            table=args.table, executor='__phi_halo_cell__SharedExecutor_0_next',
            channel='_request_in', delay_ps=0, symmetric=False, cell_only=True,
            keep_product_inputs=False, pipeline_stages=stages))


if __name__ == '__main__':
    main()
