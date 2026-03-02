#!python3

import os
import struct
import time
from enum import IntEnum


class Opcode(IntEnum):
    FMAC = 0
    RESET = 1


SHM_PATH = "/dev/shm/xls_fmac_shm"     # Linux
FMT = "<QddQQdQ"  # seq_in, reset, a, b, seq_out, out, state
SIZE = struct.calcsize(FMT)

mm = open(SHM_PATH, "r+b")

def read_regs():
    mm.seek(0)
    raw = mm.read(SIZE)
    return struct.unpack(FMT, raw)

def write_req(opcode=Opcode.FMAC, a=0.0, b=0.0):
    # preserve seq_out/out/state fields; sim owns those
    seq_in, _, _, _, seq_out, out, state = read_regs()
    assert seq_in == seq_out, f"{seq_in=}, {seq_out=}"
    seq = seq_out + 1

    mm.seek(0)
    raw = struct.pack(FMT, seq, b, a, opcode, seq_out, out, state)
    mm.write(raw)
    mm.flush()

    return seq

def wait_resp(seq, timeout_s=5.0):
    t0 = time.time()
    while True:
        seq_in, b, a, opcode, seq_out, out, state = read_regs()
        assert seq == seq_in, f"Waiting for {seq_in=} but {seq=} is active"
        if seq_out == seq:
            return out, (seq_in, b, a, Opcode(opcode), seq_out, out, state)
        elif time.time() - t0 > timeout_s:
            raise TimeoutError(f"timeout waiting for seq {seq}, state={state}")
        time.sleep(0.0005)

seq = write_req(opcode=Opcode.RESET)
out, state = wait_resp(seq)
print(f"RESET: {seq=} a=0.0 b=0.0 {out=} {state=}")

for (a, b) in [
        (1.0, 2.0),
        (2.0, 3.0),
        (3.0, 4.0),
    ]:
    seq = write_req(opcode=Opcode.FMAC, a=a, b=b)
    out, state = wait_resp(seq)
    print(f"FMAC: {seq=} {a=} {b=} {out=} {state=}")

mm.close()
