import axis;
import hls_spatial_router;
import actor_pid_addresses;

struct IngressState {
  stage: u3,
  endpoint: u16,
  slot: u32,
  valid: bool,
}

// Receive complete routed packets. A rejected packet drains through its
// actual TLAST; its contents cannot be mistaken for another routing word.
pub proc AddressedIngress {
  routed_in: chan<axis::Beat> in;
  commands_out: chan<hls_spatial_router::SpatialFrame> out;

  config(routed_in: chan<axis::Beat> in,
         commands_out: chan<hls_spatial_router::SpatialFrame> out) {
    (routed_in, commands_out)
  }
  init { zero!<IngressState>() }
  next(state: IngressState) {
    let (tok, beat) = recv(join(), routed_in);
    let (addressed, x, y) = actor_pid_addresses::destination(state.endpoint, state.slot);
    let deliver = state.stage == u3:3 && state.valid && addressed && beat.tlast;
    let frame = axis::Frame {
      header: axis::Header { op: actor_pid_addresses::WORK, payload_words: u8:1,
        ..zero!<axis::Header>() },
      payload: beat.word as bits[96],
    };
    let _done = send_if(tok, commands_out, deliver,
      hls_spatial_router::SpatialFrame {
        rectangle: hls_spatial_router::Rectangle { x0: x, y0: y, x1: x, y1: y },
        target: u2:0, frame,
      });
    if beat.tlast {
      zero!<IngressState>()
    } else {
      match state.stage {
        u3:0 => IngressState { stage: u3:1, endpoint: beat.word as u16,
          ..zero!<IngressState>() },
        u3:1 => {
          let header = axis::header_from_bits(beat.word);
          IngressState { stage: u3:2,
            valid: header.op == actor_pid_addresses::WORK && header.flags == u8:1 &&
              header.txid == u8:255 && header.payload_words == u8:2,
            ..state }
        },
        u3:2 => IngressState { stage: u3:3, slot: beat.word, ..state },
        _ => IngressState { stage: u3:4, valid: false, ..state },
      }
    }
  }
}
