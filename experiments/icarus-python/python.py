#!python3

import os, struct, time

SHM_PATH = "/dev/shm/xls_fmac_shm"     # Linux
FMT = "<IddIdI"  # seq_in,a,b,seq_out,out,state
SIZE = struct.calcsize(FMT)

mm = open(SHM_PATH, "r+b")

def read_regs():
    mm.seek(0)
    raw = mm.read(SIZE)
    return struct.unpack(FMT, raw)

def write_req(seq, a, b):
    # preserve seq_out/out/state fields; sim owns those
    _, _, _, seq_out, out, state = read_regs()
    mm.seek(0)
    raw = struct.pack(FMT, seq, a, b, seq_out, out, state)
    mm.write(raw)
    mm.flush()

def wait_resp(seq, timeout_s=5.0):
    t0 = time.time()
    while True:
        seq_in, a, b, seq_out, out, state = read_regs()
        if seq_out == seq:
            return out, state
        if time.time() - t0 > timeout_s:
            raise TimeoutError(f"timeout waiting for seq {seq}, state={state}")
        time.sleep(0.0005)

seq = 0
# Example: drive raw bits (here: just integers; for fp32 you’d pack floats)
for (a, b) in [
        (1.0, 2.0),
        (2.0, 3.0),
        (3.0, 4.0),
    ]:
    seq += 1
    write_req(seq, a, b)
    out, state = wait_resp(seq)
    print(f"{seq=} {a=} {b=} {out=} {state=}")

mm.close()

