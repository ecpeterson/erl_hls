#!/usr/bin/env python3
"""Install verified dependencies and measured xc7z030-1 DSP cascade delays."""
import argparse
from pathlib import Path
import shutil


def install(root: Path, diagnostic_switch: bool = False) -> None:
    """Install selected-bus dependencies and four measured forwarding delays.

    Build a separate binary afterward. Registered DSP timing and non-cascade
    output dependencies remain outside this narrow correction.
    """
    path = root / 'xilinx/arch.cc'
    source = path.read_text()
    declaration = 'bool Arch::getCellDelay(const CellInfo *cell, IdString fromPort, IdString toPort, DelayInfo &delay) const'
    marker = '        double d = dsp48e1CombInputDelayNS(dspStripBusIndex(fromPort));'
    include = '#include "xc7_dsp_cascade.inc"\n\n'
    addition = '''        if (!xc7DspCascadeArcPossible(fromPort.str(this), toPort.str(this),
                                     str_or_default(cell->params, id("A_INPUT"), "DIRECT"),
                                     str_or_default(cell->params, id("B_INPUT"), "DIRECT")))
            return false;
'''
    if source.count(declaration) != 1 or source.count(marker) != 1:
        raise ValueError('unexpected DSP timing implementation')
    if include not in source:
        source = source.replace(declaration, include + declaration)
    if addition not in source:
        if 'diagnostic_dsp_legacy' not in source:
            source = source.replace(marker, addition + marker)
    calibration = '''
        const double cascade = xc7DspCascadeDelayNS(fromPort.str(this), toPort.str(this),
                                                   str_or_default(cell->params, id("A_INPUT"), "DIRECT"),
                                                   str_or_default(cell->params, id("B_INPUT"), "DIRECT"));
        if (cascade >= 0 && !bool_or_default(settings, id("diagnostic_dsp_legacy"), false))
            d = cascade;
'''
    if calibration not in source:
        source = source.replace(marker, marker + calibration)
    if diagnostic_switch:
        source = source.replace('        if (!xc7DspCascadeArcPossible(',
            '        if (!bool_or_default(settings, id("diagnostic_dsp_legacy"), false) &&\n'
            '            !xc7DspCascadeArcPossible(')
        command = root / 'common/command.cc'
        driver = command.read_text()
        option = '    general.add_options()("json", po::value<std::string>(), "JSON design file to ingest");'
        start = '        bool do_pack = vm.count("pack-only") != 0 || vm.count("no-pack") == 0;'
        finish = '    if (vm.count("report")) {'
        options = '''    general.add_options()("diagnostic-dsp-cascade",
                          "route with old DSP arcs, then retime the same wires with corrected cascades");
'''
        setup = '''        if (vm.count("diagnostic-dsp-cascade"))
            ctx->settings[ctx->id("diagnostic_dsp_legacy")] = true;
'''
        compare = '''    if (vm.count("diagnostic-dsp-cascade")) {
        const uint32_t before = ctx->checksum();
        log_info("DSP_CASCADE_RECHECK: unchanged placement and routing, checksum 0x%08x\\n", before);
        ctx->settings[ctx->id("diagnostic_dsp_legacy")] = false;
        timing_analysis(ctx.get(), false, true, true, false);
        NPNR_ASSERT(ctx->checksum() == before);
        log_info("DSP_CASCADE_RECHECK_COMPLETE: graph checksum unchanged\\n");
    }

'''
        for marker, extra in ((option, options), (start, setup), (finish, compare)):
            if driver.count(marker) != 1:
                raise ValueError('unexpected command-driver layout')
            if extra not in driver:
                driver = driver.replace(marker, extra + marker)
        command.write_text(driver)
    shutil.copyfile(Path(__file__).with_name('xc7_dsp_cascade.inc'),
                    root / 'xilinx/xc7_dsp_cascade.inc')
    path.write_text(source)


def main() -> None:
    """Require an explicitly selected experimental native source tree."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('nextpnr', type=lambda p: Path(p).resolve())
    parser.add_argument('--diagnostic-switch', action='store_true',
                        help='also install an opt-in same-process old/new dependency comparison')
    args = parser.parse_args()
    install(args.nextpnr, args.diagnostic_switch)


if __name__ == '__main__':
    main()
