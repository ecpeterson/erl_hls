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

pub proc fp64_fmac {
    wire_output: chan<F64>  out;
    wire_reset:  chan<bool> in;  // message type selector
    wire_a:      chan<F64>  in;  // first input operand
    wire_b:      chan<F64>  in;  // second input operand

    config(  // inferred from handle_call branches
      wire_output: chan<F64> out, wire_reset: chan<bool> in,
      wire_a: chan<F64> in, wire_b: chan<F64> in
  ) {
        (wire_output, wire_reset, wire_a, wire_b)
    }

    init { F64_ZERO }  // init

    next(acc: F64) {  // handle_call; acc is typed by gen_server state
        let (tok0, a) = recv(join(), wire_a);  // catch inputs
        let (tok1, b) = recv(join(), wire_b);
        let (tok2, reset) = recv(join(), wire_reset);

        let acc = match reset {  // case out message type
          1 => F64_ZERO,  // branch bodies
          0 => float64::add(float64::mul(a, b), acc)  // fma optimization?
      };

        let tok3 = join(tok0, tok1, tok2);
        send(tok3, wire_output, acc);  // emit result

        acc  // update internal state
    }
}
