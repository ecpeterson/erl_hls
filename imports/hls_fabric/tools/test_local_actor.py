"""Check the public source-actor command and its binding into a transport build."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

from backend_paths import ROOT, erlang_environment


def run(command: list[str | Path], stage: Path, name: str, accepted: bool = True,
        *, env: dict[str, str] | None = None) -> str:
    """Retain one bounded build's diagnostics, including deliberate rejection."""
    path = stage / (name + '.log')
    with path.open('x') as log:
        result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=log,
                                stderr=subprocess.STDOUT, timeout=120, env=env)
    text = path.read_text()
    if (result.returncode == 0) != accepted:
        raise AssertionError((command, text[-4000:]))
    return text


def manifest(output: Path) -> dict:
    """Check emitted interfaces against their declared widths and exact DSLX identity."""
    report = json.loads(Path(str(output) + '.json').read_text())
    data = output.read_bytes()
    assert report['dslx_sha256'] == hashlib.sha256(data).hexdigest()
    assert f"pub type MachineBits = bits[{report['machine_bits']}]".encode() in data
    for name in report['function_ports']:
        assert ('pub fn ' + name + '(').encode() in data, name
    for module in report['source_imports']:
        assert ('import ' + module + ';').encode() in data, module
    assert report['physical_locality_established'] is False
    assert 'network_runtime' in report['excluded']
    return report


def main() -> None:
    """Build actual source, reject either occupied output, and check the production transport caller."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    args = parser.parse_args()
    stage = args.stage.resolve()
    stage.mkdir()
    options = stage / 'options.term'
    options.write_text('[].\n')
    target = stage / 'actor.x'
    command = ['bash', 'tools/emit_local_actor.sh', 'test/hls_local_actor_fixture.erl', options, target]
    run(command, stage, 'single')
    standalone = manifest(target)
    original = {p: p.read_bytes() for p in [target, Path(str(target) + '.json')]}
    assert 'local_actor_output_exists' in run(command, stage, 'existing', False)
    assert all(p.read_bytes() == data for p, data in original.items())
    for suffix in ['', '.json']:
        name = 'occupied-dslx' if not suffix else 'occupied-json'
        output = stage / (name + '.x')
        occupied = Path(str(output) + suffix)
        occupied.write_text('retained sentinel\n')
        assert 'local_actor_output_exists' in run(command[:-1] + [output], stage, name, False)
        assert occupied.read_text() == 'retained sentinel\n'
        companion = Path(str(output) + ('.json' if not suffix else ''))
        assert not companion.exists()
    missing = stage / 'missing.x'
    run(command[:2] + [stage / 'absent.erl', options, missing], stage, 'missing-source', False)
    assert not missing.exists() and not Path(str(missing) + '.json').exists()
    config = stage / 'transport.config'
    config.write_text('#{sources => [{"test/hls_protocol_capture_fixture.erl",[]},{"test/hls_protocol_transport_topology.erl",[]}],topology => {hls_protocol_transport_topology,topology,[]},actor_limit => 3}.\n')
    transport = stage / 'transport'
    # The command-entry escript emits sources only; XLS circuit checks run in the existing transport suite.
    run(['escript', 'tools/emit_protocol_transport.escript', config, transport], stage, 'transport',
        env=erlang_environment('default'))
    summary = json.loads((transport / 'summary.json').read_text())
    assert summary['actors'] == 3 and summary['actor_runtime'] is False and summary['eligible'] is False
    [role] = summary['actor_functions']
    actor = manifest(transport / role['file'])
    assert actor == role['manifest']
    source = summary['source_plans'][role['module']]
    assert source == {key: actor['source_plan'][key] for key in source}
    assert actor['clock_proc'] == 'local_owner_clock'
    receivers = summary['receivers']
    assert [receiver['index'] for receiver in receivers] == [0, 1, 2]
    expected_files = {role['file']}
    ordinary = (transport / role['file']).read_bytes()
    for receiver in receivers:
        assert receiver['module'] == role['module']
        output = transport / receiver['file']
        bound = manifest(output)
        assert bound == receiver['manifest']
        assert bound['source_plan'] == actor['source_plan']
        assert bound['clock_proc'] == 'local_inbox_clock'
        assert output.read_bytes().startswith(ordinary)
        expected_files.add(receiver['file'])
    # One shared ordinary definition plus one bound receiver per instance; no extras.
    actual_files = {str(p.relative_to(transport)) for p in (transport / 'actors').glob('*.x')}
    assert len(expected_files) == 4 and actual_files == expected_files
    (stage / 'result.json').write_text(json.dumps({'passed': True, 'single_actor': standalone['source_plan'],
        'transport_actor_instances': 3, 'transport_function_definitions': 1,
        'transport_receiver_definitions': len(receivers),
        'same_source_plan': True, 'actor_runtime': False, 'negative_builds': 4}, indent=2) + '\n')


if __name__ == '__main__':
    main()
