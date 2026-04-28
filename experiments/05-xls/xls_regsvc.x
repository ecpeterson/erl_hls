// axis_regsvc.x
//
// XLS implementation of axis_regsvc.v .
//
// TODO:
//  + bulk get
//  + make better use of arrays: register file, multiword messages
//  + parametrize over max message size, register file size, ...
//  + split axis pipes into separate modules for re-use

pub struct AXISIn {
  tlast: u1,
  word: u32,
}

pub struct AXISOut {
  tlast: u1,
  word: u32,
}

pub enum Op : u8 {
  GET      = u8:0x01,
  SET      = u8:0x02,
  BULK_GET = u8:0x03,
  PING     = u8:0x04,

  ACK      = u8:0x81,
  READ_RSP = u8:0x82,
  BULK_RSP = u8:0x83,
  ERROR    = u8:0xe0,
  EVENT    = u8:0xf0,
}

pub enum Err : u8 {
  BAD_OPCODE   = u8:1,
  BAD_LENGTH   = u8:2,
  BAD_REGISTER = u8:3,
}

const NUM_REGS = u32:16;
const MAX_PAYLOAD = u8:3;

pub struct Header {
  op: u8,
  flags: u8,
  txid: u8,
  payload_words: u8,
}

pub struct Instr {
  hdr: Header,
  w0: u32,
  w1: u32,
  w2: u32,
  actual_payload_words: u8,
}

pub enum RespKind : u8 {
  NONE = u8:0,
  READ = u8:1,
  BULK = u8:2,
  PING = u8:3,
  ERROR = u8:4,
}

pub struct Resp {
  kind: RespKind,
  txid: u8,
  err: u8,
  reg: u8,
  value: u32,
  bulk_start: u8,
  bulk_count: u8,
  cookie: u32,
}

pub fn decode_header(w: u32) -> Header {
  Header {
    op: (w >> u32:24) as u8,
    flags: (w >> u32:16) as u8,
    txid: (w >> u32:8) as u8,
    payload_words: w as u8,
  }
}

pub fn make_header(op: u8, flags: u8, txid: u8, payload_words: u8) -> u32 {
  ((op as u32) << u32:24) |
  ((flags as u32) << u32:16) |
  ((txid as u32) << u32:8) |
  (payload_words as u32)
}

pub fn is_valid_reg(r: u8) -> bool {
  (r as u32) < NUM_REGS
}

pub fn no_resp() -> Resp {
  Resp {
    kind: RespKind::NONE,
    txid: u8:0,
    err: u8:0,
    reg: u8:0,
    value: u32:0,
    bulk_start: u8:0,
    bulk_count: u8:0,
    cookie: u32:0,
  }
}

pub fn err_resp(txid: u8, err: u8) -> Resp {
  Resp {
    kind: RespKind::ERROR,
    txid,
    err,
    reg: u8:0,
    value: u32:0,
    bulk_start: u8:0,
    bulk_count: u8:0,
    cookie: u32:0,
  }
}

pub fn ping_resp(txid: u8, cookie: u32) -> Resp {
  Resp {
    kind: RespKind::PING,
    txid,
    err: u8:0,
    reg: u8:0,
    value: u32:0,
    bulk_start: u8:0,
    bulk_count: u8:0,
    cookie,
  }
}

pub fn read_resp(txid: u8, reg: u8, value: u32) -> Resp {
  Resp {
    kind: RespKind::READ,
    txid,
    err: u8:0,
    reg,
    value,
    bulk_start: u8:0,
    bulk_count: u8:0,
    cookie: u32:0,
  }
}

pub fn bulk_resp(txid: u8, start: u8, count: u8) -> Resp {
  Resp {
    kind: RespKind::BULK,
    txid,
    err: u8:0,
    reg: u8:0,
    value: u32:0,
    bulk_start: start,
    bulk_count: count,
    cookie: u32:0,
  }
}

enum RxState : u2 {
  IDLE = u2:0,
  PAYLOAD = u2:1,
}

