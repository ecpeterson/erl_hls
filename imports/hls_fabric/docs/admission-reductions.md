# Admission reductions

Set `admission_reductions => true` on a materialized scheduler group to collect eligible reduction messages without an actor-state RAM transaction. This is an experimental placement option: fewer actor visits need not mean faster clocks or smaller hardware. All groups sharing an actor module must agree; that module cannot also have direct instances. The option currently requires an ordinary `hls_statem` actor with reductions and without synchronous replies.

Admission preserves the existing producer arbitration. A checked contribution can use the collector only when its mailbox is empty, the actor is unowned, and no callback is being issued for it. Contribution selection and folding use the ordinary compiled callbacks, including their state-dependent guards. Pending entry/internal events, early or wrong-key traffic, malformed frames and invalid members take the ordinary mailbox path. No message overtakes already queued work.

The collector owns partial reduction state. Dispatch captures it for the executor; retirement returns the updated state. Ordinary and collected contributions therefore share one accumulator and membership set. Completion still needs the normal executor and effect capacity. A failed fold retains its outstanding member obligations and reports failure through ordinary completion.

Actor RAM can contain an older reduction snapshot. Generated debug projections use a passive live progress output for selected/arrived/missing members, phase and failure; host queries cannot backpressure that output. Projection schema 5 requires an instrumentation tool that understands this authority. Reset clears collector state and observation validity together with the scheduler.

The collector retains the callback context needed to select contributions. Hardware cost depends on that context and the reducer; this option does not promise bounded area independent of application state.
