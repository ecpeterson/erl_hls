// One-actor SharedService harness for hls_statem_reduction_rtl_fixture.x.
// The RAM models are intentionally tiny test fixtures, not synthesizable
// replacements for the external 1R1W memories used by generated topologies.

import axis;
import hls_statem_reduction_rtl_fixture as actor;

const ACTOR_COUNT = u32:1;
const PRODUCER_COUNT = u32:1;
const MAILBOX_ROWS = u32:4;

proc MachineRam {
  read_req_in: chan<actor::MachineRamReadReq> in;
  read_resp_out: chan<actor::MachineRamReadResp> out;
  write_req_in: chan<actor::MachineRamWriteReq> in;
  write_resp_out: chan<actor::MachineRamWriteResp> out;

  config(
      read_req_in: chan<actor::MachineRamReadReq> in,
      read_resp_out: chan<actor::MachineRamReadResp> out,
      write_req_in: chan<actor::MachineRamWriteReq> in,
      write_resp_out: chan<actor::MachineRamWriteResp> out
  ) {
    (read_req_in, read_resp_out, write_req_in, write_resp_out)
  }

  init { zero!<actor::MachineBits[ACTOR_COUNT]>() }

  next(rows: actor::MachineBits[ACTOR_COUNT]) {
    let (read_tok, read_req, read_valid) = recv_if_non_blocking(
      join(), read_req_in, true, zero!<actor::MachineRamReadReq>());
    let (write_tok, write_req, write_valid) = recv_if_non_blocking(
      read_tok, write_req_in, true, zero!<actor::MachineRamWriteReq>());
    let response_tok = send_if(
      write_tok,
      read_resp_out,
      read_valid,
      actor::MachineRamReadResp { data: rows[read_req.addr] });
    let _done = send_if(
      response_tok,
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

  config(
      read_req_in: chan<actor::ReductionRamReadReq> in,
      read_resp_out: chan<actor::ReductionRamReadResp> out,
      write_req_in: chan<actor::ReductionRamWriteReq> in,
      write_resp_out: chan<actor::ReductionRamWriteResp> out
  ) {
    (read_req_in, read_resp_out, write_req_in, write_resp_out)
  }

  init { zero!<actor::ReductionBits[ACTOR_COUNT]>() }

  next(rows: actor::ReductionBits[ACTOR_COUNT]) {
    let (read_tok, read_req, read_valid) = recv_if_non_blocking(
      join(), read_req_in, true, zero!<actor::ReductionRamReadReq>());
    let (write_tok, write_req, write_valid) = recv_if_non_blocking(
      read_tok, write_req_in, true, zero!<actor::ReductionRamWriteReq>());
    let response_tok = send_if(
      write_tok,
      read_resp_out,
      read_valid,
      actor::ReductionRamReadResp { data: rows[read_req.addr] });
    let _done = send_if(
      response_tok,
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

// Credits and application frames share the one producer ingress exactly as
// they do in a generated scheduler router. Alternating polls are sufficient
// for this bounded witness and avoid consuming an unselected channel value.
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

  init { u1:0 }

  next(credit_turn: u1) {
    if credit_turn {
      let (tok, credit, valid) = recv_if_non_blocking(
        join(), credit_in, true, zero!<actor::ScheduledRequest>());
      let _done = send_if(tok, request_out, valid, credit);
      u1:0
    } else {
      let (tok, frame, valid) = recv_if_non_blocking(
        join(), frame_in, true, zero!<axis::Frame>());
      let request = actor::ScheduledRequest {
        slot: u32:0,
        frame,
        ..zero!<actor::ScheduledRequest>()
      };
      let _done = send_if(tok, request_out, valid, request);
      u1:1
    }
  }
}

struct EffectState {
  active: u1,
  scheduled: actor::ScheduledEffects,
  index: u8,
}

proc EffectRouter {
  scheduled_in: chan<actor::ScheduledEffects> in;
  frame_out: chan<axis::Frame> out;
  credit_out: chan<actor::ScheduledRequest> out;

  config(
      scheduled_in: chan<actor::ScheduledEffects> in,
      frame_out: chan<axis::Frame> out,
      credit_out: chan<actor::ScheduledRequest> out
  ) {
    (scheduled_in, frame_out, credit_out)
  }

  init { zero!<EffectState>() }

  next(state: EffectState) {
    if !state.active {
      let (_tok, scheduled) = recv(join(), scheduled_in);
      EffectState { active: u1:1, scheduled, ..zero!<EffectState>() }
    } else {
      let effect = actor::scheduled_effect(state.scheduled, state.index);
      let frame_tok = send_if(join(), frame_out, effect.1, effect.0.frame);
      let _done = send_if(
        frame_tok,
        credit_out,
        effect.2,
        actor::ScheduledRequest {
          credit: u1:1,
          ..zero!<actor::ScheduledRequest>()
        });
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
  out_send: chan<axis::Beat> out;

  config(
      ext_recv: chan<axis::Beat> in,
      out_send: chan<axis::Beat> out
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
      state_write_resp_p);
    spawn ReductionRam(
      reduction_read_req_c,
      reduction_read_resp_p,
      reduction_write_req_c,
      reduction_write_resp_p);
    spawn MailboxRam(
      mail_read_req_c,
      mail_read_resp_p,
      mail_write_req_c,
      mail_write_resp_p);
    spawn EffectRouter(scheduled_c, output_p, credit_p);
    spawn axis::Tx(output_c, out_send);
    (ext_recv, out_send)
  }

  init { () }
  next(state: ()) { state }
}
