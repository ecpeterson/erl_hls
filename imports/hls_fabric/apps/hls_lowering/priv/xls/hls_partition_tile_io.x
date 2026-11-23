// Constant tile configuration must remain stable throughout reset and execution.
import axis;
import hls_spatial_router;
import hls_partition_io;

// Assemble complete packets against the wrapper's host and deployment identity.
proc Receive<SERVICE: u16> {
  binding: chan<bits[272]> in;
  input: chan<axis::Beat> in;
  control: chan<hls_spatial_router::SpatialFrame> out;
  management: chan<axis::FrameN<u32:8>> out;
  // Connect the routed input to ordered commands and attachment/fault replies.
  config(binding: chan<bits[272]> in, input: chan<axis::Beat> in,
      control: chan<hls_spatial_router::SpatialFrame> out,
      management: chan<axis::FrameN<u32:8>> out) { (binding, input, control, management) }
  // Reset discards partial packets and requires a fresh attachment.
  init { zero!<hls_partition_io::ReceiveState>() }
  // Consume one input beat; complete valid commands and management replies block until accepted.
  next(state: hls_partition_io::ReceiveState) {
    let (tok, config) = recv(join(), binding);
    let (tok, beat) = recv(tok, input);
    let identity = config[16+:bits[256]];
    let (state, attach, valid, fault, command) = hls_partition_io::receive_step(
      state, beat, identity, config[0+:u16], SERVICE);
    let tok = send_if(tok, control, valid, command);
    let _done = send_if(tok, management, attach || fault,
      hls_partition_io::response(attach, identity));
    state
  }
}

// Poll streams fairly, retaining one complete frame while its words are sent.
proc Transmit<N: u32, SERVICE: u16> {
  host: chan<u16> in;
  management: chan<axis::FrameN<u32:8>> in;
  events: chan<axis::Frame>[N] in;
  output: chan<axis::Beat> out;
  // Connect management and event inputs to the one serialized routed output.
  config(host: chan<u16> in, management: chan<axis::FrameN<u32:8>> in,
      events: chan<axis::Frame>[N] in, output: chan<axis::Beat> out) {
    (host, management, events, output)
  }
  // Reset clears the retained packet and keeps ordinary events blocked until attachment.
  init { zero!<hls_partition_io::TransmitState>() }
  // Poll one eligible input or send one retained word; a blocked output preserves packet order.
  next(state: hls_partition_io::TransmitState) {
    let (config_tok, host) = recv(join(), host);
    if !state.sending {
      let (tok, reply, reply_valid) = recv_if_non_blocking(config_tok, management,
        !state.started || state.cursor == N, zero!<axis::FrameN<u32:8>>());
      let (_, frame, source, valid) = unroll_for! (i, acc):
          (u32, (token, axis::FrameN<u32:8>, u16, bool)) in u32:0..N {
        let (tok, event, valid) = recv_if_non_blocking(acc.0, events[i],
          state.started && state.cursor == i, zero!<axis::Frame>());
        (tok, if valid { axis::FrameN<u32:8> {
          header: event.header, payload: event.payload as bits[256],
        } } else { acc.1 }, if valid { u16:8 + i as u16 } else { acc.2 }, valid || acc.3)
      }((tok, reply, SERVICE, reply_valid));
      hls_partition_io::TransmitState { frame, source, sending: valid, index: u4:0,
        cursor: if state.cursor == N { u32:0 } else { state.cursor + u32:1 }, ..state }
    } else {
      let _done = send(config_tok, output, hls_partition_io::transmit_beat(state, host));
      hls_partition_io::transmitted(state, SERVICE)
    }
  }
}

// The application ABI is unchanged; only device-specific constants are inputs.
pub proc Boundary<N: u32, SERVICE: u16> {
  // Join receive and transmit with one buffered management reply channel.
  config(binding: chan<bits[272]> in, host: chan<u16> in,
      input: chan<axis::Beat> in, output: chan<axis::Beat> out,
      control: chan<hls_spatial_router::SpatialFrame> out, events: chan<axis::Frame>[N] in) {
    let (management_p, management_c) = chan<axis::FrameN<u32:8>, u32:1>("management");
    spawn Receive<SERVICE>(binding, input, control, management_p);
    spawn Transmit<N, SERVICE>(host, management_c, events, output);
    ()
  }
  // All mutable framing state belongs to the child receiver and transmitter.
  init { () }
  // This structural wrapper performs no independent transfers.
  next(state: ()) { state }
}
