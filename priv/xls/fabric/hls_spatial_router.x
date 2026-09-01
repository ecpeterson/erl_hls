// Hierarchical, rectangle-addressed control routing.
//
// A SpatialFrame is the payload accepted by one externally addressed router
// service; it is not itself an ERTS destination. It carries one ordinary
// application Frame together with an inclusive, non-wrapping rectangle and a
// small topology-owned target selector. Target allocation and interface
// checking belong to the generated deployment; the spatial tree only decides
// which coordinates intersect.
//
// This file implements a tree inside one generated fabric. It does not split a
// global rectangle across FPGA partitions, address remote fabric routers, or
// make a multi-FPGA broadcast atomic. A deployment adapter must intersect the
// rectangle with each local partition and re-originate an explicitly addressed
// command per fabric. Partial delivery, failure, and retry semantics remain
// outside this primitive.
//
// QuadRouter and PairRouter are generated-tree building blocks. Every selected
// child output channel accepts one copy before the router accepts another
// packet during the current router activation.
// Channel depths remain a property of the channels instantiated around these
// procs; the pinned XLS build requires those internal channels to carry
// explicit FIFO metadata.

import axis;

pub struct Rectangle {
  x0: u16,
  y0: u16,
  x1: u16,
  y1: u16,
}

pub struct SpatialFrame {
  rectangle: Rectangle,
  target: u2,
  frame: axis::Frame,
}

pub fn rectangle(x0: u16, y0: u16, x1: u16, y1: u16) -> Rectangle {
  Rectangle { x0, y0, x1, y1 }
}

pub fn valid(bounds: Rectangle) -> u1 {
  bounds.x0 <= bounds.x1 && bounds.y0 <= bounds.y1
}

pub fn intersects(left: Rectangle, right: Rectangle) -> u1 {
  valid(left) && valid(right) &&
    left.x0 <= right.x1 && right.x0 <= left.x1 &&
    left.y0 <= right.y1 && right.y0 <= left.y1
}

pub fn contains(bounds: Rectangle, x: u16, y: u16) -> u1 {
  valid(bounds) &&
    bounds.x0 <= x && x <= bounds.x1 &&
    bounds.y0 <= y && y <= bounds.y1
}

// Splits a nonempty region at (XMID, YMID). The four inclusive child regions
// are [X0..XMID] x [Y0..YMID], [XMID+1..X1] x [Y0..YMID],
// [X0..XMID] x [YMID+1..Y1], and [XMID+1..X1] x [YMID+1..Y1].
// The elaborator must choose strict interior split points.
pub proc QuadRouter<
    X0: u16,
    Y0: u16,
    XMID: u16,
    YMID: u16,
    X1: u16,
    Y1: u16
> {
  spatial_in: chan<SpatialFrame> in;
  child_0_out: chan<SpatialFrame> out;
  child_1_out: chan<SpatialFrame> out;
  child_2_out: chan<SpatialFrame> out;
  child_3_out: chan<SpatialFrame> out;

  config(
      spatial_in: chan<SpatialFrame> in,
      child_0_out: chan<SpatialFrame> out,
      child_1_out: chan<SpatialFrame> out,
      child_2_out: chan<SpatialFrame> out,
      child_3_out: chan<SpatialFrame> out
  ) {
    (spatial_in, child_0_out, child_1_out, child_2_out, child_3_out)
  }

  init { () }

  next(state: ()) {
    let (tok, packet) = recv(join(), spatial_in);
    let child_0 = rectangle(X0, Y0, XMID, YMID);
    let child_1 = rectangle(XMID + u16:1, Y0, X1, YMID);
    let child_2 = rectangle(X0, YMID + u16:1, XMID, Y1);
    let child_3 = rectangle(XMID + u16:1, YMID + u16:1, X1, Y1);
    let tok_0 = send_if(
      tok, child_0_out, intersects(packet.rectangle, child_0), packet);
    let tok_1 = send_if(
      tok, child_1_out, intersects(packet.rectangle, child_1), packet);
    let tok_2 = send_if(
      tok, child_2_out, intersects(packet.rectangle, child_2), packet);
    let tok_3 = send_if(
      tok, child_3_out, intersects(packet.rectangle, child_3), packet);
    let _done = join(tok_0, tok_1, tok_2, tok_3);
    state
  }
}

