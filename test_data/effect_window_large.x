// A larger connected scheduler domain must remain practical to elaborate.
import effect_window;

pub proc Top {
  config(requests: chan<u1>[12] in, grants: chan<u1>[12] out,
      releases: chan<u1>[12] in) {
    spawn effect_window::Arbiter<u32:12>(requests, grants, releases);
    ()
  }
  init { () }
  next(state: ()) { state }
}
