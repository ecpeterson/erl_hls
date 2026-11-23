// Routed word framing for independently backpressured domain management/application lanes.
// Every buffer holds one finite packet; owners decide when to consume or transmit it.
pub struct Packet<B: u32> { route: u32, header: u32, payload: bits[B] }
// Malformed input drains through TLAST without wrapping its retained length.
pub struct Receive<B: u32> {
  packet: Packet<B>, stage: u2, seen: u32, bad: bool, full: bool,
}
// One accepted beat advances this lane only; callers stop accepting while full.
pub fn receive<B: u32>(s: Receive<B>, word: u32, last: bool) -> Receive<B> {
  let next = match s.stage {
    u2:0 => Receive<B> { packet: Packet<B> { route: word, ..s.packet }, stage: u2:1, bad: last, ..s },
    u2:1 => Receive<B> { packet: Packet<B> { header: word, ..s.packet }, stage: u2:2,
      bad: s.bad || word[0+:u8] as u32 > B/u32:32 || last != (word[0+:u8] == u8:0), ..s },
    _ => {
      let accept = !s.bad && s.seen < B/u32:32 && s.seen < s.packet.header[0+:u8] as u32;
      let seen = s.seen + accept as u32;
      Receive<B> { seen,
        packet: Packet<B> { payload: if accept { bit_slice_update(s.packet.payload, s.seen*u32:32, word) } else { s.packet.payload }, ..s.packet },
        bad: s.bad || !accept || last != (seen == s.packet.header[0+:u8] as u32), ..s }
    },
  };
  Receive<B> { full: last, ..next }
}
// Position zero is the route, one the canonical header, then little-word-order payload.
pub fn word<B: u32>(packet: Packet<B>, position: u32) -> u32 {
  match position { u32:0 => packet.route, u32:1 => packet.header,
    _ => (packet.payload >> ((position-u32:2)*u32:32)) as u32 }
}
// Payload length is at most 255; the u32 cursor cannot wrap within a packet.
pub fn last<B: u32>(packet: Packet<B>, position: u32) -> bool {
  position == packet.header[0+:u8] as u32 + u32:1
}
// Replacement of header operation/length preserves the broker transaction and flags.
pub fn header(original: u32, operation: u8, words: u8) -> u32 {
  (operation as u32 << u32:24) | (original & u32:0x00ffff00) | words as u32
}
