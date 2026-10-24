"""Optional XLS convenience driver for the Erlang-owned repetition example."""
from pathlib import Path
import argparse
from backend_paths import ROOT
from backend_commands import run


def emit_application(width: int, directory: Path, inspect: bool = False, split: int | None = None,
                     mixed: bool = False, share_arithmetic: bool = False) -> Path:
    """Call the native source command; Erlang owns configuration and all placement validation."""
    directory.mkdir()
    build = directory / 'build'
    run(['rebar3', 'release'], directory, 'compile-backend')
    command = [ROOT / '_build/default/rel/hls/bin/hls-repetition',
               '--width', str(width), '--output', build]
    if split is not None:
        command += ['--split', str(split)]
    for enabled, flag in [(inspect, '--inspect'), (mixed, '--mixed'), (share_arithmetic, '--share-arithmetic')]:
        if enabled:
            command.append(flag)
    run(command, directory, 'emit-application')
    return build


def build_application(xls: Path, width: int, directory: Path, inspect: bool = False, split: int | None = None,
                      mixed: bool = False, share_arithmetic: bool = False) -> Path:
    """Optionally compile the emitted bundle with XLS; source emission itself needs no external compiler."""
    build = emit_application(width, directory, inspect, split, mixed, share_arithmetic)
    # The compiler driver bounds each XLS stage at 300s across all emitted roles.
    run([ROOT / "_build/default/rel/hls/bin/compile-source-build", xls, build],
        directory, "compile-application", timeout=None)
    return build


def main() -> None:
    """Write complete RTL and deployment to a fresh output; no board or semantic admission implied."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('width',type=int)
    parser.add_argument('output',type=lambda p:Path(p).resolve())
    parser.add_argument('--inspect',action='store_true',help='include passive endpoint-2 process inspection')
    parser.add_argument('--split',type=int,help='place [0,split) and [split,width) on two framed devices')
    parser.add_argument("--mixed",action="store_true",help="run data actors in BEAM and syndrome/Phi in one framed RTL partition")
    parser.add_argument("--share-arithmetic",action="store_true",help="share one scalar completion among the two or three Phi actors")
    args=parser.parse_args();build_application(args.xls,args.width,args.output,args.inspect,args.split,args.mixed,args.share_arithmetic)


if __name__=='__main__':main()
