// Bounded retained-call ownership and continuation scheduling. The callback
// worker has no access to wire transaction IDs. Tokens never wrap per reset.
import axis;

// One callback invocation; initialization and continuation consume no input frame.
pub struct Invocation<S: u32> {
  state: bits[S], frame: axis::Frame, from: u64, continuation: u8, initialize: bool,
}

// One callback outcome: at most one reply and one next internal operation.
pub struct Outcome<S: u32> {
  state: bits[S], reply: axis::Frame, from: u64, continuation: u8,
  error: u32, reply_allowed: bool,
}

// A live handle owns its transaction until its reply enters the output channel.
pub struct Slot { handle: u64, txid: u8 }

// Finds the first live/empty slot. N is positive; found gates index validity.
pub fn first<N: u32>(slots: Slot[N], live: bool) -> (bool, u32) {
  for (i, found): (u32, (bool, u32)) in u32:0..N {
    if !found.0 && (slots[i].handle != u64:0) == live { (true, i) } else { found }
  }((false, u32:0))
}

// Only a complete nonzero handle selects its caller; a retired handle cannot select a reused slot.
pub fn lookup<N: u32>(slots: Slot[N], handle: u64) -> (bool, u32) {
  for (i, found): (u32, (bool, u32)) in u32:0..N {
    if handle != u64:0 && slots[i].handle == handle { (true, i) } else { found }
  }((false, u32:0))
}

// Generic service failures use the established ERROR tag and one payload word.
fn error_frame(txid: u8, code: u32) -> axis::Frame {
  axis::Frame { header: axis::Header {
    op: u8:1, payload_words: u8:1, txid, flags: u8:0,
  }, payload: code as bits[96] }
}

// Application data, finite reply slots and continuation priority belong to one activation.
struct State<S: u32, N: u32> {
  data: bits[S], slots: Slot[N], sequence: u64, continuation: u8,
  initialized: bool, failure: u32,
}

// Calls are classified by a compile-time tag bitmap split into u64 parameters.
// A full reply table rejects calls but never blocks a cast that can release them.
pub proc Driver<S: u32, N: u32, C0: u64, C1: u64, C2: u64, C3: u64> {
  input: chan<axis::Frame> in;
  output: chan<axis::Frame> out;
  invoke: chan<Invocation<S>> out;
  outcome: chan<Outcome<S>> in;
  // The generated worker must answer exactly once for each accepted invocation.
  config(input: chan<axis::Frame> in, output: chan<axis::Frame> out,
      invoke: chan<Invocation<S>> out, outcome: chan<Outcome<S>> in) {
    (input, output, invoke, outcome)
  }
  // Zero is never issued as a handle; initialization precedes external input.
  init { State<S, N> { sequence: u64:1, ..zero!<State<S, N>>() } }
  // A blocked reply suspends this actor; continuations precede the next request.
  next(state: State<S, N>) {
    if state.failure != u32:0 {
      let (pending, index) = first(state.slots, true);
      let (tok, frame) = recv_if(join(), input, !pending, zero!<axis::Frame>());
      let txid = if pending { state.slots[index].txid } else { frame.header.txid };
      let _done = send(tok, output, error_frame(txid, state.failure));
      State<S, N> { slots: if pending { update(state.slots, index, zero!<Slot>()) }
        else { state.slots }, ..state }
    } else {
      let external = state.initialized && state.continuation == u8:0;
      let (tok, frame) = recv_if(join(), input, external, zero!<axis::Frame>());
      let calls = C3 ++ C2 ++ C1 ++ C0;
      let call = external && ((calls >> frame.header.op as u32) as bool);
      let (free, index) = first(state.slots, false);
      let duplicate = for (i, duplicate): (u32, bool) in u32:0..N {
        duplicate || (state.slots[i].handle != u64:0 && state.slots[i].txid == frame.header.txid)
      }(false);
      let exhausted = state.sequence == u64:0x0100000000000000;
      let protocol = call && (duplicate || frame.header.txid == u8:255);
      if protocol || (call && exhausted) {
        let code = if protocol { u32:18 } else { u32:17 };
        // Existing ownership receives one failure per transaction, never a duplicate completion.
        let _done = send_if(tok, output, !duplicate, error_frame(frame.header.txid, code));
        State<S, N> { failure: code, ..state }
      } else if call && !free {
        let _done = send(tok, output, error_frame(frame.header.txid, u32:16));
        state
      } else {
        let from = if call { (state.sequence << u32:8) | frame.header.op as u64 } else { u64:0 };
        let slots = if call { update(state.slots, index, Slot { handle: from, txid: frame.header.txid }) }
          else { state.slots };
        let tok = send(tok, invoke, Invocation<S> { state: state.data, frame, from,
          continuation: state.continuation, initialize: !state.initialized });
        let (tok, result) = recv(tok, outcome);
        let (reply, reply_index) = lookup(slots, result.from);
        let contract_fault = reply && result.reply.header.op != u8:0 && !result.reply_allowed;
        let error = if result.error != u32:0 { result.error }
          else if contract_fault { u32:15 } else { u32:0 };
        let reply = reply && result.reply.header.op != u8:0 && error == u32:0;
        let response = axis::Frame { header: axis::Header {
          txid: slots[reply_index].txid, ..result.reply.header }, ..result.reply };
        let tok = send_if(tok, output, reply, response);
        // A failed cast has no retained slot; its reserved transaction gets the fault too.
        let _done = send_if(tok, output, error != u32:0 && external && !call,
          error_frame(frame.header.txid, error));
        State<S, N> {
          data: if error == u32:0 { result.state } else { state.data },
          slots: if reply { update(slots, reply_index, zero!<Slot>()) } else { slots },
          sequence: state.sequence + call as u64, initialized: true,
          continuation: result.continuation, failure: error,
        }
      }
    }
  }
}
