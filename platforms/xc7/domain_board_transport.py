#!/usr/bin/env python3
"""Expose four board DMA lanes as bounded local FIFOs over caller-selected authenticated commands.

Each command must launch domain_board_relay through an authenticated channel (for
example ssh -T); this tool opens no listening socket and never reconnects. The
board helper needs no Python. Only host frames traverse these pipes; endpoint
DATA/ACK crossings remain on the FPGA Ethernet path. One packet is retained per
lane/direction; inherited FIFO/SSH/socket/broker buffers are additional bounded
transport storage, not native acceptance or retirement evidence.
"""
import argparse
import hashlib
from collections import deque
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import time
from typing import Any

FRAME_MAX = 1028
MESSAGE_MAX = FRAME_MAX + 1


def frame_valid(frame: bytes | bytearray) -> bool:
    """Accept exactly one full native little-endian routed frame."""
    return 8 <= len(frame) <= FRAME_MAX and len(frame) == 8 + 4 * frame[4]


def packet(body: bytes) -> bytes:
    """Prefix one bounded private relay message with its big-endian byte count."""
    if not 1 <= len(body) <= MESSAGE_MAX:
        raise ValueError('relay message length')
    return struct.pack('>I', len(body)) + body


def pop_packet(buffer: bytearray) -> bytes | None:
    """Remove one complete bounded message; malformed lengths fail before allocation."""
    if len(buffer) < 4:
        return None
    length = struct.unpack('>I', buffer[:4])[0]
    if not 1 <= length <= MESSAGE_MAX:
        raise ValueError('relay message length')
    if len(buffer) < 4 + length:
        return None
    body = bytes(buffer[4:4 + length])
    del buffer[:4 + length]
    return body


