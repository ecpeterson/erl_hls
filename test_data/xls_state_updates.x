// Six independently addressed words whose stored values are always eight bits.
// The wide interface makes removal of the constant high bits observable in IR.
pub proc Rows {
  command: chan<(u3, u8)> in;
  result: chan<u32> out;

  // Each accepted command reads the selected old word before replacing it.
  config(command: chan<(u3, u8)> in, result: chan<u32> out) {
    (command, result)
  }

  // Every row starts empty; no input can introduce a nonzero high bit.
  init { u32[6]:[u32:0, ...] }

  // XLS clamps an out-of-range read and ignores an out-of-range update.
  next(state: u32[6]) {
    let (tok, (index, value)) = recv(join(), command);
    send(tok, result, state[index]);
    update(state, index, value as u32)
  }
}
