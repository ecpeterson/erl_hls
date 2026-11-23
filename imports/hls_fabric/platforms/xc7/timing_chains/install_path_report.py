#!/usr/bin/env python3
"""Add an opt-in critical-path diagnostic to the pinned native nextpnr driver."""
import argparse
from pathlib import Path


def install(root: Path) -> None:
    """Patch the command driver idempotently; reject an unexpected source layout."""
    path = root / 'common/command.cc'
    source = path.read_text()
    option = '    general.add_options()("json", po::value<std::string>(), "JSON design file to ingest");'
    report = '    if (vm.count("report")) {'
    addition = '''    general.add_options()("diagnostic-timing-paths",
                          "print critical paths; unrouted interconnect remains estimated");
'''
    invocation = '''    if (vm.count("diagnostic-timing-paths")) {
        log_info("Diagnostic timing paths may use estimated interconnect; this is not evidence of routing completion.\\n");
        timing_analysis(ctx.get(), false, true, true, false);
    }

'''
    for marker, extra in ((option, addition), (report, invocation)):
        if source.count(marker) != 1:
            raise ValueError(f'unexpected nextpnr command layout: {marker}')
        if extra not in source:
            source = source.replace(marker, extra + marker)
    path.write_text(source)


def main() -> None:
    """Install into a dedicated source tree; leave tool compilation explicit."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('nextpnr', type=Path)
    install(parser.parse_args().nextpnr.resolve())


if __name__ == '__main__':
    main()
