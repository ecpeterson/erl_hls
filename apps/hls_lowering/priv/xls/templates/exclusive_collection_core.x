// Count received identities without imposing an order on their reduction.
fn collection_count(seen: ReductionMembers) -> ReductionRemaining {
  unroll_for! (index, count): (u32, ReductionRemaining) in u32:0..COLLECTION_MEMBER_COUNT {
    count + ((seen >> index) as u1 as ReductionRemaining)
  }(ReductionRemaining:0)
}

// Decode without actor state or side effects, so producer capture may retain it.
fn collection_decode(frame: axis::Frame) -> CollectionInput {
  CollectionInput { contribution: reduction_transport_contribution(frame),
    frame_valid: collection_frame_valid(frame) }
}

// Apply a held decoded contribution with all epoch, membership and reducer checks.
fn collection_push_input(state: ReductionState, opened: bool, input: CollectionInput)
    -> (ReductionState, hls_failure::Code) {
  let contribution = input.contribution;
  let first = state.status == ReductionStatus::IDLE;
  let member_bit = reduction_member_bit(contribution.site, contribution.member);
  let accepted = input.frame_valid && contribution.valid &&
    (first || (state.site == contribution.site && state.key == contribution.key)) &&
    member_bit != zero!<ReductionMembers>() && (state.seen & member_bit) == zero!<ReductionMembers>() &&
    (!opened || (collection_expected(state) & member_bit) != zero!<ReductionMembers>());
  if !accepted { (state, hls_failure::REDUCTION_PROTOCOL) } else {
    let (value, failure) = if hls_failure::failed(state.failure) {
      (state.accumulator, state.failure)
    } else if first { (contribution.value, hls_failure::NONE) } else {
      reduction_reduce(reduction_site_name(contribution.site), state.accumulator, contribution.value)
    };
    let remaining = if opened { state.remaining - ReductionRemaining:1 } else { ReductionRemaining:0 };
    (ReductionState {
      status: if opened && remaining == ReductionRemaining:0 { ReductionStatus::COMPLETE }
        else { ReductionStatus::OPEN },
      key: contribution.key, site: contribution.site, remaining, seen: state.seen | member_bit,
      accumulator: if hls_failure::failed(failure) { state.accumulator } else { value },
      failure, ..state
    }, hls_failure::NONE)
  }
}

// Reduce one reserved frame without depending on phase, callback data, or ownership.
// An unopened bank binds its epoch on the first arrival; open validates membership.
fn collection_push(state: ReductionState, opened: bool, frame: axis::Frame)
    -> (ReductionState, hls_failure::Code) {
  collection_push_input(state, opened, collection_decode(frame))
}

// Opening combines the actor's initial value with all arrivals, including ones
// accepted after dispatch. A failed reducer still waits for every required member.
fn collection_open(early: ReductionState, opening: ReductionState)
    -> (ReductionState, hls_failure::Code) {
  let live = early.status != ReductionStatus::IDLE;
  let expected = collection_expected(opening);
  let valid = !live || (early.key == opening.key && early.site == opening.site &&
    (early.seen & !expected) == zero!<ReductionMembers>());
  if !valid { (early, hls_failure::REDUCTION_PROTOCOL) } else if !live {
    (opening, hls_failure::NONE)
  } else {
    let failure = hls_failure::first(opening.failure, early.failure);
    let (value, failure) = if hls_failure::failed(failure) { (early.accumulator, failure) }
      else { reduction_reduce(reduction_site_name(opening.site), opening.accumulator, early.accumulator) };
    let remaining = opening.remaining - collection_count(early.seen);
    (ReductionState {
      status: if remaining == ReductionRemaining:0 { ReductionStatus::COMPLETE } else { ReductionStatus::OPEN },
      remaining, seen: early.seen, accumulator: value, failure, ..opening
    }, hls_failure::NONE)
  }
}


// Apply one registered ownership command to a committed collector snapshot.
// Reducer failure remains in the reduction and cannot release missing members.
fn collection_control(bank: CollectionBank, control: CollectionControl) -> CollectionBank {
  let releasing = control.release && bank.opened &&
    bank.reduction.status == ReductionStatus::COMPLETE && bank.reduction.key == control.release_key;
  let release_error = control.release && !releasing;
  let prior = if releasing { zero!<ReductionState>() } else { bank.reduction };
  let still_open = bank.opened && !releasing;
  let checked = collection_open(prior, control.opening);
  let open_error = control.open && (still_open || control.opening.status != ReductionStatus::OPEN);
  let failure = hls_failure::first(bank.failure,
    if release_error || open_error { hls_failure::REDUCTION_PROTOCOL }
    else if control.open { checked.1 } else { hls_failure::NONE });
  CollectionBank {
    reduction: if control.open && !hls_failure::failed(failure) { checked.0 } else { prior },
    opened: still_open || (control.open && !hls_failure::failed(failure)), failure,
  }
}

// Eligibility needs only the held key/classification, never a fresh payload lift.
fn collection_accepts_input(bank: CollectionBank, input: CollectionInput) -> bool {
  let contribution = input.contribution;
  !hls_failure::failed(bank.failure) &&
    !(bank.opened && bank.reduction.status == ReductionStatus::COMPLETE &&
      contribution.valid && contribution.key != bank.reduction.key)
}

// A successor arriving while a completed bank awaits release stays in its input
// slot. Same-epoch duplicates and interleaving into an incomplete bank still fail.
fn collection_accepts(bank: CollectionBank, frame: axis::Frame) -> bool {
  collection_accepts_input(bank, collection_decode(frame))
}

// Direct and shared adapters use the same checked bank transition. Selection
// and control/fold conflict policy belong to the adapter, not to the reducer.
fn collection_fold_input(bank: CollectionBank, input: CollectionInput, valid: bool) -> CollectionBank {
  let pushed = if valid && !hls_failure::failed(bank.failure) {
    collection_push_input(bank.reduction, bank.opened, input)
  } else { (bank.reduction, hls_failure::NONE) };
  CollectionBank { reduction: pushed.0,
    failure: hls_failure::first(bank.failure, pushed.1), ..bank }
}

// Decode an unregistered direct input before applying the common bank transition.
fn collection_fold(bank: CollectionBank, frame: axis::Frame, valid: bool) -> CollectionBank {
  collection_fold_input(bank, collection_decode(frame), valid)
}
