// Three-actor SharedService harness for the reduction/effect-window HOL tests.
// The first emitted effect batch is drained while its credit is held. Actor
// zero can therefore produce a second, blocked ordinary result while actor
// one's local reduction fold remains independent work. The third actor lets
// the harness put a non-contribution mailbox head ahead of another local
// fold. The testbench eventually releases the credit and checks exact output
// recovery after the independent fold results traverse the relay.

import axis;
import hls_statem_reduction_rtl_fixture as actor;

const ACTOR_COUNT = u32:3;
const PRODUCER_COUNT = u32:1;
const MAILBOX_ROWS = u32:12;

proc MachineRam {
  read_req_in: chan<actor::MachineRamReadReq> in;
  read_resp_out: chan<actor::MachineRamReadResp> out;
  write_req_in: chan<actor::MachineRamWriteReq> in;
  write_resp_out: chan<actor::MachineRamWriteResp> out;
  read_probe_out: chan<u32> out;
  write_probe_out: chan<u32> out;

  config(
      read_req_in: chan<actor::MachineRamReadReq> in,
      read_resp_out: chan<actor::MachineRamReadResp> out,
      write_req_in: chan<actor::MachineRamWriteReq> in,
      write_resp_out: chan<actor::MachineRamWriteResp> out,
      read_probe_out: chan<u32> out,
      write_probe_out: chan<u32> out
  ) {
    (read_req_in, read_resp_out, write_req_in, write_resp_out,
      read_probe_out, write_probe_out)
  }

  init { zero!<actor::MachineBits[ACTOR_COUNT]>() }

  next(rows: actor::MachineBits[ACTOR_COUNT]) {
    let (read_tok, read_req, read_valid) = recv_if_non_blocking(
      join(), read_req_in, true, zero!<actor::MachineRamReadReq>());
    let (write_tok, write_req, write_valid) = recv_if_non_blocking(
      read_tok, write_req_in, true, zero!<actor::MachineRamWriteReq>());
    let read_probe_tok = send_if(
      write_tok, read_probe_out, read_valid, read_req.addr);
    let response_tok = send_if(
      read_probe_tok,
      read_resp_out,
      read_valid,
      actor::MachineRamReadResp { data: rows[read_req.addr] });
    let probe_tok = send_if(
      response_tok, write_probe_out, write_valid, write_req.addr);
    let _done = send_if(
      probe_tok,
      write_resp_out,
      write_valid,
      zero!<actor::MachineRamWriteResp>());
    if write_valid {
      update(rows, write_req.addr, write_req.data)
    } else {
      rows
    }
  }
}

proc ReductionRam {
  read_req_in: chan<actor::ReductionRamReadReq> in;
  read_resp_out: chan<actor::ReductionRamReadResp> out;
  write_req_in: chan<actor::ReductionRamWriteReq> in;
  write_resp_out: chan<actor::ReductionRamWriteResp> out;
  read_probe_out: chan<u32> out;
  write_probe_out: chan<u32> out;

  config(
      read_req_in: chan<actor::ReductionRamReadReq> in,
      read_resp_out: chan<actor::ReductionRamReadResp> out,
      write_req_in: chan<actor::ReductionRamWriteReq> in,
      write_resp_out: chan<actor::ReductionRamWriteResp> out,
      read_probe_out: chan<u32> out,
      write_probe_out: chan<u32> out
  ) {
    (read_req_in, read_resp_out, write_req_in, write_resp_out,
      read_probe_out, write_probe_out)
  }

  init { zero!<actor::ReductionBits[ACTOR_COUNT]>() }

  next(rows: actor::ReductionBits[ACTOR_COUNT]) {
    let (read_tok, read_req, read_valid) = recv_if_non_blocking(
      join(), read_req_in, true, zero!<actor::ReductionRamReadReq>());
    let (write_tok, write_req, write_valid) = recv_if_non_blocking(
      read_tok, write_req_in, true, zero!<actor::ReductionRamWriteReq>());
    let read_probe_tok = send_if(
      write_tok, read_probe_out, read_valid, read_req.addr);
    let response_tok = send_if(
      read_probe_tok,
      read_resp_out,
      read_valid,
      actor::ReductionRamReadResp { data: rows[read_req.addr] });
    let probe_tok = send_if(
      response_tok, write_probe_out, write_valid, write_req.addr);
    let _done = send_if(
      probe_tok,
      write_resp_out,
      write_valid,
      zero!<actor::ReductionRamWriteResp>());
    if write_valid {
      update(rows, write_req.addr, write_req.data)
    } else {
      rows
    }
  }
}

