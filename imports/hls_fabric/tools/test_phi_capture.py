"""Exercise streaming capture publication and failure cleanup with an actual FIFO writer."""
import gzip
import json
from pathlib import Path
import tempfile
import unittest

from phi_capture import compressed_capture, prune_simulation
from test_actor_rtl import digest
from phi_cycle_trace import capture_path


class CaptureTests(unittest.TestCase):
    """Only a completed producer and successful compressor may publish a recording."""

    def test_bytes(self) -> None:
        """Retain exact repeated observations while avoiding a raw intermediate file."""
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory)
            path = stage/'cycle-trace.csv'
            data = b'device,cycle,value\n' + b'0,10,beef\n'*100000
            with compressed_capture(path):
                self.assertFalse(path.is_file())
                with path.open('wb') as producer:
                    producer.write(data)
            self.assertFalse(path.exists())
            self.assertEqual(gzip.decompress(capture_path(stage).read_bytes()), data)

    def test_failure(self) -> None:
        """Close the pipe and leave failed output unpublished when simulation aborts."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'cycle-trace.csv'
            with self.assertRaisesRegex(RuntimeError, 'producer failed'):
                with compressed_capture(path):
                    with path.open('wb') as producer:
                        producer.write(b'partial')
                    raise RuntimeError('producer failed')
            self.assertFalse(path.exists())
            self.assertFalse(path.with_suffix('.csv.gz').exists())
            self.assertEqual(gzip.decompress(path.with_suffix('.csv.gz.partial').read_bytes()), b'partial')

    def test_existing(self) -> None:
        """Reject an existing recording without changing its bytes."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'cycle-trace.csv'
            path.write_bytes(b'original')
            with self.assertRaises(FileExistsError):
                with compressed_capture(path):
                    self.fail('existing recording accepted')
            self.assertEqual(path.read_bytes(), b'original')

    def test_pruning(self) -> None:
        """Remove only checked local intermediates, leaving the reusable build and recording."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage = root/'capture'
            observer = stage/'message-rtl/device0/instrumented.v'
            observer.parent.mkdir(parents=True)
            build = root/'device0.v'
            executable = stage/'profile.vvp'
            recording = stage/'cycle-trace.csv.gz'
            for path in (observer, build, executable, recording):
                path.write_bytes(b'checked')
            inputs = {'vvp_sha256': digest(executable),
                      'hardware_sources': {str(p): digest(p) for p in (observer, build)}}
            (stage/'profile-inputs.json').write_text(json.dumps(inputs))
            observer.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'intermediate changed'):
                prune_simulation(stage)
            self.assertTrue(executable.exists())
            observer.write_bytes(b'checked')
            prune_simulation(stage)
            self.assertFalse(executable.exists())
            self.assertFalse(observer.exists())
            self.assertEqual(build.read_bytes(), b'checked')
            self.assertEqual(recording.read_bytes(), b'checked')
            self.assertEqual(len(json.loads((stage/'discarded-intermediates.json').read_text())), 2)


if __name__ == '__main__':
    unittest.main()
