#!/usr/bin/env python3
"""Check that toolchain installation rejects corruption and preserves other builds."""
import gzip
from pathlib import Path
import tempfile
import unittest

from install import digest, replace


class InstallTest(unittest.TestCase):
    """Exercise installation boundaries using inert binary payloads."""

    def test_integrity_and_atomic_replacement(self) -> None:
        """Corrupt downloads and unknown installed tools cannot change the destination."""
        old, new = b'upstream compiler', b'patched compiler'
        zipped = gzip.compress(new, mtime=0)
        pin = dict(upstream_codegen_sha256=digest(old), codegen_sha256=digest(new),
                   asset_sha256=digest(zipped))
        with tempfile.TemporaryDirectory() as directory:
            destination, asset = Path(directory) / 'codegen_main', Path(directory) / 'asset.gz'
            destination.write_bytes(old)
            asset.write_bytes(zipped + b'corrupt')
            with self.assertRaisesRegex(ValueError, 'archive digest'):
                replace(destination, asset, pin)
            self.assertEqual(destination.read_bytes(), old)
            asset.write_bytes(gzip.compress(b'wrong binary', mtime=0))
            corrupt_pin = pin | {'asset_sha256': digest(asset.read_bytes())}
            with self.assertRaisesRegex(ValueError, 'binary digest'):
                replace(destination, asset, corrupt_pin)
            self.assertEqual(destination.read_bytes(), old)
            asset.write_bytes(zipped)
            destination.write_bytes(b'another local build')
            with self.assertRaisesRegex(ValueError, 'unexpected codegen'):
                replace(destination, asset, pin)
            self.assertEqual(destination.read_bytes(), b'another local build')
            destination.write_bytes(old)
            replace(destination, asset, pin)
            self.assertEqual(destination.read_bytes(), new)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o755)
            asset.unlink()
            replace(destination, asset, pin)
            self.assertEqual(destination.read_bytes(), new)
            self.assertEqual(list(Path(directory).iterdir()), [destination])


if __name__ == '__main__':
    unittest.main()