proc MailboxRam {
  read_req_in: chan<actor::MailboxRamReadReq> in;
  read_resp_out: chan<actor::MailboxRamReadResp> out;
  write_req_in: chan<actor::MailboxRamWriteReq> in;
  write_resp_out: chan<actor::MailboxRamWriteResp> out;

  config(
      read_req_in: chan<actor::MailboxRamReadReq> in,
      read_resp_out: chan<actor::MailboxRamReadResp> out,
      write_req_in: chan<actor::MailboxRamWriteReq> in,
      write_resp_out: chan<actor::MailboxRamWriteResp> out
  ) {
    (read_req_in, read_resp_out, write_req_in, write_resp_out)
  }

  init { zero!<bits[axis::FRAME_BITS][MAILBOX_ROWS]>() }

  next(rows: bits[axis::FRAME_BITS][MAILBOX_ROWS]) {
    let (read_tok, read_req, read_valid) = recv_if_non_blocking(
      join(), read_req_in, true, zero!<actor::MailboxRamReadReq>());
    let (write_tok, write_req, write_valid) = recv_if_non_blocking(
      read_tok, write_req_in, true, zero!<actor::MailboxRamWriteReq>());
    let response_tok = send_if(
      write_tok,
      read_resp_out,
      read_valid,
      actor::MailboxRamReadResp { data: rows[read_req.addr] });
    let _done = send_if(
      response_tok,
      write_resp_out,
      write_valid,
      zero!<actor::MailboxRamWriteResp>());
    if write_valid {
      update(rows, write_req.addr, write_req.data)
    } else {
      rows
    }
  }
}

// The testbench selects an actor with the otherwise-unused transaction id.
// This is harness-local routing; the actor still receives its ordinary frame.
proc RequestMux {
  frame_in: chan<axis::Frame> in;
  credit_in: chan<actor::ScheduledRequest> in;
  request_out: chan<actor::ScheduledRequest> out;

  config(
      frame_in: chan<axis::Frame> in,
      credit_in: chan<actor::ScheduledRequest> in,
      request_out: chan<actor::ScheduledRequest> out
  ) {
    (frame_in, credit_in, request_out)
  }

  init { () }

  next(state: ()) {
    // Returning the held effect credit has priority for one activation. The
    // frame receive is conditional, so an application frame is never consumed
    // and dropped when both inputs are ready.
    let (credit_tok, credit, credit_valid) = recv_if_non_blocking(
      join(), credit_in, true, zero!<actor::ScheduledRequest>());
    let (frame_tok, frame, frame_valid) = recv_if_non_blocking(
      credit_tok, frame_in, !credit_valid, zero!<axis::Frame>());
    let frame_request = actor::ScheduledRequest {
      slot: frame.header.txid as u32,
      frame,
      ..zero!<actor::ScheduledRequest>()
    };
    let request = if credit_valid { credit } else { frame_request };
    let _done = send_if(
      frame_tok, request_out, credit_valid || frame_valid, request);
    state
  }
}

// The testbench releases the one deliberately held effect credit only after
// independent local folds have traversed the relay. This turns the original
// HOL witness into a recovery test without changing SharedService's ingress.
proc CreditRelease {
  release_in: chan<u1> in;
  credit_out: chan<actor::ScheduledRequest> out;

  config(
      release_in: chan<u1> in,
      credit_out: chan<actor::ScheduledRequest> out
  ) {
    (release_in, credit_out)
  }

  init { () }

  next(state: ()) {
    let (tok, _release) = recv(join(), release_in);
    let _done = send(
      tok,
      credit_out,
      actor::ScheduledRequest {
        credit: u1:1,
        ..zero!<actor::ScheduledRequest>()
      });
    state
  }
}

struct EffectState {
  active: u1,
  scheduled: actor::ScheduledEffects,
  index: u8,
}

// Drains effect batches without returning credit itself. The testbench holds
// the first credit through CreditRelease, so a second effect-bearing executor
// result remains buffered inside SharedService until the liveness check.
proc UncreditedEffectSink {
  scheduled_in: chan<actor::ScheduledEffects> in;
  frame_out: chan<axis::Frame> out;

  config(
      scheduled_in: chan<actor::ScheduledEffects> in,
      frame_out: chan<axis::Frame> out
  ) {
    (scheduled_in, frame_out)
  }

  init { zero!<EffectState>() }

  next(state: EffectState) {
    if !state.active {
      let (_tok, scheduled) = recv(join(), scheduled_in);
      EffectState { active: u1:1, scheduled, ..zero!<EffectState>() }
    } else {
      let effect = actor::scheduled_effect(state.scheduled, state.index);
      let _done = send_if(join(), frame_out, effect.1, effect.0.frame);
      if effect.2 {
        zero!<EffectState>()
      } else {
        EffectState { index: state.index + u8:1, ..state }
      }
    }
  }
}

