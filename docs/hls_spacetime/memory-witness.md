# Optional RTL memory witness

The umbrella fixture `apps/erl_hls/test_data/spacetime_memory_tb.sv` exercises the target-owned `hls_1r1w_ram` primitive as two four-bit lanes with independent write enables, plus one response register. A request sampled before edge C returns before edge C+2. The testbench only reads internal memory for observation; it never initializes or writes it through hierarchy. It records all 17 clocks, the two words before and after each edge, operation controls and valid read responses.

The localized witness covers full and nibble-masked writes, equal-valued writes, holds, address reuse, simultaneous read-first collisions and reset retirement. Reset clears response validity but retains RAM contents; the artifact begins new carry-in roots and does not link retired requests across reset. The supported masks are `0x0f`, `0xf0` and `0xff`; partial-nibble masks, other collision modes and uninitialized reads reject. This fixture's logical `bram` resource describes memory semantics, not native BRAM inference or placement. Its physical catalogue remains `null`.

The default unit suite does not run a simulator. The optional witness requires the maintained umbrella testbench and primitive explicitly; the repository never searches for or fetches another checkout. With Icarus (`iverilog` and `vvp`) on `PATH`, use a fresh output directory under the normal serial local-test limits:

```sh
apps/hls_spacetime/test/memory_witness.escript \
  apps/erl_hls/test_data/spacetime_memory_tb.sv \
  apps/hls_target/priv/rtl/hls_1r1w_ram.v /path/to/fresh-output
```

With no arguments the runner reports that the optional witness was skipped. The explicit invocation compiles the two supplied RTL sources, checks the recording and fourteen deliberate corruptions, and writes `bundle/bundle.etf`, `bundle/bundle.json` and their validated inventory plus source/tool identities. It never runs a decoder or a native implementation.

The helper accepts at most 128 KiB of trusted simulator terms and 4096 rows; it requires consecutive cycles and an explicit complete footer. It checks every enabled write and response against observed words before constructing storage histories. The finite witness yields 40 events and 15 versions: six writes, including two equal and two masked writes; seven accepted reads, five returned responses and two requests retired by reset. Fourteen deliberate corruptions check rejection of missing coverage, unsupported masks/collisions, inconsistent contents, incorrect responses and invalid reset behavior. These are simulation and validator witnesses, not a proof for arbitrary RAM configurations. Retain exact source, compiled-simulator and observer hashes plus Icarus/tool versions with exported evidence; the source identity alone is insufficient.

Prepare the result with the same workflow as any other producer:

```sh
_build/default/bin/spacetime validate /path/to/fresh-output/bundle/bundle.etf
node scripts/prepare-view.mjs --bundle /path/to/fresh-output/bundle/bundle.json --output /path/to/fresh-view
npm start -- --data /path/to/fresh-view
```

Build the offline command first with `rebar3 escriptize`. The resulting view uses logical address lanes because the witness supplies no native catalogue. It does not need a campaign archive or hard-coded example event IDs.
