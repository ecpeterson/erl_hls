// Reset-owned framed source partition. Trusted peers retire all deployment transports before
// coordinated reset; sessions identify incarnations, not authenticated principals.
// One RX frame and one immutable TX frame. No replay after ambiguous delivery.

import protocol_framing as framing;
import protocol_envelope as envelope;

// Canonical remote data or a final-delivery acknowledgment/credit.
pub type Packet = envelope::Packet;
// Exact ABI: low bits hold the ordinary destination frame.
pub fn unpack(value: bits[256]) -> Packet { envelope::unpack_packet(value) }
// The shared schema supplies the wire layout used by the Erlang peer.
pub fn pack(p: Packet) -> bits[256] { envelope::pack_packet(p) }
// One selected native source, observed before any retirement on this edge.
pub struct Offer { valid: bool, slot: u8, frame: bits[128] }
// Credit identity and native free observation; never a duplicated payload.
pub struct Credit { link: u16, slot: u8, free: bool }
// Outbound reservation spans physical transmission and the exact peer ACK.
pub struct Owner { blocked: bool, sent: bool, sequence: u32, slot: u8 }
// Saturating receive assembly; malformed frames terminate at their TLAST.
pub type Receive = framing::Receive<320>;
// A held frame is never replaced on its final physical beat.
pub struct Transmit { full: bool, header: u32, payload: bits[256], position: u4, actor: bool, source: u16 }
// Every sequence is nonwrapping; reset cancels all ownership only after retirement.
pub struct State<I: u32, C: u32, O: u32> {
  rx: Receive, tx: Transmit, attached: bool, session: u64, started: bool, fault: bool,
  incoming_sequence: u32[I], issued: bool[C], owners: Owner[O], event_sequence: u32, cursor: u16,
}
// Clock samples; ready is ordinary data, never a stall of the whole XLS proc.
pub struct Inputs<I: u32, C: u32, O: u32, E: u32> {
  reset: bool, retire: bool, child_fault: bool, word: u32, last: bool, valid: bool, ready: bool,
  incoming_links: u16[I], incoming_ready: bool[I], credits: Credit[C],
  outgoing_links: u16[O], outgoing: Offer[O], externals: Offer[E],
  control_legal: bool, control_ready: bool, start_ready: bool,
}
// Only one incoming class or outgoing event transfers in one clock.
pub struct Outputs<I: u32, O: u32, E: u32> {
  ready: bool, valid: bool, word: u32, last: bool, fault: bool, active: bool,
  packet: Packet, incoming_valid: bool[I], outgoing_ready: bool[O], external_ready: bool[E],
  control_valid: bool, start_valid: bool,
}
// State and pre-edge pin observations remain distinct.
pub struct Tick<I: u32, C: u32, O: u32, E: u32> { state: State<I,C,O>, output: Outputs<I,O,E> }
// Selection identifies one contender before copying any payload.
struct Selection { valid: bool, index: u32 }
// Validated receive classes and matching owners, all observed before this edge.
struct Reception<I: u32, C: u32, O: u32> {
  packet: Packet, attach: bool, setup: bool, start: bool, data: bool, ack: bool, bad: bool,
  inputs: bool[I], credits: bool[C], acknowledgments: bool[O],
}
// Reply priority, output reservation and physical completion are separate decisions.
struct Transmission {
  attach_reply: bool, start_reply: bool, grant: Selection, credit: bool, actor: bool,
  last: bool, sent: bool,
}

// Round-robin arbitration passes blocked links without reordering one link's messages.
fn select<C: u32, O: u32, E: u32>(cursor: u16, issued: bool[C], owners: Owner[O],
    credits: Credit[C], outgoing: Offer[O], externals: Offer[E]) -> Selection {
  let count = C + O + E;
  for (k, choice): (u32, Selection) in u32:0..count {
    let sum = cursor as u32 + k;
    let index = if sum >= count { sum - count } else { sum };
    let valid = if index < C {
      credits[index].free && !issued[index]
    } else if index < C + O {
      outgoing[index - C].valid && !owners[index - C].blocked
    } else {
      externals[index - C - O].valid
    };
    if !choice.valid && valid { Selection { valid: true, index } } else { choice }
  }(zero!<Selection>())
}

