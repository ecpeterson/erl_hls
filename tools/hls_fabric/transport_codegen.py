"""Compile queue-boundary adapters with explicit XLS schedules, leaving other RTL intact.

XLS currently validates IO constraints only against the top proc. Each selected
queue proc is therefore compiled from its own unchanged optimized proc and linked
back through an identical module interface. No queue behavior is written in RTL.
"""
import hashlib
import json
from pathlib import Path
import re

from backend_commands import digest, execute


def adapter_procs(ir: str) -> list[tuple[str, str, str]]:
    """Extract supported queue procs; reject calls, unexpected state or unrecognized IR operations."""
    found = []
    pattern = r'^proc (\w*(?:__hls_packed_link__(?:Deliver|Wire)_|_ReductionFrame_|_ReductionMux_)\w+)[^\n]*\{\n.*?^}'
    for match in re.finditer(pattern, ir, re.M | re.S):
        name = match[1]
        kind = ('Deliver' if '__hls_packed_link__Deliver_' in name else
                'ReductionMux' if '_ReductionMux_' in name else 'Wire')
        header = match[0].splitlines()[0]
        if kind == 'ReductionMux':
            # Only the polling cursor belongs to this proc; payloads stay in its input queues.
            if not header.endswith('>() {') and not re.search(r'>\(__state: bits\[\d+\](?: pos=\[.*?\])?, init=\{0\}\) \{$', header):
                raise ValueError(f'aggregate mux has unexpected state: {name}')
        elif not header.endswith('>() {'):
            raise ValueError(f'adapter acquired state: {name}')
        operations = re.findall(r'^  [\w.]+: .*? = (\w+)\(', match[0], re.M)
        allowed = {'after_all', 'receive', 'send', 'tuple_index', 'literal'}
        if kind == 'ReductionMux':
            allowed |= {'state_read', 'next_value', 'not', 'or', 'and', 'nor', 'nand', 'xor',
                        'eq', 'ne', 'ult', 'uge', 'add', 'bit_slice', 'concat', 'zero_ext',
                        'sel', 'priority_sel', 'one_hot_sel', 'one_hot', 'tuple'}
        if not operations or set(operations) - allowed:
            raise ValueError(f'adapter is no longer self-contained: {name}')
        found.append((name, kind, match[0]))
    if '__hls_packed_link__Bridge_' in ir and not {'Deliver', 'Wire'} <= {kind for _, kind, _ in found}:
        raise ValueError('packed bridge lacks its expected queue adapters')
    return found


def replace_module(rtl: str, name: str, replacement: str) -> str:
    """Replace exactly one module after checking its full interface; preserve every other byte."""
    pattern = rf'^module {re.escape(name)}\(.*?^endmodule'
    original, = re.findall(pattern, rtl, re.M | re.S)
    updated, = re.findall(pattern, replacement, re.M | re.S)
    if replacement.replace(updated, '').strip():
        raise ValueError('adapter compilation emitted unexpected modules')
    if original.split('\n);', 1)[0] != updated.split('\n);', 1)[0]:
        raise ValueError(f'adapter interface changed: {name}')
    return rtl.replace(original, updated, 1)


def specialize(compiler: Path, ir: Path, rtl: Path, stage: Path,
               receive: bool = True, transmit: bool = True, reduction: bool = True,
               delay_options: list[str] | None = None) -> dict:
    """Apply selected schedules and record exact compiler inputs, products and unchanged logic.

    The receive queue head reaches its consumer in the same cycle; its credit
    follows in the next cycle. The transmit queue already holds stalled words,
    so its forwarding proc needs one combinational stage. The aggregate mux keeps
    its cursor and input queues but forwards the selected head in the same cycle. Switches support
    isolated latency experiments; normal builds enable all three schedules.
    """
    source, original = ir.read_text(), rtl.read_text()
    candidates = adapter_procs(source)
    selected = [(name, kind, body) for name, kind, body in candidates
                if {'Deliver': receive, 'Wire': transmit, 'ReductionMux': reduction}[kind]]
    record = {'ir_sha256': digest(ir), 'input_rtl_sha256': digest(rtl),
              'driver_sha256': digest(Path(__file__)), 'adapters': []}
    if not selected:
        return record
    stage.mkdir(parents=True, exist_ok=False)
    updated = original
    files = '\n'.join(re.findall(r'^file_number.*$', source, re.M))
    for name, kind, body in selected:
        unit = stage/(name+'.ir')
        output = stage/(name+'.v')
        unit.write_text('package adapter\n'+files+'\n\ntop '+body+'\n')
        options = ['--pipeline_stages=1'] if kind != 'Deliver' else [
            '--pipeline_stages=2',
            '--io_constraints=_delivered_queue:recv:_delivered_frame:send:0:0,'
            '_delivered_frame:send:_delivered_credit:send:1:1']
        command = [str(compiler), *options, *(delay_options or ['--delay_model=unit']), '--flop_inputs=false',
                   '--flop_outputs=false', '--use_system_verilog=false', '--reset=reset',
                   '--fifo_module=', f'--module_name={name}', str(unit)]
        execute(command, stage, name, output=output, timeout=120)
        updated = replace_module(updated, name, output.read_text())
        record['adapters'].append({'module': name, 'command': command,
            'proc_sha256': hashlib.sha256(body.encode()).hexdigest(), 'rtl_sha256': digest(output)})
    if ir.read_text() != source or rtl.read_text() != original:
        raise ValueError('compiler inputs changed while specializing adapters')
    rtl.write_text(updated)
    record['output_rtl_sha256'] = digest(rtl)
    (stage/'manifest.json').write_text(json.dumps(record, indent=2)+'\n')
    return record
