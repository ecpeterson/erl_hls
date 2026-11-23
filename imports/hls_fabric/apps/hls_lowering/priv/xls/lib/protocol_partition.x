// Receiver-owned boundary fault; canonical payload storage stays in the capture.
pub struct State { fault: bool }

// A sampled incoming offer and the destination slot's old-state credit.
pub struct Inputs { reset: bool, valid: bool, canonical: bool, slot_ready: bool }

// Invalid offers retire into a sticky fault and never become a capture arrival.
pub struct View { ready: bool, capture: bool, fault: bool }

// Valid frames wait for their own slot. Faults stop this link until common reset.
pub fn observe(s: State, io: Inputs) -> View {
    let ready = !io.reset && !s.fault && (!io.canonical || io.slot_ready);
    View { ready, capture: ready && io.valid && io.canonical, fault: !io.reset && s.fault }
}

// One fault bit is the only new state; no replay or independent reset protocol.
pub fn next(s: State, io: Inputs) -> State {
    State { fault: !io.reset && (s.fault || (io.valid && !io.canonical)) }
}