// A completed frame is legal only against the old session, credit and sequence state.
// DATA requires native readiness; SETUP and START instead wait for their handshakes.
fn inspect_receive<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    identity: bits[256], live: bool) -> Reception<I,C,O> {
  let packet = unpack(s.rx.payload as bits[256]);
  let op = s.rx.header[24+:u8];
  let words = s.rx.header[0+:u8];
  let complete = live && s.rx.full && !s.rx.bad;
  let attach = complete && op == u8:1 && words == u8:10 && !s.attached &&
    s.rx.payload[0+:u64] != u64:0 && s.rx.payload[64+:bits[256]] == identity;
  let same_session = s.attached && s.rx.payload[0+:u64] == s.session;
  let setup = complete && op == u8:2 && same_session && io.control_legal;
  let start = complete && op == u8:3 && same_session && words == u8:3 && !s.started &&
    s.rx.payload[64+:bits[256]] == bits[256]:0;
  let envelope = complete && op == u8:4 && words == u8:8 && s.attached && packet.session == s.session;
  let inputs = for (i, matches): (u32, bool[I]) in u32:0..I {
    update(matches, i, io.incoming_links[i] == packet.link)
  }(bool[I]:[false,...]);
  let credits = for (i, matches): (u32, bool[C]) in u32:0..C {
    update(matches, i, io.credits[i].link == packet.link && io.credits[i].slot == packet.slot &&
      s.issued[i] && io.credits[i].free)
  }(bool[C]:[false,...]);
  let input_ready = for (i, ready): (u32, bool) in u32:0..I {
    ready || (inputs[i] && io.incoming_ready[i])
  }(false);
  let credited = for (i, any): (u32, bool) in u32:0..C { any || credits[i] }(false);
  let sequence_ok = for (i, matches): (u32, bool) in u32:0..I {
    matches || (inputs[i] && s.incoming_sequence[i] == packet.sequence && packet.sequence != u32:0xffffffff)
  }(false);
  let acknowledgments = for (i, matches): (u32, bool[O]) in u32:0..O {
    let owner = s.owners[i];
    update(matches, i, io.outgoing_links[i] == packet.link && owner.blocked && owner.sent &&
      owner.sequence == packet.sequence && owner.slot == packet.slot)
  }(bool[O]:[false,...]);
  let known_ack = for (i, any): (u32, bool) in u32:0..O { any || acknowledgments[i] }(false);
  let data = envelope && packet.kind == u8:1 && credited && input_ready && sequence_ok;
  let ack = envelope && packet.kind == u8:2 && packet.frame == bits[128]:0 && known_ack;
  let legal = attach || setup || start || data || ack;
  Reception { packet, attach, setup, start, data, ack, inputs, credits, acknowledgments,
    bad: live && s.rx.full && !legal }
}

// Replies outrank new grants. Neither a final TX beat nor an ACK can free capacity
// for selection on this edge: arbitration uses the original issued/owner arrays.
fn decide_transmit<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    rx: Reception<I,C,O>, enabled: bool) -> Transmission {
  let choice = select(s.cursor, s.issued, s.owners, io.credits, io.outgoing, io.externals);
  let grant = Selection { valid: enabled && s.attached && !s.tx.full && !(rx.attach || rx.start) &&
    choice.valid && s.event_sequence != u32:0xffffffff, ..choice };
  let last = framing::last(s.tx.header, s.tx.position);
  Transmission {
    attach_reply: rx.attach && !s.tx.full,
    start_reply: rx.start && !s.tx.full && io.start_ready,
    grant, credit: choice.index < C, actor: choice.index >= C && choice.index < C + O,
    last, sent: enabled && s.tx.full && io.ready && last,
  }
}

// RX holds a complete waiting command; consuming it cannot accept another beat.
fn next_receive<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    rx: Reception<I,C,O>, tx: Transmission, live: bool, host: u16, service: u16) -> Receive {
  let consume = tx.attach_reply || tx.start_reply || (rx.setup && io.control_ready) || rx.data || rx.ack;
  if consume {
    zero!<Receive>()
  } else if live && !s.rx.full && io.valid {
    framing::receive(s.rx, io.word, io.last, host, service)
  } else { s.rx }
}

// Copy exactly the selected offer into the sole TX reservation. External events
// have their own envelope and do not allocate an actor owner or sequence number.
fn reserve_transmit<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    tx: Transmission) -> Transmit {
  let index = tx.grant.index;
  let reserved = Transmit { full: true, actor: tx.actor, source: (index - C) as u16, ..zero!<Transmit>() };
  if tx.credit || tx.actor {
    let packet = if tx.credit {
      Packet { kind: u8:2, session: s.session, sequence: s.event_sequence,
        link: io.credits[index].link, slot: io.credits[index].slot, frame: bits[128]:0 }
    } else {
      Packet { kind: u8:1, session: s.session, sequence: s.event_sequence,
        link: io.outgoing_links[index - C], slot: io.outgoing[index - C].slot, frame: io.outgoing[index - C].frame }
    };
    Transmit { header: u32:0x84000008, payload: pack(packet), ..reserved }
  } else {
    Transmit { header: u32:0x85000006 | ((index - C - O) << u32:8),
      payload: (io.externals[index - C - O].frame ++ s.session) as bits[256], ..reserved }
  }
}

