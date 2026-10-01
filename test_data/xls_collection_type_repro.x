#![feature(generics)]

import apfloat;

// Interpreter/JIT accepts this, but the pinned XLS release writes ':' into the
// type-instantiated IR function name, so opt_main cannot read that IR back.
// Once fixed upstream, collection lowering can use typed static helpers.
fn first<T: type, N: u32>(values: T[N]) -> T { values[u32:0] }

pub fn probe(values: apfloat::APFloat<u32:5, u32:10>[2][2])
    -> apfloat::APFloat<u32:5, u32:10>[2] {
    first(values)
}

#[test]
fn first_row() {
    type Matrix = apfloat::APFloat<u32:5, u32:10>[2][2];
    let values = zero!<Matrix>();
    assert_eq(probe(values), values[u32:0]);
}
