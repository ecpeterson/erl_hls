// Public boundary fixture: two event streams and an observable control output.
import axis;
import hls_partition_tile_io;
import hls_spatial_router;

pub proc Top {
  config(tile_gateway: chan<bits[272]> in, tile_host: chan<u16> in, app_in: chan<axis::Beat> in, app_out: chan<axis::Beat> out,
      control_out: chan<hls_spatial_router::SpatialFrame> out,
      events_in: chan<axis::Frame>[2] in) {
    spawn hls_partition_tile_io::Boundary<u32:2, u16:7>(tile_gateway, tile_host, app_in, app_out, control_out, events_in);
    ()
  }
  init { () }
  next(state: ()) { state }
}