// Retain a stalled output byte-for-byte. Clearing its final beat never refills TX.
fn next_transmit<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    tx: Transmission, enabled: bool) -> Transmit {
  if tx.attach_reply || tx.start_reply {
    Transmit { full: true, header: if tx.attach_reply { u32:0x81000002 } else { u32:0x83000003 },
      payload: if tx.attach_reply { s.rx.payload as u64 as bits[256] } else { s.session as bits[256] },
      ..zero!<Transmit>() }
  } else if tx.grant.valid {
    reserve_transmit(s, io, tx)
  } else if enabled && s.tx.full && io.ready {
    Transmit { full: !tx.last, position: if tx.last { u4:0 } else { s.tx.position + u4:1 }, ..s.tx }
  } else { s.tx }
}

// ACK releases only the exact old sent reservation. A new grant records its own
// source slot/sequence; physical completion marks sent without releasing ownership.
fn next_owners<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    rx: Reception<I,C,O>, tx: Transmission) -> Owner[O] {
  for (i, owners): (u32, Owner[O]) in u32:0..O {
    let owner = if rx.ack && rx.acknowledgments[i] {
      zero!<Owner>()
    } else {
      Owner { sent: s.owners[i].sent || (tx.sent && s.tx.actor && s.tx.source == i as u16), ..s.owners[i] }
    };
    update(owners, i, if tx.grant.valid && tx.actor && tx.grant.index - C == i {
      Owner { blocked: true, sent: false, sequence: s.event_sequence, slot: io.outgoing[i].slot }
    } else { owner })
  }(s.owners)
}

// Commit once from the old state and the already chosen transfers. Reset has final
// priority; retirement/failure is sticky and does not silently discard reservations.
fn commit<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    rx: Reception<I,C,O>, tx: Transmission, live: bool, enabled: bool, host: u16, service: u16) -> State<I,C,O> {
  let issued = for (i, issued): (u32, bool[C]) in u32:0..C {
    update(issued, i, (s.issued[i] && !(rx.data && rx.credits[i])) ||
      (tx.grant.valid && tx.credit && tx.grant.index == i))
  }(s.issued);
  let incoming_sequence = for (i, sequences): (u32, u32[I]) in u32:0..I {
    update(sequences, i, s.incoming_sequence[i] + (rx.data && rx.inputs[i]) as u32)
  }(s.incoming_sequence);
  let next = State<I,C,O> {
    rx: next_receive(s, io, rx, tx, live, host, service), tx: next_transmit(s, io, tx, enabled),
    owners: next_owners(s, io, rx, tx), issued, incoming_sequence,
    attached: s.attached || tx.attach_reply,
    session: if tx.attach_reply { s.rx.payload as u64 } else { s.session },
    started: s.started || tx.start_reply,
    fault: s.fault || io.retire || io.child_fault || rx.bad ||
      (s.attached && s.event_sequence == u32:0xffffffff && !s.tx.full),
    event_sequence: s.event_sequence + (tx.grant.valid && (tx.credit || tx.actor)) as u32,
    cursor: if tx.grant.valid {
      if tx.grant.index + u32:1 == C + O + E { u16:0 } else { (tx.grant.index + u32:1) as u16 }
    } else { s.cursor },
  };
  if io.reset { zero!<State<I,C,O>>() } else { next }
}

// Current pins expose the retained frame and accepted old-state offers, never the
// next state. A newly assembled input or newly reserved output appears next cycle.
fn observe_outputs<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    rx: Reception<I,C,O>, tx: Transmission, live: bool, enabled: bool, host: u16, service: u16) -> Outputs<I,O,E> {
  Outputs<I,O,E> {
    ready: live && !s.rx.full, valid: enabled && s.tx.full,
    word: framing::word(s.tx.header, s.tx.payload, s.tx.position, service, host), last: tx.last,
    fault: !io.reset && (s.fault || io.retire || io.child_fault || rx.bad),
    active: enabled && s.attached, packet: rx.packet,
    incoming_valid: for (i, valid): (u32, bool[I]) in u32:0..I {
      update(valid, i, rx.data && rx.inputs[i])
    }(bool[I]:[false,...]),
    outgoing_ready: for (i, ready): (u32, bool[O]) in u32:0..O {
      update(ready, i, tx.grant.valid && tx.actor && tx.grant.index - C == i)
    }(bool[O]:[false,...]),
    external_ready: for (i, ready): (u32, bool[E]) in u32:0..E {
      update(ready, i, tx.grant.valid && tx.grant.index == C + O + i)
    }(bool[E]:[false,...]),
    control_valid: rx.setup && enabled, start_valid: rx.start && enabled && !s.tx.full,
  }
}

// One sampled edge: validate RX, choose TX using old ownership, then commit and
// observe separately. These pure helpers introduce no state or pipeline stages.
pub fn tick<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    identity: bits[256], host: u16, service: u16) -> Tick<I,C,O,E> {
  let live = !io.reset && !io.retire && !io.child_fault && !s.fault;
  let rx = inspect_receive(s, io, identity, live);
  let enabled = live && !rx.bad;
  let tx = decide_transmit(s, io, rx, enabled);
  Tick {
    state: commit(s, io, rx, tx, live, enabled, host, service),
    output: observe_outputs(s, io, rx, tx, live, enabled, host, service),
  }
}
