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

import float32;
import apfloat_fmac;

type F32 = float32::F32;

const F32_ZERO = float32::zero(false);
const F32_ONE = float32::one(false);

pub proc fp32_fmac {
    init { () }

    config(input_a: chan<F32> in, input_b: chan<F32> in,
          reset: chan<bool> in, output: chan<F32> out) {
        spawn apfloat_fmac::fmac<u32:8, u32:23>(input_a, input_b, reset, output);
    }

    // Nothing to do here - the spawned fmac does all the lifting.
    next(state: ()) { () }
}

