#!/usr/bin/env python3
"""Check the compiler-owned runtime library without starting project applications."""
from erl_hls_tools.package_boundaries import main

if __name__ == '__main__':
    raise SystemExit(main())
