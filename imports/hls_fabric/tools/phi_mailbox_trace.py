"""Retain mailbox payload aliases for passive, identity-preserving simulation capture."""
import argparse
import importlib
import gzip
import shutil
import json
from pathlib import Path
import sys

from backend_commands import digest


def payload_net(channel: str) -> str:
    """Name the data vector associated with a public ready/valid boundary."""
    name = channel.replace('/', '.')
    return name+'_data' if name.endswith(('.push', '.pop')) else name


def retained_rtl(build: Path, stage: Path, device: int, public: Path, selected: dict) -> tuple[Path, dict, dict]:
    """Preserve selected aliases while requiring identical cells, ports and public observations."""
    sys.path.insert(0, str(public/'tools'))
    topology = importlib.import_module('topology_debug')
    target = stage/'message-rtl'/f'device{device}'
    target.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((stage/f'device{device}-manifest.json').read_text())
    name = f'phi_device_{device}'
    sources = [build/f'device{device}/{name}.v', build/f'source/{name}_ram.v', public/'priv/rtl/hls_1r1w_ram.v']
    yosys = Path(json.loads((build/'inputs.json').read_text())['tools']['yosys']['path'])
    inputs = [*sources, yosys, build/f'source/{name}_actors.json',
              *sorted((public/'tools').glob('topology_debug*.py'))]
    hashes = {str(p): digest(p) for p in inputs}
    cache = target/'payload-aliases.json.gz'
    if cache.exists():
        saved = json.loads(gzip.decompress(cache.read_bytes()))
        if saved['inputs'] == hashes and saved['selected'] == sorted(selected) and saved['rtl_sha256'] == digest(target/'instrumented.v'):
            return target/'instrumented.v', saved['nets'], {**hashes, str(target/'instrumented.v'): saved['rtl_sha256']}
    topology.instrument(argparse.Namespace(rtl=sources, top=name+'_ram', clock='clk', reset='reset',
        reset_active_low=False, output_top=f'hls_phi_device_{device}', stage=target, yosys=str(yosys),
        actor_projection=build/f'source/{name}_actors.json', actor_root=''))
    if json.loads((target/'manifest.json').read_text()) != manifest:
        raise ValueError('payload retention changed the public observation manifest')
    flat = json.loads((target/'flat.json').read_text())['modules'][name+'_ram']
    exported = json.loads((target/'instrumented.json').read_text())
    module = exported['modules'][f'hls_phi_device_{device}']
    # The public exporter may add only the two passive output aliases.
    stripped = {**module, **{key: {n:v for n,v in module[key].items()
        if n not in ('hls_probe_values', 'hls_actor_writes')} for key in ('ports', 'netnames')}}
    if stripped != flat:
        raise ValueError('payload retention changed application cells or ports')
    for resource in manifest['resources']:
        if resource['id'] in selected:
            module['netnames'][payload_net(resource['name'])]['attributes']['keep'] = '1'
    (target/'instrumented.json').write_text(json.dumps(exported))
    topology.yosys_run(str(yosys), f'read_json {topology.quote(target/"instrumented.json")}\n'
        'opt_reduce\nopt_clean -purge\nsplitnets -driver\n'
        'attrmap -remove src -remove hdlname\nattrmap -modattr -remove src -remove hdlname\n'
        f'write_verilog {topology.quote(target/"instrumented.v")}\n', target, 'retained')
    if hashes != {str(p): digest(p) for p in inputs}:
        raise ValueError('payload retention inputs changed during export')
    # The trace keeps a compact binding, not several gigabytes of Yosys intermediates.
    nets = {payload_net(r['name']): module['netnames'][payload_net(r['name'])]
            for r in manifest['resources'] if r['id'] in selected}
    for filename in ('flat.json', 'hierarchy.json', 'instrumented.json'):
        (target/filename).unlink()
    with gzip.open(cache, 'wt') as output:
        json.dump({'inputs': hashes, 'selected': sorted(selected), 'nets': nets,
                   'rtl_sha256': digest(target/'instrumented.v')}, output)
    for log in target.glob('*.log'):
        with log.open('rb') as source, gzip.open(log.with_suffix('.log.gz'), 'wb', compresslevel=1) as output:
            shutil.copyfileobj(source, output)
        log.unlink()
    hashes[str(target/'instrumented.v')] = digest(target/'instrumented.v')
    return target/'instrumented.v', nets, hashes
