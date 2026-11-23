#!/usr/bin/env python3
"""Continue an explicitly reviewed component-screen rejection without changing its evidence.

One fixed fresh continuation directory per mapped image permits one route and
assembly attempt. The original frozen driver, payloads, whole-device gates,
routing settings and physical checks remain authoritative. No board access.
"""

import argparse
import json
from pathlib import Path
import sys
from typing import Any

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from application import domain_board as board


def admission(original: Path, review: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    """Require an explicit disposition bound to this exact path, inputs and successful whole-image map."""
    original = original.resolve(strict=True)
    decision = json.loads(review.read_text())
    required = {'schema':'hls_board_route_disposition_v2', 'component_screen_override_only':True,
        'component_cost_established':False, 'synthesis_repeat':False, 'route_attempts_per_role':1,
        'routing_settings_unchanged':True, 'whole_image_budgets_unchanged':True,
        'physical_board_access_authorized_now':False}
    instruction = decision.get('user_instruction')
    if (any(type(decision.get(key)) is not type(value) or decision[key] != value for key,value in required.items()) or
            not isinstance(instruction, str) or not instruction.strip()):
        raise ValueError('missing or incompatible explicit route disposition')
    selected = decision.get('selected_images')
    fields = {'path', 'input_manifest_sha256', 'map_result_sha256'}
    if (not isinstance(selected, list) or not selected or
            any(not isinstance(row, dict) or row.keys() != fields or
                not isinstance(row['path'], str) or not Path(row['path']).is_absolute() or
                str(Path(row['path']).resolve()) != row['path'] for row in selected)):
        raise ValueError('review requires exact resolved image paths and both identities')
    if len({row['path'] for row in selected}) != len(selected):
        raise ValueError('review contains duplicate image paths')
    matching = [row for row in selected if row['path'] == str(original)]
    if len(matching) != 1:
        raise ValueError('review does not select this mapped image')
    for name, field in (('inputs.json', 'input_manifest_sha256'), ('map/result.json', 'map_result_sha256')):
        if board.digest(original / name) != matching[0][field]:
            raise ValueError('reviewed image identity changed: ' + name)
    if (original / 'route').exists() or (original / 'assemble').exists():
        raise ValueError('original image already has a physical attempt')
    frozen = json.loads((original / 'inputs.json').read_text())
    board.unchanged(frozen)
    result = json.loads((original / 'map/result.json').read_text())
    if not result.get('success') or result.get('changed_inputs') or not result.get('whole_image_passes'):
        raise ValueError('failed or changed whole-image map cannot be overridden')
    if result.get('component_screen_passes') is not False or result.get('route_admitted') is not False:
        raise ValueError('continuation requires the retained component-only rejection')
    if result['input_manifest_sha256'] != board.digest(original / 'inputs.json'):
        raise ValueError('map belongs to another input manifest')
    for name,key in (('netlist.json','netlist_sha256'),('resources.json','resources_sha256'),
                     ('link-screen.json','link_screen_sha256')):
        if board.digest(original / 'map' / name) != result[key]:
            raise ValueError('changed mapped gate evidence: ' + name)
    area = json.loads((original / 'map/resources.json').read_text())
    if not area['mapped']['complete'] or not area['bounds']['passes']:
        raise ValueError('incomplete or failed whole-image resource evidence')
    return frozen,result


def prepare(original: Path, review: Path) -> Path:
    """Bind one explicit admission receipt and link unchanged map artifacts into a fresh directory."""
    original, review = original.resolve(strict=True), review.resolve(strict=True)
    _,result = admission(original,review)
    output = original.with_name(original.name + '-route-1')
    output.mkdir(exist_ok=False)
    (output / 'map').mkdir()
    bindings = {str(path):board.digest(path) for path in (
        review,Path(__file__).resolve(),original / 'inputs.json',original / 'map/result.json',
        *(original / 'map' / name for name in ('netlist.json','resources.json','link-screen.json')))}
    (output / 'inputs.json').symlink_to(original / 'inputs.json')
    for name in ('netlist.json','resources.json','link-screen.json'):
        (output / 'map' / name).symlink_to(original / 'map' / name)
    (output / 'map/original-result.json').symlink_to(original / 'map/result.json')
    derived = result | {'route_admitted':True, 'original_route_admitted':False,
        'admission_basis':'Explicit user component-screen exception; component_screen_passes remains false.',
        'review_sha256':bindings[str(review)], 'original_result_sha256':bindings[str(original / 'map/result.json')]}
    board.save(output / 'map/result.json',derived)
    bindings[str(output / 'map/result.json')] = board.digest(output / 'map/result.json')
    board.save(output / 'admission.json',{'schema':'hls_board_derived_route_admission_v1',
        'original':str(original),'review':str(review),'output':str(output),'bindings':bindings,
        'component_screen_passes':False,'original_route_admitted':False,
        'component_cost_established':False,'physical_board_access':False})
    return output


def verify(output: Path) -> None:
    """Recheck the original review, map and derived admission before and after each physical phase."""
    receipt = json.loads((output / 'admission.json').read_text())
    original,review = Path(receipt['original']),Path(receipt['review'])
    if (receipt.get('schema') != 'hls_board_derived_route_admission_v1' or receipt['output'] != str(output)
            or output != original.with_name(original.name + '-route-1')):
        raise ValueError('continuation does not match its fixed one-attempt receipt')
    for name,expected in receipt['bindings'].items():
        if board.digest(Path(name)) != expected:
            raise ValueError('changed continuation review or evidence: ' + name)
    admission(original,review)
    for target,source in [('inputs.json','inputs.json'),('map/original-result.json','map/result.json'),
            *[(f'map/{name}',f'map/{name}') for name in ('netlist.json','resources.json','link-screen.json')]]:
        if (output / target).resolve(strict=True) != (original / source).resolve(strict=True):
            raise ValueError('continuation artifact no longer references the original map')


def phase(output: Path, name: str) -> None:
    """Use the frozen route/assembly implementation once, retaining review failures separately."""
    verify(output)
    primary = None
    try:
        board.phase(output,name)
    except BaseException as error:
        primary = error
    try:
        verify(output)
    except BaseException as error:
        result_path = output / name / 'result.json'
        if result_path.exists():
            result = json.loads(result_path.read_text())
            result.update(success=False,admission_verification_error=f'{type(error).__name__}: {error}')
            board.save(result_path,result)
        if primary is None:
            primary = error
    if primary is not None:
        raise primary


def main() -> None:
    """Prepare a reviewed continuation, then explicitly route or assemble under the root guard."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase',choices=('prepare','route','assemble'))
    parser.add_argument('image',type=lambda p:Path(p).resolve())
    parser.add_argument('--review',type=lambda p:Path(p).resolve())
    args = parser.parse_args()
    if args.phase == 'prepare':
        if args.review is None: parser.error('prepare requires the recorded --review')
        output = prepare(args.image,args.review)
    else:
        if args.review is not None: parser.error('physical phases use the bound admission receipt')
        output = args.image
        phase(output,args.phase)
    print(json.dumps({'completed':True,'phase':args.phase,'output':str(output)}))


if __name__ == '__main__':
    main()
