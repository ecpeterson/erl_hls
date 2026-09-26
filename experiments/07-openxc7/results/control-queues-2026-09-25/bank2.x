import axis;
import frame_queue;
const COUNT = u32:2;
// One combinational bank transition; enabled addresses must be in range.
pub fn main(raw: uN[516], controls: u2,
    pop_source: u32, push_source: u32, payload: uN[128]) -> uN[516] {
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
  let packed = unroll_for! (i, values): (u32, uN[258][COUNT]) in u32:0..COUNT {
    let q = actual[i];
    update(values, i, q.current_valid ++ axis::bits_from_frame(q.current) ++
      q.lookahead_valid ++ axis::bits_from_frame(q.lookahead))
  }(zero!<uN[258][COUNT]>());
  packed as uN[516]
}
