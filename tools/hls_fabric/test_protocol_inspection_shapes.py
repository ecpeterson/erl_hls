"""Application-free checks of retained inspection projections against typed machine fields."""
from pathlib import Path
from types import SimpleNamespace
import json
from backend_paths import ROOT, erlang_paths
from compiler_paths import compiler_resource, compiler_root
from backend_commands import run
from test_local_protocol import prove


def shapes(xls: Path, stage: Path) -> None:
    """Compare packed projections to ordinary typed machine fields, including active gather/scalar priority."""
    expression='[C,S]=init:get_plain_arguments(),ok=hls_protocol_inspection_shapes:write(C,S),halt().'
    run(['erl','+S','2:2','-noshell','-pa',*erlang_paths("test"),'-eval',expression,'-extra',compiler_root("test"),stage],stage.parent,'shapes-emit')
    for name in ['plain','scalar','gather','gather_sites']:
        shape_case(xls,stage/name)


def shape_case(xls: Path, part: Path) -> None:
    """Check one freshly emitted shape against the ordinary typed machine unpacker."""
    source=part/'shape.x';raw=part/'shape.ir'
    public = compiler_root('test')
    imports=[part,ROOT/'apps/hls_target/priv/xls/lib',compiler_resource(public, 'hls_compile', 'priv/xls/lib'),compiler_resource(public, 'hls_fabric', 'priv/xls/fabric')]
    run([xls/'ir_converter_main','--warnings_as_errors=false','--dslx_path='+':'.join(map(str,imports)),
         '--dslx_stdlib_path='+str(xls/'xls/dslx/stdlib'),source],part,'shape-convert',raw)
    result=prove(SimpleNamespace(xls=xls,yosys='yosys'),part,raw,'shape','metadata',True)
    (part/'result.json').write_text(json.dumps({'result':result,
        'domain':'All raw machine bits and initialization/reset Booleans for this source fixture.',
        'trust':['source extraction','typed machine unpacker','DSLX/XLS','Yosys/ABC/SAT'],
        'limits':'Combinational projection equivalence; no temporal progress or arbitrary-source claim.'},indent=2)+'\n')
