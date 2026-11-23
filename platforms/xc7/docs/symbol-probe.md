# External raw-symbol diagnostic

This two-board diagnostic sits between the passing external PRBS test and the failing external Ethernet PCS test. It uses the Ethernet-specific GTX CDR setting, external lane selection and both carrier polarity inversions, but bypasses the fabric 10b/8b decoder, gearbox and PCS. Each board continuously transmits alternating negative- and positive-disparity K28.5 code groups. Its receiver searches every phase of the recovered 20-bit stream, then enables the GTX hard comma aligner and checks the resulting word orientation.

The image uses identity `0x53594d37` (`SYM7`), ABI 1 and UIO name `erl-hls-symbol`. Control bit 0 runs the lane, bit 1 enables both comma aligners and bit 4 selects the second status page. The diagnostic reports the last recovered 20-bit word, detected phase, recovered-word count, pattern matches, the two aligned orientations and phase changes. Counters wrap at 32 bits and snapshots cross asynchronously to the 25-MHz control domain.

## Board procedure

Install the five files from `symbol-external-clock-ssh-fat/` on both FAT boot partitions and cold-boot with the DAC connected. Require the usual `CLOCK configured` and `CLOCK handoff` messages, a PASS from `probe_clock`, and UIO name `erl-hls-symbol`. Restore board A/B PS Ethernet addresses `192.168.77.31` and `.32` if necessary.

From the Mac, start one lead process, wait one second, and start the follower:

```sh
ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes \
  -i ~/.ssh/id_ed25519 root@192.168.77.32 \
  '/mnt/sd/probe_symbols /dev/uio0 --lead' \
  > /tmp/symbol-b.log 2>&1 &
lead_pid=$!
sleep 1
ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes \
  -i ~/.ssh/id_ed25519 root@192.168.77.31 \
  '/mnt/sd/probe_symbols /dev/uio0 --follow' \
  > /tmp/symbol-a.log 2>&1
follow_rc=$?
wait "$lead_pid"
lead_rc=$?
cat /tmp/symbol-a.log
cat /tmp/symbol-b.log
printf 'follow=%s lead=%s\n' "$follow_rc" "$lead_rc"
```

Both boards transmit throughout the attempt, so this single coordinated run observes both receive directions. Each process records a free-running sample, enables hard comma alignment, waits one second and records an aligned sample. The lead then holds its transmitter active for one additional second so the follower can complete its later status-page reads before reset fill reaches its receiver. A PASS requires advancing recovered words, at least 90% pattern matches, at least 90% observations in one of the two legal 10-bit orientations, phase 0 or 10, a legal final word and no more than eight phase changes. Both exit codes must be zero.

If only one board fails, retain both logs because the failure is directional. A pattern-recovery failure points to the Ethernet CDR/raw-sideband path despite the earlier PRBS result. Stable free-running patterns followed by an alignment failure point more narrowly to comma control or word orientation. Two PASS results move the next diagnostic boundary into the fabric 10b/8b decoder, ordered-set recognition or PCS state machine. This is not BER, sustained-load or Ethernet qualification.

On 2026-10-09, both delivered boards passed one coordinated run. Each receiver found the alternating K28.5 stream before alignment, then reported a legal phase and stable aligned orientation without invalid progression. This is a bounded two-direction raw-symbol and hard-comma witness, not BER or PCS qualification.

## Build and evidence

`run_symbol_probe.sh` runs source and Yosys-mapped simulation witnesses, compiles the host fixture, synthesizes the design and routes it with the isolated GTX-correct backend. The routed model reports 74.67 MHz for the 25-MHz control clock and 121.86 MHz for the 62.5-MHz recovered path. These are partial native timing-model results, not measurements or full PS/GTX timing closure.

The checked assembly matches all 324 enabled features against the retained external-Ethernet GTX reference across the complete 1,933-bit known mask. Frame serialization recovers all 59,662 non-ECC set bits, and two fresh assemblies have identical frame and normalized bitstream hashes. The [reference record](../boot/symbol-external.json) binds the source, route, backend, retained reference, assembly and output identities. These checks qualify the stated digital construction and known-mask equality; they do not independently validate unknown configuration semantics, analog behavior or hardware operation.
