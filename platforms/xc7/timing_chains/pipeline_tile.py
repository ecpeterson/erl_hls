#!/usr/bin/env python3
"""Apply the same boundary comparison to complete 4×2-qubit tiles in the D6 mesh."""
import argparse
import json
from pathlib import Path
import sys

from pipeline_ablation import CUTS, ROOT, sha, transform


def main() -> None:
    """Reuse the production tile builder with recorded, experiment-only source transformations."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage','xls','delay-table','tile-cache'):
        parser.add_argument('--'+name,required=True,type=lambda p:Path(p).resolve())
    parser.add_argument('--erl-hls', type=Path, help='Explicit compiler source root with test-profile beams.')
    parser.add_argument('--yosys',required=True)
    parser.add_argument('--remove',nargs='*',choices=CUTS,default=[])
    parser.add_argument('--devices',type=int,nargs='+')
    args = parser.parse_args()
    sys.path.insert(0, str(ROOT/'tools/hls_fabric'))
    import phi_mesh_build as mesh
    from compiler_paths import compiler_root
    args.erl_hls = compiler_root('test', args.erl_hls, ROOT)
    args.shape, args.planes = [6,6], ['x','z']
    args.memory, args.memory_case, args.placement = True, 'mesh_memory', 'coalesced'
    args.phi_actors_per_scheduler, args.reductions = 4, 'source_fragments'
    args.transport = {'words':4,'credits':4,'compact':True}
    args.link_words, args.link_credits, args.link_compact = 4,4,True
    args.tiles, args.jobs, args.reuse_actors = True,1,None
    args.delay_model, args.compiler_timeout = 'xc7_7030', 1800
    identity = {'remove':args.remove,'transform_sha256':sha(Path(__file__).with_name('pipeline_ablation.py')),
                'runner_sha256':sha(Path(__file__))}
    def change(source: Path) -> None:
        """Retain before/after digests for each actual shared-actor source."""
        changes = {}
        for path in sorted(source.glob('*.x')):
            text = path.read_text()
            if 'pub proc SharedService<' not in text:
                continue
            before = sha(path)
            path.write_text(transform(text,set(args.remove)))
            changes[path.name] = {'before':before,'after':sha(path)}
        if set(changes) != {'phi_halo_cell.x','phenom_data_cell.x','phenom_syndrome_cell.x'}:
            raise ValueError('unexpected complete-tile actor population')
        (source/'ablation.json').write_text(json.dumps({'identity':identity,'sources':changes},indent=2)+'\n')
    mesh.build(args,transform=change,experiment=identity)


if __name__ == '__main__':
    main()
