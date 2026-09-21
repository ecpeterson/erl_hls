#!/usr/bin/env python3
"""Check optional packet-DMA CDC and public AXI-to-MAC co-simulation."""

import argparse
import json
import shutil
import struct
import subprocess
import tempfile
import time
from pathlib import Path

from cosim.runtime import compile_rtl, rtl_server
from ethernet.dma_fixture import ROOT, sources
from ethernet.prepare import digest
from test_ethernet import simulation_models, synthesize, yosys_data
from test_qemu_cosim import BASE, Peer


def cdc(yosys: Path, stage: Path) -> dict:
    """Compare packet boundaries/recovery before and after XC7 mapping; require BRAM."""
    owned = [ROOT / "zynq_ps_probe.v", ROOT / "ethernet/cdc_slot.v", ROOT / "ethernet/dma_packets.v"]
    cells = {}
    for mapped in (False, True):
        run = stage / ("mapped" if mapped else "raw")
        run.mkdir(parents=True, exist_ok=True)
        rtl = [synthesize(yosys, run, owned, True, "ethernet_dma_packets")] if mapped else owned
        if mapped:
            cells = json.loads((run / "stat.json").read_text())["modules"]["\\ethernet_dma_packets"]["num_cells_by_type"]
            if cells.get("RAMB18E1") != 2 or cells.get("RAMB36E1", 0):
                raise AssertionError(f"CDC packet RAM no longer maps to two RAMB18s: {cells}")
        models = simulation_models(run, yosys_data(yosys) / "xilinx/cells_sim.v" if mapped else None, stage / "sources")
        executable = run / "test.vvp"
        subprocess.run(["iverilog", "-g2012", "-s", "dma_packets_tb", *(["-s", "glbl"] if mapped else []),
                        "-o", str(executable), str(ROOT / "ethernet/dma_packets_tb.sv"),
                        *map(str, [*rtl, *models])], check=True, timeout=30)
        with (run / "simulation.log").open("w") as log:
            subprocess.run(["vvp", str(executable)], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)
        print((run / "simulation.log").read_text().strip())
    return cells


def wait_mask(peer: Peer, address: int, mask: int, value: int) -> None:
    """Advance the external clock schedule until an observed register predicate holds."""
    for _ in range(400):
        status, data, _, _ = peer.request(1, address)
        if status:
            raise AssertionError(f"register read failed: {address:x}")
        if data & mask == value:
            return
        peer.request(3, amount=256)
    raise AssertionError(f"timed out waiting for register {address:x} mask={mask:x} value={value:x}")


def submit(peer: Peer, payload: bytes) -> None:
    """Fill unpublished TX RAM and commit one padded length envelope through AXI."""
    wait_mask(peer, BASE+8, 1, 0)
    envelope = struct.pack("<I", len(payload)) + payload + b"\0"*(-len(payload) % 4)
    for i, (word,) in enumerate(struct.iter_unpack("<I", envelope)):
        if peer.request(2, BASE+0x1000+4*i, word)[0]:
            raise AssertionError("TX RAM write failed")
    if peer.request(2, BASE+12, len(envelope))[0]:
        raise AssertionError("TX publication failed")


def receive(peer: Peer, payload: bytes) -> None:
    """Check returned bytes, Ethernet padding and exact envelope size through AXI."""
    wait_mask(peer, BASE+8, 6, 2)
    expected = payload.ljust(60, b"\0")
    status, length, _, _ = peer.request(1, BASE+16)
    if status or length != 4+((len(expected)+3)//4)*4:
        raise AssertionError(f"unexpected RX length: {length}")
    words = []
    for i in range(length//4):
        status, word, _, _ = peer.request(1, BASE+0x2000+4*i)
        if status:
            raise AssertionError("RX RAM read failed")
        words.append(word)
    data = struct.pack("<"+"I"*len(words), *words)
    if struct.unpack_from("<I", data)[0] != len(expected) or data[4:4+len(expected)] != expected:
        raise AssertionError("packet changed while traversing DMA/PCS/MAC")
    peer.request(2, BASE+20, 3)


def packets(stage: Path, yosys: Path | None = None) -> None:
    """Drive actual AXI pins and PCS/MAC; link loss cannot invalidate committed RX."""
    compile_rtl(stage, ethernet_sources=sources(stage, yosys))
    with tempfile.TemporaryDirectory(prefix="eth-cosim-", dir="/tmp") as temporary:
        socket = Path(temporary) / "rtl.sock"
        with rtl_server(stage, socket, stage / "rtl.log") as process:
            peer = Peer(socket)
            try:
                peer.request(4, amount=0)
                if peer.request(1, BASE)[:2] != (0, 0x484c454d):
                    raise AssertionError("wrong packet mailbox profile")
                wait_mask(peer, BASE+0x3008, 3, 3)
                peer.request(2, BASE+24, 7)
                for length in (14, 17, 60, 61, 1021, 1513, 1514):
                    payload = bytes((i*37 ^ length) & 255 for i in range(length))
                    submit(peer, payload)
                    receive(peer, payload)
                # Hold a committed CDC packet, lose the link, then read it intact.
                peer.request(2, BASE+0x3004, 2)
                payload = bytes(range(93))
                submit(peer, payload)
                wait_mask(peer, BASE+0x3008, 8, 8)
                peer.request(2, BASE+0x3004, 3)
                wait_mask(peer, BASE+0x3008, 3, 0)
                peer.request(2, BASE+0x3004, 1)
                receive(peer, payload)
                peer.request(2, BASE+0x3004, 0)
                wait_mask(peer, BASE+0x3008, 3, 3)
                payload = bytes(reversed(range(67)))
                submit(peer, payload)
                receive(peer, payload)
            finally:
                peer.socket.close()
            if process.wait(timeout=5):
                raise AssertionError((stage / "rtl.log").read_text())
    print("PASS: AXI mailbox, byte envelopes, MAC/PCS loopback and committed RX through link recovery")


def run(yosys: Path, output: Path) -> dict:
    """Run bounded portable checks and retain area, elapsed time and source provenance."""
    started = time.monotonic()
    cells = cdc(yosys, output)
    packets(output / "packet-cosim", yosys)
    report = {"cdc_cells": cells, "elapsed_seconds": round(time.monotonic()-started, 2),
              "hardware_qualified": False,
              "yosys": subprocess.check_output([str(yosys), "-V"], text=True).strip(),
              "inputs": {str(path.relative_to(ROOT)): digest(path) for path in [
                  Path(__file__), ROOT / "test_ethernet.py", ROOT / "test_qemu_cosim.py", ROOT / "zynq_ps_probe.v",
                  ROOT / "dma/zynq_dma_mailbox.v", ROOT / "cosim/runtime.py", ROOT / "cosim/mailbox_tb.sv",
                  ROOT / "cosim/ethernet_fixture.sv", ROOT / "cosim/icarus_bridge.c", ROOT / "cosim/protocol.h",
                  *[ROOT / "ethernet" / name for name in (
                      "prepare.py", "generate.py", "dma_fixture.py", "cdc_slot.v", "dma_packets.v", "dma_packets_tb.sv",
                      "packet_endpoint.v", "frame_store.v", "sources.lock.json", "models.lock.json")]]}}
    (output / "result.json").write_text(json.dumps(report, indent=2)+"\n")
    return report


def main() -> None:
    """Select tools/output; full Linux/PL330 co-simulation is a separate command."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path, default=Path(shutil.which("yosys") or "yosys"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/ethernet-dma")
    args = parser.parse_args()
    run(args.yosys.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
