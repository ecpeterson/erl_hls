# Host stream ownership cleanup

- [x] Expose relay and mixed-owner retained state, sequential work passes and typed write decisions; keep one physical issue point per owner.
- [x] Keep peer-forwarding completion distinct from successful BEAM admission, including different command/ACK priorities and start-event order.
- [x] Repair relay endpoint rejection calls so they reach the current initializer and test the intended validation boundary.
- [x] Pass local qualification: 13 relay cases, four mixed-owner cases, admission and distribution suites; 19 contract-checker self-tests, 393-file audit (328 inherited gaps, zero new), and Dialyzer. Automatic CI remains disabled.
