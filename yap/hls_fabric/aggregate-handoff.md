# Aggregate handoff experiment

The #35 D6 recording splits 288.8 ns/step of aggregate-to-executor delay into 66.4 ns queue/poll waits, 111.2 ns mux forwarding and 111.2 ns scheduler admission. The selected chain has 139 aggregate crossings in ten complete intervals. The mux's payload register is redundant with the existing per-actor queues and downstream queue.

Before measuring a new full build, predict 0.10–0.12 µs/step savings from compiling the unchanged polling mux in one stage, giving roughly 1.57–1.58 µs from 1.6838 µs. Cursor advancement, fairness, input queue capacities and public scheduler logic remain unchanged. Physical timing may worsen from the longer combinational handoff; no routed clock claim follows from synthesis. Direct ready/valid stall tests and complete-board SCC checks must precede adoption.

Use the retained observations to expose collector enqueue, mux selection, mux forwarding and scheduler capture as separate causal nodes. Keep source identity by per-actor and accepted-mux ordinals; reject ambiguous or inverted histories. Resource competition remains separate from message causality.

Removing the forwarding register removes one shared pipeline holding slot. The per-actor input queues still reserve one complete aggregate each, and each actor has at most one open window. Thus the existing queues can retain every outstanding aggregate while the scheduler stalls; correctness does not rely on the removed shared slot. The generated mux retains its cursor when its selected output is blocked. The RTL probe requires a stable offered payload through that stall.
