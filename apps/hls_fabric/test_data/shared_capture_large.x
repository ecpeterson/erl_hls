// Exercise generated pending-request capture with seven independent producers.
// The initialization regression generates the imported actor from Erlang.
import xls_init_statem_fixture as actor;

pub proc Top {
  config(
      requests: chan<actor::ScheduledRequest>[7] in,
      startup: chan<actor::ScheduledRequest> in,
      effects: chan<actor::ScheduledEffects> out,
      state_read: chan<actor::MachineRamReadReq> out,
      state_response: chan<actor::MachineRamReadResp> in,
      state_write: chan<actor::MachineRamWriteReq> out,
      state_completion: chan<actor::MachineRamWriteResp> in,
      mail_read: chan<actor::MailboxRamReadReq> out,
      mail_response: chan<actor::MailboxRamReadResp> in,
      mail_write: chan<actor::MailboxRamWriteReq> out,
      mail_completion: chan<actor::MailboxRamWriteResp> in) {
    spawn actor::SharedService<u32:6, u32:7, u32:0, u32:0>(
      requests, startup, effects, state_read, state_response,
      state_write, state_completion, mail_read, mail_response,
      mail_write, mail_completion);
    ()
  }
  init { () }
  next(state: ()) { state }
}
