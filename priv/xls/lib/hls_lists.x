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

// Invalid accesses return a safe placeholder index; the actor's failure
// outcome prevents its associated value or update from becoming observable.
pub fn checked_index<N: u32, S: bool, W: u32>(index: xN[S][W]) -> (u32, bool) {
    const_assert!(N > u32:0);
    let valid = range_valid<N>(index, u32:1);
    (if valid { (index as u32) - u32:1 } else { u32:0 }, !valid)
}

// A typed array_slice and element selection remain at the call site. The mask
// preserves exact range semantics and zero-padding for any element type.
pub fn slice_bounds<N: u32, OUT: u32, SS: bool, SW: u32, CS: bool, CW: u32>
    (start: xN[SS][SW], count: xN[CS][CW]) -> (u32, bool[OUT], bool) {
    const_assert!(N > u32:0 && OUT > u32:0);
    let valid = range_valid<N>(start, count);
    type Mask = bool[OUT];
    let mask = for (i, result): (u32, bool[OUT]) in u32:0..OUT {
        update(result, i, valid && i < (count as u32))
    }(zero!<Mask>());
    ((start as u32) - u32:1, mask, !valid)
}

#[test]
fn bounds_test() {
    assert_eq(checked_index<u32:3>(u8:3), (u32:2, false));
    assert_eq(checked_index<u32:3>(s8:-1), (u32:0, true));
    assert_eq(checked_index<u32:3>(u64:0x100000001), (u32:0, true));
    assert_eq(slice_bounds<u32:3, u32:3>(u8:4, u8:0),
        (u32:3, bool[3]:[false, false, false], false));
    assert_eq(slice_bounds<u32:3, u32:3>(u8:2, u8:2),
        (u32:1, bool[3]:[true, true, false], false));
    assert_eq(range_valid<u32:3>(u64:0xffffffffffffffff, u64:3), false);
    assert_eq(range_valid<u32:3>(u8:1, s8:-1), false);
    assert_eq(range_valid<u32:256>(u8:255, u8:2), true);
}
