#!/usr/bin/env python3
"""Check Icarus RPC/AXI behavior and optionally QEMU's rejection of broken peers."""

import argparse
import os
import socket
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

from cosim.runtime import compile_rtl, rtl_server

PACKET = struct.Struct("<8I")
MAGIC = 0x484C5343
BASE = 0x40000000


class Peer:
    """Issue one serialized RPC at a time and validate its complete response."""

    def __init__(self, path: Path) -> None:
        """Connect to a fresh RTL instance with bounded socket waits."""
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.settimeout(5)
        self.socket.connect(str(path))
        self.sequence = 0

    def request(self, op: int, address: int = 0, data: int = 0, amount: int = 4,
                fragmented: bool = False) -> tuple[int, int, int, int]:
        """Require matching identity/sequence and return bus status, data, IRQ, cycles."""
        self.sequence += 1
        packet = PACKET.pack(MAGIC, 1, op, self.sequence, address, data, amount, 0)
        if fragmented:
            for byte in packet:
                self.socket.sendall(bytes([byte]))
        else:
            self.socket.sendall(packet)
        response = bytearray()
        while len(response) < PACKET.size:
            part = self.socket.recv(PACKET.size - len(response))
            if not part:
                raise EOFError("RTL peer closed before replying")
            response.extend(part)
        magic, version, reply, sequence, status, value, irq, cycles = PACKET.unpack(response)
        if (magic, version, reply, sequence) != (MAGIC, 1, op | 0x80000000, self.sequence):
            raise ValueError("unexpected reply identity")
        return status, value, irq, cycles


class BridgeTests(unittest.TestCase):
    """Exercise bus traffic, autonomous steps, reset and corrupt connections."""

    @classmethod
    def setUpClass(cls) -> None:
        """Compile once; each test connects to an independent simulator process."""
        cls.temporary = tempfile.TemporaryDirectory(prefix="hls-cosim-", dir="/tmp")
        cls.root = Path(cls.temporary.name)
        compile_rtl(cls.root / "rtl")

    @classmethod
    def tearDownClass(cls) -> None:
        """Discard only this suite's temporary sockets and build products."""
        cls.temporary.cleanup()

    def test_bus_and_steps(self) -> None:
        """DMA-sized traffic uses AXI, waits for steps/IRQ, and obeys slot ownership."""
        path, log = self.root / "bus.sock", self.root / "bus.log"
        with rtl_server(self.root / "rtl", path, log) as process:
            peer = Peer(path)
            try:
                self.assertEqual(peer.request(4, amount=0)[0], 0)
                self.assertEqual(peer.request(1, BASE, fragmented=True)[:2], (0, 0x484C444D))
                self.assertEqual(peer.request(1, BASE + 0x2000)[0], 2)
                self.assertEqual(peer.request(2, BASE + 24, 7)[0], 0)
                payload = [i ^ 0xAB123456 for i in range(257)]
                for i, word in enumerate(payload):
                    self.assertEqual(peer.request(2, BASE + 0x1000 + 4*i, word)[0], 0)
                self.assertEqual(peer.request(2, BASE + 12, 1028)[0], 0)
                self.assertEqual(peer.request(1, BASE + 8)[1] & 1, 1)
                self.assertEqual(peer.request(3, amount=1024)[2], 1)
                self.assertEqual(peer.request(1, BASE + 16)[1], 1028)
                for i, word in enumerate(payload):
                    self.assertEqual(peer.request(1, BASE + 0x2000 + 4*i)[:2], (0, word))
                self.assertEqual(peer.request(1, BASE + 0x2404)[0], 2)
                # A second TX slot stays busy until software releases the first RX.
                self.assertEqual(peer.request(2, BASE + 12, 8)[0], 0)
                peer.request(3, amount=100)
                self.assertEqual(peer.request(1, BASE + 8)[1] & 3, 3)
                self.assertEqual(peer.request(2, BASE + 12, 8)[0], 2)
                peer.request(2, BASE + 20, 3)
                peer.request(3, amount=100)
                self.assertEqual(peer.request(1, BASE + 16)[1], 8)
                peer.request(4, amount=0)
                self.assertEqual(peer.request(1, BASE + 8)[:3], (0, 0, 0))
            finally:
                peer.socket.close()
            self.assertEqual(process.wait(timeout=5), 0, log.read_text())
        self.assertIn("frames=2", log.read_text())

    def test_bad_packets(self) -> None:
        """Bad version, sequence, step count and partial EOF fail without a reply."""
        packets = [PACKET.pack(MAGIC, 2, 1, 1, BASE, 0, 4, 0),
                   PACKET.pack(MAGIC, 1, 1, 2, BASE, 0, 4, 0),
                   PACKET.pack(MAGIC, 1, 3, 1, 0, 0, 4097, 0), b"truncated"]
        for i, packet in enumerate(packets):
            with self.subTest(case=i):
                path, log = self.root / f"bad{i}.sock", self.root / f"bad{i}.log"
                with rtl_server(self.root / "rtl", path, log) as process:
                    with socket.socket(socket.AF_UNIX) as client:
                        client.settimeout(5)
                        client.connect(str(path))
                        client.sendall(packet)
                        client.shutdown(socket.SHUT_WR)
                        self.assertEqual(client.recv(32), b"")
                    self.assertNotEqual(process.wait(timeout=5), 0)


