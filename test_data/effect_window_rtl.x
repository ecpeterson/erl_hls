// External handshakes exercise reservation ownership under backpressure.
import effect_window;

pub proc ArbiterTop {
  config(
      requests: chan<u1>[u32:3] in,
      grants: chan<u1>[u32:3] out,
      releases: chan<u1>[u32:3] in
  ) {
    spawn effect_window::Arbiter<u32:3>(requests, grants, releases);
    ()
  }
  init { () }
  next(state: ()) { state }
}

// A router can finish its batch before its requested grant arrives. It then
// returns the grant in the same activation. Depth-one bypass FIFOs do not
// themselves break the resulting grant/release combinational path.
proc ReturnClient {
  request_out: chan<u1> out;
  grant_in: chan<u1> in;
  release_out: chan<u1> out;
  returned_out: chan<u1> out;

  config(request_out: chan<u1> out, grant_in: chan<u1> in,
      release_out: chan<u1> out, returned_out: chan<u1> out) {
    (request_out, grant_in, release_out, returned_out)
  }
  init { false }
  next(waiting: bool) {
    let (grant_tok, _grant, received) =
      recv_if_non_blocking(join(), grant_in, waiting, u1:0);
    let transition = effect_window::advance_client(
      effect_window::ClientState {
        window_requested: waiting, ..zero!<effect_window::ClientState>() },
      false, received, false);
    let observed_tok = send_if(grant_tok, returned_out, received, u1:1);
    let release_tok = send_if(
      observed_tok, release_out, transition.release, u1:1);
    let _request_tok = send_if(
      release_tok, request_out, !waiting || received, u1:1);
    true
  }
}

pub proc ReturnTop {
  config(returned_0: chan<u1> out, returned_1: chan<u1> out) {
    let (request_p, request_c) = chan<u1, u32:1>[u32:2]("request");
    let (grant_p, grant_c) = chan<u1, u32:1>[u32:2]("grant");
    let (release_p, release_c) = chan<u1, u32:1>[u32:2]("release");
    spawn effect_window::Arbiter<u32:2>(request_c, grant_p, release_c);
    spawn ReturnClient(request_p[u32:0], grant_c[u32:0], release_p[u32:0], returned_0);
    spawn ReturnClient(request_p[u32:1], grant_c[u32:1], release_p[u32:1], returned_1);
    ()
  }
  init { () }
  next(state: ()) { state }
}
