#![feature(generics)]

import std;

// One-based, exact bounds. Widen before comparing so negative or very large
// indices cannot become valid through truncation. Subtract after checking the
// start bound rather than adding start + count in the caller's integer width.
pub fn range_valid<N: u32, SS: bool, SW: u32, CS: bool, CW: u32>
    (start: xN[SS][SW], count: xN[CS][CW]) -> bool {
    type Bound = uN[std::max(std::max(SW, CW), u32:33)];
    let end = (N as Bound) + Bound:1;
    start > 0 && count >= 0 && (start as Bound) <= end &&
        (count as Bound) <= end - (start as Bound)
}

pub fn nth<T: type, N: u32, S: bool, W: u32>
    (index: xN[S][W], values: T[N]) -> (T, bool) {
    const_assert!(N > u32:0);
    let valid = range_valid<N>(index, u32:1);
    let value = if valid { values[(index as u32) - u32:1] }
        else { zero!<T>() };
    (value, !valid)
}

pub fn set<T: type, N: u32, S: bool, W: u32>
    (index: xN[S][W], values: T[N], value: T) -> (T[N], bool) {
    const_assert!(N > u32:0);
    let valid = range_valid<N>(index, u32:1);
    (if valid { update(values, (index as u32) - u32:1, value) } else { values }, !valid)
}

pub fn slice<OUT: u32, T: type, N: u32, S: bool, W: u32>
    (values: T[N], start: xN[S][W]) -> (T[OUT], bool) {
    const_assert!(N > u32:0 && OUT > u32:0);
    type Result = T[OUT];
    let valid = range_valid<N>(start, OUT);
    (if valid { array_slice(values, (start as u32) - u32:1, zero!<Result>()) }
        else { zero!<Result>() }, !valid)
}

// Keep the input's length, with the exact selected range followed by zeroes.
pub fn sublist<T: type, N: u32, SS: bool, SW: u32, CS: bool, CW: u32>
    (values: T[N], start: xN[SS][SW], count: xN[CS][CW]) -> (T[N], bool) {
    const_assert!(N > u32:0);
    type Result = T[N];
    let valid = range_valid<N>(start, count);
    let shifted = array_slice(values, (start as u32) - u32:1, zero!<Result>());
    let selected = for (i, result): (u32, Result) in u32:0..N {
        update(result, i, if valid && i < (count as u32) { shifted[i] } else { zero!<T>() })
    }(zero!<Result>());
    (selected, !valid)
}

#[test]
fn bounds_test() {
    let values = u8[3]:[10, 20, 30];
    assert_eq(nth(u8:3, values), (u8:30, false));
    assert_eq(nth(s8:-1, values).1, true);
    assert_eq(nth(u64:0x100000001, values).1, true);
    assert_eq(set(u8:0, values, u8:99), (values, true));
    assert_eq(slice<u32:2>(values, u8:2), (u8[2]:[20, 30], false));
    assert_eq(slice<u32:2>(values, u8:3).1, true);
    assert_eq(sublist(values, u8:4, u8:0), (u8[3]:[0, 0, 0], false));
    assert_eq(sublist(values, u8:2, u8:2), (u8[3]:[20, 30, 0], false));
    assert_eq(sublist(values, u64:0xffffffffffffffff, u64:3).1, true);
    assert_eq(sublist(values, u8:1, s8:-1).1, true);
    assert_eq(range_valid<u32:256>(u8:255, u8:2), true);
}
