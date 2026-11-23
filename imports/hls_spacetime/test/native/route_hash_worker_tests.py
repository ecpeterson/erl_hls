"""Focused subprocess and Tcl pipe fixtures; no Vivado/native job is used."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[2] / "priv/tools"
WORKER = HERE / "route_hash_worker.py"
EXTENSION = HERE / "route_hash_worker.tcl"
spec = importlib.util.spec_from_file_location("route_hash_worker", WORKER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def request(number, path):
    return f"{number}\t{str(path).encode('utf-8').hex()}\n".encode()


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.output = self.root / "result/routes"
        self.output.mkdir(parents=True)
        self.input = self.root / "frozen.txt"
        self.input.write_bytes(b"input")
        self.checkpoint = self.root / "routed.dcp"
        self.checkpoint.write_bytes(b"checkpoint")
        self.file = self.output / "value [literal] $name.dat"
        self.file.write_bytes(b"first")
        self.plan = self.root / "plan.json"
        self.plan.write_text(json.dumps({"inputs": {"frozen.txt": hashlib.sha256(b"input").hexdigest(),
                                                      str(self.checkpoint): hashlib.sha256(b"checkpoint").hexdigest()}}))
        self.command = [sys.executable, str(WORKER), "--plan", str(self.plan), "--output-root", str(self.output)]

    def tearDown(self):
        self.temp.cleanup()

    def worker(self, data):
        return subprocess.run(self.command, input=data, capture_output=True, timeout=10)

    def rejected(self, data):
        result = self.worker(data)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"route hash worker failed:", result.stderr)

    def test_input_output_and_clean_eof(self):
        result = self.worker(request(1, self.input) + request(2, self.file))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"1\t" + hashlib.sha256(b"input").hexdigest().encode() + b"\n2\t" +
                         hashlib.sha256(b"first").hexdigest().encode() + b"\n")

    def test_repeated_hash_rereads_changed_file(self):
        process = subprocess.Popen(self.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            process.stdin.write(request(1, self.file)); process.stdin.flush()
            first = process.stdout.readline()
            self.file.write_bytes(b"changed")
            process.stdin.write(request(2, self.file)); process.stdin.flush()
            second = process.stdout.readline()
            process.stdin.close()
            self.assertEqual(process.wait(timeout=10), 0, process.stderr.read())
            self.assertEqual(first, b"1\t" + hashlib.sha256(b"first").hexdigest().encode() + b"\n")
            self.assertEqual(second, b"2\t" + hashlib.sha256(b"changed").hexdigest().encode() + b"\n")
        finally:
            if process.poll() is None:
                process.kill(); process.wait()
            process.stdout.close(); process.stderr.close()

    def test_forbidden_path(self):
        forbidden = self.root / "unlisted.txt"
        forbidden.write_bytes(b"not allowed")
        self.rejected(request(1, forbidden))

    def test_malformed_requests(self):
        for data in (b"1\tnot-hex\n", b"0\t00\n", b"1\tc3\n", b"1\t00\n", b"1\t2f\textra\n",
                     request(2, self.file), request(1, self.file).rstrip(b"\n")):
            with self.subTest(data=data[:30]):
                self.rejected(data)

    def test_oversized_request(self):
        self.rejected(b"x" * (module.MAX_LINE + 1) + b"\n")

    def test_missing_file_error(self):
        self.rejected(request(1, self.output / "missing.json"))

    def test_symlink_alias_rejected(self):
        link = self.output / "link.json"
        link.symlink_to(self.input)
        self.rejected(request(1, link))

    def test_distinct_dcp_and_regular_file_caps(self):
        regular, dcp = module.MAX_FILE, module.MAX_DCP
        try:
            module.MAX_FILE, module.MAX_DCP = 4, 16
            worker = module.Worker(str(self.plan), str(self.output))
            self.assertEqual(worker.hash(str(self.checkpoint)), hashlib.sha256(b"checkpoint").hexdigest())
            with self.assertRaisesRegex(ValueError, "size/type"):
                worker.hash(str(self.file))
        finally:
            module.MAX_FILE, module.MAX_DCP = regular, dcp

    def tcl(self, body, worker=WORKER, env=None):
        script = self.root / "fixture.tcl"
        script.write_text("lassign $argv extension worker python plan output target\nsource $extension\n" + body)
        return subprocess.run(["/usr/bin/tclsh", str(script), str(EXTENSION), str(worker), sys.executable,
                               str(self.plan), str(self.output), str(self.file)], capture_output=True, text=True, timeout=10, env=env)

    def test_tcl_pipe_changed_file_and_clean_close(self):
        result = self.tcl("""
