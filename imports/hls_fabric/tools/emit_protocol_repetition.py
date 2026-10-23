"""Build a fresh periodic repetition application from the pinned compiler's ordinary examples."""
from pathlib import Path
import argparse
from backend_paths import ROOT, PUBLIC, erlang_paths
from compile_protocol_application import compile_application
from test_local_protocol import run


# These application annotations propose the periodic schedule; the compiler checks
# complete source phase/route coverage, not the annotated source invariants.
PERIODIC_MODEL = """#{kind=>periodic_neighbor_barrier,contracts=>#{
  phenom_line_data_cell=>#{role=>data,phases=>[configuring,collecting,reporting,replying]},
  phenom_line_syndrome_cell=>#{role=>syndrome,phases=>[configuring,collecting,announcing]},
  phi_line_cell=>#{role=>phi,rounds=>12,phases=>[configuring,measuring,gathering,comparing,flipping]}}}"""


def emit_application(width: int, directory: Path, inspect: bool = False) -> Path:
    """Emit fresh source DSLX and a checked periodic dependency report, without XLS compilation."""
    if not 2 <= width <= 16:raise ValueError('repetition width must be 2..16')
    directory.mkdir()
    source=PUBLIC/'src/examples/phi_decoder'
    def term(path: Path) -> str:
        """Escape an Erlang string without passing it through a shell."""
        return '"'+str(path).replace('\\','\\\\').replace('"','\\"')+'"'
    modules=['phenom_line_data_cell','phenom_line_syndrome_cell','phi_line_cell','phi_repetition_topology']
    options='[{i,'+term(PUBLIC/'include')+'},{i,'+term(source)+'}]'
    sources=','.join('{'+term(source/(m+'.erl'))+','+options+'}' for m in modules)
    config=directory/'config.erl';build=directory/'build'
    config.write_text('#{sources=>['+sources+'],topology=>{phi_repetition_topology,topology,['+str(width)+',16#80000000]},actor_limit=>'+str(3*width)+',device=>board,host=>1,protocol_model=>'+PERIODIC_MODEL+(',inspection=>process' if inspect else '')+'}.\n')
    run(['rebar3','compile'],directory,'compile-backend')
    run(['env','ERL_AFLAGS='+ ' '.join('-pa "'+str(p)+'"' for p in erlang_paths()),'escript','tools/emit_protocol_application.escript',config,build],directory,'emit-application')
    return build


def build_application(xls: Path, width: int, directory: Path, inspect: bool = False) -> Path:
    """Build one N=2..16 half-rate-noise line; analysis does not change RTL or grant admission."""
    build=emit_application(width,directory,inspect)
    compile_application(xls,build,[PUBLIC/'src/examples/phi_decoder'])
    return build


def main() -> None:
    """Write complete RTL and deployment to a fresh output; no board or semantic admission implied."""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls',type=lambda p:Path(p).resolve());parser.add_argument('width',type=int)
    parser.add_argument('output',type=lambda p:Path(p).resolve())
    parser.add_argument('--inspect',action='store_true',help='include passive endpoint-2 process inspection')
    args=parser.parse_args();build_application(args.xls,args.width,args.output,args.inspect)


if __name__=='__main__':main()
