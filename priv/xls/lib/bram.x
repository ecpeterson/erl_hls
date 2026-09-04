// Typed request and response records for XLS external RAM channels.
//
// The empty masks describe whole-row accesses. A codegen RAM configuration
// assigns these four channel shapes to a physical 1R1W memory interface.

pub struct ReadReq {
  addr: u32,
  mask: (),
}

pub struct ReadResp<DATA_BITS: u32> {
  data: bits[DATA_BITS],
}

pub struct WriteReq<DATA_BITS: u32> {
  addr: u32,
  data: bits[DATA_BITS],
  mask: (),
}

pub struct WriteResp {}

pub fn read(addr: u32) -> ReadReq {
  ReadReq { addr, mask: () }
}

pub fn write<DATA_BITS: u32>(
    addr: u32, data: bits[DATA_BITS]) -> WriteReq<DATA_BITS> {
  WriteReq { addr, data, mask: () }
}

#[test]
fn whole_row_requests_test() {
  assert_eq(read(u32:7), ReadReq { addr: u32:7, mask: () });
  assert_eq(
    write(u32:9, uN[17]:0x12345),
    WriteReq<u32:17> {
      addr: u32:9,
      data: uN[17]:0x12345,
      mask: (),
    });
}
