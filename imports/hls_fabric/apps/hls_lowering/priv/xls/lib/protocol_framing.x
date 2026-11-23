// Common routed-word mechanics. Payload capacity B is a multiple of 32, at most 480 bits.
// Owners decide when to accept a beat and when to clear a completed frame.
pub struct Receive<B: u32> {
  stage: u2, header: u32, payload: bits[B], seen: u4, bad: bool, full: bool,
}
// Drain malformed input through TLAST; saturating assembly cannot wrap into a valid frame.
pub fn receive<B: u32>(s: Receive<B>, word: u32, last: bool, host: u16, service: u16) -> Receive<B> {
  let capacity = (B / u32:32) as u4;
  let next = match s.stage {
    u2:0 => Receive<B> { stage: u2:1, bad: word != (host ++ service) || last, ..s },
    u2:1 => Receive<B> { stage: u2:2, header: word,
      bad: s.bad || word[0+:u8] == u8:0 || word[0+:u8] > capacity as u8 || word[8+:u16] != u16:0 || last, ..s },
    _ => {
      let accept = !s.bad && s.seen < capacity;
      let seen = s.seen + accept as u4;
      Receive<B> { seen,
        payload: if accept { bit_slice_update(s.payload, s.seen as u32 * u32:32, word) } else { s.payload },
        bad: s.bad || !accept || last != (seen as u8 == s.header[0+:u8]), ..s }
    },
  };
  Receive<B> { full: last, ..next }
}
// Current serialized output depends only on the retained frame and its beat position.
pub fn word<B: u32>(header: u32, payload: bits[B], position: u4, source: u16, host: u16) -> u32 {
  match position {
    u4:0 => source ++ host,
    u4:1 => header,
    _ => (payload >> ((position as u32 - u32:2) * u32:32)) as u32,
  }
}
// The header counts payload words; route and header precede them.
pub fn last(header: u32, position: u4) -> bool { position as u8 == header[0+:u8] + u8:1 }
