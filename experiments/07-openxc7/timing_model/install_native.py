#!/usr/bin/env python3
"""Install the measured BRAM endpoint experiment in a dedicated nextpnr source tree."""
import argparse
from pathlib import Path
import shutil


def install(root: Path) -> None:
    """Add mode-gated BRAM arcs while leaving other primitive models unchanged."""
    path = root / 'xilinx/arch.cc'
    source = path.read_text()
    marker = 'TimingPortClass Arch::getPortTimingClass(const CellInfo *cell, IdString port, int &clockInfoCount) const\n{\n'
    if '#include "xc7_bram_model.inc"' not in source:
        if source.count(marker) != 1:
            raise ValueError('unexpected nextpnr timing interface')
        source = source.replace(marker, '#include "xc7_bram_model.inc"\n\n' + marker +
            '    if (xc7 && xc7IsBram(this, cell)) {\n'
            '        TimingClockingInfo info;\n'
            '        auto kind = xc7BramTiming(this, cell, port, info);\n'
            '        clockInfoCount = (kind == TMG_REGISTER_INPUT || kind == TMG_REGISTER_OUTPUT) ? 1 : 0;\n'
            '        return kind;\n    }\n')
        marker = 'TimingClockingInfo Arch::getPortClockingInfo(const CellInfo *cell, IdString port, int index) const\n{\n    TimingClockingInfo info;\n'
        if source.count(marker) != 1:
            raise ValueError('unexpected nextpnr clocking interface')
        source = source.replace(marker, marker +
            '    if (xc7 && xc7IsBram(this, cell)) {\n'
            '        xc7BramTiming(this, cell, port, info);\n'
            '        return info;\n    }\n')
        path.write_text(source)
    shutil.copyfile(Path(__file__).with_name('bram_model.inc'), root / 'xilinx/xc7_bram_model.inc')


def main() -> None:
    """Require an explicit, disposable checkout; keep the earlier binary for comparison."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('nextpnr', type=Path)
    install(parser.parse_args().nextpnr.resolve())


if __name__ == '__main__':
    main()
