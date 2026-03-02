// Copyright 2021 The XLS Authors
// Lightly modified 2026 Eric Peterson
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#![feature(type_inference_v2)]

import float64;  // default header stuff, at least when erl uses floats
type F64 = float64::F64;
const F64_ZERO = float64::zero(false);
const F64_ONE  = float64::one(false);

pub enum Opcode : u1 {
  FMAC = 0,
  RESET = 1,
}

pub struct Req {
  op: Opcode,
  // inferred from handle_call branches
  a: F64,
  b: F64,
}

pub proc fp64_fmac {
  wire_req:    chan<Req> in;
  wire_output: chan<F64> out;

  config(wire_req: chan<Req> in, wire_output: chan<F64> out) {
    (wire_req, wire_output)
  }

  init { F64_ZERO }  // init

  next(acc: F64) {  // handle_call; acc is typed by gen_server state
    let (tok_req, req) = recv(join(), wire_req);  // catch inputs

    let acc = match req.op {  // case out message type
      Opcode::RESET => F64_ZERO,  // branch bodies
      Opcode::FMAC => float64::add(float64::mul(req.a, req.b), acc)  // fma optimization?
    };

    send(tok_req, wire_output, acc);  // emit result

    acc  // update internal state
  }
}
