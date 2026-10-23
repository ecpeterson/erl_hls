// Application control adapter for the existing rectangle ABI; no transport/session state.
pub struct Decoded { valid: bool, ingress: bits[194] }
// Decode an unprefixed, word-aligned command. Native ingress still validates route/schema.
pub fn decode(payload: bits[256], words: u8) -> Decoded {
  Decoded {
    valid: words >= u8:4 && words <= u8:7 &&
      payload[66+:bits[30]] == bits[30]:0 && payload[104+:u16] == u16:0 &&
      payload[96+:u8] == words-u8:4 && payload[0+:u16] <= payload[32+:u16] &&
      payload[16+:u16] <= payload[48+:u16],
    ingress: payload[0+:u16] ++ payload[16+:u16] ++ payload[32+:u16] ++ payload[48+:u16] ++
      payload[64+:u2] ++ payload[96+:u8] ++ payload[104+:u8] ++ payload[112+:u8] ++
      payload[120+:u8] ++ payload[128+:bits[96]],
  }
}
