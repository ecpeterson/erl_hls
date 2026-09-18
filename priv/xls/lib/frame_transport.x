// Frame transport shared by explicit, family, and scheduler topologies.
// Array muxes poll exactly one input per activation, even when it is empty.
// Blocking output preserves the selected frame and cursor under backpressure.
// Grid dimensions are inner-to-outer: frame_in[x][y].

import axis;

// Counts and grid dimensions are positive; the caller chooses grid FIFO depth.

// Forward complete frames in order; a stalled output backpressures the input.
pub proc FrameRelay {
  frame_in: chan<axis::Frame> in;
  frame_out: chan<axis::Frame> out;

  // Bind the upstream source and downstream destination.
  config(
      frame_in: chan<axis::Frame> in,
      frame_out: chan<axis::Frame> out
  ) {
    (frame_in, frame_out)
  }

  // Start with no retained application state.
  init { () }

  // Complete one receive/send pair before accepting another frame.
  next(state: ()) {
    let (tok, frame) = recv(join(), frame_in);
    let _done = send(tok, frame_out, frame);
    state
  }
}

// Poll one input per activation in round-robin order, including empty inputs.
// INPUT_COUNT must be positive; a selected frame blocks further polling until sent.
pub proc FrameArrayMux<INPUT_COUNT: u32> {
  frame_in: chan<axis::Frame>[INPUT_COUNT] in;
  frame_out: chan<axis::Frame> out;

  // Bind all input lanes to the one ordered output.
  config(
      frame_in: chan<axis::Frame>[INPUT_COUNT] in,
      frame_out: chan<axis::Frame> out
  ) {
    (frame_in, frame_out)
  }

  // Start polling at input zero.
  init { u32:0 }

  // Poll the current lane and forward any frame before advancing the cursor.
  next(cursor: u32) {
    let (tok, received, frame) =
      unroll_for! (candidate, acc):
          (u32, (token, u1, axis::Frame)) in u32:0..INPUT_COUNT {
        let selected = cursor == candidate;
        let (next_tok, next_frame, valid) = recv_if_non_blocking(
          acc.0,
          frame_in[candidate],
          selected,
          zero!<axis::Frame>());
        (
          next_tok,
          acc.1 | valid,
          if valid { next_frame } else { acc.2 }
        )
      }((join(), u1:0, zero!<axis::Frame>()));
    let _done = send_if(tok, frame_out, received, frame);
    if cursor + u32:1 == INPUT_COUNT {
      u32:0
    } else {
      cursor + u32:1
    }
  }
}

// Merge frame_in[x][y] with bounded column queues and per-stage round-robin polling.
// Both dimensions must be positive. Per-input order is preserved, with no global
// arrival order or equal service-rate guarantee between rows and columns.
pub proc FrameGridMux<GRID_WIDTH: u32, GRID_HEIGHT: u32, CHANNEL_DEPTH: u32> {
  // Connect every grid lane, using CHANNEL_DEPTH for each column queue.
  config(
      frame_in: chan<axis::Frame>[GRID_HEIGHT][GRID_WIDTH] in,
      frame_out: chan<axis::Frame> out
  ) {
    let (column_p, column_c) =
      chan<axis::Frame, CHANNEL_DEPTH>[GRID_WIDTH]("grid_column");
    unroll_for! (x, _): (u32, ()) in u32:0..GRID_WIDTH {
      spawn FrameArrayMux<GRID_HEIGHT>(frame_in[x], column_p[x]);
    }(());
    spawn FrameArrayMux<GRID_WIDTH>(column_c, frame_out);
    ()
  }

  // Retain no state beyond the child muxes.
  init { () }
  // Leave all polling and forwarding to the child muxes.
  next(state: ()) { state }
}

