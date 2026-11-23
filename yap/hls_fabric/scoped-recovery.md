# Recovery boundaries and acceptance

`Notes/erl_xls/Roadmap.md` is the sole active task list. P5 owns application recovery meaning, P6 owns selected physical deployment, and G1 owns additional Erlang links/exhaustion and collective-retirement semantics. This note supports those items; the original staged plan is superseded by the implemented [domain contract](../docs/domain-recovery.md) and [qualification record](actor-recovery.md).

## Established digital boundary

A monitor reports failure or loss of reachability; a supervisor decides which children to replace. Geometric neighbors and message routes are not automatically Erlang failure links. Current managed domains distinguish actual actor failure from `noconnection`, retain prior-output delivery frontiers, reject stale identities and expose replacement actors through fresh endpoints/PIDs. Connection loss does not prove accepted work was unexecuted, and no uncertain application work is automatically replayed.

Host OTP supervision, static FPGA supervisors, bounded temporary children and framed dependent restart groups have finite native/RTL witnesses. Crossing channels bind a generation to both endpoint incarnations; the present dependent-group policy requires both endpoints fresh before rebinding. These are explicit composition contracts, not a general asynchronous independent-peer restart protocol. Ordinary legacy partition bridges retain their common-reset transport assumptions.

Dynamic Erlang links and exit propagation remain unsupported. The current digital controller records one lifecycle transition and first fault, not application work history. Local replacement does not establish external-resource validity or reverse an emitted effect.

## Collective retirement contract — G1/G3

A failed member contributes failure, never a successful identity value. Before reusing a result or contribution slot, every enrolled member must have contributed or been definitively retired behind a fence that excludes late contributions. Missing reachability alone cannot retire a live contributor. Membership, work epoch and storage ownership remain distinct from geometric placement and channel generation.

A selected extension must exercise accepted work, partial traffic and an outstanding collective during failure, with an independent region continuing. Saturation, late contributions, repeated failures and finite-identity exhaustion must preserve one terminal outcome per monitored incarnation. An attempted relationship cannot silently disappear on resource exhaustion; its failure/admission policy belongs to G1.

## Application recovery contract — P5

Replacing an actor with initial state is not necessarily valid application recovery. The application chooses which result remains meaningful, which dependent resources stay reserved and what restart region is permitted. Any promised resumed computation needs an explicit checkpoint or retained-input boundary and a reference against which recovered results can be compared. An impossible or uncertain result must remain explicit. Quantum-code deformation and resource-specific safety rules belong outside the compiler/runtime.

## Physical deployment contract — P6

A real deployment must establish old-transport exclusion, descriptor release, reset completion and readiness independently of host process death. Management cannot depend solely on a failed or blocked application lane. Accepted replies/effects and uncertain operations retain the ordering and uncertainty prescribed by the supported backend. Framing integrity, actual CDC/reset isolation and device failure-detection deadlines require their own physical qualification; finite digital recovery does not supply them.
