# XSim reproduction note

Vivado/XSim 2024.2's behavioral run of the generated MAC/PCS stopped advancing at the first packet, shortly after host status reported both links up at 128.84 us. Multiple runs reached the same transition; an explicit `-maxdeltaid 10000` did not terminate it. Sampling the busy kernel showed repeated combinational process execution. This is evidence of a scheduling problem, not a minimized upstream bug report.

The batch therefore synthesizes the accelerated MAC/PCS and simulates its functional netlist alongside the handwritten endpoint, gearbox, actual GTX/MMCM models and host-control fixture. That run delivered 25 checked frames on each of two attempts, completing stop/restart at 430.32 us. Native Icarus regressions separately pass for behavioral and mapped MAC/PCS. Do not silently treat the abandoned behavioral XSim run as a pass; minimize it separately if pursuing an upstream simulator issue.

For the raw PRBS model, a single recovered-clock interval is not a frequency measurement: the CDR can move individual edges. The test averages 256 intervals and still requires both clean PRBS reception and an observed injected error. Keep reset timing unaccelerated in both vendor primitive tests; only PCS negotiation and packet gaps are accelerated.
