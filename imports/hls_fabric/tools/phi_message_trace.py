"""Bind passive accepted-payload observations to the exact generated mesh RTL."""
import json
from pathlib import Path
import re

from backend_commands import digest


def declarations(path: Path) -> dict[str, int]:
    """Read emitted scalar/vector net declarations without interpreting RTL expressions."""
    result = {}
    pattern = re.compile(r'  (?:wire|reg) (?:\[(\d+):(\d+)\] )?\\?(\S+) ;$')
    with path.open() as source:
        for line in source:
            match = pattern.fullmatch(line.rstrip('\n'))
            if match:
                hi, lo, name = match.groups()
                width = int(hi)-int(lo)+1 if hi is not None else 1
                if width < 1 or name in result and result[name] != width:
                    raise ValueError(f'inconsistent net declaration: {name}')
                result[name] = width
    return result


def alias_parts(names: list[str], nets: dict[str, int], flat: dict) -> dict[str, list[dict]]:
    """Resolve surviving aliases; mark optimized-away bits unknown instead of guessing their values."""
    wanted = {bit for name in names for bit in flat[name]['bits'] if isinstance(bit, int)}
    found = {}
    # Prefer wide surviving aliases, which keep the observer small and readable.
    for name in sorted(nets, key=lambda n: (-nets[n], n)):
        if name in flat:
            bits = flat[name]['bits']
        else:
            match = re.fullmatch(r'(.+)\[(\d+)(?::(\d+))?\]', name)
            if not match or match[1] not in flat:
                continue
            hi, lo = int(match[2]), int(match[3] or match[2])
            bits = flat[match[1]]['bits'][lo:hi+1]
        if len(bits) != nets[name]:
            raise ValueError(f'alias width changed: {name}')
        for offset, bit in enumerate(bits):
            if bit in wanted and bit not in found:
                found[bit] = (name, offset)
    result = {}
    for name in names:
        parts = []
        for index, bit in enumerate(flat[name]['bits']):
            if bit in ('0', '1'):
                part = {'constant': int(bit), 'offset': index, 'width': 1}
            elif bit in found:
                net, shift = found[bit]
                part = {'name': net, 'shift': shift, 'offset': index, 'width': 1}
            else:
                part = {'constant': 0, 'offset': index, 'width': 1, 'known': False}
            if parts and 'name' in part and parts[-1].get('name') == part['name'] and parts[-1]['shift']+parts[-1]['width'] == part['shift']:
                parts[-1]['width'] += 1
            elif parts and 'constant' in part and 'constant' in parts[-1] and part.get('known', True) == parts[-1].get('known', True):
                parts[-1]['constant'] |= part['constant'] << parts[-1]['width']
                parts[-1]['width'] += 1
            else:
                parts.append(part)
        result[name] = list(reversed(parts))
    return result


def selected_channels(resources: list[dict]) -> dict[int, str]:
    """Select message production, link queues, reduction consumption and executor admission."""
    selected = {}
    for resource in resources:
        name = resource['name']
        if resource['kind'] == 'fifo' and re.search(r'fifo__(outgoing|received)_\d+__\d+_$', name):
            for side in (('pop',) if '__outgoing_' in name else ('push',)):
                selected[resource[side]] = side+' '+name
        elif resource['kind'] == 'channel':
            if 'ActorOutboxDrain' in name and re.search(r'/_(effects|fragment_\d+)$', name):
                selected[resource['id']] = 'effect'
            elif 'ReductionCollector' in name and re.search(r'/_frame_\d+$', name):
                selected[resource['id']] = 'fragment'
            elif 'SharedExecutor' in name and name.endswith(('/_request_in', '/_result_out')):
                selected[resource['id']] = 'executor' if name.endswith('/_request_in') else 'executor_result'
            elif 'SharedService' in name and re.search(r'/_(request_in__\d+|startup_in|mailbox_(read|write)_req_out|mailbox_read_resp_in)$', name):
                selected[resource['id']] = 'mailbox'
            elif re.search(r'__(FrameMux2|Router\d+|SchedulerInput\d+|SchedulerIngress\d+|ControlRouter)_', name):
                selected[resource['id']] = 'route'
    # Retain both ends of each selected FIFO, preserving identity through buffering.
    changed = True
    while changed:
        changed = False
        for resource in resources:
            if resource['kind'] == 'fifo' and (resource['push'] in selected or resource['pop'] in selected):
                for side in ('push', 'pop'):
                    if resource[side] not in selected:
                        selected[resource[side]] = side+' '+resource['name']
                        changed = True
    return selected