struct RxSt {
  state: RxState,
  hdr: Header,
  payload_seen: u8,
  w0: u32,
  w1: u32,
  w2: u32,
}

proc AxisRx {
  axis_in: chan<AXISIn> in;
  instr_out: chan<Instr> out;

  config(axis_in: chan<AXISIn> in, instr_out: chan<Instr> out) {
    (axis_in, instr_out)
  }

  init {
    RxSt {
      state: RxState::IDLE,
      hdr: Header { op: u8:0, flags: u8:0, txid: u8:0, payload_words: u8:0 },
      payload_seen: u8:0,
      w0: u32:0,
      w1: u32:0,
      w2: u32:0,
    }
  }

  next(st: RxSt) {
    let (tok1, beat) = recv(join(), axis_in);

    let next_st = match st.state {
      RxState::IDLE => {
        let hdr = decode_header(beat.word);

        if beat.tlast {
          let instr = Instr {
            hdr,
            w0: u32:0,
            w1: u32:0,
            w2: u32:0,
            actual_payload_words: u8:0,
          };
          let tok2 = send(tok1, instr_out, instr);
          RxSt {
            state: RxState::IDLE,
            hdr,
            payload_seen: u8:0,
            w0: u32:0,
            w1: u32:0,
            w2: u32:0,
          }
        } else {
          RxSt {
            state: RxState::PAYLOAD,
            hdr,
            payload_seen: u8:0,
            w0: u32:0,
            w1: u32:0,
            w2: u32:0,
          }
        }
      },

      RxState::PAYLOAD => {
        let seen = st.payload_seen;
        let nw0 = if seen == u8:0 { beat.word } else { st.w0 };
        let nw1 = if seen == u8:1 { beat.word } else { st.w1 };
        let nw2 = if seen == u8:2 { beat.word } else { st.w2 };
        let nseen = seen + u8:1;

        if beat.tlast {
          let instr = Instr {
            hdr: st.hdr,
            w0: nw0,
            w1: nw1,
            w2: nw2,
            actual_payload_words: nseen,
          };
          let tok2 = send(tok1, instr_out, instr);
          RxSt {
            state: RxState::IDLE,
            hdr: st.hdr,
            payload_seen: u8:0,
            w0: u32:0,
            w1: u32:0,
            w2: u32:0,
          }
        } else {
          RxSt {
            state: RxState::PAYLOAD,
            hdr: st.hdr,
            payload_seen: nseen,
            w0: nw0,
            w1: nw1,
            w2: nw2,
          }
        }
      },
    };

    next_st
  }
}

struct ExecSt {
  regs: u32[16],
}

fn init_regs() -> u32[16] {
  u32[16]:[
    u32:0, u32:0, u32:0, u32:0,
    u32:0, u32:0, u32:0, u32:0,
    u32:0, u32:0, u32:0, u32:0,
    u32:0, u32:0, u32:0, u32:0,
  ]
}

