#!python3

import mmap, os, struct, time

SHM_PATH = "/dev/shm/xls_fmac_shm"     # Linux
FMT = "<IffIfI"  # seq_in,a,b,seq_out,out,state
SIZE = struct.calcsize(FMT)

fd = os.open(SHM_PATH, os.O_RDWR)
mm = mmap.mmap(fd, SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
os.close(fd)

def read_regs():
    mm.seek(0)
    return struct.unpack(FMT, mm.read(SIZE))

def write_req(seq, a, b):
    # preserve seq_out/out/state fields; sim owns those
    _, _, _, seq_out, out, state = read_regs()
    mm.seek(0)
    mm.write(struct.pack(FMT, seq, a, b, seq_out, out, state))
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