def plan(build: Path, stage: Path, devices: tuple[int, ...], public: Path) -> Path:
    """Generate a read-only observer; preserve payload bindings and source digests for replay."""
    bindings, hashes = [], {}
    lines = ['`timescale 1ns/1ps', 'module phi_message_observer;', 'integer stream;',
             'initial begin', '  stream = $fopen("message-trace.csv", "w");',
             '  if (!stream) $fatal(1, "message trace open failed");',
             '  $fwrite(stream, "time_ns,device,epoch,id,value\\n");', 'end']
    for device in devices:
        source = build/f'device{device}/debug/instrumented.v'
        manifest = stage/f'device{device}-manifest.json'
        hashes[str(source)] = digest(source)
        hashes[str(manifest)] = digest(manifest)
        resources = json.loads(manifest.read_text())['resources']
        selected = selected_channels(resources)
        from phi_mailbox_trace import retained_rtl
        source, flat, alias_hashes = retained_rtl(build, stage, device, public, selected)
        nets = declarations(source)
        hashes.update(alias_hashes)
        names = [r['name'].replace('/', '.') for r in resources if r['id'] in selected]
        names = [name+'_data' if name.endswith(('.push', '.pop')) else name for name in names]
        resolved = alias_parts(names, nets, flat)
        del flat
        lines += [f'integer epoch{device} = 0;', f'reg was_reset{device} = 1;',
                  f'always @(posedge phi_bridge_tb.clk{device}) begin',
                  f'  if (phi_bridge_tb.reset{device}) begin',
                  f'    if (!was_reset{device}) epoch{device} = epoch{device}+1;',
                  f'    was_reset{device} = 1;', '  end else begin',
                  f'    was_reset{device} = 0;', '    if (phi_bridge_tb.resetn) begin']
        for resource in resources:
            ident = resource['id']
            if ident not in selected:
                continue
            net = resource['name'].replace('/', '.')
            if net.endswith('.push') or net.endswith('.pop'):
                net += '_data'
            parts = resolved[net]
            binding = {'device': device, 'id': ident, 'channel': resource['name'],
                       'role': selected[ident], 'parts': parts, 'width': sum(p['width'] for p in parts),
                       'known_mask': hex(sum(((1 << p['width'])-1) << p['offset'] for p in parts if p.get('known', True)))}
            bindings.append(binding)
            expressions = [f"{p['width']}'d{p['constant']}" if 'constant' in p else
                f"{p['width']}'(phi_bridge_tb.device_{device}.application.\\{p['name']} >> {p.get('shift', 0)})" for p in parts]
            expression = '{'+', '.join(expressions)+'}'
            lines += [f'      if (phi_bridge_tb.device_{device}.probe_values[{64*ident} +: 2] === 2\'b11) begin',
                      f'        if ((^{expression}) === 1\'bx) $fatal(1, "unknown accepted payload D{device}/{ident}");',
                      f'        $fwrite(stream, "%.0f,{device},%0d,{ident},%h\\n", $realtime, epoch{device}, {expression});',
                      '      end']
        lines += ['    end', '  end', 'end']
        if digest(source) != hashes[str(source)]:
            raise ValueError('RTL changed during observer preparation')
    lines += ['final $fclose(stream);', 'endmodule']
    output = stage/'phi_message_observer.sv'
    output.write_text('\n'.join(lines)+'\n')
    (stage/'message-bindings.json').write_text(json.dumps({'schema': 1, 'sources': hashes,
        'observer_sha256': digest(output), 'channels': bindings}, indent=2)+'\n')
    return output
