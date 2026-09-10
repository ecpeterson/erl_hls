// Two-frame queues used by source-fragment reduction banks.
// Callers establish capacity before pushing. Pop precedes push, including
// when both operations address the same full queue in one activation.

import axis;

pub struct Queue {
  current_valid: u1,
  current: axis::Frame,
  lookahead_valid: u1,
  lookahead: axis::Frame,
}

pub fn pop(queue: Queue) -> Queue {
  Queue {
    current_valid: queue.lookahead_valid,
    current: if queue.lookahead_valid { queue.lookahead } else { queue.current },
    lookahead_valid: u1:0,
    lookahead: queue.lookahead,
  }
}

pub fn push(queue: Queue, frame: axis::Frame) -> Queue {
  if !queue.current_valid {
    Queue { current_valid: u1:1, current: frame, ..queue }
  } else {
    Queue { lookahead_valid: u1:1, lookahead: frame, ..queue }
  }
}

pub fn after_pop(queue: Queue, do_pop: u1) -> Queue {
  if do_pop { pop(queue) } else { queue }
}

pub fn update_bank<COUNT: u32>(
    bank: Queue[COUNT], pop_valid: u1, pop_source: u32,
    push_valid: u1, push_source: u32, push_frame: axis::Frame) -> Queue[COUNT] {
  let after_pop = if pop_valid {
    update(bank, pop_source, pop(bank[pop_source]))
  } else { bank };
  if push_valid {
    update(after_pop, push_source, push(after_pop[push_source], push_frame))
  } else { after_pop }
}

#[test]
fn full_queue_pop_push_preserves_order_test() {
  let first = axis::pack(u8:1, u32:1);
  let second = axis::pack(u8:1, u32:2);
  let third = axis::pack(u8:1, u32:3);
  let full = push(push(zero!<Queue>(), first), second);
  let replaced = update_bank([full], true, u32:0, true, u32:0, third)[u32:0];
  assert_eq(replaced, Queue {
    current_valid: true, current: second,
    lookahead_valid: true, lookahead: third });
  let last = pop(replaced);
  assert_eq(last.current, third);
  assert_eq(last.current_valid, true);
  assert_eq(last.lookahead_valid, false);
  assert_eq(pop(last).current_valid, false);
}

#[test]
fn distinct_bank_updates_leave_other_queues_intact_test() {
  let first = axis::pack(u8:1, u32:1);
  let next = axis::pack(u8:2, u32:2);
  let occupied = push(zero!<Queue>(), first);
  let bank = [occupied, zero!<Queue>(), occupied];
  let updated = update_bank(bank, true, u32:0, true, u32:1, next);
  assert_eq(updated[u32:0].current_valid, false);
  assert_eq(updated[u32:1].current, next);
  assert_eq(updated[u32:1].current_valid, true);
  assert_eq(updated[u32:2], occupied);
  assert_eq(update_bank(bank, false, u32:99, false, u32:99, next), bank);
}

#[test]
fn capacity_is_measured_after_selected_pop_test() {
  let frame = axis::pack(u8:1, u32:0);
  let empty = zero!<Queue>();
  let one = push(empty, frame);
  let full = push(one, frame);
  assert_eq(after_pop(empty, false).lookahead_valid, false);
  assert_eq(after_pop(one, false).lookahead_valid, false);
  assert_eq(after_pop(full, false).lookahead_valid, true);
  assert_eq(after_pop(full, true).lookahead_valid, false);
}