// Splits a region into two arbitrary inclusive child rectangles. Generated
// trees use this for one-dimensional remnants after a QuadRouter split.
pub proc PairRouter<
    A_X0: u16,
    A_Y0: u16,
    A_X1: u16,
    A_Y1: u16,
    B_X0: u16,
    B_Y0: u16,
    B_X1: u16,
    B_Y1: u16
> {
  spatial_in: chan<SpatialFrame> in;
  child_a_out: chan<SpatialFrame> out;
  child_b_out: chan<SpatialFrame> out;

  config(
      spatial_in: chan<SpatialFrame> in,
      child_a_out: chan<SpatialFrame> out,
      child_b_out: chan<SpatialFrame> out
  ) {
    (spatial_in, child_a_out, child_b_out)
  }

  init { () }

  next(state: ()) {
    let (tok, packet) = recv(join(), spatial_in);
    let child_a = rectangle(A_X0, A_Y0, A_X1, A_Y1);
    let child_b = rectangle(B_X0, B_Y0, B_X1, B_Y1);
    let tok_a = send_if(
      tok, child_a_out, intersects(packet.rectangle, child_a), packet);
    let tok_b = send_if(
      tok, child_b_out, intersects(packet.rectangle, child_b), packet);
    let _done = join(tok_a, tok_b);
    state
  }
}

// Converts one spatial leaf back to the actor's ordinary Frame stream. Target
// selection has already happened before the spatial tree.
pub proc Leaf<X: u16, Y: u16> {
  spatial_in: chan<SpatialFrame> in;
  frame_out: chan<axis::Frame> out;

  config(
      spatial_in: chan<SpatialFrame> in,
      frame_out: chan<axis::Frame> out
  ) {
    (spatial_in, frame_out)
  }

  init { () }

  next(state: ()) {
    let (tok, packet) = recv(join(), spatial_in);
    let selected = contains(packet.rectangle, X, Y);
    let _done = send_if(tok, frame_out, selected, packet.frame);
    state
  }
}

// A coupled two-recipient leaf, used when two actor planes share one spatial
// coordinate system. Both output channels accept the Frame before this leaf
// accepts another packet during the current router activation. This is not an
// actor-mailbox admission or cross-restart delivery guarantee.
pub proc Leaf2<X: u16, Y: u16> {
  spatial_in: chan<SpatialFrame> in;
  frame_a_out: chan<axis::Frame> out;
  frame_b_out: chan<axis::Frame> out;

  config(
      spatial_in: chan<SpatialFrame> in,
      frame_a_out: chan<axis::Frame> out,
      frame_b_out: chan<axis::Frame> out
  ) {
    (spatial_in, frame_a_out, frame_b_out)
  }

  init { () }

  next(state: ()) {
    let (tok, packet) = recv(join(), spatial_in);
    let selected = contains(packet.rectangle, X, Y);
    let a_tok = send_if(tok, frame_a_out, selected, packet.frame);
    let b_tok = send_if(tok, frame_b_out, selected, packet.frame);
    let _done = join(a_tok, b_tok);
    state
  }
}

#[test]
fn rectangle_bounds_are_inclusive_test() {
  let bounds = rectangle(u16:2, u16:3, u16:5, u16:7);
  assert_eq(contains(bounds, u16:2, u16:3), u1:1);
  assert_eq(contains(bounds, u16:5, u16:7), u1:1);
  assert_eq(contains(bounds, u16:1, u16:3), u1:0);
  assert_eq(contains(bounds, u16:5, u16:8), u1:0);
}

#[test]
fn rectangle_intersection_includes_shared_edges_test() {
  let left = rectangle(u16:0, u16:0, u16:2, u16:2);
  let touching = rectangle(u16:2, u16:1, u16:4, u16:3);
  let disjoint = rectangle(u16:3, u16:0, u16:4, u16:1);
  let invalid = rectangle(u16:4, u16:0, u16:3, u16:1);
  assert_eq(intersects(left, touching), u1:1);
  assert_eq(intersects(left, disjoint), u1:0);
  assert_eq(intersects(left, invalid), u1:0);
}

