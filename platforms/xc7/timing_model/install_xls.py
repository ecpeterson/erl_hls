#!/usr/bin/env python3
"""Install the experimental estimator in a disposable XLS source checkout."""
import argparse
from pathlib import Path
import shutil

RULE = '''
cc_library(
    name = "model_xc7_7030",
    srcs = ["xc7_delay_estimator.cc"],
    alwayslink = True,
    deps = [
        "//xls/estimators/delay_model:delay_estimator",
        "//xls/ir",
        "//xls/ir:op",
        "@abseil-cpp//absl/flags:flag",
        "@abseil-cpp//absl/status",
        "@abseil-cpp//absl/status:statusor",
    ],
)
'''


AUDIT_RULE = '\n'.join([
    '', 'cc_binary(', '    name = "xc7_audit_main",',
    '    srcs = ["audit_main.cc"],', '    deps = [',
    '        ":model_xc7_7030",',
    '        "//xls/common:init_xls",',
    '        "//xls/estimators/delay_model:delay_estimator",',
    '        "//xls/ir",', '        "//xls/ir:ir_parser",',
    '    ],', ')', ''])


def install(root: Path) -> None:
    """Add one named estimator without changing the default or existing models."""
    directory = root / 'xls/estimators/delay_model/models'
    build = directory / 'BUILD'
    source = build.read_text()
    if 'model_xc7_7030' not in source:
        marker = '        ":model_unit",\n'
        if source.count(marker) != 1:
            raise ValueError('unexpected XLS model registry')
        source = source.replace(marker, marker + '        ":model_xc7_7030",\n')
        build.write_text(source + RULE)
    if 'name = "xc7_audit_main"' not in build.read_text():
        with build.open('a') as stream:
            stream.write(AUDIT_RULE)
    for name in ('xc7_delay_estimator.cc', 'audit_main.cc'):
        shutil.copyfile(Path(__file__).with_name(name), directory / name)


def main() -> None:
    """Require an explicit source checkout, normally a dedicated worktree."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('xls', type=Path)
    install(parser.parse_args().xls.resolve())


if __name__ == '__main__':
    main()
