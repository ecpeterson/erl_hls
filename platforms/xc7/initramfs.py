"""Encode small Linux initramfs overlays for QEMU and board preparation."""


def cpio(files: list[tuple[str, bytes, int]]) -> bytes:
    """Encode a small newc archive for a disposable initramfs overlay."""
    output = bytearray()
    for index, (name, data, mode) in enumerate(files + [("TRAILER!!!", b"", 0)]):
        encoded = name.encode() + b"\0"
        fields = [index + 1, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded), 0]
        output.extend(b"070701" + b"".join(f"{field:08x}".encode() for field in fields))
        output.extend(encoded)
        output.extend(b"\0" * (-len(output) % 4))
        output.extend(data)
        output.extend(b"\0" * (-len(output) % 4))
    return bytes(output)
