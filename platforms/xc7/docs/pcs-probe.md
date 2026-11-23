# External 1000BASE-X PCS-boundary diagnostic

This two-board diagnostic follows the passing external raw-symbol test. It retains the external Ethernet GTX profile, both carrier polarity inversions, hard comma alignment and the production LiteEth 8b/10b decoder/autonegotiation timers. It sends 1000BASE-X configuration ordered sets but no Ethernet frames. The generated diagnostic is fixed to 1000BASE-X rather than runtime SGMII selection; two TX-domain registers isolate autonegotiation control from the encoder. They delay control changes by two symbols without changing ordered-set contents.

The image uses identity `0x50435337` (`PCS7`), ABI 1 and UIO name `erl-hls-pcs`. Control bit 0 runs the lane and bits 6:4 select one of five status pages. The pages report raw 20-bit words and commas in each half; decoded symbols, invalid symbols and K28.5; `/C1/`, `/C2/` and complete configuration words; PCS configuration events, restarts and received ability registers; and final raw, gearbox and decoded values. Counters wrap at 32 bits. Held snapshots cross to the 25-MHz control clock after acknowledgement settling.

## Board procedure

Install the five files from `pcs-external-clock-ssh-fat-autoneg/` on both FAT boot partitions and cold-boot with the DAC connected. Require the usual clock-startup messages, a PASS from `probe_clock`, and UIO name `erl-hls-pcs`. Restore board A/B PS Ethernet addresses `192.168.77.31` and `.32` if necessary.

From the Mac, start one lead process, wait one second, and start the follower:

```sh
ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes \
  -i ~/.ssh/id_ed25519 root@192.168.77.32 \
  '/mnt/sd/probe_pcs /dev/uio0 --lead' \
  > /tmp/pcs-b.log 2>&1 &
lead_pid=$!
sleep 1
ssh -nT -o BatchMode=yes -o IdentitiesOnly=yes \
  -i ~/.ssh/id_ed25519 root@192.168.77.31 \
  '/mnt/sd/probe_pcs /dev/uio0 --follow' \
  > /tmp/pcs-a.log 2>&1
follow_rc=$?
wait "$lead_pid"
lead_rc=$?
cat /tmp/pcs-a.log
cat /tmp/pcs-b.log
printf 'follow=%s lead=%s\n' "$follow_rc" "$lead_rc"
```

Both boards transmit throughout the attempt. A PASS requires physical readiness and an advancing recovered raw-word counter; it means the diagnostic trace was captured, not that a PCS link formed. For the corrected image, require both `autoneg` lines to report `link=1`. After link completion, the transmitter replaces configuration ordered sets with `/I1/` and `/I2/` idles, so a retained post-link window is expected to have no new C1/C2 or complete configuration words. Reporter builds containing the post-link correction classify this as `boundary=link reached RUNNING; post-link idle window`; the original reporter incorrectly classified it as missing C1/C2. Preserve every line. The one-second delay is intentional: it checks convergence when one PCS leaves break-link substantially later than its peer.

## Build and evidence

`run_pcs_probe.sh` tests the raw/decoder/configuration counters and host lead/follow sequencing, regenerates the PCS and gearbox from hash-checked sources, then synthesizes and routes the board image. Its directed independent-clock regression releases the second PCS at eight offsets; the corrected PCS reaches link on both peers in every case, while the prior generated PCS fails. The retained route reports 154.54 MHz TX and 168.89 MHz RX against 125 MHz, plus 586.17 and 236.69 MHz against the 62.5-MHz half-rate constraints. These are simulation witnesses and partial native timing-model results, not complete PS/GTX timing signoff.

Both the original and MMCM-site-pinned images reached `CLOCKS` with CPLL lock but neither MMCM locked. Comparing the failed native image with the hardware-working Vivado external-Ethernet image found `ZINV_PWRDWN` missing at both MMCMs. The corrected diagnostic adds only the corresponding two non-ECC bits. A physical startup trace then reached `READY` with both MMCMs locked.

The first complete two-board trace counted no invalid 8b/10b symbols and about 34.6 million configuration words per endpoint, but remained link-down. One PCS received `0x4020` while locally transmitting `0x0020`; the other received `0x0020` while transmitting `0x4020`. This is the complementary `WAIT-ABI`/`WAIT-ACK` deadlock exposed by starting the follower one second late. The correction excludes the all-zero break-link word from ability events and permits a stable ACK-bearing configuration to supply the peer ability in `WAIT-ABI`.

On 2026-10-10, the corrected image converged with the same one-second stagger on both delivered boards. Each endpoint reported `last_config=4020`, `lp_abi=4020`, `link=1`, both generated-clock locks, no invalid decoded symbols and about 69.2 million valid Config-or-Idle events during its retained window. C1, C2 and complete-configuration deltas were zero because the linked PCS was then sending idles. This is a two-end physical autonegotiation witness, not Ethernet-frame, BER or sustained-link qualification.

The checked assembly matches all 324 enabled features against the retained external-Ethernet GTX reference across the complete 1,933-bit known mask. Frame serialization recovers 102,652 non-ECC set bits. Two fresh assemblies produced identical frame and normalized bitstream hashes. The [reference record](../boot/pcs-external.json) binds the source, route, backend, retained reference, assembly and output identities. These checks qualify the stated digital construction and known-mask equality. The physical run witnesses corrected autonegotiation convergence; Ethernet frames, BER, jitter, sustained operation and unknown configuration semantics remain unqualified.