#[test_proc]
proc PairRouterCopiesCrossingRectangleTest {
  terminator: chan<bool> out;
  spatial_out: chan<SpatialFrame> out;
  child_a_in: chan<SpatialFrame> in;
  child_b_in: chan<SpatialFrame> in;

  config(terminator: chan<bool> out) {
    let (spatial_p, spatial_c) =
      chan<SpatialFrame, u32:1>("pair_test_input");
    let (child_a_p, child_a_c) =
      chan<SpatialFrame, u32:1>("pair_test_a");
    let (child_b_p, child_b_c) =
      chan<SpatialFrame, u32:1>("pair_test_b");
    spawn PairRouter<
      u16:0, u16:0, u16:1, u16:0,
      u16:2, u16:0, u16:3, u16:0
    >(spatial_c, child_a_p, child_b_p);
    (terminator, spatial_p, child_a_c, child_b_c)
  }

  init { () }

  next(state: ()) {
    let packet = SpatialFrame {
      rectangle: rectangle(u16:1, u16:0, u16:2, u16:0),
      target: u2:0,
      frame: zero!<axis::Frame>(),
    };
    let sent_tok = send(join(), spatial_out, packet);
    let (a_tok, child_a) = recv(join(), child_a_in);
    let (b_tok, child_b) = recv(join(), child_b_in);
    assert_eq(child_a, packet);
    assert_eq(child_b, packet);
    let _done = send(join(sent_tok, a_tok, b_tok), terminator, true);
    state
  }
}

#[test_proc]
proc QuadRouterSelectsOneLeafTest {
  terminator: chan<bool> out;
  spatial_out: chan<SpatialFrame> out;
  _frame_0_in: chan<axis::Frame> in;
  _frame_1_in: chan<axis::Frame> in;
  _frame_2_in: chan<axis::Frame> in;
  frame_3_a_in: chan<axis::Frame> in;
  frame_3_b_in: chan<axis::Frame> in;

  config(terminator: chan<bool> out) {
    let (spatial_p, spatial_c) =
      chan<SpatialFrame, u32:1>("quad_test_input");
    let (child_0_p, child_0_c) =
      chan<SpatialFrame, u32:1>("quad_test_child_0");
    let (child_1_p, child_1_c) =
      chan<SpatialFrame, u32:1>("quad_test_child_1");
    let (child_2_p, child_2_c) =
      chan<SpatialFrame, u32:1>("quad_test_child_2");
    let (child_3_p, child_3_c) =
      chan<SpatialFrame, u32:1>("quad_test_child_3");
    let (frame_0_p, frame_0_c) =
      chan<axis::Frame, u32:1>("quad_test_frame_0");
    let (frame_1_p, frame_1_c) =
      chan<axis::Frame, u32:1>("quad_test_frame_1");
    let (frame_2_p, frame_2_c) =
      chan<axis::Frame, u32:1>("quad_test_frame_2");
    let (frame_3_a_p, frame_3_a_c) =
      chan<axis::Frame, u32:1>("quad_test_frame_3_a");
    let (frame_3_b_p, frame_3_b_c) =
      chan<axis::Frame, u32:1>("quad_test_frame_3_b");
    spawn QuadRouter<
      u16:0, u16:0, u16:1, u16:1, u16:2, u16:2
    >(spatial_c, child_0_p, child_1_p, child_2_p, child_3_p);
    spawn Leaf<u16:0, u16:0>(
      child_0_c, frame_0_p);
    spawn Leaf<u16:2, u16:0>(
      child_1_c, frame_1_p);
    spawn Leaf<u16:0, u16:2>(
      child_2_c, frame_2_p);
    spawn Leaf2<u16:2, u16:2>(
      child_3_c, frame_3_a_p, frame_3_b_p);
    (
      terminator,
      spatial_p,
      frame_0_c,
      frame_1_c,
      frame_2_c,
      frame_3_a_c,
      frame_3_b_c,
    )
  }

  init { () }

  next(state: ()) {
    let expected = axis::pack(u8:13, u32:0x12345678);
    let packet = SpatialFrame {
      rectangle: rectangle(u16:2, u16:2, u16:2, u16:2),
      target: u2:0,
      frame: expected,
    };
    let sent_tok = send(join(), spatial_out, packet);
    let (a_tok, received_a) = recv(join(), frame_3_a_in);
    let (b_tok, received_b) = recv(join(), frame_3_b_in);
    assert_eq(received_a, expected);
    assert_eq(received_b, expected);
    let _done = send(join(sent_tok, a_tok, b_tok), terminator, true);
    state
  }
}
