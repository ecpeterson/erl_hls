import axis;
import hls_spatial_router as spatial;

// Canonical schema: arbitrary payload bits, exact ordinary header and padding.
pub struct Domain { valid: bool, mask: bits[axis::FRAME_BITS], value: bits[axis::FRAME_BITS] }
// One elaborated recipient at a checked coordinate; absent entries cannot receive.
pub struct Point { present: bool, x: u16, y: u16 }
// One selector's exact source schemas and dense actor-indexed recipient table.
pub struct Target<N: u32, D: u32> { points: Point[N], domains: Domain[D] }
// Checked packet decoding; invalid commands must never enter the pending register.
pub struct Decoded<N: u32> { frame: bits[axis::FRAME_BITS], selected: bits[N], canonical: bool }

// Decode the ordinary flattened SpatialFrame (rectangle, selector, Frame struct).
// N>=1, 1<=T<=4, D>=1, 1<=width,height<=65536; tables come from source binding.
pub fn decode<N: u32, D: u32, T: u32>(packet: bits[axis::FRAME_BITS + u32:66], targets: Target<N,D>[T], width: u32, height: u32) -> Decoded<N> {
  let bounds = spatial::Rectangle { x0: packet[(axis::FRAME_BITS + u32:50)+:u16], y0: packet[(axis::FRAME_BITS + u32:34)+:u16],
    x1: packet[(axis::FRAME_BITS + u32:18)+:u16], y1: packet[(axis::FRAME_BITS + u32:2)+:u16] };
  let selector = packet[axis::FRAME_BITS+:u2];
  let frame = axis::bits_from_frame(axis::Frame { payload: packet[0+:bits[axis::PAYLOAD_BITS]],
    header: axis::Header { payload_words: packet[(axis::PAYLOAD_BITS + u32:24)+:u8], txid: packet[(axis::PAYLOAD_BITS + u32:16)+:u8],
      flags: packet[(axis::PAYLOAD_BITS + u32:8)+:u8], op: packet[axis::PAYLOAD_BITS+:u8] } });
  let bounded = spatial::valid(bounds) && (bounds.x1 as u32) < width && (bounds.y1 as u32) < height;
  for (k, decoded): (u32, Decoded<N>) in u32:0..T {
    let target = targets[k];
    let canonical = for (j, matched): (u32, bool) in u32:0..D {
      let d = target.domains[j]; matched || (d.valid && (frame & d.mask) == d.value)
    }(false);
    let selected = for (j, mask): (u32, bits[N]) in u32:0..N {
      let p = target.points[j];
      mask | (((p.present && spatial::contains(bounds, p.x, p.y)) as bits[N]) << j)
    }(bits[N]:0);
    if (selector as u32) == k { Decoded<N> { frame, selected, canonical: bounded && canonical } }
    else { decoded }
  }(Decoded<N> { frame, selected: bits[N]:0, canonical: false })
}

// One shared immutable frame; each pending bit belongs to an independent inbox.
pub struct State<N: u32> { frame: bits[axis::FRAME_BITS], pending: bits[N], fault: bool }
// Pre-edge observations never depend on the offered command or consume feedback.
pub struct Offer<N: u32> { ready: bool, valid: bits[N], frame: bits[axis::FRAME_BITS], fault: bool }
// Startup enable must reflect only old source state; reset masks all handshakes.
pub fn observe<N: u32>(s: State<N>, reset: bool, enable: bool) -> Offer<N> {
  let active = !reset && enable && !s.fault;
  Offer<N> { ready: active && s.pending == bits[N]:0,
    valid: if active { s.pending } else { bits[N]:0 }, frame: s.frame, fault: !reset && s.fault }
}

// Source consume alone retires a recipient. Reservation/postponement must not be
// connected to consumed. A full command cannot refill on its last-consume edge.
pub fn tick<N: u32>(s: State<N>, reset: bool, enable: bool, valid: bool,
                   decoded: Decoded<N>, consumed: bits[N]) -> State<N> {
  let offer = observe(s, reset, enable);
  if reset { zero!<State<N>>() }
  else if !enable || s.fault { s }
  else if s.pending != bits[N]:0 { State<N> { pending: s.pending & !consumed, ..s } }
  else if valid && offer.ready {
    if decoded.canonical { State<N> { frame: decoded.frame, pending: decoded.selected, fault: false } }
    else { State<N> { fault: true, ..s } }
  } else { s }
}
