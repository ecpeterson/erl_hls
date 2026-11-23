#!/usr/bin/env python3
"""Check runtime ownership with the selected compiler's shared package auditor."""
import argparse
from compiler_paths import compiler_root, compiler_tool


def main() -> int:
    """Use one already-built profile; all policy/report options pass to the shared auditor."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--profile', default='default')
    arguments, rest = parser.parse_known_args()
    auditor = compiler_tool(compiler_root(arguments.profile), 'package_boundaries')
    return auditor.main(['--profile', arguments.profile, *rest])


if __name__ == '__main__':
    raise SystemExit(main())
