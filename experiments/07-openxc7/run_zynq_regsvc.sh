#!/usr/bin/env bash
# Compile and route two services with independent application/debug DMA banks.
set -euo pipefail
experiment_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$experiment_root/openxc7_common.sh"
prepare_zynq7030
rtl=${1:-"$build_root/routed-dma/rtl"}
stage="$build_root/zynq-regsvc"
mkdir -p "$stage"
rm -f "$stage/manifest.json"
python3 - "$experiment_root" "$rtl" "$stage" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from build_regsvc_rtl import sources
root, rtl, stage = map(Path, sys.argv[1:])
inputs = sources(rtl) + [root / name for name in (
    'zynq_ps_probe.v', 'dma/zynq_dma_mailbox.v', 'dma/zynq_dma_pair.v',
    'dma/zynq_regsvc_core.sv', 'dma/zynq_dma_top.v')]
if any('"' in str(p) or '\n' in str(p) for p in inputs):
    raise ValueError('unsupported source path')
script = 'read_verilog -sv ' + ' '.join('"'+str(p)+'"' for p in inputs) + ';\n'
script += 'chparam -set ROUTED 1 zynq_dma_top;\n'
script += 'synth_xilinx -flatten -abc9 -arch xc7 -top zynq_dma_top; check -assert;\n'
script += 'select -assert-count 1 t:PS7; select -assert-count 1 t:BUFG;\n'
script += 'select -assert-count 4 t:RAMB18E1; select -assert-count 6 t:RAMB36E1; select -clear;\n'
script += f'write_json "{stage / "netlist.json"}";\n'
script += f'tee -o "{stage / "stats.json"}" stat -json;\n'
(stage / 'synth.ys').write_text(script)
PY
"$oss_cad_suite/bin/yosys" -Q -q -l "$stage/yosys.log" -s "$stage/synth.ys"
build_bitstream zynq-regsvc "$stage/netlist.json" xc7z030sbg485-1 \
    "$experiment_root/zynq_ps_probe.xdc" strict 25
verify_bitstream xc7z030sbg485-1 "$stage/xc7z030sbg485-1"
python3 - "$experiment_root" "$rtl" "$stage" <<'PYTHON'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from dma.routed_image import physical_manifest
physical_manifest(Path(sys.argv[2]), Path(sys.argv[3]))
PYTHON
