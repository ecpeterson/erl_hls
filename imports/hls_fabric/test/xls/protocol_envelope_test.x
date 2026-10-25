import axis;
import hls_spatial_router;
import protocol_envelope as envelope;
import protocol_rectangle as rectangle;

// Fixed independent values include high bits in every field that bridge policy allows.
fn packet_fixture() -> envelope::Packet {
  envelope::Packet {
    frame: bits[128]:0x00112233445566778899aabbccddeeff,
    slot: u8:0xf1, link: u16:0xddee, sequence: u32:0x99aabbcc,
    session: u64:0x1122334455667788, kind: u8:1,
  }
}

// Ordered unequal bounds and three unequal payload words make each part observable.
fn rectangle_fixture() -> envelope::RectangleCommand {
  envelope::RectangleCommand {
    x0: u16:0x1234, y0: u16:0x2345, x1: u16:0x4567, y1: u16:0x5678,
    target: u32:2, header: u32:0x9a000003, payload: bits[96]:0x0123456789abcdeffedcba98,
  }
}

// Unequal fields expose byte/field reversals without deriving offsets from the codec.
#[test]
fn packet_vector_test() {
  let packet = packet_fixture();
  let raw = bits[256]:0x01_1122334455667788_99aabbcc_ddee_f1_00112233445566778899aabbccddeeff;
  assert_eq(envelope::pack_packet(packet), raw);
  assert_eq(envelope::unpack_packet(raw), packet);
}

// Raw envelope codecs preserve the whole bit domain; bridge policy owns reserved values.
#[test]
fn packet_limits_test() {
  let zero = envelope::Packet {
    frame: bits[128]:0, slot: u8:0, link: u16:0, sequence: u32:0,
    session: u64:0, kind: u8:0,
  };
  let maximum = envelope::Packet {
    frame: !bits[128]:0, slot: !u8:0, link: !u16:0, sequence: !u32:0,
    session: !u64:0, kind: !u8:0,
  };
  assert_eq(envelope::pack_packet(zero), bits[256]:0);
  assert_eq(envelope::unpack_packet(bits[256]:0), zero);
  assert_eq(envelope::pack_packet(maximum), !bits[256]:0);
  assert_eq(envelope::unpack_packet(!bits[256]:0), maximum);
}

// The host wire vector and native SpatialFrame agree despite their different field order.
#[test]
fn rectangle_vector_test() {
  let command = rectangle_fixture();
  let raw = bits[224]:0x0123456789abcdeffedcba98_9a000003_00000002_5678_4567_2345_1234;
  assert_eq(envelope::pack_rectangle(command), raw);
  assert_eq(envelope::unpack_rectangle(raw), command);
  let decoded = rectangle::decode(raw as bits[256], u8:7);
  let expected = hls_spatial_router::SpatialFrame {
    rectangle: hls_spatial_router::Rectangle {
      x0: u16:0x1234, y0: u16:0x2345, x1: u16:0x4567, y1: u16:0x5678,
    },
    target: u2:2,
    frame: axis::Frame {
      header: axis::Header {payload_words: u8:3, txid: u8:0, flags: u8:0, op: u8:0x9a},
      payload: bits[96]:0x0123456789abcdeffedcba98,
    },
  };
  assert_eq(decoded.valid, true);
  assert_eq(decoded.frame, expected);
  let ingress = u16:0x1234 ++ u16:0x2345 ++ u16:0x4567 ++ u16:0x5678 ++
    u2:2 ++ u8:3 ++ u8:0 ++ u8:0 ++ u8:0x9a ++ bits[96]:0x0123456789abcdeffedcba98;
  assert_eq(rectangle::ingress(decoded.frame), ingress);
}

// Zero through three ordinary payload words all keep their declared length and content.
#[test]
fn rectangle_word_counts_test() {
  let payloads = bits[96][4]:[
    bits[96]:0, bits[96]:0xfedcba98, bits[96]:0x89abcdeffedcba98,
    bits[96]:0x0123456789abcdeffedcba98,
  ];
  for (words, ()): (u32, ()) in u32:0..u32:4 {
    let command = envelope::RectangleCommand {
      header: u32:0x9a000000 | words, payload: payloads[words], ..rectangle_fixture()
    };
    let raw = envelope::pack_rectangle(command) as bits[256];
    let decoded = rectangle::decode(raw, (words + u32:4) as u8);
    assert_eq(decoded.valid, true);
    assert_eq(decoded.frame.frame.header.payload_words, words as u8);
    assert_eq(decoded.frame.frame.payload, payloads[words]);
  }(())
}

// The adapter rejects reserved target/header bits, inverted bounds and length disagreements.
#[test]
fn rectangle_rejections_test() {
  let command = rectangle_fixture();
  let invalid = envelope::RectangleCommand[5]:[
    envelope::RectangleCommand {target: u32:4, ..command},
    envelope::RectangleCommand {header: u32:0x9a000103, ..command},
    envelope::RectangleCommand {header: u32:0x9a010003, ..command},
    envelope::RectangleCommand {x0: u16:0x4568, ..command},
    envelope::RectangleCommand {y0: u16:0x5679, ..command},
  ];
  for (index, ()): (u32, ()) in u32:0..u32:5 {
    let raw = envelope::pack_rectangle(invalid[index]) as bits[256];
    assert_eq(rectangle::decode(raw, u8:7).valid, false);
  }(());
  let raw = envelope::pack_rectangle(command) as bits[256];
  assert_eq(rectangle::decode(raw, u8:3).valid, false);
  assert_eq(rectangle::decode(raw, u8:8).valid, false);
  assert_eq(rectangle::decode(raw, u8:6).valid, false);
  let edge = envelope::RectangleCommand {
    x0: u16:65535, y0: u16:65535, x1: u16:65535, y1: u16:65535,
    target: u32:3, ..command
  };
  assert_eq(rectangle::decode(envelope::pack_rectangle(edge) as bits[256], u8:7).valid, true);
}