proc RegExec {
  instr_in: chan<Instr> in;
  resp_out: chan<Resp> out;

  config(instr_in: chan<Instr> in, resp_out: chan<Resp> out) {
    (instr_in, resp_out)
  }

  init {
    ExecSt { regs: init_regs() }
  }

  next(st: ExecSt) {
    let tok0 = join();
    let (tok1, instr) = recv(tok0, instr_in);

    let hdr = instr.hdr;
    let bad_len = instr.actual_payload_words != hdr.payload_words;
    let reg = instr.w0 as u8;
    let count = instr.w1 as u8;

    let old_value = if is_valid_reg(reg) {
      st.regs[reg as u32]
    } else {
      u32:0
    };

    let set_value = instr.w1;
    let set_mask = instr.w2;
    let new_value = (old_value & !set_mask) | (set_value & set_mask);

    let bulk_bad = (!is_valid_reg(reg)) ||
                   (count == u8:0) ||
                   (((reg as u32) + (count as u32)) > NUM_REGS);

    let resp = if bad_len {
      err_resp(hdr.txid, Err::BAD_LENGTH as u8)
    } else if hdr.op == (Op::GET as u8) {
      if hdr.payload_words != u8:1 {
        err_resp(hdr.txid, Err::BAD_LENGTH as u8)
      } else if !is_valid_reg(reg) {
        err_resp(hdr.txid, Err::BAD_REGISTER as u8)
      } else {
        read_resp(hdr.txid, reg, old_value)
      }
    } else if hdr.op == (Op::SET as u8) {
      if hdr.payload_words != u8:3 {
        err_resp(hdr.txid, Err::BAD_LENGTH as u8)
      } else if !is_valid_reg(reg) {
        err_resp(hdr.txid, Err::BAD_REGISTER as u8)
      } else {
        no_resp()
      }
    } else if hdr.op == (Op::BULK_GET as u8) {
      if hdr.payload_words != u8:2 {
        err_resp(hdr.txid, Err::BAD_LENGTH as u8)
      } else if bulk_bad {
        err_resp(hdr.txid, Err::BAD_REGISTER as u8)
      } else {
        bulk_resp(hdr.txid, reg, count)
      }
    } else if hdr.op == (Op::PING as u8) {
      if hdr.payload_words != u8:1 {
        err_resp(hdr.txid, Err::BAD_LENGTH as u8)
      } else {
        ping_resp(hdr.txid, instr.w0)
      }
    } else {
      err_resp(hdr.txid, Err::BAD_OPCODE as u8)
    };

    let nregs = if (!bad_len) &&
                   hdr.op == (Op::SET as u8) &&
                   hdr.payload_words == u8:3 &&
                   is_valid_reg(reg) {
      update(st.regs, reg as u32, new_value)
    } else {
      st.regs
    };

    if resp.kind != RespKind::NONE {
      let tok2 = send(tok1, resp_out, resp);
    } else {
      ()
    };

    ExecSt { regs: nregs }
  }
}

enum TxState : u3 {
  IDLE = u3:0,
  W0 = u3:1,
  W1 = u3:2,
  W2 = u3:3,
  BULK_META = u3:4,
  BULK_DATA = u3:5,
}

struct TxSt {
  state: TxState,
  resp: Resp,
  bulk_index: u8,
  regs_snapshot: u32[16],
}

