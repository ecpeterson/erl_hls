"""Prepare the optional DMA-to-packet test fixture from pinned MAC/PCS sources."""

import subprocess
import shutil
import sys
import tempfile
from pathlib import Path

from ethernet.prepare import environment

ROOT = Path(__file__).resolve().parent.parent


def sources(output: Path, yosys: Path | None = None) -> list[Path]:
    """Generate accelerated-negotiation RTL and return its complete source closure."""
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as temporary:
        env = environment(output / "sources", Path(temporary))
        subprocess.run([sys.executable, "-S", str(ROOT / "ethernet/generate.py"),
                        str(output / "generated"), "--simulation"], env=env, check=True, timeout=30)
    # Lower the generated processes as in the packet regression. Direct Icarus
    # evaluation of generated combinational temporaries can churn in delta cycles.
    # The decoder ROM is embedded, making the compiled fixture self-contained.
    tool = yosys or Path(shutil.which("yosys") or "yosys")
    lowered = output / "packet-core.v"
    commands = ('read_verilog liteeth_packet_core.v; hierarchy -top liteeth_packet_core; '
                'proc; opt; check -assert; scc -expect 0; '
                f'write_verilog -noattr "{lowered}"')
    subprocess.run([str(tool), "-Q", "-q", "-l", str(output / "lower.log"), "-p", commands],
                   cwd=output / "generated", check=True, timeout=30)
    return [lowered, ROOT / "zynq_ps_probe.v",
            *[ROOT / "ethernet" / (name + ".v") for name in
              ("frame_store", "packet_endpoint", "cdc_slot", "dma_packets")]]
