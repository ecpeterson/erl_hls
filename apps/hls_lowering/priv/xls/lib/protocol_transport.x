// Source-local immutable publication and sender-local capture ownership.
// Readiness is sampled data, not a blocking XLS channel shared by recipients.

// One evaluated payload/layout and the remaining per-recipient deliveries.
pub struct Publication<W: u32, D: u32, S: u32> {
  payload: bits[W], pending: bits[D * S], busy: bool,
}

// Each recipient selects its earliest remaining source-ordered delivery.
pub fn publication_view<W: u32, D: u32, S: u32>(
    state: Publication<W, D, S>, reset: bool) -> (bits[D], u8[D]) {
  const_assert!(W > u32:0 && D > u32:0 && S > u32:0 && S <= u32:256);
  unroll_for! (d, result): (u32, (bits[D], u8[D])) in u32:0..D {
    let pending = (state.pending >> (d * S)) as bits[S];
    let index = unroll_for! (s, index): (u32, u8) in u32:0..S {
      if ((pending >> s) as bool) && ((pending & ((bits[S]:1 << s) - bits[S]:1)) == bits[S]:0) {
        s as u8
      } else { index }
    }(u8:0);
    let valid = !reset && state.busy && pending != bits[S]:0;
    (result.0 | ((valid as bits[D]) << d), update(result.1, d, index))
  }((bits[D]:0, zero!<u8[D]>()))
}

// Accept while idle; retire recipients independently. Last acceptance frees
// the snapshot on the following clock, with no combinational credit bypass.
pub fn publication_next<W: u32, D: u32, S: u32>(state: Publication<W, D, S>,
    reset: bool, valid: bool, payload: bits[W], mask: bits[D * S], ready: bits[D]) -> Publication<W, D, S> {
  let (active, indices) = publication_view(state, reset);
  let remaining = unroll_for! (d, pending): (u32, bits[D * S]) in u32:0..D {
    let retire = ((active & ready) >> d) as bool;
    let selected_bit = bits[D * S]:1 << (d * S + indices[d] as u32);
    if retire { pending & !selected_bit } else { pending }
  }(state.pending);
  if reset { zero!<Publication<W, D, S>>() }
  else if !state.busy && valid { Publication { payload, pending: mask, busy: mask != bits[D * S]:0 } }
  else { Publication { pending: remaining, busy: remaining != bits[D * S]:0, ..state } }
}

// FREE=0, FULL=1, LEASED=2. The payload is readable through last-read release.
pub struct Capture<W: u32> { owner: u2, payload: bits[W] }

// Write only with free credit. Acquisition keeps the value; release frees the
// slot on the next clock. Reset cancels both the value and ownership.
pub fn capture_next<W: u32>(state: Capture<W>, reset: bool, arrive: bool,
    payload: bits[W], acquire: bool, release: bool) -> Capture<W> {
  if reset { zero!<Capture<W>>() }
  else if state.owner == u2:0 && arrive { Capture { owner: u2:1, payload } }
  else if state.owner == u2:1 && acquire { Capture { owner: u2:2, ..state } }
  else if state.owner == u2:2 && release { Capture { owner: u2:0, ..state } }
  else { state }
}

// Entry i*S+j means slot i arrived before slot j, for one sender/recipient.
pub struct Order<S: u32> { pending: bits[S], older: bits[S * S] }

// Select the oldest eligible pending slot, bypassing ineligible postponed
// messages. Legal arrivals establish a strict order within this pair only.
pub fn select<S: u32>(state: Order<S>, reset: bool, eligible: bits[S]) -> bits[S] {
  let candidates = if reset { bits[S]:0 } else { state.pending & eligible };
  unroll_for! (a, selected): (u32, bits[S]) in u32:0..S {
    let blocked = unroll_for! (b, blocked): (u32, bool) in u32:0..S {
      blocked || (((candidates >> b) as bool) && ((state.older >> (b * S + a)) as bool))
    }(false);
    selected | (((!blocked && ((candidates >> a) as bool)) as bits[S]) << a)
  }(bits[S]:0)
}

// Arrive must be one-hot-or-zero and target an absent slot, established by
// capture credit and the single bound source. Acquisitions retire first.
pub fn order_next<S: u32>(state: Order<S>, reset: bool, arrive: bits[S],
    selected: bits[S], take: bool) -> Order<S> {
  let surviving = state.pending & !(if take { selected } else { bits[S]:0 });
  let older = unroll_for! (i, older): (u32, bits[S * S]) in u32:0..S {
    unroll_for! (j, older): (u32, bits[S * S]) in u32:0..S {
      let precedes = ((surviving >> i) as bool) &&
        ((((surviving >> j) as bool) && ((state.older >> (i * S + j)) as bool)) || ((arrive >> j) as bool));
      older | ((precedes as bits[S * S]) << (i * S + j))
    }(older)
  }(bits[S * S]:0);
  if reset { zero!<Order<S>>() } else { Order { pending: surviving | arrive, older } }
}
