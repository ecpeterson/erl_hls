// Public boundary fixture: two event streams and an observable control output.
import axis;
import hls_partition_io;
import hls_spatial_router;

pub proc Top {
  config(app_in: chan<axis::Beat> in, app_out: chan<axis::Beat> out,
      control_out: chan<hls_spatial_router::SpatialFrame> out,
      events_in: chan<axis::Frame>[2] in) {
    spawn hls_partition_io::Boundary<u32:2, u64:0x12345678, u64:0, u64:0, u64:0, u16:1, u16:7>(app_in, app_out, control_out, events_in);
    ()
  }
  init { () }
  next(state: ()) { state }
}
