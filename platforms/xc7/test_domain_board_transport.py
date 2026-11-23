#!/usr/bin/env python3
"""Finite in-memory codec and local packet-socket relay witnesses; never opens a board.

Pass --helper /absolute/path/to/a/separately/compiled/domain_board_relay to run
native I/O cases. This driver performs no compilation or remote execution.
"""
import argparse
from contextlib import contextmanager
import os
from pathlib import Path
import select
import signal
import socket
import struct
import subprocess
import tempfile
import time
import unittest
from collections.abc import Callable, Iterator
from typing import BinaryIO

from domain_board_transport import Lane, configuration, frame_valid, packet, pop_packet

HELPER: Path | None = None


def frame(words: int, seed: int = 0) -> bytes:
    """Produce all legal routed payload lengths with distinct opaque words."""
    return struct.pack('<II', 4, (128 << 24) | words) + b''.join(
        struct.pack('<I', seed ^ (index * 0x12345)) for index in range(words))


def exact(pipe: BinaryIO, count: int) -> bytes:
    """Read a bounded partial private packet for deterministic close-race scheduling."""
    result = bytearray()
    deadline = time.monotonic() + 2
    while len(result) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([pipe], [], [], remaining)[0]:
            raise TimeoutError('local protocol read')
        chunk = os.read(pipe.fileno(), count - len(result))
        if not chunk:
            raise EOFError('helper closed protocol pipe')
        result.extend(chunk)
    return bytes(result)


def receive(pipe: BinaryIO) -> bytes:
    """Read one private packet with a finite deadline and exact framing."""
    fd = pipe.fileno()
    data = bytearray()
    total = 4
    while len(data) < total:
        if not select.select([fd], [], [], 2)[0]:
            raise TimeoutError('local relay response')
        chunk = os.read(fd, total - len(data))
        if not chunk:
            raise EOFError('local relay EOF')
        data.extend(chunk)
        if len(data) == 4:
            total += struct.unpack('>I', data)[0]
            if total > 1033:
                raise ValueError('relay response bound')
    return bytes(data[4:])


@contextmanager
def native() -> Iterator[tuple[subprocess.Popen, socket.socket]]:
    """Give the helper a local packet socket implementing whole-frame device I/O."""
    assert HELPER is not None
    device, peer = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)
    peer.settimeout(2)
    process = subprocess.Popen([str(HELPER), '--test-fd', str(device.fileno()), '--bank', '1',
                                '--timeout-ms', '5000'], pass_fds=(device.fileno(),),
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, bufsize=0)
    device.close()
    try:
        yield process, peer
    finally:
        if process.poll() is None:
            # A failed same-poll shutdown case may leave the helper stopped.
            os.kill(process.pid, signal.SIGCONT)
            process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)
        for pipe in (process.stdin, process.stdout, process.stderr):
            pipe.close()
        peer.close()


class CodecTests(unittest.TestCase):
    """Exercise finite native framing and private credit state without any subprocess."""

    def test_every_native_length_and_fragmentation(self) -> None:
        """All 256 native payload lengths survive byte-at-a-time envelope delivery."""
        for words in range(256):
            value = frame(words)
            self.assertTrue(frame_valid(value))
            wire = packet(b'R' + value)
            pending = bytearray()
            for byte in wire[:-1]:
                pending.append(byte)
                self.assertIsNone(pop_packet(pending))
            pending.append(wire[-1])
            self.assertEqual(b'R' + value, pop_packet(pending))
            self.assertEqual(bytearray(), pending)
        self.assertFalse(frame_valid(frame(1)[:-1]))
        with self.assertRaises(ValueError):
            pop_packet(bytearray(struct.pack('>I', 1030)))

    def test_exact_credit_and_command_configuration(self) -> None:
        """Unexpected replies and second uncredited RX frames cannot replace retained ownership."""
        lane = object.__new__(Lane)
        lane.bank = 1
        lane.greeted = lane.tx_busy = lane.tx_sent = lane.rx_owned = False
        lane.rx = bytearray()
        lane.written = lane.received = 0
        lane.accept(b'H\x01\x01')
        with self.assertRaises(ValueError):
            lane.accept(b'A')
        lane.accept(b'R' + frame(0))
        with self.assertRaises(ValueError):
            lane.accept(b'R' + frame(1))
        self.assertEqual(1, lane.received)
        roles = [{'index': index, 'application': ['authenticated', 'bank0'],
                  'management': ['authenticated', 'bank1']} for index in (0, 1)]
        self.assertEqual(4, len(configuration({'roles': roles})))
        with self.assertRaises(ValueError):
            configuration({'roles': [roles[0], roles[0]]})