class Lane:
    """Own one helper process and one fixed packet in each direction, with explicit credit."""

    def __init__(self, stage: Path, role: int, bank: int, command: list[str], *, pass_fds: tuple[int, ...] = ()) -> None:
        """Create fresh FIFOs and launch once; pass_fds is only for local packet-socket fixtures."""
        name = f'board{role}_' + ('application' if bank == 0 else 'management')
        self.prefix = stage / name
        self.role, self.bank = role, bank
        self.tx_fd = self.rx_fd = -1
        self.process = None
        self.stderr = None
        self.tx = bytearray()
        self.rx = bytearray()
        self.network = bytearray()
        self.output = bytearray()
        self.controls: deque[bytes] = deque()
        self.tx_busy = self.tx_sent = self.rx_owned = False
        self.greeted = self.stopping = self.quit_sent = self.closed = False
        self.output_kind = b''
        self.written = self.received = 0
        try:
            for suffix in ('_tx', '_rx'):
                os.mkfifo(str(self.prefix) + suffix, 0o600)
            self.tx_fd = os.open(str(self.prefix) + '_tx', os.O_RDWR | os.O_NONBLOCK)
            self.rx_fd = os.open(str(self.prefix) + '_rx', os.O_RDWR | os.O_NONBLOCK)
            self.stderr = (stage / (name + '-relay.log')).open('xb')
            self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=self.stderr, bufsize=0, pass_fds=pass_fds)
            assert self.process.stdin is not None and self.process.stdout is not None
            os.set_blocking(self.process.stdin.fileno(), False)
            os.set_blocking(self.process.stdout.fileno(), False)
        except BaseException:
            self.close()
            raise

    def accept(self, body: bytes) -> None:
        """Validate the private credit protocol; any duplicate/unexpected message is terminal."""
        if not self.greeted:
            if body != bytes((ord('H'), 1, self.bank)):
                raise ValueError('relay version/bank handshake')
            self.greeted = True
        elif body == b'A' and self.tx_busy and self.tx_sent:
            self.tx_busy = self.tx_sent = False
            self.written += 1
        elif body[:1] == b'R' and not self.rx_owned and frame_valid(body[1:]):
            self.rx_owned = True
            self.rx = bytearray(body[1:])
            self.received += 1
        elif body == b'Z' and self.quit_sent and not self.tx_busy and not self.rx_owned:
            self.closed = True
            for fd in (self.tx_fd, self.rx_fd):
                if fd >= 0:
                    os.close(fd)
            self.tx_fd = self.rx_fd = -1
        else:
            raise ValueError('unexpected relay message')

    def pump(self) -> None:
        """Perform only currently ready nonblocking I/O, without accumulating extra packets."""
        assert self.process is not None and self.process.stdin is not None and self.process.stdout is not None
        if self.closed:
            return
        read_fd, write_fd = self.process.stdout.fileno(), self.process.stdin.fileno()
        readable, writable, _ = select.select([read_fd, self.tx_fd], [write_fd, self.rx_fd], [], 0)
        if read_fd in readable:
            # Read only the next message, retaining at most one incomplete frame.
            needed = 4 - len(self.network) if len(self.network) < 4 else (
                4 + struct.unpack('>I', self.network[:4])[0] - len(self.network))
            if not 0 < needed <= MESSAGE_MAX:
                raise ValueError('relay receive bound')
            chunk = os.read(read_fd, needed)
            if not chunk:
                raise RuntimeError('relay EOF')
            self.network.extend(chunk)
            body = pop_packet(self.network)
            if body is not None:
                self.accept(body)
        if self.rx and self.rx_fd in writable:
            count = os.write(self.rx_fd, self.rx)
            del self.rx[:count]
            if not self.rx:
                self.controls.append(b'C')
        if self.greeted and not self.tx_busy and not self.quit_sent and self.tx_fd in readable:
            needed = 8 - len(self.tx) if len(self.tx) < 8 else 8 + 4 * self.tx[4] - len(self.tx)
            if needed:
                self.tx.extend(os.read(self.tx_fd, needed))
        if self.tx and len(self.tx) >= 8 and len(self.tx) == 8 + 4 * self.tx[4] and not self.output:
            if not frame_valid(self.tx):
                raise ValueError('local routed frame')
            self.output_kind = b'T'
            self.output = bytearray(packet(b'T' + self.tx))
            self.tx.clear()
            self.tx_busy = True
        if not self.output and self.controls:
            self.output_kind = self.controls.popleft()
            self.output = bytearray(packet(self.output_kind))
        # A partial R prefix/payload is already observed ownership; finish it before Q.
        # The native helper also tolerates an unobserved captured R crossing Q.
        if (self.stopping and self.greeted and not self.quit_sent and not self.tx_busy and
                not self.tx and not self.rx_owned and not self.network and not self.output and not self.controls and
                self.tx_fd not in readable):
            self.output_kind = b'Q'
            self.output = bytearray(packet(b'Q'))
            self.quit_sent = True
        if self.output and write_fd in writable:
            count = os.write(write_fd, self.output)
            del self.output[:count]
            if not self.output:
                if self.output_kind == b'T':
                    self.tx_sent = True
                elif self.output_kind == b'C':
                    self.rx_owned = False
                self.output_kind = b''
        if len(self.controls) > 1:
            raise ValueError('relay credit bound')

    def close(self) -> None:
        """Close local FIFOs and terminate this attachment; never reopen or replay it."""
        for fd in (self.tx_fd, self.rx_fd):
            if fd >= 0:
                os.close(fd)
        self.tx_fd = self.rx_fd = -1
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=6)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=2)
            for pipe in (self.process.stdin, self.process.stdout):
                if pipe is not None:
                    pipe.close()
        if self.stderr is not None:
            self.stderr.close()


def configuration(value: Any) -> list[tuple[int, int, list[str]]]:
    """Require two explicit roles and four exact command vectors; no shell interpolation."""
    if not isinstance(value, dict) or set(value) != {'roles'}:
        raise ValueError('transport configuration')
    result = []
    for role in value['roles']:
        if not isinstance(role, dict) or set(role) != {'index', 'application', 'management'}:
            raise ValueError('role configuration')
        index = role['index']
        if type(index) is not int or index not in (0, 1):
            raise ValueError('role index')
        for bank, key in enumerate(('application', 'management')):
            command = role[key]
            if not isinstance(command, list) or not command or not all(isinstance(x, str) and x for x in command):
                raise ValueError('explicit authenticated command vector required')
            result.append((index, bank, command))
    if sorted((role, bank) for role, bank, _ in result) != [(0, 0), (0, 1), (1, 0), (1, 1)]:
        raise ValueError('two distinct roles required')
    return result



