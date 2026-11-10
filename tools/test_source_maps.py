#!/usr/bin/env python3
"""Witness real XLS attribution after relocating emitted actor source bundles.

Prepare --stage with xls_source_map_dslx:write/1 in the test BEAM profile first.
Only conversion runs: three invalid expressions must reject with their original
source locations, while the valid actor control must produce IR. This is a
finite diagnostic witness, not equivalence or an optimization/codegen test.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
from types import ModuleType


ROOT = Path(__file__).resolve().parents[1]


def load_driver() -> ModuleType:
    """Load the same standalone source-bundle driver distributed with the compiler."""
    path = ROOT / 'priv/tools/compile_source_build.py'
    spec = importlib.util.spec_from_file_location('source_map_build_driver', path)
    if spec is None or spec.loader is None:
        raise ImportError(str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path: Path) -> str:
    """Identify exact retained fixture and diagnostic bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_case(driver: ModuleType, xls: Path, stage: Path, case: dict) -> dict:
    """Move a whole bundle, verify its annotations, and retain original and augmented diagnostics."""
    name = case['name']
    original = stage / 'emitted' / name
    relocated = stage / 'relocated bundles' / name
    relocated.parent.mkdir(parents=True, exist_ok=True)
    if relocated.exists():
        raise FileExistsError(relocated)
    shutil.move(original, relocated)
    assert not original.exists(), original
    plan = driver.plan_build(xls, relocated)
    bound = {row['file']: row['sha256'] for row in plan['inputs']}
    assert not any(path.endswith('.x.map.json') for path in bound), bound
    annotated = sorted(path for path in bound if path.endswith('.x') and
                       b'@erl ' in (relocated / path).read_bytes())
    assert 'actor.x' in annotated, annotated
    if name == 'remote':
        assert any(path.endswith('/remote_math.x') for path in annotated), annotated
    for path in annotated:
        assert digest(relocated / path) == bound[path], path
    unit, = plan['units']
    command = unit['commands'][0]
    assert command['stage'] == 'convert', command
    argv = [('--dslx_stdlib_path=' + plan['stdlib'])
            if value == '--dslx_stdlib_path=_stdlib' else value for value in command['command']]
    work = stage / 'diagnostics' / name
    work.mkdir(parents=True)
    (work / 'command.json').write_text(json.dumps(argv, indent=2) + '\n')
    try:
        driver.executor().run(argv, work, 'raw.ir', 120, cwd=relocated)
    except RuntimeError as error:
        surfaced = str(error)
    else:
        surfaced = None
    raw = (work / 'stderr.log').read_bytes()
    metrics = json.loads((work / 'time.json').read_text())
    expected = case['source']
    if expected is None:
        assert surfaced is None, surfaced
        assert metrics['returncode'] == 0, metrics
        assert (work / 'raw.ir').stat().st_size > 0
    else:
        assert surfaced is not None, f'{name}: ill-typed expression unexpectedly accepted'
        assert metrics['returncode'] > 0, metrics
        text = raw.decode(errors='replace')
        assert re.search(r'(TypeInferenceError|TypeMismatchError|type mismatch)', text, re.I), text
        assert text in surfaced, surfaced
        note = f'Erlang source: {expected}:{case["line"]} (generated '
        assert note in surfaced, surfaced
        assert b'Erlang source:' not in raw, raw
        assert not (relocated / expected).exists(), expected
        (work / 'surfaced.txt').write_text(surfaced + '\n')
        assert digest(work / 'stderr.log') == hashlib.sha256(raw).hexdigest()
    return {'case': name, 'expected_source': expected, 'expected_line': case['line'],
            'source_build_sha256': plan['source_build_sha256'], 'annotated_sources': annotated,
            'stderr_sha256': digest(work / 'stderr.log'), 'metrics': metrics,
            'converter_sha256': plan['xls_tools']['ir_converter_main']['sha256']}



def check_continuation(driver: ModuleType, xls: Path, stage: Path) -> dict:
    """A real converter diagnostic must follow physical rows inserted by the annotation renderer."""
    directory = stage / 'relocated continuation'
    directory.mkdir()
    source = directory / 'continuation_probe.x'
    shutil.move(stage / source.name, source)
    lines = source.read_text().splitlines()
    assert any('// @erl+' in line for line in lines), lines
    generated_line, = [index for index, line in enumerate(lines, 1) if line.lstrip().startswith('value + true')]
    assert generated_line > 3, lines
    work = stage / 'diagnostics' / 'continuation'
    work.mkdir(parents=True)
    xls = xls.resolve()
    argv = [str(xls / 'ir_converter_main'), '--warnings_as_errors=false', '--top=probe',
            '--dslx_path=.', '--dslx_stdlib_path=' + str(xls / 'xls/dslx/stdlib'), source.name]
    (work / 'command.json').write_text(json.dumps(argv, indent=2) + '\n')
    try:
        driver.executor().run(argv, work, 'raw.ir', 120, cwd=directory)
    except RuntimeError as error:
        surfaced = str(error)
    else:
        raise AssertionError('continuation probe: ill-typed expression unexpectedly accepted')
    raw = (work / 'stderr.log').read_text(errors='replace')
    metrics = json.loads((work / 'time.json').read_text())
    assert metrics['returncode'] > 0, metrics
    assert re.search(r'(TypeInferenceError|TypeMismatchError|type mismatch)', raw, re.I), raw
    assert f'{source.name}:{generated_line}:' in raw, raw
    assert raw in surfaced, surfaced
    assert f'Erlang source: probe.erl:71 (generated {source.name}:{generated_line}:' in surfaced, surfaced
    assert 'Erlang source:' not in raw, raw
    (work / 'surfaced.txt').write_text(surfaced + '\n')
    return {'generated_line': generated_line, 'expected_source': 'probe.erl', 'expected_line': 71,
            'source_sha256': digest(source), 'stderr_sha256': digest(work / 'stderr.log'),
            'metrics': metrics}


def main() -> None:
    """Run the four actor cases and continuation probe serially, retaining their finite results."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xls', type=Path, required=True)
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    stage = args.stage.resolve()
    cases = json.loads((stage / 'cases.json').read_text())
    assert [case['name'] for case in cases] == ['actor', 'include', 'remote', 'control'], cases
    driver = load_driver()
    result = [check_case(driver, args.xls, stage, case) for case in cases]
    continuation = check_continuation(driver, args.xls, stage)
    (stage / 'result.json').write_text(json.dumps({'cases': result, 'continuation': continuation}, indent=2) + '\n')
    print('PASS: three relocated actor rejections, one XLS conversion control and one continuation-row diagnostic')


if __name__ == '__main__':
    main()