::hls_spacetime_routes::start_hash_worker [list $python $worker --plan $plan --output-root $output]
set first [::hls_spacetime_routes::hash $target]
set stream [open $target w]; puts -nonewline $stream changed; close $stream
set second [::hls_spacetime_routes::hash $target]
::hls_spacetime_routes::stop_hash_worker
puts "$first $second"
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), hashlib.sha256(b"first").hexdigest() + " " + hashlib.sha256(b"changed").hexdigest())

    def test_tcl_worker_error_has_no_fallback(self):
        result = self.tcl("""
::hls_spacetime_routes::start_hash_worker [list $python $worker --plan $plan --output-root $output]
if {![catch {::hls_spacetime_routes::hash [file join $output missing]} reason]} {error "accepted missing file"}
if {![catch {::hls_spacetime_routes::stop_hash_worker} close_error]} {error "lost worker failure status"}
puts "failed closed"
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "failed closed")

    def test_tcl_rejects_eof_and_bad_reply(self):
        fake = self.root / "fake_worker.py"
        for reply in (b"", b"999\t" + b"a" * 64 + b"\n", b"1\tbad\n", b"1\t" + b"a" * 200 + b"\n"):
            with self.subTest(reply=reply[:20]):
                fake.write_text("import sys\nsys.stdin.buffer.readline()\nsys.stdout.buffer.write(" + repr(reply) + ")\nsys.stdout.buffer.flush()\n")
                result = self.tcl("""
::hls_spacetime_routes::start_hash_worker [list $python $worker]
if {![catch {::hls_spacetime_routes::hash $target} reason]} {error "accepted malformed reply"}
catch {::hls_spacetime_routes::stop_hash_worker}
puts "failed closed"
""", fake)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "failed closed")

    def test_tcl_startup_stderr_survives_caught_close(self):
        fake = self.root / "startup_failure.py"
        fake.write_text("import sys\nsys.stderr.write('fixture startup diagnostic\\n')\nsys.stderr.flush()\nsys.exit(2)\n")
        result = self.tcl("""
::hls_spacetime_routes::start_hash_worker [list $python $worker]
if {![catch {::hls_spacetime_routes::hash $target} reason]} {error "accepted failed worker"}
catch {::hls_spacetime_routes::stop_hash_worker}
puts "failed closed"
""", fake)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "failed closed")
        self.assertIn("fixture startup diagnostic", result.stderr)

    def test_tcl_isolated_python_ignores_vendor_home(self):
        environment = {**os.environ, "PYTHONHOME": str(self.root / "incompatible-vendor-python")}
        result = self.tcl("""
::hls_spacetime_routes::start_hash_worker [list $python -I $worker --plan $plan --output-root $output]
puts [::hls_spacetime_routes::hash $target]
::hls_spacetime_routes::stop_hash_worker
""", env=environment)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), hashlib.sha256(b"first").hexdigest())

    def test_tcl_unstarted_fallback_unchanged(self):
        expected = hashlib.sha256(b"fallback").hexdigest()
        result = self.tcl("""
rename exec original_exec
proc exec {args} {
    if {[lrange $args 0 1] ne {sha256sum --}} {error "unexpected fallback"}
    return """ + "{" + expected + "  fixture}" + """
}
puts [::hls_spacetime_routes::hash $target]
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), expected)


if __name__ == "__main__":
    unittest.main()
