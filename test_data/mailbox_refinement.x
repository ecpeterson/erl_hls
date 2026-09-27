import mailbox;

// Legal storage consists of an in-range order array and a distinct live prefix.
pub fn layout<DEPTH: u32>(order: u8[DEPTH], occupied: u8) -> bool {
  occupied as u32 <= DEPTH && unroll_for! (i, valid): (u32, bool) in u32:0..DEPTH {
    valid && order[i] as u32 < DEPTH && unroll_for! (j, distinct):
        (u32, bool) in u32:0..DEPTH {
      distinct && (!(i < j && j < occupied as u32) || order[i] != order[j])
    }(true)
  }(true)
}

// Only live slots may be postponed; reuse must never postpone a new message.
pub fn invariant<DEPTH: u32>(order: u8[DEPTH], occupied: u8,
    postponed: bool[DEPTH]) -> bool {
  layout(order, occupied) && unroll_for! (slot, valid): (u32, bool) in u32:0..DEPTH {
    let live = unroll_for! (i, live): (u32, bool) in u32:0..DEPTH {
      live || (i < occupied as u32 && order[i] as u32 == slot)
    }(false);
    valid && (!postponed[slot] || live)
  }(true)
}

// Independent sequential specification: first unpostponed entry in the live prefix.
pub fn reference<DEPTH: u32>(order: u8[DEPTH], occupied: u8,
    postponed: bool[DEPTH]) -> (bool, u8, u8) {
  unroll_for! (i, choice): (u32, (bool, u8, u8)) in u32:0..DEPTH {
    if !choice.0 && i < occupied as u32 && !postponed[order[i] as u32] {
      (true, i as u8, order[i])
    } else { choice }
  }((false, u8:0, u8:0))
}

// Exact bank selection for every legal row, actor and postponement mask.
pub fn selection<ACTORS: u32, DEPTH: u32>(order: u8[DEPTH][ACTORS],
    occupied: u8[ACTORS], postponed: bool[DEPTH][ACTORS], actor: u32) -> bool {
  let legal = actor < ACTORS && unroll_for! (i, valid):
      (u32, bool) in u32:0..ACTORS {
    valid && layout(order[i], occupied[i])
  }(true);
  let expected = reference(order[actor], occupied[actor], postponed[actor]);
  !legal || (mailbox::select_actor(order, occupied, postponed, actor) == expected &&
    mailbox::select(order[actor], occupied[actor], postponed[actor]) == expected)
}

// An arbitrary retirement followed by optional admission, phase change and reset.
// Low two operation bits select idle/consume/postpone/idle; bits 2/3/4 request
// admission/phase change/reset independently, including consume-plus-append.
// Keeping the selected message stable during execution is a scheduler obligation.
pub fn transition<DEPTH: u32>(order: u8[DEPTH], occupied: u8,
    postponed: bool[DEPTH], operation: u5) -> bool {
  let choice = reference(order, occupied, postponed);
  let consume = operation[0+:u2] == u2:1 && choice.0;
  let postpone = operation[0+:u2] == u2:2 && choice.0;
  let append = operation[2+:u1];
  let clear = operation[3+:u1];
  let reset = operation[4+:u1];
  let original = mailbox::Metadata<u32:1, DEPTH> {
    order: [order], occupied: [occupied], postponed: [postponed],
    ..zero!<mailbox::Metadata<u32:1, DEPTH>>()
  };
  let retired = mailbox::retire(original, u32:0, choice.1, choice.2,
    mailbox::Retirement {valid: true, consume, postpone, phase_boundary: clear,
      ..zero!<mailbox::Retirement>()});
  let admitted = mailbox::reserve_admission(retired.occupied, retired.order,
    retired.mail_candidates, u32:0, [zero!<mailbox::ScheduledRequest>()],
    [append], false, u32:0, false, u32:0);
  let next_order = if reset { zero!<u8[DEPTH]>() } else { admitted.order[u32:0] };
  let next_count = if reset { u8:0 } else { admitted.occupied[u32:0] };
  let next_postponed = if reset { zero!<bool[DEPTH]>() } else { retired.postponed[u32:0] };
  let remaining = occupied - (consume as u8);
  let push = append && remaining as u32 < DEPTH;
  let expected_count = if reset { u8:0 } else { remaining + (push as u8) };
  let prefix_preserved = unroll_for! (i, valid): (u32, bool) in u32:0..DEPTH {
    let old_index = if consume && i >= choice.1 as u32 { i + u32:1 } else { i };
    let retained = !reset && i < remaining as u32;
    valid && (!retained || next_order[i] == order[old_index])
  }(true);
  let fresh = reset || !push || unroll_for! (i, valid): (u32, bool) in u32:0..DEPTH {
    valid && (i >= remaining as u32 || next_order[remaining as u32] != retired.order[u32:0][i])
  }(true);
  let flags = unroll_for! (i, valid): (u32, bool) in u32:0..DEPTH {
    valid && next_postponed[i] == (!reset && !clear &&
      (postponed[i] || (postpone && i == choice.2 as u32)))
  }(true);
  // Base plus arbitrary-state inductive step, not a bounded history sample.
  invariant(zero!<u8[DEPTH]>(), u8:0, zero!<bool[DEPTH]>()) &&
    (!invariant(order, occupied, postponed) ||
      (invariant(next_order, next_count, next_postponed) && next_count == expected_count &&
       (reset || !push || !next_postponed[next_order[remaining as u32] as u32]) &&
       prefix_preserved && fresh && flags && admitted.admission.valid == push))
}