def validate_result(stage: Path, bundle: Path, native: Path, namespace: int) -> dict[str, Any]:
    """Reuse the existing native-oracle comparison, checking actual replacement identities only."""
    tools = Path(__file__).resolve().parents[2] / 'apps/hls_phi/tools'
    sys.path.insert(0, str(tools))
    from protocol_repetition_result import compare
    metadata = json.loads((bundle / 'fixture.json').read_text())
    expected = json.loads(native.read_text())
    actual = json.loads((stage / 'result.json').read_text())
    assert actual['passed'] and actual['descriptors_closed'] and actual['old_pids_terminal']
    assert actual['endpoint_namespace'] == namespace
    assert actual['held_output_frontier_witness'] is False
    first, second = actual['incarnations']
    recovery = actual['recovery']
    assert recovery['delivery'] == 'natural' and recovery['one_for_all']
    assert recovery['held_output_frontier_witness'] is False and recovery['source_failure_code'] > 0
    assert recovery['old_endpoints'] == 3 * metadata['width']
    channels = {row['index']: row for row in metadata['channels']}
    for incarnation in (first, second):
        compare({**incarnation, 'descriptors_closed': actual['descriptors_closed']}, expected, metadata['width'])
        bindings = {row['index']: row for row in incarnation['endpoint_bindings']}
        assert len(bindings) == len(incarnation['endpoint_bindings']) and bindings.keys() == channels.keys()
        for index, binding in bindings.items():
            channel = channels[index]
            assert binding['namespace'] == namespace and binding['generation'] > 0
            assert binding['source_incarnation'] == incarnation['domain_incarnations'][channel['source_domain']]
            assert binding['destination_incarnation'] == incarnation['domain_incarnations'][channel['destination_domain']]
    assert all(b > a for a, b in zip(first['domain_incarnations'], second['domain_incarnations']))
    previous = {row['index']: row for row in first['endpoint_bindings']}
    assert all(row['generation'] > previous[row['index']]['generation'] for row in second['endpoint_bindings'])
    return {'passed': True, 'evidence': 'Finite attached host application witness',
            'result': actual, 'native_sha256': hashlib.sha256(native.read_bytes()).hexdigest(),
            'fixture_sha256': hashlib.sha256((bundle / 'fixture.json').read_bytes()).hexdigest(),
            'limits': 'Natural delivery only; no deliberately held-output frontier, injected physical loss, '
                      'CDC timing, transparent reconnect, DMA cancellation or complete-board qualification claim.'}


def main() -> None:
    """Run one finite attachment; finished requests descriptor closure, never native drain."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('config', type=Path)
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--native', type=Path)
    parser.add_argument('--namespace', type=int)
    args = parser.parse_args()
    if not 0 < args.timeout <= 3600:
        raise ValueError('finite timeout required')
    qualification = (args.bundle, args.native, args.namespace)
    if any(value is not None for value in qualification):
        if not all(value is not None for value in qualification) or not 0 < args.namespace < 2**64:
            raise ValueError('--bundle, --native and nonzero --namespace must be supplied together')
    commands = configuration(json.loads(args.config.read_text()))
    args.stage.mkdir(parents=True, exist_ok=True)
    if any((args.stage / name).exists() for name in ('finished', 'transport.ready', 'transport-result.json')):
        raise ValueError('fresh transport stage required')
    lanes: list[Lane] = []
    deadline = time.monotonic() + args.timeout
    ready = False
    try:
        for role, bank, command in commands:
            lanes.append(Lane(args.stage, role, bank, command))
        while not all(lane.closed for lane in lanes):
            if time.monotonic() >= deadline:
                raise TimeoutError('board transport deadline')
            stopping = (args.stage / 'finished').exists()
            for lane in lanes:
                lane.stopping = stopping
                lane.pump()
            if not ready and all(lane.greeted for lane in lanes):
                (args.stage / 'transport.ready').write_text('1\n')
                ready = True
            time.sleep(0.001)
        for lane in lanes:
            assert lane.process is not None
            if lane.process.wait(timeout=6) != 0:
                raise RuntimeError('relay failed after close acknowledgement')
        result = {'evidence': 'Observed transport descriptor closure', 'native_dma_drained': False,
                  'native_dma_cancelled': False, 'reconnects': 0,
                  'relay_packet_slots_per_lane': {'tx': 1, 'rx': 1, 'maximum_bytes': FRAME_MAX},
                  'inherited_buffers': 'FIFO, SSH/socket and ordinary broker buffers are additional.',
                  'lanes': [{'role': x.role, 'bank': x.bank, 'written': x.written,
                             'received': x.received, 'descriptor_closed': x.closed} for x in lanes]}
        (args.stage / 'transport-result.json').write_text(json.dumps(result, indent=2) + '\n')
        if args.native is not None:
            result_deadline = time.monotonic() + 5
            while not (args.stage / 'result.json').exists():
                if time.monotonic() >= result_deadline:
                    raise TimeoutError('application result after local descriptor closure')
                time.sleep(0.01)
            evidence = validate_result(args.stage, args.bundle, args.native, args.namespace)
            (args.stage / 'board-result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    finally:
        for lane in lanes:
            lane.close()


if __name__ == '__main__':
    main()
