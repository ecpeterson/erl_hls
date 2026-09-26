import mailbox;
const COUNT = u32:2;
const DEPTH = u32:4;
const ROW_BITS = u32:11 + u32:9 * DEPTH;
// Indexed retirement used before the local-row experiment.
fn reference_retire<ACTOR_COUNT: u32, DEPTH: u32>(
    metadata: mailbox::Metadata<ACTOR_COUNT, DEPTH>, slot: u32,
    order_index: u8, mailbox_index: u8, outcome: mailbox::Retirement)
    -> mailbox::Metadata<ACTOR_COUNT, DEPTH> {
  if !outcome.valid { metadata } else {
    let old_count = metadata.occupied[slot];
    let occupied = if outcome.consume {
      update(metadata.occupied, slot, old_count - u8:1)
    } else { metadata.occupied };
    let order = if outcome.consume {
      update(metadata.order, slot,
        mailbox::compact_order(metadata.order[slot], order_index, old_count))
    } else { metadata.order };
    // A phase boundary clears every postponed message, including the selected
    // one. Otherwise only an explicit postponement changes the bitmap.
    let postponed_row = if outcome.phase_boundary {
      zero!<u1[DEPTH]>()
    } else if outcome.postpone {
      update(metadata.postponed[slot], mailbox_index as u32, u1:1)
    } else { metadata.postponed[slot] };
    let postponed = update(metadata.postponed, slot, postponed_row);
    let (mail_remaining, _, _) = mailbox::select(order[slot], occupied[slot], postponed_row);
    mailbox::Metadata<ACTOR_COUNT, DEPTH> {
      occupied,
      order,
      postponed,
      mail_candidates: update(metadata.mail_candidates, slot,
        mail_remaining && !outcome.failed),
      entry_probes: update(metadata.entry_probes, slot,
        outcome.enter_pending && !outcome.egress_blocked && !outcome.failed),
      egress_waiters: update(metadata.egress_waiters, slot,
        outcome.enter_pending && outcome.egress_blocked && !outcome.failed),
    }
  }
}

// One actor's completed activation updates its own mailbox metadata.
pub fn main(raw: uN[ROW_BITS*COUNT], slot: u32, indices: u16, control: u7) -> bool {
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
  (outcome.valid && slot >= COUNT) || actual == reference_retire(metadata, slot, indices[0+:u8], indices[8+:u8], outcome)
}
