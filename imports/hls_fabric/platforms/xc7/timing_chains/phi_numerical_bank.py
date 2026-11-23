#!/usr/bin/env python3
"""Exercise exclusive recurrence ownership and publication under stalls and reset."""
import argparse
from collections import Counter
import json
from pathlib import Path
import random
import shutil

from architecture import sha
from phi_numerical import HERE, recurrence
from staged_reciprocal import run


def commands(slots: int) -> list[tuple[int, ...]]:
    """Mix valid rounds, epoch wrap, bad requests and release/reacquire transitions."""
    rng = random.Random(260927)
    rows = []
    for session in range(20):
        epoch = 0xfffffff8 if session % 2 == 0 else session * 12
        for slot in range(slots):
            rows.append((0, slot, epoch, rng.getrandbits(32), rng.getrandbits(32),
                         (1 << 32)-1 if session == 0 else rng.getrandbits(1), 0, 0))
        for round_id in range(24):
            for slot in range(slots):
                if round_id % 7 == 0:
                    rows.append((1, slot, (epoch+7) & 0xffffffff, 0, 0, 0, 0, 0))
                    rows.append((0, slot, epoch, 17, 91, 0, 0, 0))
                rows.append((1, slot, epoch, 0, 0, 0,
                             rng.randint(-(1 << 33), (1 << 33)-4),
                             rng.randint(-(1 << 33), (1 << 33)-4)))
            epoch = (epoch+1) & 0xffffffff
        for slot in range(slots):
            rows += [(2, slot, epoch, 0, 0, 0, 0, 0),
                     (1, slot, epoch, 0, 0, 0, 0, 0),
                     (3, slot, epoch, 0, 0, 0, 0, 0)]
    return rows


def torus_commands() -> list[tuple[int, ...]]:
    """Drive 12 rounds of the real two-layer recurrence on a periodic 2×2 phi grid."""
    fields = [(0, 0)] * 4
    sources = (1, 0, 0, 1)
    rows = [(0, slot, 0, 0, 0, sources[slot], 0, 0) for slot in range(4)]
    for epoch in range(12):
        updated = []
        for slot in range(4):
            neighbors = (slot ^ 1, slot ^ 1, slot ^ 2, slot ^ 2)
            sums = tuple(sum(fields[n][component] for n in neighbors) for component in range(2))
            rows.append((1, slot, epoch, 0, 0, 0, *sums))
            updated.append(recurrence(*fields[slot], *sums, sources[slot]))
        fields = updated
    rows += [(2, slot, 12, 0, 0, 0, 0, 0) for slot in range(4)]
    return rows


def signed(n: int, bits: int) -> int:
    """Interpret a wire word in two's-complement form."""
    return n - (1 << bits) if n & (1 << (bits-1)) else n


def scoreboard(log: Path, slots: int) -> dict:
    """Check accepted commands against a semantic oracle, independent of pipeline timing."""
    state = {slot: (False, 0, 0, 0, 0) for slot in range(slots)}
    pending = {}
    counts = Counter()
    latencies = Counter()
    peak = 0
    last_cycle = 0
    first_advance = None
    last_advance = None
    for line in log.read_text().splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == 'RESET':
            counts['reset'] += 1
            counts['discarded_by_reset'] += len(pending)
            pending.clear()
            state = {slot: (False, 0, 0, 0, 0) for slot in range(slots)}
        elif words[0] == 'C':
            cycle, kind, slot, epoch, f0, f1, anyon, sum0, sum1 = [int(s, 16) for s in words[1:]]
            if slot in pending:
                raise ValueError('slot reused before publication')
            owned, old_epoch, a, b, source = state[slot]
            error = (1 if kind == 3 else 2 if (owned if kind == 0 else not owned)
                     else 3 if kind != 0 and epoch != old_epoch else 0)
            if not error:
                if kind == 0:
                    owned, old_epoch, a, b, source = True, epoch, signed(f0, 32), signed(f1, 32), anyon
                elif kind == 1:
                    a, b = recurrence(a, b, signed(sum0, 34), signed(sum1, 34), source)
                    old_epoch = (old_epoch+1) & 0xffffffff
                    if first_advance is None:
                        first_advance = cycle
                state[slot] = (owned, old_epoch, a, b, source)
            expected = (3 if error else kind, error, old_epoch, a & 0xffffffff, b & 0xffffffff)
            pending[slot] = (expected, cycle)
            counts['commands'] += 1
            counts['error_'+str(error) if error else ('acquire', 'advance', 'release')[kind]] += 1
            peak = max(peak, len(pending))
        elif words[0] == 'R':
            cycle, slot, kind, error, epoch, a, b = [int(s, 16) for s in words[1:]]
            expected, accepted = pending.pop(slot)
            if (kind, error, epoch, a, b) != expected:
                raise ValueError(f'response at {cycle}: {(kind,error,epoch,a,b)} != {expected}')
            if kind == 2:
                state[slot] = (False, *state[slot][1:])
            if kind == 1:
                latencies[cycle-accepted] += 1
                last_advance = cycle
            counts['responses'] += 1
            last_cycle = cycle
        elif words[0] == 'PASS':
            counts['completed'] += 1
    if pending or counts['completed'] != 1:
        raise ValueError('unaccounted commands or incomplete simulation')
    return {'counts': dict(counts), 'max_reserved_slots': peak,
            'advance_response_cycles': dict(sorted(latencies.items())), 'last_response_cycle': last_cycle,
            'advance_span_cycles': None if last_advance is None else last_advance-first_advance}


