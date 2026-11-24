"""Compile one source-identical tile and bind separately checked device configurations."""
import phi_tool_paths  # Resolve shared tooling for this application.
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

from transport_codegen import specialize
from backend_commands import digest, execute
from backend_paths import ROOT
from backend_build_profile import read as read_profile


def identity(source: Path, xls: Path, ram_helper: Path, schedulers: int,
             build_profile: Path, delay_table: Path | None = None) -> dict:
    """Fingerprint shared source, external tools and the supplied Erlang-owned build policy."""
    profile = read_profile(build_profile)
    if profile["profile"]["postprocess"]["completion_storage"] != "registers":
        raise ValueError("Phi tiles support only registers completion storage")
    delay_model = profile["profile"]["schedules"]["channel"]["delay_model"]
    sources = {p.name: digest(p) for p in sorted(source.glob('*.x'))
               if not p.name.startswith(('device_', 'phi_device_'))}
    if (delay_model == 'xc7_7030') != (delay_table is not None):
        raise ValueError('xc7_7030 requires a delay table; other models do not accept one')
    result = {'schema': 1, 'sources': sources,
            'transport_codegen': digest(ROOT / 'tools/hls_fabric/transport_codegen.py'),
            'tools': {name: digest(xls/name) for name in ('ir_converter_main', 'opt_main', 'codegen_main')},
            'stdlib': {str(p.relative_to(xls/'xls/dslx/stdlib')): digest(p)
                       for p in sorted((xls/'xls/dslx/stdlib').rglob('*.x'))},
            'ram_helper': digest(ram_helper), 'schedulers': schedulers,
            'build_profile': profile, 'build_profile_sha256': digest(build_profile),
            'flags': [*profile['codegen_flags'], '--module_name=phi_tile']}
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
    build_profile = source/'build-profile.json'
    delay_table = getattr(args, 'delay_table', None)
    inputs = identity(source, args.xls, helper, counts.pop(), build_profile, delay_table)
    delay_model = inputs['build_profile']['profile']['schedules']['channel']['delay_model']
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
        shutil.copyfile(build_profile, cache/'build-profile.json')
        if digest(cache/'build-profile.json') != inputs['build_profile_sha256']:
            raise ValueError('build profile changed during snapshot')
        if delay_table is not None:
            shutil.copyfile(delay_table, cache/'xc7_delay_table.tsv')
            if digest(cache/'xc7_delay_table.tsv') != inputs['delay_table_sha256']:
                raise ValueError('delay table changed during snapshot')
        ram = subprocess.check_output(['bash', '-c', 'source "$1"; scheduler_ram_configurations "$2"',
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
        if inputs != identity(source, args.xls, helper, inputs['schedulers'], build_profile, delay_table):
            raise ValueError('tile inputs changed during compilation')
        saved = {'inputs': inputs, 'outputs': outputs(cache), 'seconds': timings,
                 'commands': [c for _, c, _ in commands]}
        manifest.write_text(json.dumps(saved, indent=2)+'\n')
        reused = False
    (args.stage/'tile.json').write_text(json.dumps({'key': key, 'cache': str(cache),
        'reused': reused, 'seconds': saved['seconds'], 'rtl_sha256': saved['outputs']['phi_tile.v'],
        'build_profile': inputs['build_profile'], 'build_profile_sha256': inputs['build_profile_sha256']}, indent=2)+'\n')
    return cache/'phi_tile.v'


RAM_HELPER = ROOT / "tools/hls_fabric/scheduler_ram_configurations.sh"

def outputs(cache: Path) -> dict[str, str]:
    """Hash compiler products; log files do not establish cache validity."""
    names = ['phi_tile.ir', 'phi_tile.opt.ir', 'phi_tile.v', 'build-profile.json']
    if (cache/'xc7_delay_table.tsv').exists():
        names.append('xc7_delay_table.tsv')
    return {name: digest(cache/name) for name in names}


def bind(args: argparse.Namespace, device: dict, rtl: Path) -> None:
    """Bind compiled logic and its retained policy; reject changed source policy before output."""
    retained_profile = rtl.parent/'build-profile.json'
    saved = json.loads((rtl.parent/'complete.json').read_text())
    profile_sha256 = saved['inputs']['build_profile_sha256']
    profile = read_profile(retained_profile)
    if (digest(retained_profile) != profile_sha256
            or digest(args.stage/'source/build-profile.json') != profile_sha256):
        raise ValueError('build profile changed since tile compilation')
    directory = args.stage/f'device{device["id"]}'
    directory.mkdir()
    name = f'phi_device_{device["id"]}.v'
    shutil.copyfile(rtl, directory/name)
    (directory/'build.json').write_text(json.dumps({'tile': str(rtl), 'rtl_sha256': digest(rtl),
        'build_profile': profile, 'build_profile_sha256': profile_sha256,
        'configuration_sha256': digest(args.stage/f'source/phi_device_{device["id"]}_config.json'),
        'wrapper_sha256': digest(args.stage/f'source/phi_device_{device["id"]}_ram.v')}, indent=2)+'\n')