pub proc Top {
  ext_recv: chan<axis::Beat> in;
  release_credit: chan<u1> in;
  out_send: chan<axis::Beat> out;
  state_read_probe: chan<u32> out;
  state_write_probe: chan<u32> out;
  reduction_read_probe: chan<u32> out;
  reduction_write_probe: chan<u32> out;

  config(
      ext_recv: chan<axis::Beat> in,
      release_credit: chan<u1> in,
      out_send: chan<axis::Beat> out,
      state_read_probe: chan<u32> out,
      state_write_probe: chan<u32> out,
      reduction_read_probe: chan<u32> out,
      reduction_write_probe: chan<u32> out
  ) {
    let (frame_p, frame_c) = chan<axis::Frame, u32:1>("frame");
    let (request_p, request_c) =
      chan<actor::ScheduledRequest, u32:1>[PRODUCER_COUNT]("request");
    let (_startup_p, startup_c) =
      chan<actor::ScheduledRequest, u32:1>("startup");
    let (scheduled_p, scheduled_c) =
      chan<actor::ScheduledEffects, u32:1>("scheduled");
    let (credit_p, credit_c) =
      chan<actor::ScheduledRequest, u32:1>("credit");
    let (output_p, output_c) = chan<axis::Frame, u32:1>("output");

    let (state_read_req_p, state_read_req_c) =
      chan<actor::MachineRamReadReq, u32:1>("state_read_req");
    let (state_read_resp_p, state_read_resp_c) =
      chan<actor::MachineRamReadResp, u32:1>("state_read_resp");
    let (state_write_req_p, state_write_req_c) =
      chan<actor::MachineRamWriteReq, u32:1>("state_write_req");
    let (state_write_resp_p, state_write_resp_c) =
      chan<actor::MachineRamWriteResp, u32:1>("state_write_resp");

    let (reduction_read_req_p, reduction_read_req_c) =
      chan<actor::ReductionRamReadReq, u32:1>("reduction_read_req");
    let (reduction_read_resp_p, reduction_read_resp_c) =
      chan<actor::ReductionRamReadResp, u32:1>("reduction_read_resp");
    let (reduction_write_req_p, reduction_write_req_c) =
      chan<actor::ReductionRamWriteReq, u32:1>("reduction_write_req");
    let (reduction_write_resp_p, reduction_write_resp_c) =
      chan<actor::ReductionRamWriteResp, u32:1>("reduction_write_resp");

    let (mail_read_req_p, mail_read_req_c) =
      chan<actor::MailboxRamReadReq, u32:1>("mail_read_req");
    let (mail_read_resp_p, mail_read_resp_c) =
      chan<actor::MailboxRamReadResp, u32:1>("mail_read_resp");
    let (mail_write_req_p, mail_write_req_c) =
      chan<actor::MailboxRamWriteReq, u32:1>("mail_write_req");
    let (mail_write_resp_p, mail_write_resp_c) =
      chan<actor::MailboxRamWriteResp, u32:1>("mail_write_resp");

    spawn axis::Rx(ext_recv, frame_p);
    spawn RequestMux(frame_c, credit_c, request_p[u32:0]);
    spawn CreditRelease(release_credit, credit_p);
    spawn actor::SharedService<
      ACTOR_COUNT, PRODUCER_COUNT, u32:0, u32:0>(
        request_c,
        startup_c,
        scheduled_p,
        state_read_req_p,
        state_read_resp_c,
        state_write_req_p,
        state_write_resp_c,
        mail_read_req_p,
        mail_read_resp_c,
        mail_write_req_p,
        mail_write_resp_c,
        reduction_read_req_p,
        reduction_read_resp_c,
        reduction_write_req_p,
        reduction_write_resp_c);
    spawn MachineRam(
      state_read_req_c,
      state_read_resp_p,
      state_write_req_c,
      state_write_resp_p,
      state_read_probe,
      state_write_probe);
    spawn ReductionRam(
      reduction_read_req_c,
      reduction_read_resp_p,
      reduction_write_req_c,
      reduction_write_resp_p,
      reduction_read_probe,
      reduction_write_probe);
    spawn MailboxRam(
      mail_read_req_c,
      mail_read_resp_p,
      mail_write_req_c,
      mail_write_resp_p);
    spawn UncreditedEffectSink(scheduled_c, output_p);
    spawn axis::Tx(output_c, out_send);
    (
      ext_recv,
      release_credit,
      out_send,
      state_read_probe,
      state_write_probe,
      reduction_read_probe,
      reduction_write_probe
    )
  }

  init { () }
  next(state: ()) { state }
}
