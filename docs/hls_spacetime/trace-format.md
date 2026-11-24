# Protocol-stream capture dialect

`priv/include/spacetime_trace.h` and `hls_spacetime_trace` share this bounded pre-edge recording format. Its eleven fixed public fields describe the current 32-bit source-protocol stream interface. It is a capture dialect, not the backend-neutral cycle artifact: other producers may construct that artifact without using these fields. Backend adapters give sampled taps their meaning.

The protocol-specific harness, FIFO transport, fault aggregation, stimulus schedules and live/replay/drive commands belong to [hls_fabric capture](../hls_fabric/spacetime-capture.md). This library provides only recording transport and checked offline reading.

The trace is ASCII TSV. Every row, including the footer, ends in a newline:

```text
H<TAB>spacetime_cycle_trace<TAB>1
P<TAB>reset<TAB>input_valid<TAB>input_data<TAB>input_last<TAB>output_ready<TAB>input_ready<TAB>output_valid<TAB>output_data<TAB>output_last<TAB>fault<TAB>running
T<TAB>ID<TAB>WIDTH<TAB>VPI_PATH
S<TAB>FIRST_CYCLE<TAB>RUN_LENGTH<TAB>PUBLIC_VALUES...<TAB>TAP_VALUES...
F<TAB>END_CYCLE<TAB>complete|incomplete<TAB>SAMPLE_COUNT<TAB>RECORD_COUNT<TAB>DECODED_UPPER_BOUND<TAB>CAUSE
```

The two header rows occur once, followed by zero or more tap declarations, then sample runs, then exactly one final footer. Each sample has eleven public values in header order and one value per tap declaration. Values are canonical lowercase hexadecimal without a prefix or redundant leading zeroes; zero is `0`. Public data words have width 32 and all other public fields width 1. Tap widths are 1 through 65536. Logical aliases may share a VPI path at the same width; IDs must remain unique. Unknown VPI bits, invalid widths, missing handles, duplicate tap IDs and malformed fields reject. The producer defines the aggregation behind `fault`; the field itself carries only one bit.

Cycles, run lengths, widths and footer counters use canonical unsigned decimal. Runs partition `[0, END_CYCLE)` without gaps or overlaps. A run repeats the entire pre-edge sample, including offered inputs and active handshakes; repeated accepted transactions still occur separately on every clock. Sampling follows low-clock evaluation and precedes the rising edge. The producer owns reset and stall schedules; sampled offers preserve what actually occurred independently of host scheduling.

`SAMPLE_COUNT` equals `END_CYCLE`; `RECORD_COUNT` counts `S` rows. `DECODED_UPPER_BOUND` starts at 4096 bytes for footer allowance, adds the actual newline-inclusive header/tap-row sizes, then adds `RUN_LENGTH * (32 + sum(value_token_bytes + 1))` for each sample run. It conservatively bounds expansion as TSV, without materializing repeated cycles. The writer and reader reject more than 4,000,000 cycles, 1,000,000 sample rows, 256 MiB decoded size, 4096 taps or a 1 MiB line. Runtime limits and packed-file retention belong to the producer and outer collection guard.

A successful footer has `complete` and cause `ok`. Errors attempt an `incomplete` footer covering the contiguous observed prefix; causes contain ASCII letters/digits/underscore/hyphen only and are capped at 200 characters. A missing/unwritable footer cannot be certified complete. Replay requires a complete footer with matching counters and no following data. It compares every public field and requested tap on every clock, including inactive data, and retains the observed prefix on mismatch. Samples alone are not semantic events: the lowering-specific importer must interpret accepted controls, state writes, leases and reset retirement. Bit equality or transitions do not create transaction identities.
