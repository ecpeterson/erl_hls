// Typed request and response records for XLS external RAM channels.
//
// The empty masks describe whole-row accesses. A codegen RAM configuration
// assigns these four channel shapes to a physical 1R1W memory interface.

// Request one whole row at a physical RAM address.
pub struct ReadReq {
  addr: u32,
  mask: (),
}

// Complete row returned for an accepted read, in request order.
pub struct ReadResp<DATA_BITS: u32> {
  data: bits[DATA_BITS],
}

// Replace one whole row at a physical RAM address.
pub struct WriteReq<DATA_BITS: u32> {
  addr: u32,
  data: bits[DATA_BITS],
  mask: (),
}

// Completion token for one accepted write; carries no data.
pub struct WriteResp {}

// Construct an unmasked read; the caller must supply an in-range address.
pub fn read(addr: u32) -> ReadReq {
  ReadReq { addr, mask: () }
}

// Construct an unmasked write; the caller must supply an in-range address.
pub fn write<DATA_BITS: u32>(
    addr: u32, data: bits[DATA_BITS]) -> WriteReq<DATA_BITS> {
  WriteReq { addr, data, mask: () }
}

// Confirm that constructors preserve addresses and whole-row payloads.
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
