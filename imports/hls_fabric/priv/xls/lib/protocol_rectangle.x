// Application control adapter for the existing rectangle ABI; no transport/session state.
import axis;
import hls_spatial_router as spatial;
import protocol_envelope as envelope;

// A decoded command retains its fields even when validation rejects it.
pub struct Decoded { valid: bool, frame: spatial::SpatialFrame }
// Decode an unprefixed, word-aligned command. Native ingress still validates route/schema.
pub fn decode(payload: bits[256], words: u8) -> Decoded {
  let command = envelope::unpack_rectangle(payload as bits[224]);
  let header = axis::header_from_bits(command.header);
  Decoded {
    valid: words >= u8:4 && words <= u8:7 && command.target < u32:4 &&
      header.txid == u8:0 && header.flags == u8:0 && header.payload_words == words-u8:4 &&
      command.x0 <= command.x1 && command.y0 <= command.y1,
    frame: spatial::SpatialFrame {
      rectangle: spatial::Rectangle { x0: command.x0, y0: command.y0, x1: command.x1, y1: command.y1 },
      target: command.target as u2,
      frame: axis::Frame { header, payload: command.payload },
    },
  }
}

// Adapt the typed command to the native source ingress ABI, distinct from wire byte order.
pub fn ingress(frame: spatial::SpatialFrame) -> bits[194] {
  let bounds = frame.rectangle;
  let header = frame.frame.header;
  bounds.x0 ++ bounds.y0 ++ bounds.x1 ++ bounds.y1 ++ frame.target ++
    header.payload_words ++ header.txid ++ header.flags ++ header.op ++ frame.frame.payload
}