// Check relay order through a bufferless output.
#[test_proc]
proc RelayPreservesFramesTest {
  done: chan<bool> out;
  input: chan<axis::Frame> out;
  output: chan<axis::Frame> in;

  // Connect the relay between a buffered input and bufferless output.
  config(done: chan<bool> out) {
    let (input_p, input_c) = chan<axis::Frame, u32:2>("relay_input");
    let (output_p, output_c) = chan<axis::Frame, u32:0>("relay_output");
    spawn FrameRelay(input_c, output_p);
    (done, input_p, output_c)
  }

  // Start the one-shot witness without retained state.
  init { () }

  // Send two distinct frames and require the same order on receipt.
  next(state: ()) {
    let first = axis::pack(u8:1, u32:11);
    let second = axis::pack(u8:2, u32:22);
    let tok = send(join(), input, first);
    let tok = send(tok, input, second);
    let (tok, actual) = recv(tok, output);
    assert_eq(actual, first);
    let (tok, actual) = recv(tok, output);
    assert_eq(actual, second);
    let _done = send(tok, done, true);
    state
  }
}

// Check progress past empty lanes and retention under output pressure.
#[test_proc]
proc ArrayMuxPollsPastEmptyInputsTest {
  done: chan<bool> out;
  input: chan<axis::Frame>[3] out;
  output: chan<axis::Frame> in;

  // Expose three mux inputs and a bufferless output to the witness.
  config(done: chan<bool> out) {
    let (input_p, input_c) = chan<axis::Frame, u32:2>[3]("mux_input");
    let (output_p, output_c) = chan<axis::Frame, u32:0>("mux_output");
    spawn FrameArrayMux<u32:3>(input_c, output_p);
    (done, input_p, output_c)
  }

  // Start the one-shot witness without retained state.
  init { () }

  // Use only the last lane and require both frames to survive output stalls.
  next(state: ()) {
    let first = axis::pack(u8:3, u32:31);
    let second = axis::pack(u8:3, u32:32);
    // The output has no storage, so the mux must retain its blocked frame.
    // Empty inputs zero and one must not prevent polling input two again.
    let tok = send(join(), input[u32:2], first);
    let tok = send(tok, input[u32:2], second);
    let (tok, actual) = recv(tok, output);
    assert_eq(actual, first);
    let (tok, actual) = recv(tok, output);
    assert_eq(actual, second);
    let _done = send(tok, done, true);
    state
  }
}

// Check that rectangular dimensions neither omit nor duplicate inputs.
#[test_proc]
proc RectangularGridIncludesEveryLaneTest {
  done: chan<bool> out;
  input: chan<axis::Frame>[2][3] out;
  output: chan<axis::Frame> in;

  // Connect all six lanes of a three-by-two grid.
  config(done: chan<bool> out) {
    let (input_p, input_c) = chan<axis::Frame, u32:1>[2][3]("grid_input");
    let (output_p, output_c) = chan<axis::Frame, u32:0>("grid_output");
    spawn FrameGridMux<u32:3, u32:2, u32:1>(input_c, output_p);
    (done, input_p, output_c)
  }

  // Start the one-shot witness without retained state.
  init { () }

  // Send one tagged frame per lane and require every tag exactly once.
  next(state: ()) {
    let tok = unroll_for! (x, tok): (u32, token) in u32:0..u32:3 {
      unroll_for! (y, tok): (u32, token) in u32:0..u32:2 {
        send(tok, input[x][y], axis::pack((x * u32:2 + y) as u8, u32:0))
      }(tok)
    }(join());
    let (tok, seen) = unroll_for! (_, acc): (u32, (token, u6)) in u32:0..u32:6 {
      let (tok, frame) = recv(acc.0, output);
      assert_eq(frame.header.op < u8:6, true);
      let bit = u6:1 << frame.header.op;
      assert_eq(acc.1 & bit, u6:0);
      (tok, acc.1 | bit)
    }((tok, u6:0));
    assert_eq(seen, u6:63);
    let _done = send(tok, done, true);
    state
  }
}