// In this first cut, BULK response values cannot be generated in TxProc
// unless TxProc has a copy of the register file. There are two choices:
//   A. carry the bulk data values inside Resp, increasing message size;
//   B. have ExecProc convert BULK_GET into multiple response packets;
//   C. give TxProc a register snapshot.
// This draft chooses a placeholder snapshot initialized to zero.
// For production, I would change Resp to include data words for BULK.
proc AxisTx {
  resp_in: chan<Resp> in;
  axis_out: chan<AXISOut> out;

  config(resp_in: chan<Resp> in, axis_out: chan<AXISOut> out) {
    (resp_in, axis_out)
  }

  init {
    TxSt {
      state: TxState::IDLE,
      resp: no_resp(),
      bulk_index: u8:0,
      regs_snapshot: init_regs(),
    }
  }

  next(st: TxSt) {
    let tok0 = join();

    let next_st = match st.state {
      TxState::IDLE => {
        let (tok1, resp) = recv(tok0, resp_in);

        if resp.kind == RespKind::READ {
          let word = make_header(Op::READ_RSP as u8, u8:0, resp.txid, u8:2);
          let beat = AXISOut { tlast: u1:0, word };
          let tok2 = send(tok1, axis_out, beat);
          TxSt { state: TxState::W1, resp, bulk_index: u8:0, regs_snapshot: st.regs_snapshot }

        } else if resp.kind == RespKind::PING {
          let word = make_header(Op::ACK as u8, u8:1, resp.txid, u8:1);
          let beat = AXISOut { tlast: u1:0, word };
          let tok2 = send(tok1, axis_out, beat);
          TxSt { state: TxState::W1, resp, bulk_index: u8:0, regs_snapshot: st.regs_snapshot }

        } else if resp.kind == RespKind::ERROR {
          let word = make_header(Op::ERROR as u8, u8:0, resp.txid, u8:1);
          let beat = AXISOut { tlast: u1:0, word };
          let tok2 = send(tok1, axis_out, beat);
          TxSt { state: TxState::W1, resp, bulk_index: u8:0, regs_snapshot: st.regs_snapshot }

        } else if resp.kind == RespKind::BULK {
          let word = make_header(Op::BULK_RSP as u8, u8:0, resp.txid,
                                 resp.bulk_count + u8:1);
          let beat = AXISOut { tlast: u1:0, word };
          let tok2 = send(tok1, axis_out, beat);
          TxSt { state: TxState::BULK_META, resp, bulk_index: u8:0, regs_snapshot: st.regs_snapshot }

        } else {
          st
        }
      },

      TxState::W1 => {
        let word = if st.resp.kind == RespKind::PING {
          st.resp.cookie
        } else if st.resp.kind == RespKind::ERROR {
          st.resp.err as u32
        } else {
          st.resp.reg as u32
        };

        let last = if st.resp.kind == RespKind::PING ||
                      st.resp.kind == RespKind::ERROR { u1:1 } else { u1:0 };
        let beat = AXISOut { tlast: last, word };
        let tok1 = send(tok0, axis_out, beat);

        if last {
          TxSt { state: TxState::IDLE, resp: no_resp(), bulk_index: u8:0, regs_snapshot: st.regs_snapshot }
        } else {
          TxSt { state: TxState::W2, resp: st.resp, bulk_index: u8:0, regs_snapshot: st.regs_snapshot }
        }
      },

      TxState::W2 => {
        let beat = AXISOut { tlast: u1:1, word: st.resp.value };
        let tok1 = send(tok0, axis_out, beat);
        TxSt { state: TxState::IDLE, resp: no_resp(), bulk_index: u8:0, regs_snapshot: st.regs_snapshot }
      },

      TxState::BULK_META => {
        let meta = ((st.resp.bulk_start as u32) << u32:8) |
                   (st.resp.bulk_count as u32);
        let beat = AXISOut { tlast: u1:0, word: meta };
        let tok1 = send(tok0, axis_out, beat);
        TxSt { state: TxState::BULK_DATA, resp: st.resp, bulk_index: u8:0, regs_snapshot: st.regs_snapshot }
      },

      TxState::BULK_DATA => {
        let idx = st.resp.bulk_start + st.bulk_index;
        let value = st.regs_snapshot[idx as u32];
        let last = if st.bulk_index == (st.resp.bulk_count - u8:1) { u1:1 } else { u1:0 };
        let beat = AXISOut { tlast: last, word: value };
        let tok1 = send(tok0, axis_out, beat);

        if last {
          TxSt { state: TxState::IDLE, resp: no_resp(), bulk_index: u8:0, regs_snapshot: st.regs_snapshot }
        } else {
          TxSt {
            state: TxState::BULK_DATA,
            resp: st.resp,
            bulk_index: st.bulk_index + u8:1,
            regs_snapshot: st.regs_snapshot,
          }
        }
      },

      _ => st,
    };

    next_st
  }
}

proc Top {
  ext_recv: chan<AXISIn> in;
  ext_send: chan<AXISOut> out;

  config(ext_recv: chan<AXISIn> in, ext_send: chan<AXISOut> out) {
    let (instr_p, instr_c) = chan<Instr, u32:1>("instr");
    let (resp_p, resp_c) = chan<Resp, u32:1>("resp");

    spawn AxisRx(ext_recv, instr_p);
    spawn RegExec(instr_c, resp_p);
    spawn AxisTx(resp_c, ext_send);

    (ext_recv, ext_send)
  }

  init {
    ()
  }

  next(st: ()) {
    st
  }
}
