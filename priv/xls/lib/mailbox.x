// Shared-scheduler mailbox storage primitives.
//
// Queue metadata remains in the scheduler. This module describes the frame
// rows stored in external RAM and the stable flattened address calculation.

import axis;
import bram;

pub struct Slot {
  postponed: u1,
  frame: axis::Frame,
}

pub struct ScheduledRequest {
  slot: u32,
  frame: axis::Frame,
  credit: u1,
}

pub struct Admission {
  valid: u1,
  producer: u32,
  slot: u32,
  physical: u8,
}

pub type RamReadReq = bram::ReadReq;
pub type RamReadResp = bram::ReadResp<axis::FRAME_BITS>;
pub type RamWriteReq = bram::WriteReq<axis::FRAME_BITS>;
pub type RamWriteResp = bram::WriteResp;

pub fn address(slot: u32, index: u8, capacity: u32) -> u32 {
  slot * capacity + index as u32
}

pub fn read(slot: u32, index: u8, capacity: u32) -> RamReadReq {
  bram::read(address(slot, index, capacity))
}

pub fn write(
    slot: u32, index: u8, capacity: u32, frame: axis::Frame)
    -> RamWriteReq {
  bram::write(address(slot, index, capacity), axis::bits_from_frame(frame))
}

#[test]
fn rows_are_slot_major_and_hold_one_frame_test() {
  let frame = axis::pack(u8:13, u32:0x12345678);
  assert_eq(address(u32:3, u8:2, u32:5), u32:17);
  assert_eq(read(u32:3, u8:2, u32:5), bram::read(u32:17));
  assert_eq(
    write(u32:3, u8:2, u32:5, frame),
    bram::write(u32:17, axis::bits_from_frame(frame)));
}
