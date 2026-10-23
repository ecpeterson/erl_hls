// Reset-owned framed source partition. Trusted peers retire all deployment transports before
// coordinated reset; sessions identify incarnations, not authenticated principals.
// One RX frame and one immutable TX frame. No replay after ambiguous delivery.

import protocol_framing as framing;

// Canonical remote data or a final-delivery acknowledgment/credit.
pub struct Packet { kind: u8, session: u64, sequence: u32, link: u16, slot: u8, frame: bits[128] }
// Exact ABI: low bits hold the ordinary destination frame.
pub fn unpack(value: bits[256]) -> Packet {
  Packet { kind: value[248+:u8], session: value[184+:u64], sequence: value[152+:u32],
    link: value[136+:u16], slot: value[128+:u8], frame: value[0+:bits[128]] }
}
// The Erlang wire owner uses the same little-endian word layout.
pub fn pack(p: Packet) -> bits[256] { p.kind ++ p.session ++ p.sequence ++ p.link ++ p.slot ++ p.frame }
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
// Round-robin arbitration passes blocked links without reordering one link's messages.
fn select<C: u32, O: u32, E: u32>(cursor: u16, issued: bool[C], owners: Owner[O],
    credits: Credit[C], outgoing: Offer[O], externals: Offer[E]) -> Selection {
  let count = C+O+E;
  for (k,a): (u32,Selection) in u32:0..count {
    let sum = cursor as u32+k; let j = if sum >= count { sum-count } else { sum };
    let valid = if j<C { credits[j].free && !issued[j] }
      else if j<C+O { outgoing[j-C].valid && !owners[j-C].blocked }
      else { externals[j-C-O].valid };
    if !a.valid && valid { Selection { valid:true, index:j } } else { a }
  }(zero!<Selection>())
}
// Session, credit and sequence validation precedes canonical native capture.
// All selectors read old state; simultaneous ACK cannot bypass an old reservation.
pub fn tick<I: u32, C: u32, O: u32, E: u32>(s: State<I,C,O>, io: Inputs<I,C,O,E>,
    identity: bits[256], host: u16, service: u16) -> Tick<I,C,O,E> {
  let live = !io.reset && !io.retire && !io.child_fault && !s.fault;
  let p = unpack(s.rx.payload as bits[256]);
  let op = s.rx.header[24+:u8]; let words = s.rx.header[0+:u8];
  let complete = live && s.rx.full && !s.rx.bad;
  let attach = complete && op == u8:1 && words == u8:10 && !s.attached &&
    s.rx.payload[0+:u64] != u64:0 && s.rx.payload[64+:bits[256]] == identity;
  let same = s.attached && s.rx.payload[0+:u64] == s.session;
  let setup = complete && op == u8:2 && same && io.control_legal;
  let start = complete && op == u8:3 && same && words == u8:3 && !s.started &&
    s.rx.payload[64+:bits[256]] == bits[256]:0;
  let packet = complete && op == u8:4 && words == u8:8 && s.attached && p.session == s.session;
  let input_match = for (i, a): (u32, bool[I]) in u32:0..I { update(a,i,io.incoming_links[i] == p.link) }(bool[I]:[false,...]);
  let credit_match = for (i,a): (u32,bool[C]) in u32:0..C {
    update(a,i,io.credits[i].link == p.link && io.credits[i].slot == p.slot && s.issued[i] && io.credits[i].free)
  }(bool[C]:[false,...]);
  let input_ready = for (i,a): (u32,bool) in u32:0..I { a || (input_match[i] && io.incoming_ready[i]) }(false);
  let credited = for (i,a): (u32,bool) in u32:0..C { a || credit_match[i] }(false);
  let sequence_ok = for (i,a): (u32,bool) in u32:0..I {
    a || (input_match[i] && s.incoming_sequence[i] == p.sequence && p.sequence != u32:0xffffffff)
  }(false);
  let ack_match = for (i,a): (u32,bool[O]) in u32:0..O {
    update(a,i,io.outgoing_links[i] == p.link && s.owners[i].blocked && s.owners[i].sent &&
      s.owners[i].sequence == p.sequence && s.owners[i].slot == p.slot)
  }(bool[O]:[false,...]);
  let known_ack = for (i,a): (u32,bool) in u32:0..O { a || ack_match[i] }(false);
  let data = packet && p.kind == u8:1 && credited && input_ready && sequence_ok;
  let ack = packet && p.kind == u8:2 && p.frame == bits[128]:0 && known_ack;
  let legal = attach || setup || start || data || ack;
  let bad = live && s.rx.full && !legal;
  let can = live && !bad;
  let attach_take = attach && !s.tx.full;
  let start_take = start && !s.tx.full && io.start_ready;
  let setup_take = setup && io.control_ready;
  let consume = attach_take || start_take || setup_take || data || ack;
  let rx = if consume { zero!<Receive>() } else if live && !s.rx.full && io.valid {
    framing::receive(s.rx,io.word,io.last,host,service)
  } else { s.rx };
  let tx_last = framing::last(s.tx.header,s.tx.position);
  let sent = can && s.tx.full && io.ready && tx_last;
  let tx_word = framing::word(s.tx.header,s.tx.payload,s.tx.position,service,host);
  let owners = for (i,a): (u32,Owner[O]) in u32:0..O {
    let owner = if ack && ack_match[i] { zero!<Owner>() } else {
      Owner { sent: s.owners[i].sent || (sent && s.tx.actor && s.tx.source == i as u16), ..s.owners[i] }
    }; update(a,i,owner)
  }(s.owners);
  let issued = for (i,a): (u32,bool[C]) in u32:0..C { update(a,i,s.issued[i] && !(data && credit_match[i])) }(s.issued);
  let sequences = for (i,a): (u32,u32[I]) in u32:0..I {
    update(a,i,s.incoming_sequence[i]+(data && input_match[i]) as u32)
  }(s.incoming_sequence);
  let count = C+O+E;
  let choice = select(s.cursor,s.issued,s.owners,io.credits,io.outgoing,io.externals);
  let grant = can && s.attached && !s.tx.full && !(attach || start) && choice.valid && s.event_sequence != u32:0xffffffff;
  let j = choice.index;
  let is_credit = j<C; let is_actor = j>=C && j<C+O;
  let outbound = if is_credit {
    Packet { kind:u8:2, session:s.session, sequence:s.event_sequence, link:io.credits[j].link,
      slot:io.credits[j].slot, frame:bits[128]:0 }
  } else { Packet { kind:u8:1, session:s.session, sequence:s.event_sequence, link:io.outgoing_links[j-C],
      slot:io.outgoing[j-C].slot, frame:io.outgoing[j-C].frame } };
  let tx = if attach_take || start_take {
    Transmit { full:true, header:if attach_take {u32:0x81000002} else {u32:0x83000003},
      payload:if attach_take {s.rx.payload as u64 as bits[256]} else {s.session as bits[256]}, ..zero!<Transmit>() }
  } else if grant {
    Transmit { full:true, header:if is_credit || is_actor {u32:0x84000008} else {u32:0x85000006 | ((j-C-O)<<u32:8)},
      payload:if is_credit || is_actor {pack(outbound)} else {(io.externals[j-C-O].frame ++ s.session) as bits[256]},
      actor:is_actor, source:(j-C) as u16, ..zero!<Transmit>() }
  } else if can && s.tx.full && io.ready {
    Transmit { full:!tx_last, position:if tx_last {u4:0} else {s.tx.position+u4:1}, ..s.tx }
  } else {s.tx};
  let owners = for (i,a): (u32,Owner[O]) in u32:0..O {
    update(a,i,if grant && is_actor && j-C==i {
      Owner {blocked:true,sent:false,sequence:s.event_sequence,slot:io.outgoing[i].slot}
    } else {a[i]})
  }(owners);
  let issued = for (i,a): (u32,bool[C]) in u32:0..C { update(a,i,a[i] || (grant && is_credit && j==i)) }(issued);
  let next = State<I,C,O> { rx,tx,owners,issued,incoming_sequence:sequences,
    attached:s.attached || attach_take,session:if attach_take {s.rx.payload as u64} else {s.session},
    started:s.started || start_take,
    fault:s.fault || io.retire || io.child_fault || bad || (s.attached && s.event_sequence==u32:0xffffffff && !s.tx.full),
    event_sequence:s.event_sequence+(grant && (is_credit || is_actor)) as u32,
    cursor:if grant {if j+u32:1==count {u16:0} else {(j+u32:1) as u16}} else {s.cursor} };
  Tick { state:if io.reset {zero!<State<I,C,O>>()} else {next}, output:Outputs<I,O,E> {
    ready:live && !s.rx.full,valid:can && s.tx.full,word:tx_word,last:tx_last,
    fault:!io.reset && (s.fault || io.retire || io.child_fault || bad),active:can && s.attached,packet:p,
    incoming_valid:for (i,a): (u32,bool[I]) in u32:0..I {update(a,i,data && input_match[i])}(bool[I]:[false,...]),
    outgoing_ready:for (i,a): (u32,bool[O]) in u32:0..O {update(a,i,grant && is_actor && j-C==i)}(bool[O]:[false,...]),
    external_ready:for (i,a): (u32,bool[E]) in u32:0..E {update(a,i,grant && j==C+O+i)}(bool[E]:[false,...]),
    control_valid:setup && can,start_valid:start && can && !s.tx.full,
  } }
}
