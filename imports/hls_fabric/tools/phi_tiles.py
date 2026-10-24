"""Compile one source-identical tile and bind separately checked device configurations."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

from transport_codegen import specialize
from backend_commands import digest, execute


def identity(source: Path, xls: Path, ram_helper: Path, schedulers: int,
             delay_model: str = "unit", delay_table: Path | None = None) -> dict:
    """Fingerprint shared source, compiler binaries, standard library and codegen settings."""
    sources = {p.name: digest(p) for p in sorted(source.glob('*.x'))
               if not p.name.startswith(('device_', 'phi_device_'))}
    if (delay_model == 'xc7_7030') != (delay_table is not None):
        raise ValueError('xc7_7030 requires a delay table; other models do not accept one')
    result = {'schema': 1, 'sources': sources,
            'transport_codegen': digest(Path(__file__).with_name('transport_codegen.py')),
            'tools': {name: digest(xls/name) for name in ('ir_converter_main', 'opt_main', 'codegen_main')},
            'stdlib': {str(p.relative_to(xls/'xls/dslx/stdlib')): digest(p)
                       for p in sorted((xls/'xls/dslx/stdlib').rglob('*.x'))},
            'ram_helper': digest(ram_helper), 'schedulers': schedulers,
            'flags': ['--pipeline_stages=2', f'--delay_model={delay_model}', '--flop_inputs=false',
                      '--flop_outputs=true', '--use_system_verilog=false', '--reset=reset',
                      '--fifo_module=', '--module_name=phi_tile']}
    if delay_table is not None:
        result['delay_table_sha256'] = digest(delay_table)
        result['flags'].append('--xc7_delay_table=xc7_delay_table.tsv')
    return result


def check_sources(source: Path, devices: list[dict]) -> None:
    """Require every board's complete graph and wrapper to match the common DSLX byte for byte."""
    graph, wrapper = (source/name for name in ('tile_graph.x', 'phi_tile.x'))
    for device in devices:
        d = device['id']
        if not device.get('tile') or (source/f'device_{d}_graph.x').read_bytes() != graph.read_bytes():
            raise ValueError(f'device {d} has a different tile graph')
        if (source/f'phi_device_{d}.x').read_bytes() != wrapper.read_bytes():
            raise ValueError(f'device {d} has a different tile wrapper')


def prepare(args: argparse.Namespace, devices: list[dict]) -> Path:
    """Reuse a content-addressed tile only after checking all retained output digests."""
    source = args.stage/'source'
    check_sources(source, devices)
    counts = {d['scheduler_count'] for d in devices}
    if len(counts) != 1:
        raise ValueError('congruent tiles require one RAM layout')
    helper = RAM_HELPER
    delay_model, delay_table = getattr(args, 'delay_model', 'unit'), getattr(args, 'delay_table', None)
    inputs = identity(source, args.xls, helper, counts.pop(), delay_model, delay_table)
    key = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
    cache = args.tile_cache/key
    manifest = cache/'complete.json'
    if manifest.exists():
        saved = json.loads(manifest.read_text())
        if saved['inputs'] != inputs or saved['outputs'] != outputs(cache):
            raise ValueError(f'tile cache changed: {cache}')
        reused = True
    else:
        cache.mkdir(parents=True, exist_ok=False)
        if delay_table is not None:
            shutil.copyfile(delay_table, cache/'xc7_delay_table.tsv')
            if digest(cache/'xc7_delay_table.tsv') != inputs['delay_table_sha256']:
                raise ValueError('delay table changed during snapshot')
        ram = subprocess.check_output(['bash', '-c', 'source "$1"; phi_scheduler_ram_configurations "$2"',
            'tile-rams', str(helper), str(inputs['schedulers'])], text=True).strip()
        commands = [
            ('convert', [str(args.xls/'ir_converter_main'), '--top=Top', '--warnings_as_errors=false',
                         f'--dslx_path={source}', f'--dslx_stdlib_path={args.xls/"xls/dslx/stdlib"}',
                         str(source/'phi_tile.x')], cache/'phi_tile.ir'),
            ('optimize', [str(args.xls/'opt_main'), str(cache/'phi_tile.ir')], cache/'phi_tile.opt.ir'),
            ('codegen', [str(args.xls/'codegen_main'), *inputs['flags'], f'--ram_configurations={ram}',
                         str(cache/'phi_tile.opt.ir')], cache/'phi_tile.v')]
        timings = {}
        for name, command, output in commands:
            start = time.monotonic()
            execute(command, cache, name, timeout=1800, output=output)
            timings[name] = time.monotonic()-start
            print(f'Tile {name}: {timings[name]:.1f} s', flush=True)
        specialize(args.xls/'codegen_main', cache/'phi_tile.opt.ir', cache/'phi_tile.v', cache/'adapters',
                   delay_options=[f'--delay_model={delay_model}'] +
                   ([f'--xc7_delay_table={cache / "xc7_delay_table.tsv"}'] if delay_table is not None else []))
        if inputs != identity(source, args.xls, helper, inputs['schedulers'], delay_model, delay_table):
            raise ValueError('tile inputs changed during compilation')
        saved = {'inputs': inputs, 'outputs': outputs(cache), 'seconds': timings,
                 'commands': [c for _, c, _ in commands]}
        manifest.write_text(json.dumps(saved, indent=2)+'\n')
        reused = False
    (args.stage/'tile.json').write_text(json.dumps({'key': key, 'cache': str(cache),
        'reused': reused, 'seconds': saved['seconds'], 'rtl_sha256': saved['outputs']['phi_tile.v']}, indent=2)+'\n')
    return cache/'phi_tile.v'


RAM_HELPER = Path(__file__).resolve().with_name("phi_scheduler_rams.sh")

def outputs(cache: Path) -> dict[str, str]:
    """Hash compiler products; log files do not establish cache validity."""
    names = ['phi_tile.ir', 'phi_tile.opt.ir', 'phi_tile.v']
    if (cache/'xc7_delay_table.tsv').exists():
        names.append('xc7_delay_table.tsv')
    return {name: digest(cache/name) for name in names}


def bind(args: argparse.Namespace, device: dict, rtl: Path) -> None:
    """Copy the same compiled logic beside the board's constant and RAM wrapper."""
    directory = args.stage/f'device{device["id"]}'
    directory.mkdir()
    name = f'phi_device_{device["id"]}.v'
    shutil.copyfile(rtl, directory/name)
    (directory/'build.json').write_text(json.dumps({'tile': str(rtl), 'rtl_sha256': digest(rtl),
        'configuration_sha256': digest(args.stage/f'source/phi_device_{device["id"]}_config.json'),
        'wrapper_sha256': digest(args.stage/f'source/phi_device_{device["id"]}_ram.v')}, indent=2)+'\n')
