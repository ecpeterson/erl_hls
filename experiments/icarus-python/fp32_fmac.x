// Copyright 2021 The XLS Authors
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

import float32;  // default header stuff, at least when erl uses floats
type F32 = float32::F32;
const F32_ZERO = float32::zero(false);
const F32_ONE  = float32::one(false);

pub proc fp32_fmac {
    wire_output: chan<F32>  out;
    wire_reset:  chan<bool> in;  // message type selector
    wire_a:      chan<F32>  in;  // first input operand
    wire_b:      chan<F32>  in;  // second input operand

    config(  // inferred from handle_call branches
      wire_output: chan<F32> out, wire_reset: chan<bool> in,
      wire_a: chan<F32> in, wire_b: chan<F32> in
  ) {
        (wire_output, wire_reset, wire_a, wire_b)
    }

    init { F32_ZERO }  // init

    next(acc: F32) {  // handle_call; acc is typed by gen_server state
        let (tok0, a) = recv(join(), wire_a);  // catch inputs
        let (tok1, b) = recv(join(), wire_b);
        let (tok2, reset) = recv(join(), wire_reset);

        let acc = match reset {  // case out message type
          1 => F32_ZERO,  // branch bodies
          0 => float32::add(float32::mul(a, b), acc)  // fma optimization?
      };

        let tok3 = join(tok0, tok1, tok2);
        send(tok3, wire_output, acc);  // emit result

        acc  // update internal state
    }
}
