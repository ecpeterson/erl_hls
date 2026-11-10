// Appended to the normally lowered actor. This harness exposes one complete
// generated owner step; it does not implement mailbox or callback semantics.
// Keeping Machine as an opaque RTL feedback port avoids a copied state layout.
pub fn differential_step(
    machine: Machine, kind: u8, value: u8,
    valid: bool, ready: bool, reset: bool) -> (Machine, u64) {
  let current = if reset { initial_machine() } else { machine };
  let accept = !reset && valid && current.admission_pending &&
    !current.enter_pending && !hls_failure::failed(current.failure);
  let frame = axis::pack(Tag::COMMAND as u8,
    bits_from_command(Command { kind, value }));
  let step = if reset {
    MachineStep { machine: current, ..zero!<MachineStep>() }
  } else { machine_step(current, frame, accept, ready) };
  let next = step.machine;
  let postponed = unroll_for! (index, count): (u32, u8) in u32:0..u32:3 {
    count + ((index < next.occupied as u32 && next.slots[index].postponed) as u8)
  }(u8:0);
  let result = output_from_bits(step.egress.frame.payload);
  let observed = bits[9]:0 ++ (next.phase as u8) ++ next.data.value ++
    next.occupied ++ postponed ++ (hls_failure::kind(next.failure) as u4) ++
    next.enter_pending ++ (accept as u1) ++ step.egress_valid ++
    (step.egress.port as u8) ++ result.value;
  (next, observed)
}
