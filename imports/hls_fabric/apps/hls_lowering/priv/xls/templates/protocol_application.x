import axis;
import hls_partition_io as gateway;
import application_config as config;

// Public framed application ports around the shared ordered gateway.
pub proc Top {
  // The network's endpoint streams preserve per-sender order, not cross-sender chronology.
  config(app_in: chan<axis::Beat> in, app_out: chan<axis::Beat> out,
      commands_out: chan<gateway::OrderedCommand> out, started_in: chan<bool> in,
      events_in: chan<axis::Frame>[config::EVENTS] in) {
    spawn gateway::OrderedBoundary<config::EVENTS, config::ID0, config::ID1, config::ID2, config::ID3, config::HOST, config::CONTROL>
      (app_in, app_out, commands_out, started_in, events_in);
    ()
  }
  // All state belongs to the shared receiver/transmitter.
  init { () }
  // This structural wrapper owns no separate protocol state.
  next(state: ()) { state }
}
