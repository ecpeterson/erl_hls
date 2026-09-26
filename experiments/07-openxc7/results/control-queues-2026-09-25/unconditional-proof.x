import axis;
import frame_queue;
const COUNT = u32:2;
// Reference retains the prior payload-preserving pop, independent of the library.
fn reference_pop(queue: frame_queue::Queue) -> frame_queue::Queue {
  frame_queue::Queue {
    current_valid: queue.lookahead_valid,
    current: if queue.lookahead_valid { queue.lookahead } else { queue.current },
    lookahead_valid: u1:0,
    lookahead: queue.lookahead,
  }
}
// One combinational bank transition; enabled addresses must be in range.
pub fn main(raw: uN[516], controls: u2,
    pop_source: u32, push_source: u32, payload: uN[128]) -> bool {
  let words = raw as uN[258][COUNT];
  let bank = unroll_for! (i, queues): (u32, frame_queue::Queue[COUNT]) in u32:0..COUNT {
    let word = words[i];
    update(queues, i, frame_queue::Queue {
      current_valid: word[257+:u1],
      current: axis::frame_from_bits(word[129+:uN[128]]),
      lookahead_valid: word[128+:u1],
      lookahead: axis::frame_from_bits(word[0+:uN[128]]),
    })
  }(zero!<frame_queue::Queue[COUNT]>());
  let frame = axis::frame_from_bits(payload);
  let actual = frame_queue::update_bank(bank, controls[0+:u1], pop_source,
    controls[1+:u1], push_source, frame);
  let expected = if controls[0+:u1] != u1:0 {
    update(bank, pop_source, reference_pop(bank[pop_source]))
  } else { bank };
  let expected = if controls[1+:u1] != u1:0 {
    update(expected, push_source, frame_queue::push(expected[push_source], frame))
  } else { expected };
  let admitted = (!controls[0+:u1] || pop_source < COUNT) &&
    (!controls[1+:u1] || push_source < COUNT);
  !admitted || unroll_for! (i, equal):
      (u32, bool) in u32:0..COUNT {
    let a = actual[i];
    let b = expected[i];
    equal && a.current_valid == b.current_valid &&
      a.lookahead_valid == b.lookahead_valid &&
      (!a.current_valid || a.current == b.current) &&
      (!a.lookahead_valid || a.lookahead == b.lookahead)
  }(true)
}