class NativeRelayTests(unittest.TestCase):
    """Finite full-duplex source/native-helper witness against packet-preserving local sockets."""

    def setUp(self) -> None:
        """Native cases require an explicit externally compiled helper, never an implicit build."""
        if HELPER is None:
            self.skipTest('no --helper supplied; native relay witness not executed')

    def test_packets_credit_and_descriptor_close(self) -> None:
        """Retain a second device packet until credit; preserve both extreme frame sizes."""
        with native() as (process, peer):
            self.assertEqual(b'H\x01\x01', receive(process.stdout))
            for value in (frame(0), frame(255, 19)):
                for byte in packet(b'T' + value):
                    process.stdin.write(bytes((byte,)))
                self.assertEqual(value, peer.recv(1028))
                self.assertEqual(b'A', receive(process.stdout))
            first, second = frame(11, 6), frame(32, 8)
            peer.send(first)
            self.assertEqual(b'R' + first, receive(process.stdout))
            peer.send(second)
            self.assertEqual([], select.select([process.stdout], [], [], 0.03)[0])
            process.stdin.write(packet(b'C'))
            self.assertEqual(b'R' + second, receive(process.stdout))
            process.stdin.write(packet(b'C') + packet(b'Q'))
            self.assertEqual(b'Z', receive(process.stdout))
            self.assertEqual(0, process.wait(timeout=2))
            with self.assertRaises(OSError):
                peer.send(b'closed')

    def test_host_fifo_adapter_and_native_helper(self) -> None:
        """Drive the actual host adapter against a local helper with independently credited directions."""
        assert HELPER is not None
        device, peer = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)
        peer.settimeout(2)
        with tempfile.TemporaryDirectory() as directory:
            lane = Lane(Path(directory), 0, 1,
                        [str(HELPER), '--test-fd', str(device.fileno()), '--bank', '1',
                         '--timeout-ms', '5000'], pass_fds=(device.fileno(),))
            device.close()
            try:
                def until(predicate: Callable[[], bool]) -> None:
                    """Bound local polling by wall time; every transition still uses real I/O."""
                    deadline = time.monotonic() + 2
                    while not predicate():
                        if time.monotonic() >= deadline:
                            raise TimeoutError('host FIFO adapter')
                        lane.pump()
                        time.sleep(0.001)
                until(lambda: lane.greeted)
                value = frame(255, 12)
                os.write(lane.tx_fd, value)
                until(lambda: bool(select.select([peer], [], [], 0)[0]))
                self.assertEqual(value, peer.recv(1028))
                until(lambda: lane.written == 1)
                peer.send(frame(32, 15))
                until(lambda: lane.received == 1 and not lane.rx_owned)
                self.assertEqual(frame(32, 15), os.read(lane.rx_fd, 1028))
                lane.stopping = True
                until(lambda: lane.closed)
                self.assertEqual(0, lane.process.wait(timeout=2))
            finally:
                lane.close()
                peer.close()

    def test_bad_length_and_eof_are_terminal(self) -> None:
        """No malformed frame is published, and EOF cannot turn a held RX into replay."""
        with native() as (process, peer):
            self.assertEqual(b'H\x01\x01', receive(process.stdout))
            process.stdin.write(struct.pack('>I', 1030) + b'T')
            self.assertNotEqual(0, process.wait(timeout=2))
            with self.assertRaises(OSError):
                peer.send(b'closed')
        with native() as (process, peer):
            self.assertEqual(b'H\x01\x01', receive(process.stdout))
            peer.send(frame(1))
            self.assertEqual(b'R' + frame(1), receive(process.stdout))
            process.stdin.close()
            self.assertNotEqual(0, process.wait(timeout=2))
            with self.assertRaises(OSError):
                peer.send(b'closed')


    def greet(self, process: subprocess.Popen) -> None:
        """Verify the actual native private protocol before each finite case."""
        self.assertEqual(b'H\x01\x01', receive(process.stdout))

    def credited_close(self, process: subprocess.Popen) -> None:
        """Z must wait for C and then terminate the helper successfully."""
        self.assertEqual([], select.select([process.stdout], [], [], .03)[0])
        process.stdin.write(packet(b'C'))
        self.assertEqual(b'Z', receive(process.stdout))
        self.assertEqual(0, process.wait(timeout=2))
        self.assertEqual(b'', process.stderr.read())

    def test_q_crosses_partial_r(self) -> None:
        """Force Q after only the R header is read; retained payload must survive until C."""
        with native() as (process, peer):
            self.greet(process)
            value = frame(11)
            peer.send(value)
            self.assertEqual(struct.pack('>I', len(value) + 1) + b'R', exact(process.stdout, 5))
            process.stdin.write(packet(b'Q'))
            self.assertEqual(value, exact(process.stdout, len(value)))
            self.credited_close(process)

    def test_q_crosses_unobserved_r_and_later_device_packet(self) -> None:
        """Q may cross an unread captured R; a subsequent uncaptured device packet is not drained."""
        with native() as (process, peer):
            self.greet(process)
            first = frame(11, 2)
            peer.send(first)
            self.assertTrue(select.select([process.stdout], [], [], 2)[0])
            peer.send(frame(11, 3))
            process.stdin.write(packet(b'Q'))
            self.assertEqual(b'R' + first, receive(process.stdout))
            self.credited_close(process)

    def test_q_precedes_same_poll_device_read(self) -> None:
        """Queue Q and native input while stopped; Q closes the FD before that poll's new read."""
        with native() as (process, peer):
            self.greet(process)
            os.kill(process.pid, signal.SIGSTOP)
            deadline = time.monotonic() + 2
            while True:
                pid, state = os.waitpid(process.pid, os.WUNTRACED | os.WNOHANG)
                if pid and os.WIFSTOPPED(state):
                    break
                if time.monotonic() >= deadline:
                    raise TimeoutError('helper stop acknowledgement')
                time.sleep(.001)
            process.stdin.write(packet(b'Q'))
            peer.send(frame(11, 4))
            os.kill(process.pid, signal.SIGCONT)
            self.assertEqual(b'Z', receive(process.stdout))
            self.assertEqual(0, process.wait(timeout=2))

    def test_post_q_t_and_repeated_q_are_terminal(self) -> None:
        """While Q retains R, new T or repeated Q fails with explicit protocol-stage diagnostics."""
        for invalid in (packet(b'T' + frame(11, 5)), packet(b'Q')):
            with self.subTest(command=invalid[4:5]), native() as (process, peer):
                self.greet(process)
                value = frame(11, 6)
                peer.send(value)
                self.assertEqual(b'R' + value, receive(process.stdout))
                process.stdin.write(packet(b'Q') + invalid)
                self.assertEqual(1, process.wait(timeout=2))
                diagnostic = process.stderr.read()
                self.assertIn(b'stage=input-after-close errno=0', diagnostic)
                self.assertIn(b'closing=1', diagnostic)
                self.assertIn(b'rx_size=52', diagnostic)

    def test_python_waits_for_observed_partial_r(self) -> None:
        """Actual Lane sees only four R-prefix bytes and must not publish Q yet."""
        assert HELPER is not None
        device, peer = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)
        with tempfile.TemporaryDirectory() as directory:
            lane = Lane(Path(directory), 0, 1,
                        [str(HELPER), '--test-fd', str(device.fileno()), '--bank', '1',
                         '--timeout-ms', '5000'], pass_fds=(device.fileno(),))
            device.close()
            reader = os.open(str(lane.prefix) + '_rx', os.O_RDONLY | os.O_NONBLOCK)
            try:
                deadline = time.monotonic() + 2
                while not lane.greeted:
                    if time.monotonic() >= deadline:
                        raise TimeoutError('lane hello')
                    lane.pump()
                    time.sleep(.001)
                value = frame(11, 7)
                peer.send(value)
                self.assertTrue(select.select([lane.process.stdout], [], [], 2)[0])
                lane.stopping = True
                lane.pump()
                self.assertEqual(4, len(lane.network))
                self.assertFalse(lane.quit_sent)
                deadline = time.monotonic() + 2
                while not lane.closed:
                    if time.monotonic() >= deadline:
                        raise TimeoutError('lane close')
                    lane.pump()
                    time.sleep(.001)
                self.assertEqual(value, os.read(reader, 1028))
                self.assertEqual(0, lane.process.wait(timeout=2))
            finally:
                os.close(reader)
                lane.close()
                peer.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--helper', type=lambda value: Path(value).resolve(strict=True))
    args, rest = parser.parse_known_args()
    HELPER = args.helper
    unittest.main(argv=[__file__, *rest])
