// Public ordered gateway fixture; the RTL bench supplies the real activation bridge.
import axis;
import hls_partition_io;

// Expose routed traffic, the ordered commands, completion and two event sources.
pub proc Top {
  // The fixed identity is visible in the public attachment packet.
  config(app_in: chan<axis::Beat> in, app_out: chan<axis::Beat> out,
      commands_out: chan<hls_partition_io::OrderedCommand> out,
      started_in: chan<bool> in, events_in: chan<axis::Frame>[2] in) {
    spawn hls_partition_io::OrderedBoundary<u32:2, u64:0x12345678, u64:0, u64:0, u64:0, u16:1, u16:7>
      (app_in, app_out, commands_out, started_in, events_in);
    ()
  }
  // This wrapper has no state beyond its instantiated gateway.
  init { () }
  // All transfers execute in the shared boundary.
  next(state: ()) { state }
}
