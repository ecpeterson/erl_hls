import axis;
import retained_mux;

// Finite witness: a singleton mux retains primitive values while its output stalls.
#[test_proc]
proc PrimitiveSingletonTest {
  done: chan<bool> out;
  input: chan<u16> out;
  output: chan<u16> in;
  // Two queued inputs let the witness defer every output read until after writing.
  config(done: chan<bool> out) {
    let (input_p, input_c) = chan<u16, u32:2>[1]("primitive_input");
    let (output_p, output_c) = chan<u16, u32:0>("primitive_output");
    spawn retained_mux::Mux<u16, u32:1>(input_c, output_p);
    (done, input_p[u32:0], output_c)
  }
  // The witness runs once and keeps no state between activations.
  init { () }
  // Include zero data so validity cannot be inferred from payload bits.
  next(state: ()) {
    let tok = send(join(), input, u16:0);
    let tok = send(tok, input, u16:65535);
    let (tok, first) = recv(tok, output);
    let (tok, second) = recv(tok, output);
    assert_eq(first, u16:0);
    assert_eq(second, u16:65535);
    let _done = send(tok, done, true);
    state
  }
}

// Finite witness: imported frame types retain per-sender order across three lanes.
#[test_proc]
proc FramedThreeLaneTest {
  done: chan<bool> out;
  input: chan<axis::Frame>[3] out;
  output: chan<axis::Frame> in;
  // The unbuffered output applies backpressure while all input lanes are filled.
  config(done: chan<bool> out) {
    let (input_p, input_c) = chan<axis::Frame, u32:2>[3]("framed_input");
    let (output_p, output_c) = chan<axis::Frame, u32:0>("framed_output");
    spawn retained_mux::Mux<axis::Frame, u32:3>(input_c, output_p);
    (done, input_p, output_c)
  }
  // All finite history lives in this witness's one activation.
  init { () }
  // Require both values from every lane, allowing arbitrary cross-sender order.
  next(state: ()) {
    let tok = unroll_for! (lane, tok): (u32, token) in u32:0..u32:3 {
      let tok = send(tok, input[lane], axis::pack(lane as u8, u32:0));
      send(tok, input[lane], axis::pack(lane as u8, u32:1))
    }(join());
    let (tok, counts) = unroll_for! (_, acc): (u32, (token, u32[3])) in u32:0..u32:6 {
      let (tok, frame) = recv(acc.0, output);
      let lane = frame.header.op as u32;
      assert_eq(lane < u32:3, true);
      assert_eq(frame, axis::pack(lane as u8, acc.1[lane]));
      (tok, update(acc.1, lane, acc.1[lane] + u32:1))
    }((tok, u32[3]:[u32:0, ...]));
    assert_eq(counts, u32[3]:[u32:2, ...]);
    let _done = send(tok, done, true);
    state
  }
}
