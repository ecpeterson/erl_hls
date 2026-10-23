"""Check periodic model coverage and its public build callsite without recompiling RTL."""
from pathlib import Path
import argparse
import hashlib
from backend_paths import PUBLIC, erlang_paths
from emit_protocol_repetition import emit_application
from test_local_protocol import run


def hardware(directory: Path) -> dict[str, str]:
    """Hash generated DSLX and mechanical pin adapters using relative identities."""
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob('*') if p.suffix in ('.x', '.sv')
            and 'application-comparison' not in p.parts and p.relative_to(directory)!=Path('application/gateway.x')}


def check(directory: Path) -> None:
    """Check fresh line/halo models, one direct application caller and unchanged emitted hardware."""
    directory.mkdir()
    build=emit_application(2,directory/'application')
    env=['env','ERL_AFLAGS='+ ' '.join('-pa "'+str(p)+'"' for p in erlang_paths()),'escript']
    run([*env,'tools/check_protocol_model.escript',directory/'application/config.erl',build,directory/'binding'],directory,'binding')
    assert hardware(build)==hardware(directory/'binding-plain'), 'model annotation changed hardware'
    assert (build/'application/gateway.x').read_bytes()==(directory/'binding-plain/application-comparison/gateway.x').read_bytes(), 'model annotation changed gateway logic'
    run([*env,'tools/inspect_phi_protocol.escript',PUBLIC,directory/'inventory'],directory,'inventory')
    run([*env,'tools/check_protocol_model.escript','inventory',directory/'inventory'],directory,'models')


def main() -> None:
    """Require fresh output and preserve failed checks; no workload, synthesis or admission claim."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=lambda p:Path(p).resolve())
    check(parser.parse_args().output)


if __name__=='__main__':main()
