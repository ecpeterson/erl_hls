"""Controlled FIFO peer for host backpressure tests; no simulator or RTL access."""

import os
import fcntl
import select
import struct
import sys
import termios


def open_fifo(path):
    return os.open(path, os.O_RDWR | os.O_NONBLOCK)


def read_exact(fd, count):
    result = bytearray()
    while len(result) < count:
        if not select.select([fd], [], [], 3)[0]:
            raise TimeoutError(f"expected {count} bytes, received {len(result)}")
        result.extend(os.read(fd, count - len(result)))
    return result


rx = open_fifo(sys.argv[2])
tx = None if len(sys.argv) > 3 else open_fifo(sys.argv[1])
print("ready", flush=True)
for line in sys.stdin:
    command, *args = line.split()
    if command == "open":
        tx = open_fifo(sys.argv[1])
        print("ok", flush=True)
    elif command == "fill":
        count = 0
        try:
            while True:
                count += os.write(tx, b"\x00" * 4096)
        except BlockingIOError:
            print(count, flush=True)
    elif command == "discard":
        read_exact(tx, int(args[0]))
        print("ok", flush=True)
    elif command == "take":
        print(read_exact(tx, int(args[0])).hex(), flush=True)
    elif command == "rx_pending":
        pending = fcntl.ioctl(rx, termios.FIONREAD, struct.pack("I", 0))
        print(struct.unpack("I", pending)[0], flush=True)
    elif command == "drain":
        result = bytearray()
        try:
            while True:
                result.extend(os.read(tx, 4096))
        except BlockingIOError:
            print(result.hex(), flush=True)
    elif command == "emit":
        data = bytes.fromhex(args[0])
        while data:
            if not select.select([], [rx], [], 3)[1]:
                raise TimeoutError("receive pipe stayed full")
            data = data[os.write(rx, data):]
        print("ok", flush=True)
