// regsvc.x
//
// XLS implementation of axis_regsvc.v .

// TODO:
//  + parametrize over register file size
//  + decouple in packet size from out packet size
// desiderata:
//  + `as struct`
//  + `<T: type>`

import axis;

const NUM_REGS = u32:16;
const MAX_PAYLOAD = u32:3;

pub enum RequestOp : u8 {
  GET      = u8:0x01,
  SET      = u8:0x02,
  BULK_GET = u8:0x03,
  PING     = u8:0x04,
}

pub enum ResponseOp : u8 {
  NONE  = u8:0x00,  // suppress emission
  PING  = u8:0x81,
  READ  = u8:0x82,
  BULK  = u8:0x83,
  ERROR = u8:0xe0,
  EVENT = u8:0xf0,
}

pub enum Err : u32 {
  BAD_OPCODE   = u32:1,
  BAD_LENGTH   = u32:2,
  BAD_REGISTER = u32:3,
}

// in
struct RequestGet { register: u32, }
fn requestget_from_bits<N: u32>(raw: bits[N]) -> RequestGet {
  RequestGet { register: raw as u32 }
}
struct RequestSet { register: u32, value: u32, mask: u32, }
fn requestset_from_bits<N: u32>(raw: bits[N]) -> RequestSet {
  RequestSet { register: raw[0:32], value: raw[32:64], mask: raw[64:96] }
}
struct RequestBulkGet { start: u32, count: u32, }
fn requestbulkget_from_bits<N: u32>(raw: bits[N]) -> RequestBulkGet {
  RequestBulkGet { start: raw[0:32], count: raw[32:64] }
}
struct RequestPing { value: u32, }
fn requestping_from_bits<N: u32>(raw: bits[N]) -> RequestPing {
  RequestPing { value: raw[0:32] }
}

// out
struct ResponseErr { err: Err, }
fn bits_from_responseerr(s: ResponseErr) -> bits[bit_count<ResponseErr>()] {
  s.err as u32
}
struct ResponseRead { register: u32, value: u32, }
fn bits_from_responseread(s: ResponseRead) -> bits[bit_count<ResponseRead>()] {
  s.value ++ s.register
}
struct ResponseBulk { values: u32[MAX_PAYLOAD], }
fn bits_from_responsebulk(s: ResponseBulk) -> bits[bit_count<ResponseBulk>()] {
  s.values as bits[32 * MAX_PAYLOAD]
}
struct ResponsePing { value: u32, }
fn bits_from_responseping(s: ResponsePing) -> bits[bit_count<ResponsePing>()] {
  s.value
}

pub fn is_valid_reg(r: u32) -> bool {
  r < NUM_REGS
}

struct State { registers: u32[16], }

proc RegisterService {
  req_in:   chan<axis::Frame> in;
  resp_out: chan<axis::Frame> out;

  config(req_in: chan<axis::Frame> in, resp_out: chan<axis::Frame> out) {
    (req_in, resp_out)
  }

  init { zero!<State>() }

  next(state: State) {
    let (tok1, frame) = recv(join(), req_in);

    // cognate to {reply, Reply, State}
    let (resp, new_state) = match frame.header.op as RequestOp {
      RequestOp::GET => {
        let request = requestget_from_bits(frame.payload);
        if !is_valid_reg(request.register) {
          (axis::pack(ResponseOp::ERROR as u8,
                      bits_from_responseerr(ResponseErr { err: Err::BAD_REGISTER })
          ), state)
        } else {
          let register = request.register;
          let value = state.registers[register];
          (axis::pack(ResponseOp::READ as u8,
                      bits_from_responseread(ResponseRead { register, value })
          ), state)
        }
      },

      RequestOp::SET => {
        let request = requestset_from_bits(frame.payload);
        if !is_valid_reg(request.register) {
          (axis::pack(ResponseOp::ERROR as u8,
                      bits_from_responseerr(ResponseErr { err: Err::BAD_REGISTER })
          ), state)
        } else {
          let old_value = state.registers[request.register as u32];
          let new_value = (old_value & !request.mask) | (request.value & request.mask);
          let registers = update(state.registers, request.register, new_value);
          (zero!<axis::Frame>(), State { registers })
        }
      },

      RequestOp::BULK_GET => {
        let request = requestbulkget_from_bits(frame.payload);
        if (!is_valid_reg(request.start) ||
            !is_valid_reg(request.start + request.count)) {
          (axis::pack(ResponseOp::ERROR as u8,
                      bits_from_responseerr(ResponseErr { err: Err::BAD_REGISTER })
          ), state)
        } else {
          let all_values = state.registers as bits[32 * NUM_REGS];
          let drop_front = all_values >> (request.start * 32);
          let drop_back = drop_front & (all_ones!<bits[32 * NUM_REGS]>() << (request.count * 32));
          let values = drop_back as bits[32 * MAX_PAYLOAD] as u32[MAX_PAYLOAD];
          let naive_pack = axis::pack(ResponseOp::BULK as u8,
                                      bits_from_responsebulk(ResponseBulk { values }));
          let fixed_header = axis::Header { payload_words: request.count as u8, ..naive_pack.header};
          (axis::Frame { header: fixed_header, ..naive_pack }, state)
        }
      },

      RequestOp::PING => {
        let request = requestping_from_bits(frame.payload);
        (axis::pack(ResponseOp::PING as u8,
                    bits_from_responseping(ResponsePing { value: request.value })
        ), state)
      },

      _ => {
        (axis::pack(ResponseOp::ERROR as u8,
                    bits_from_responseerr(ResponseErr { err: Err::BAD_OPCODE })
        ), state)
      }
    };

    let txid = frame.header.txid;
    let resp2 = axis::Frame { header: axis::Header { txid, ..resp.header }, ..resp };
    send_if(tok1, resp_out, resp2.header.op != ResponseOp::NONE as u8, resp2);
    new_state
  }
}

proc Top {
  ext_recv: chan<axis::Beat> in;
  ext_send: chan<axis::Beat> out;

  config(ext_recv: chan<axis::Beat> in, ext_send: chan<axis::Beat> out) {
    let (req_p,  req_c ) = chan<axis::Frame, u32:1>("req");
    let (resp_p, resp_c) = chan<axis::Frame, u32:1>("resp");

    spawn axis::Rx(ext_recv, req_p);
    spawn RegisterService(req_c, resp_p);
    spawn axis::Tx(resp_c, ext_send);

    (ext_recv, ext_send)
  }

  init { () }

  next(state: ()) { state }
}
