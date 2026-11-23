// One actor's fault indication; code zero means no fault, including actor zero.
pub struct Fault { actor: u32, code: u16 }

// Select the first nonzero indication in network order; return zero if none.
// The loop keeps generated AST depth independent of the number of actors.
pub fn first<N: u32>(faults: Fault[N]) -> Fault {
  for (i, selected): (u32, Fault) in u32:0..N {
    if selected.code == u16:0 && faults[i].code != u16:0 { faults[i] } else { selected }
  }(zero!<Fault>())
}
