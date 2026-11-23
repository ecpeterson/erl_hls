// Small typed actor ABI for production outbox schedule tests.
import axis;
pub enum OutputPort : u3 { A = 0, B = 1, C = 2, D = 3, TAIL = 4 }
pub struct Egress { port: OutputPort, frame: axis::Frame }
pub struct ScheduledEffects { slot: u32, mode: u2, base: u32 }
pub struct ScheduledRequest { slot: u32, credit: u1 }
// Modes select ordinary, prefix-only, prefix plus tail, or empty batches.
pub fn scheduled_reduction_prefix(batch: ScheduledEffects) -> (u1, u8, u1) {
  (batch.mode == u2:1 || batch.mode == u2:2, u8:4, batch.mode == u2:1)
}
// Independent payloads expose missing, duplicated or reordered effects.
pub fn scheduled_effect(batch: ScheduledEffects, index: u8) -> (Egress, u1, u1) {
  let prefix = batch.mode == u2:1 || batch.mode == u2:2;
  let count = match batch.mode { u2:0 => u8:3, u2:1 => u8:4, u2:2 => u8:6, _ => u8:0 };
  let port = if prefix && index < u8:4 { index as OutputPort } else { OutputPort::TAIL };
  (Egress { port, frame: axis::Frame { payload: (batch.base + index as u32) as uN[96],
      ..zero!<axis::Frame>() } }, index < count, index + u8:1 >= count)
}
