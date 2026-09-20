"""Build and supervise the Icarus side of the local PS/PL co-simulation."""

import contextlib
import os
import subprocess
import time
from collections.abc import Iterator
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def compile_rtl(stage: Path, regsvc_sources: list[Path] | None = None) -> Path:
    """Build the loopback or supplied routed application, preserving diagnostics."""
    stage.mkdir(parents=True, exist_ok=True)
    with (stage / "compile.log").open("w") as output:
        subprocess.run(["iverilog-vpi", "--name=icarus_bridge", "-Wall", "-Wextra", "-Werror",
                        f"-I{ROOT / 'cosim'}", str(ROOT / "cosim/icarus_bridge.c")],
                       cwd=stage, stdout=output, stderr=subprocess.STDOUT, check=True)
        extra = ([str(ROOT / "dma/zynq_dma_pair.v"),
                  str(ROOT / "dma/zynq_regsvc_core.sv"), *map(str, regsvc_sources)]
                 if regsvc_sources else [])
        flags = ["-DREGSVC_COSIM"] if regsvc_sources else []
        subprocess.run(["iverilog", "-g2012", *flags, "-L", str(stage), "-m", "icarus_bridge",
                        "-s", "mailbox_cosim_tb", "-o", str(stage / "mailbox.vvp"),
                        str(ROOT / "cosim/mailbox_tb.sv"), str(ROOT / "dma/zynq_dma_mailbox.v"), *extra],
                       stdout=output, stderr=subprocess.STDOUT, check=True)
    return stage / "mailbox.vvp"


@contextlib.contextmanager
def rtl_server(stage: Path, socket: Path, log: Path) -> Iterator[subprocess.Popen]:
    """Start one isolated RTL peer, wait for its socket, and always reap it on exit."""
    env = dict(os.environ, HLS_COSIM_SOCKET=str(socket))
    with log.open("w") as output:
        process = subprocess.Popen(["vvp", "-M", str(stage), str(stage / "mailbox.vvp")],
                                   env=env, stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 5
            while not socket.exists():
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError(f"RTL peer did not start; see {log}")
                time.sleep(0.01)
            yield process
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
