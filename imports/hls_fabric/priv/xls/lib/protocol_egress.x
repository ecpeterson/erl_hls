import arbitration;

// Cursor and held producer indices are legal only below the caller's fan-in N.
// Reset establishes this domain; tick preserves it. No frame payload is copied.
pub struct State<C: u32> { cursor: bits[C], held: bool, owner: bits[C] }
// One frame and one-hot producer acceptance. Frame is unspecified while invalid;
// selected/index are diagnostic values.
pub struct Observation<N: u32> {
  valid: bool, frame: bits[128], ready: bits[N], selected: bits[N], index: u32,
}
// Registered arbitration ownership plus pre-edge output/handshake observations.
pub struct Tick<N: u32, C: u32> { state: State<C>, output: Observation<N> }

// N=1..256, C=1..8, 2^C>=N and cursor/owner<N. Each producer must retain
// valid/frame until ready. The held index makes later arrivals unable to replace
// a stalled frame. Current valid/frame/selection never depend on out_ready.
pub fn observe<N: u32, C: u32>(s: State<C>, reset: bool, valid: bits[N],
                               frames: bits[128][N], out_ready: bool) -> Observation<N> {
  const_assert!(N > u32:0 && N <= u32:256 && C > u32:0 && C <= u32:8 && (u32:1 << C) >= N);
  let (fresh_valid, fresh_index) = arbitration::select(rev(valid) as bool[N], s.cursor);
  let index = if s.held { s.owner } else { fresh_index };
  let selected = bits[N]:1 << index;
  let active = !reset && (if s.held { (selected & valid) != bits[N]:0 } else { fresh_valid });
  let mask = if active { selected } else { bits[N]:0 };
  // The source holds this selected frame until acceptance. Payload is ignored
  // when invalid; clearing it would add a full-width gate without a handshake effect.
  let frame = frames[index];
  Observation { valid: active, frame,
    ready: if out_ready { mask } else { bits[N]:0 }, selected: mask, index: index as u32 }
}

// Cursor advances only on transfer, after the selected producer. An offered but
// stalled frame locks its source; reset cancels the lock. Fairness counts accepted
// competing transfers under persistent requests, not elapsed clocks or progress.
pub fn tick<N: u32, C: u32>(s: State<C>, reset: bool, valid: bits[N],
                            frames: bits[128][N], out_ready: bool) -> Tick<N,C> {
  let output = observe(s, reset, valid, frames, out_ready);
  let transferred = output.valid && out_ready;
  let state = if reset { zero!<State<C>>() }
    else if transferred { State<C> { cursor: (if output.index + u32:1 == N { u32:0 } else { output.index + u32:1 }) as bits[C],
      held: false, owner: bits[C]:0 } }
    else if output.valid { State<C> { held: true, owner: output.index as bits[C], ..s } }
    else { s };
  Tick { state, output }
}