def verify(root: Path, kernel: Path, slots: int, latency: int, *, mapped: Path | None = None,
           cells: Path | None = None, torus: bool = False, reset_in_flight: bool = False,
           stall: bool = True) -> dict:
    """Run the same accepted-command oracle against generated and mapped engines."""
    root.mkdir(parents=True, exist_ok=False)
    bits = max(1, (slots-1).bit_length())
    rows = torus_commands() if torus else commands(slots)
    width = 2+bits+32*4+34*2
    encoded = []
    for row in rows:
        word = 0
        for n, nbits in zip(row, (2, bits, 32, 32, 32, 32, 34, 34)):
            word = word << nbits | (n & ((1 << nbits)-1))
        encoded.append(f'{word:0{(width+3)//4}x}')
    (root/'commands.hex').write_text('\n'.join(encoded)+'\n')
    bench = f'''module testbench;
reg clk = 0; always #5 clk = !clk;
reg reset = 1, cmd_valid = 0, rsp_ready = 0;
wire cmd_ready, rsp_valid;
reg [1:0] cmd_kind; wire [1:0] rsp_kind, rsp_error;
reg [{bits-1}:0] cmd_slot; wire [{bits-1}:0] rsp_slot;
reg [31:0] cmd_epoch, cmd_field0, cmd_field1, cmd_anyon;
reg [33:0] cmd_sum0, cmd_sum1;
wire [31:0] rsp_epoch, rsp_field0, rsp_field1;
phi_numerical_bank {'' if mapped else f'#(.SLOTS({slots}), .LATENCY({latency}))'} dut(.*);
reg [{width-1}:0] commands[0:{len(rows)-1}];
reg [31:0] rng = 32'h85977af2;
reg [{99+bits}:0] held;
reg blocked = 0;
integer i = 0, cycle = 0, drained = 0, outstanding = 0;
initial begin
  $readmemh("commands.hex", commands);
  repeat ({len(rows)*80}) begin
    @(negedge clk);
    rng = {{rng[30:0], rng[31]^rng[21]^rng[1]^rng[0]}};
    reset = cycle == 0 || ({int(reset_in_flight)} && (cycle == 17 || cycle == 3001 || cycle == 6007));
    rsp_ready = !{int(stall)} || (rng[3:0] != 0 && cycle % 127 >= 31);
    // The torus replay may know its oracle inputs in advance, but must wait for
    // all previous-round responses before making the next round available.
    cmd_valid = i < {len(rows)} && (!{int(torus)} || i % {slots} != 0 || outstanding == 0);
    {{cmd_kind,cmd_slot,cmd_epoch,cmd_field0,cmd_field1,cmd_anyon,cmd_sum0,cmd_sum1}} =
      cmd_valid ? commands[i] : 0;
    @(posedge clk);
    if (reset) begin $display("RESET"); blocked = 0; outstanding = 0; end
    else begin
      if (blocked && (!rsp_valid || {{rsp_slot,rsp_kind,rsp_error,rsp_epoch,rsp_field0,rsp_field1}} !== held))
        $fatal(1,"unstable stalled response cycle %0d",cycle);
      if (cmd_valid && cmd_ready) begin
        $display("C %h %h %h %h %h %h %h %h %h",cycle,cmd_kind,cmd_slot,cmd_epoch,cmd_field0,cmd_field1,cmd_anyon,cmd_sum0,cmd_sum1);
        i = i + 1;
        outstanding = outstanding + 1;
      end
      if (rsp_valid && rsp_ready) begin
        $display("R %h %h %h %h %h %h %h",cycle,rsp_slot,rsp_kind,rsp_error,rsp_epoch,rsp_field0,rsp_field1);
        outstanding = outstanding - 1;
      end
      blocked = rsp_valid && !rsp_ready;
      held = {{rsp_slot,rsp_kind,rsp_error,rsp_epoch,rsp_field0,rsp_field1}};
    end
    if (i == {len(rows)}) drained = drained + 1;
    if (drained == 200) begin $display("PASS"); $finish; end
    cycle = cycle + 1;
  end
  $fatal(1,"timeout");
end
endmodule
'''
    (root/'testbench.sv').write_text(bench)
    sources = [str(mapped), str(cells)] if mapped else [str(HERE/'phi_numerical_bank.sv'),
               *[str(p) for p in kernel.glob('*.v') if p.name != 'mapped.v']]
    run(['iverilog', '-g2012', '-s', 'testbench', '-o', 'sim.vvp', 'testbench.sv', *sources], root, 'compile')
    run(['vvp', 'sim.vvp'], root, 'simulation')
    (root/'sim.vvp').unlink()
    result = scoreboard(root/'simulation.log', slots)
    (root/'summary.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def map_bank(root: Path, kernel: Path, yosys: Path, slots: int, latency: int) -> dict:
    """Map all ownership/control/storage alongside the kernel, keeping DSP cuts in fabric."""
    root.mkdir(parents=True, exist_ok=False)
    sources = [HERE/'phi_numerical_bank.sv', *[p for p in kernel.glob('*.v') if p.name != 'mapped.v']]
    for source in sources:
        shutil.copyfile(source, root/source.name)
    cells = yosys.parent.parent/'share/yosys/xilinx/cells_sim.v'
    script = ('read_verilog -sv '+ ' '.join(p.name for p in sources) + '\n'
        f'chparam -set SLOTS {slots} -set LATENCY {latency} phi_numerical_bank\n'
        'scratchpad -set xilinx_dsp.multonly 1\n'
        'synth_xilinx -flatten -abc9 -nosrl -family xc7 -noiopad -noclkbuf -top phi_numerical_bank\n'
        'check -assert\nscc -expect 0\ndelete t:$scopeinfo\n'
        'write_edif -pvector bra mapped.edf\nwrite_json mapped.json\nwrite_verilog -noattr mapped.v\n')
    (root/'map.ys').write_text(script)
    run([str(yosys), '-Q', '-T', '-s', 'map.ys'], root, 'map')
    data = json.loads((root/'mapped.json').read_text())
    top = data['modules']['phi_numerical_bank']
    counts = Counter(c['type'] for c in top['cells'].values())
    data['modules'] = {'phi_numerical_bank': top}
    (root/'mapped.json').write_text(json.dumps(data, separators=(',', ':'))+'\n')
    result = {'cells': dict(counts), 'luts': sum(v for k,v in counts.items() if k.startswith('LUT')),
              'ffs': sum(v for k,v in counts.items() if k.startswith('FD')),
              'inputs': {str(p): sha(p) for p in [*sources, yosys, cells]}}
    (root/'mapping.json').write_text(json.dumps(result, indent=2)+'\n')
    return result


def main() -> None:
    """Screen the full owner with one or five arithmetic stages and 1/3/4/8 slots."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('stage', 'kernel', 'yosys'):
        parser.add_argument('--'+name, required=True, type=lambda p: Path(p).resolve())
    args = parser.parse_args()
    args.stage.mkdir(parents=True, exist_ok=False)
    results = {}
    for name, latency in (('reference', 1), ('split', 5)):
        for slots in (1, 3, 4, 8):
            key = f'{name}-{slots}'
            row = results[key] = {}
            row['rtl'] = verify(args.stage/(key+'-rtl'), args.kernel/name, slots, latency)
            row['reset'] = verify(args.stage/(key+'-reset'), args.kernel/name, slots, latency, reset_in_flight=True)
            if slots == 4:
                for stall in (False, True):
                    row['torus-stall-'+str(stall)] = verify(args.stage/(key+'-torus-'+str(stall)),
                        args.kernel/name, slots, latency, torus=True, stall=stall)
                root = args.stage/(key+'-map')
                row['mapping'] = map_bank(root, args.kernel/name, args.yosys, slots, latency)
                row['mapped'] = verify(args.stage/(key+'-mapped'), args.kernel/name, slots, latency,
                    mapped=root/'mapped.v', cells=args.yosys.parent.parent/'share/yosys/xilinx/cells_sim.v',
                    reset_in_flight=True)
            print(key, json.dumps(row), flush=True)
            (args.stage/'summary.json').write_text(json.dumps(results, indent=2)+'\n')


if __name__ == '__main__':
    main()
