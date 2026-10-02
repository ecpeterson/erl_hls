// XLS 1R1W channel shapes for member-masked gather storage. Addresses stay u32
// until the physical wrapper selects its checked address width. The codegen RAM
// adapter owns ready/valid and write acknowledgments; this module defines no queue.

// Request one complete row; reads do not use a member mask.
pub struct ReadReq {
  addr: u32,
  mask: (),
}

// One ordered full-row response. The consumer applies declared inactive padding.
pub struct ReadResp<ELEMENT_BITS: u32, MEMBERS: u32, ROW_BITS: u32 = {ELEMENT_BITS * MEMBERS}> {
  data: bits[ROW_BITS],
}

// Mask bit m replaces the element at m*ELEMENT_BITS, including a zero-valued input.
pub struct WriteReq<ELEMENT_BITS: u32, MEMBERS: u32, ROW_BITS: u32 = {ELEMENT_BITS * MEMBERS}> {
  addr: u32,
  data: bits[ROW_BITS],
  mask: bits[MEMBERS],
}

// Every accepted write request receives one acknowledgment, including a zero mask.
pub struct WriteResp {}

// Request an in-range physical row; the owner validates the address before sending.
pub fn read(addr: u32) -> ReadReq {
  ReadReq { addr, mask: () }
}

// Construct a general masked write, preserving all member data and mask positions.
pub fn write<ELEMENT_BITS: u32, MEMBERS: u32, ROW_BITS: u32 = {ELEMENT_BITS * MEMBERS}>(
    addr: u32, data: bits[ROW_BITS], mask: bits[MEMBERS]) -> WriteReq<ELEMENT_BITS, MEMBERS> {
  const_assert!(ELEMENT_BITS > u32:0 && MEMBERS > u32:0 && ROW_BITS == ELEMENT_BITS * MEMBERS);
  WriteReq<ELEMENT_BITS, MEMBERS> { addr, data, mask }
}

// Broadcast one value to all row slices and enable only its checked member. Data
// in disabled slices is unspecified; replication avoids a wide variable shifter.
// The owner must supply member < MEMBERS and separately validate key/membership.
pub fn write_member<ELEMENT_BITS: u32, MEMBERS: u32, ROW_BITS: u32 = {ELEMENT_BITS * MEMBERS}>(
    addr: u32, member: u32, value: bits[ELEMENT_BITS]) -> WriteReq<ELEMENT_BITS, MEMBERS> {
  let data = unroll_for! (index, row): (u32, bits[ROW_BITS]) in u32:0..MEMBERS {
    bit_slice_update(row, index * ELEMENT_BITS, value)
  }(bits[ROW_BITS]:0);
  write<ELEMENT_BITS, MEMBERS>(addr, data, bits[MEMBERS]:1 << member)
}

// Empty and sparse masks retain their exact shape, and member zero is least significant.
#[test]
fn row_and_member_requests_test() {
  assert_eq(read(u32:9), ReadReq { addr: u32:9, mask: () });
  assert_eq(write<u32:8, u32:4>(u32:3, u32:0x44332211, u4:0),
    WriteReq<u32:8, u32:4> { addr: u32:3, data: u32:0x44332211, mask: u4:0 });
  assert_eq(write<u32:8, u32:4>(u32:3, u32:0x44332211, u4:9),
    WriteReq<u32:8, u32:4> { addr: u32:3, data: u32:0x44332211, mask: u4:9 });
  let first = write_member<u32:8, u32:4>(u32:3, u32:0, u8:0xaa);
  assert_eq((first.addr, first.mask, first.data as u8), (u32:3, u4:1, u8:0xaa));
  let third = write_member<u32:8, u32:4>(u32:3, u32:2, u8:0xaa);
  assert_eq((third.addr, third.mask, (third.data >> u32:16) as u8), (u32:3, u4:4, u8:0xaa));
}

// Full-width payloads preserve every bit when positioned in each of six members.
#[test]
fn wide_member_requests_test() {
  let value = u46:0x123456789abc;
  for (member, ()): (u32, ()) in u32:0..u32:6 {
    let request = write_member<u32:46, u32:6>(u32:11, member, value);
    assert_eq(request.mask, u6:1 << member);
    assert_eq((request.data >> (member * u32:46)) as u46, value);
  }(())
}
