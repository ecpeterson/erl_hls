# Framed bridge transition cleanup

- [x] Extract the hardware half of post-campaign R10 into typed receive/transmit decisions, explicit state commit and pre-edge pin observations.
- [x] Qualify the unchanged clock contract with focused schedules, old/new component equivalence and the existing small framed-role/reset witness.
- [ ] Leave host stream transition/effect factoring as the remaining R10 task; do not combine distinct peer-forwarding and BEAM-admission acknowledgments.

Evidence belongs in `hls_artifacts/runs/erlang-local-cells-2026-10-16/post-campaign-cleanup-7/`. This is a control-flow refactor, with no new scheduling support, state, frame ABI, performance claim or live-device run. The earlier review's canonical identity (R3) and compiler-owned layouts (R4) remain separate tasks.

Eleven DSLX schedules pass. The external-event case rejects the original implementation: an unused actor-packet expression indexed beyond the outgoing array; the selected-source branches avoid that evaluation. All state/input/identity/address bits of the old and new transition compare equal by combinational SAT at I=1, C=2, O=1, E=1, trusting DSLX/XLS and Yosys SAT. This does not quantify all parameter populations or prove temporal progress.

The existing three-actor, two-role broker/RTL fixture passes two incarnations (39 records and 27 forwarded messages each), descriptor closure, three reset interruptions, retirement, stale-session and identity rejection. Nineteen checker self-tests, contracts (391 files, 328 inherited gaps, zero new) and Dialyzer pass. Final local checks were serial under the six-GiB guard with no remaining owned processes. Initial harness/assertion failures and the interpreter indexing failure are retained in the evidence directory; no application integration or Actions run was added.
