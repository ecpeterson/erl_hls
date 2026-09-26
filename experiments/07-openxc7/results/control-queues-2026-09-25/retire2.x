import mailbox;
const COUNT = u32:2;
const DEPTH = u32:4;
const ROW_BITS = u32:11 + u32:9 * DEPTH;

// One actor's completed activation updates its own mailbox metadata.
pub fn main(raw: uN[ROW_BITS*COUNT], slot: u32, indices: u16, control: u7) -> uN[ROW_BITS*COUNT] {
  let rows = raw as uN[ROW_BITS][COUNT];
  let metadata = unroll_for! (i, m): (u32, mailbox::Metadata<COUNT,DEPTH>) in u32:0..COUNT {
    mailbox::Metadata<COUNT,DEPTH> {
      occupied: update(m.occupied,i,rows[i][0+:u8]),
      order: update(m.order,i,rows[i][8+:uN[DEPTH*u32:8]] as u8[DEPTH]),
      postponed: update(m.postponed,i,rows[i][40+:uN[DEPTH]] as u1[DEPTH]),
      mail_candidates: update(m.mail_candidates,i,rows[i][44+:u1]),
      entry_probes: update(m.entry_probes,i,rows[i][45+:u1]),
      egress_waiters: update(m.egress_waiters,i,rows[i][46+:u1]),
    }
  }(zero!<mailbox::Metadata<COUNT,DEPTH>>());
  let outcome = mailbox::Retirement {
    valid: control[0+:u1], consume: control[1+:u1], postpone: control[2+:u1],
    phase_boundary: control[3+:u1], failed: control[4+:u1],
    enter_pending: control[5+:u1], egress_blocked: control[6+:u1],
  };
  let actual = mailbox::retire(metadata,slot,indices[0+:u8],indices[8+:u8],outcome);
  let packed = unroll_for! (i, words): (u32, uN[ROW_BITS][COUNT]) in u32:0..COUNT {
    update(words, i, actual.egress_waiters[i] ++ actual.entry_probes[i] ++ actual.mail_candidates[i] ++
      (actual.postponed[i] as uN[DEPTH]) ++ (actual.order[i] as uN[DEPTH*u32:8]) ++ actual.occupied[i])
  }(zero!<uN[ROW_BITS][COUNT]>());
  packed as uN[ROW_BITS*COUNT]
}