class QemuBridgeTests(unittest.TestCase):
    """Require the built emulator to stop on corrupt replies or lost RTL peers."""

    qemu: Path

    def test_bad_replies(self) -> None:
        """Reject bad identity, sequence, status, IRQ, cycle count and partial EOF."""
        replies = [[MAGIC, 2, 0x80000004, 1, 0, 0, 0, 5],
                   [MAGIC, 1, 0x80000004, 2, 0, 0, 0, 5],
                   [MAGIC, 1, 0x80000004, 1, 4, 0, 0, 5],
                   [MAGIC, 1, 0x80000004, 1, 0, 0, 2, 5],
                   [MAGIC, 1, 0x80000004, 1, 0, 0, 0, 4097]]
        for i, packet in enumerate([*(PACKET.pack(*reply) for reply in replies), b"partial", b""]):
            with self.subTest(case=i), tempfile.TemporaryDirectory(prefix="hls-peer-", dir="/tmp") as temporary:
                path = Path(temporary) / "peer.sock"
                with socket.socket(socket.AF_UNIX) as listener:
                    listener.settimeout(5)
                    listener.bind(str(path))
                    listener.listen(1)
                    with subprocess.Popen([str(self.qemu), "-M", "xilinx-zynq-a9", "-m", "1024",
                                           "-display", "none", "-serial", "none", "-monitor", "none",
                                           "-nic", "none", "-S"],
                                          env=dict(os.environ, HLS_COSIM_SOCKET=str(path)),
                                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
                        try:
                            connection, _ = listener.accept()
                            with connection:
                                connection.settimeout(5)
                                request = bytearray()
                                while len(request) < PACKET.size:
                                    part = connection.recv(PACKET.size - len(request))
                                    if not part:
                                        raise EOFError("QEMU closed before its reset request")
                                    request.extend(part)
                                self.assertEqual(PACKET.unpack(request), (MAGIC, 1, 4, 1, 0, 0, 0, 0))
                                connection.sendall(packet)
                                connection.shutdown(socket.SHUT_WR)
                                output, _ = process.communicate(timeout=5)
                            self.assertNotEqual(process.returncode, 0, output)
                            self.assertIn(b"HLS co-simulation:", output)
                        finally:
                            if process.poll() is None:
                                process.kill()
                                process.wait()


def run(qemu: Path | None = None) -> None:
    """Run portable bridge checks and optional native-QEMU connection failures."""
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(BridgeTests)
    if qemu:
        QemuBridgeTests.qemu = qemu.resolve()
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(QemuBridgeTests))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise RuntimeError("QEMU/Icarus bridge checks failed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qemu", type=Path)
    run(parser.parse_args().qemu)
