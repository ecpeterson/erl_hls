// Preserve each source lane's window order, including several aliased output ports.
import axis;

// MULTIPLICITY is the number of prefix messages this source sends to this destination.
// Each output has two frame slots. The receiver joins one head from every fragment.
pub proc Split<MULTIPLICITY: u32> {
  incoming: chan<axis::Frame> in;
  fragments: chan<axis::Frame>[MULTIPLICITY] out;
  // Bind one ordered lane to its consecutive positions within every opening prefix.
  config(incoming: chan<axis::Frame> in, fragments: chan<axis::Frame>[MULTIPLICITY] out) {
    (incoming, fragments)
  }
  // The first frame after reset occupies the first prefix position.
  init { u32:0 }
  // Do not advance a position until its frame is accepted.
  next(position: u32) {
    let (tok, frame) = recv(join(), incoming);
    let _sent = unroll_for! (index, tok): (u32, token) in u32:0..MULTIPLICITY {
      send_if(tok, fragments[index], index == position, frame)
    }(tok);
    if position + u32:1 == MULTIPLICITY { u32:0 } else { position + u32:1 }
  }
}
