# Local development checks

Use OTP 28.0.2 and rebar3 3.24.0. The Erlang modules invoke neither compiler nor vendor tools; the umbrella application consumes target-owned physical validators. The pinned erlfmt project plugin formats production source. From the repository root:

```sh
rebar3 fmt
rebar3 fmt --check
rebar3 as spacetime eunit --dir=apps/hls_spacetime/test
rebar3 as spacetime dialyzer
```

The unit suite uses small synthetic artifacts, native-shaped table fixtures and bounded capture/SDF strings. These checks do not invoke the application compiler, Vivado, a decoder simulation or the optional RAM witness. Their success establishes parser/validator behavior, not native correctness.

Run `python3 tools/check_source_contracts.py --strict apps/hls_spacetime/src apps/hls_target/src/characterization` from the umbrella root. Require every returned file's findings to be empty. This scans formal exported docs, specs, private-declaration comments and unique source declarations. It does not establish that a specification is truthful.

The C++ transport has an independent C++17 test. Supply a fresh existing output directory:

```sh
c++ -std=c++17 -Wall -Wextra -Werror -I apps/hls_spacetime/priv/include \
  apps/hls_spacetime/test/native/spacetime_trace_tests.cpp -o /tmp/spacetime-trace-tests
mkdir /tmp/spacetime-trace-results
/tmp/spacetime-trace-tests /tmp/spacetime-trace-results
```

Run substantial checks serially under the project's 6 GiB local process-group guard. Retain diagnostics outside Git; `_build/` is disposable. [The RAM witness](memory-witness.md) requires explicit testbench and primitive paths and is excluded from normal tests.

The target-owned native-export hash transport has a small local subprocess/Tcl fixture suite: `python3 apps/hls_target/test/native/route_hash_worker_tests.py`. It checks hash freshness, bounded input/output paths and fail-closed pipe behavior without Vivado.
