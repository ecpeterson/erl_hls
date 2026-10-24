"""Check periodic model coverage and its public build callsite without recompiling RTL."""
from pathlib import Path
import argparse
import hashlib
from compiler_paths import PUBLIC
from backend_paths import erlang_environment
from emit_protocol_repetition import emit_application
from backend_commands import run


def hardware(directory: Path) -> dict[str, str]:
    """Compare generated hardware, excluding copied support libraries and the comparison gateway."""
    return {str(p.relative_to(directory)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob('*') if p.suffix in ('.x', '.sv')
            and p.relative_to(directory).parts[0] != 'support' and 'application-comparison' not in p.parts and p.relative_to(directory)!=Path('application/gateway.x')}


def check(directory: Path) -> None:
    """Check fresh line/halo models, one direct application caller and unchanged emitted hardware."""
    directory.mkdir()
    build=emit_application(2,directory/'application')
    env=erlang_environment("default")
    run(['escript','tools/check_protocol_model.escript',build/'config.erl',build,directory/'binding'],directory,'binding',env=env)
    assert hardware(build)==hardware(directory/'binding-plain'), 'model annotation changed hardware'
    assert (build/'application/gateway.x').read_bytes()==(directory/'binding-plain/application-comparison/gateway.x').read_bytes(), 'model annotation changed gateway logic'
    run(['escript','tools/inspect_phi_protocol.escript',PUBLIC,directory/'inventory'],directory,'inventory',env=env)
    run(['escript','tools/check_protocol_model.escript','inventory',directory/'inventory'],directory,'models',env=env)


def main() -> None:
    """Require fresh output and preserve failed checks; no workload, synthesis or admission claim."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=lambda p:Path(p).resolve())
    check(parser.parse_args().output)


if __name__=='__main__':main()
