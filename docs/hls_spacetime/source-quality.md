# Local development checks

Use OTP 28.0.2 and rebar3 3.24.0. The Erlang library depends only on OTP; the pinned erlfmt project plugin formats production source. From this repository:

```sh
rebar3 fmt
rebar3 fmt --check
rebar3 eunit
rebar3 dialyzer
```

The unit suite uses small synthetic artifacts, native-shaped table fixtures and bounded capture/SDF strings. These checks do not invoke the application compiler, Vivado, a decoder simulation or the optional RAM witness. Their success establishes parser/validator behavior, not native correctness.

The existing source-contract auditor is maintained in `erl_hls`; point it at this library without adding a runtime dependency. Compile its `tools/source_contracts.erl` into a disposable directory and invoke `source_contracts:main/0` with the library's `src/*.erl` and `test/*.erl` files. Require every returned file's `findings` list to be empty. This scans formal exported docs, specs, private-declaration comments and unique source declarations. It does not establish that a specification is truthful. The initial library qualification records the exact auditor source revision in its test report.

The C++ transport has an independent C++17 test. Supply a fresh existing output directory:

```sh
c++ -std=c++17 -Wall -Wextra -Werror -I priv/include \
  test/native/spacetime_trace_tests.cpp -o /tmp/spacetime-trace-tests
mkdir /tmp/spacetime-trace-results
/tmp/spacetime-trace-tests /tmp/spacetime-trace-results
```

Run substantial checks serially under the project's 6 GiB local process-group guard. Retain diagnostics outside Git; `_build/` is disposable. [The RAM witness](memory-witness.md) requires explicit testbench and primitive paths and is excluded from normal tests.

The optional native-export hash transport has a small local subprocess/Tcl fixture suite: `python3 test/native/route_hash_worker_tests.py`. It checks hash freshness, bounded input/output paths and fail-closed pipe behavior without Vivado.
