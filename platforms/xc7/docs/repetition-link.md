# N=6 repetition link

This application places a periodic six-cell repetition experiment across two
TE0715 roles. Each PL owns three coordinates and three shared schedulers. Four
private serial-credit lanes in each direction cross the packet CDC and external
1000BASE-X link; BEAM reaches only the local public application and debug DMA
endpoints.

```text
BEAM A ↔ DMA A ↔ cells 0..2 ══ private PL Ethernet ══ cells 3..5 ↔ DMA B ↔ BEAM B
                 three schedulers                         three schedulers
```

`build_repetition_link_application.py` normalizes the N=6 topology, attaches
source-fragment reductions, emits deterministic role deployments and compiles
two-stage 25 MHz RTL. State and mailbox storage use external 1R1W RAM shells.
The physical build therefore requires the checked 72-bit parity mapping and
routed-width guards in [bram-sdp72.md](bram-sdp72.md). The optional five-bit
scheduler probe is passive: it observes state/mailbox requests without changing
ready or valid.

The private receive adapter prefetches word zero with the length header and
then presents one word per application clock. A bounded exact two-role
PCS/MAC simulation at a 12.5 MHz application clock and 100 ppm-separated wire
clocks exchanged 337 frames in each direction over 10,000 application cycles
with no drop, overflow, abort, preamble, CRC or packet fault. That simulation
is a witness over the stated horizon, not a CDC, timing or hardware proof.

## Host programs

Run both roles concurrently after a paired restart:

```sh
/opt/erl-hls/bin/check_repetition_link --demo a 120000
/opt/erl-hls/bin/check_repetition_link --demo b 120000
```

`--run` keeps the same acceptance criterion but suppresses individual events.
`--demo` prints every decoded `phi_correction` and `phi_status` before
requiring one complete three-cell local status round. It demonstrates the
generated decoder and host-visible result path; it does not apply corrections
to data cells or measure a logical observable.

`--memory` adds a small coordinator over PS Ethernet. Each BEAM applies its
local corrections, forwards cross-partition corrections, waits for a common
quiet/empty step after every acknowledgement, then queries all six data cells
in the logical-X basis. Its encoding and state-machine invariants have offline
tests, but this mode has not yet completed on the physical pair. Do not label it
a logical-memory hardware witness until both roles print their final PASS line.

The debug endpoint remains available in every image. The private-link,
scheduler-stage and packet smoke modes are post-failure diagnostics; packet
trace is one-shot and must not be drained before the application run.

## Repeat an activation

The generated gateway accepts one attachment per PL activation. Stopping BEAM
does not reset the actors. `restart_repetition_pair.py` restarts both complete
roles concurrently:

```sh
python3 platforms/xc7/restart_repetition_pair.py \
  --key ~/.ssh/id_ed25519
```

The default paired PS reboot is physically exercised and verifies a changed
kernel boot ID, FPGA-manager state, both DMA devices and installed inputs. It
does not require removing board power. `--method reload` instead uses Linux
FPGA Manager while keeping SSH alive; that path checks firmware hashes,
exclusive DMA ownership, driver rebind and endpoint health, but remains
experimental until a successful two-board application run follows it.

## Portable checks

Generate both roles with the pinned XLS tools, then run:

```sh
python3 platforms/xc7/test_repetition_link.py \
  --generated /path/to/repetition-link/rtl
```

The checker self-test covers correction/status decoding, logical parity,
coordinator packets and DMA-state parsing. The restart unit tests cover boot-ID
fencing. The optional generated-RTL tests require exactly 17 attachment/cutoff
words, scheduler state and mailbox activity, a public identity reply and a
complete private packet from each role. These are bounded witnesses, not
physical-link or timing qualification.

`application/repetition_link_rtl_tb.sv`,
`repetition_packet_pair_tb.sv` and `repetition_mac_pair_tb.sv` retain the
longer two-role witnesses used during bring-up.

## Physical result and packaging

On 2026-10-13 the corrected 3+3 images accepted the ten-word identity and
seven-word cutoff frames on both boards. Each role completed one local
three-cell status round. After identity, role A exposed two corrections and six
statuses; role B exposed one correction and six statuses. Each packet monitor
recorded 250 graph frames, and neither side reported protocol, preamble or CRC
fault. This is a bounded two-board witness for that activation, not decoder
threshold, BER or timing qualification.

`application/link_board.py` builds each role around the common DMA/debug,
packet and GTX shell. `prepare_partition_link.py` checks the application,
route, assembly, clock and root manifests; installs both deployments, the
checker, firmware and restart helpers; and QEMU-checks one shared ext4 root.
Use the checked media procedures in [sd-maintenance.md](sd-maintenance.md) for
role-specific FAT payloads.
