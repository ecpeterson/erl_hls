// Frozen pre-factoring reserve/offer semantics; only shared type definitions come from core.
// Body SHA-256 before type qualification: 0de41e4f7eddb9f8a1f51bf1b2bf6c48c425063ec820802504c1abe95fddc943.
import indexed_collection_core as core;

// Construct the original selected-bank lease without invoking production helpers.
fn ticket<CAPACITY: u32>(
    state: core::State<CAPACITY>, bank: u1) -> core::Lease {
  let selected = state.banks[bank as u32];
  core::Lease { bank, key: selected.key, generation: selected.generation,
    reset_epoch: state.reset_epoch }
}

// Retain the original first-failure rule and zero failure result.
fn fail<CAPACITY: u32>(
    state: core::State<CAPACITY>, error: core::Error)
    -> (core::State<CAPACITY>, core::Result) {
  (core::State<CAPACITY> {
    failure: if state.failure.code == core::Fault::NONE { error } else { state.failure },
    ..state
  }, core::Result { outcome: core::Outcome::FAILED, ..zero!<core::Result>() })
}

// Preserve the original duplicate, capacity and generation decisions.
pub fn reserve<CAPACITY: u32>(
    state: core::State<CAPACITY>, key: u32, candidates: bits[CAPACITY])
    -> (core::State<CAPACITY>, core::Result) {
  let first = state.banks[u32:0];
  let second = state.banks[u32:1];
  let duplicate = (first.status != core::Status::FREE && first.key == key) ||
    (second.status != core::Status::FREE && second.key == key);
  let available = first.status == core::Status::FREE || second.status == core::Status::FREE;
  let slot = if first.status == core::Status::FREE { u1:0 } else { u1:1 };
  let prior = state.banks[slot as u32];
  let fault = if state.failure.code != core::Fault::NONE { state.failure.code }
    else if duplicate { core::Fault::DUPLICATE_RESERVATION }
    else { core::Fault::NONE };
  if fault != core::Fault::NONE {
    fail(state, core::Error { code: fault, key, member: u32:0 })
  } else if !available {
    (state, core::Result { outcome: core::Outcome::WAIT, ..zero!<core::Result>() })
  } else {
    let bank = core::Bank<CAPACITY> { status: core::Status::PROVISIONAL,
      key, candidates, generation: prior.generation + u32:1,
      ..zero!<core::Bank<CAPACITY>>() };
    let next = core::State<CAPACITY> {
      banks: update(state.banks, slot as u32, bank), ..state };
    (next, core::Result { outcome: core::Outcome::ACCEPTED, lease: ticket(next, slot), ..zero!<core::Result>() })
  }
}

// Preserve the original member, deferred-error and write-intent decisions.
pub fn offer<CAPACITY: u32>(
    state: core::State<CAPACITY>, key: u32, member: u32)
    -> (core::State<CAPACITY>, core::Result) {
  let first = state.banks[u32:0];
  let second = state.banks[u32:1];
  let first_key_match = first.status != core::Status::FREE && first.key == key;
  let second_key_match = second.status != core::Status::FREE && second.key == key;
  let slot = if first_key_match { u1:0 } else { u1:1 };
  let bank = state.banks[slot as u32];
  let lease = ticket(state, slot);
  let member_bit = bits[CAPACITY]:1 << member;
  let expected = if bank.status == core::Status::PROVISIONAL { bank.candidates } else { bank.members };
  let fault = if member >= CAPACITY { core::Fault::MEMBER_RANGE }
    else if (expected & member_bit) == bits[CAPACITY]:0 { core::Fault::FOREIGN_MEMBER }
    else if (bank.seen & member_bit) != bits[CAPACITY]:0 { core::Fault::DUPLICATE_MEMBER }
    else if bank.status != core::Status::PROVISIONAL && bank.status != core::Status::OPEN { core::Fault::WRONG_STATUS }
    else { core::Fault::NONE };
  let error = core::Error { code: fault, key, member };
  if state.failure.code != core::Fault::NONE || !(first_key_match || second_key_match) {
    fail(state, core::Error { code: core::Fault::UNRESERVED_KEY, key, member })
  } else if bank.status == core::Status::PROVISIONAL && bank.deferred.code != core::Fault::NONE {
    (state, core::Result { outcome: core::Outcome::WAIT, lease, ..zero!<core::Result>() })
  } else if fault != core::Fault::NONE && bank.status != core::Status::PROVISIONAL {
    fail(state, error)
  } else if fault != core::Fault::NONE {
    (core::State<CAPACITY> { banks: update(state.banks, slot as u32,
      core::Bank<CAPACITY> { deferred: error, ..bank }), ..state },
      core::Result { outcome: core::Outcome::DEFERRED, lease, ..zero!<core::Result>() })
  } else {
    let seen = bank.seen | member_bit;
    let next_bank = core::Bank<CAPACITY> { seen,
      status: if bank.status == core::Status::OPEN && seen == bank.members { core::Status::SEALED }
        else { bank.status }, ..bank };
    (core::State<CAPACITY> { banks: update(state.banks, slot as u32, next_bank), ..state },
      core::Result { outcome: core::Outcome::ACCEPTED, lease,
        write: core::WriteIntent { valid: true, bank: slot, member } })
  }
}

// Reproduce the adapter's existing-key reservation followed by a separate whole-state offer.
pub fn reserve_and_offer<CAPACITY: u32>(
    state: core::State<CAPACITY>, key: u32, candidates: bits[CAPACITY], member: u32)
    -> (core::State<CAPACITY>, core::Result, core::Result) {
  let first = state.banks[u32:0];
  let second = state.banks[u32:1];
  let a = first.status != core::Status::FREE && first.key == key;
  let b = second.status != core::Status::FREE && second.key == key;
  let reservation = if a || b {
    (state, core::Result { outcome: core::Outcome::ACCEPTED,
      lease: ticket(state, if a { u1:0 } else { u1:1 }), ..zero!<core::Result>() })
  } else { reserve(state, key, candidates) };
  if reservation.1.outcome == core::Outcome::WAIT {
    (state, reservation.1, core::Result { outcome: core::Outcome::WAIT, ..zero!<core::Result>() })
  } else {
    let offered = offer(reservation.0, key, member);
    (offered.0, reservation.1, offered.1)
  }
}
