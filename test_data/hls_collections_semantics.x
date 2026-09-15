import hls_lists;

// Each constant access should reduce to wiring, including all failure flags.
pub fn constant_probe(values: u32[3], replacement: u32)
    -> (u32, u32[3], u32[3], u32[2], u4) {
    let (element, a) = hls_lists::nth(u32:2, values);
    let (updated, b) = hls_lists::set(u32:2, values, replacement);
    let (padded, c) = hls_lists::sublist(values, u32:2, u32:1);
    let (slice, d) = hls_lists::slice<u32:2>(values, u32:2);
    (element, updated, padded, slice, a ++ b ++ c ++ d)
}

#[test]
fn constant_accesses() {
    assert_eq(constant_probe(u32[3]:[10, 20, 30], u32:99),
        (u32:20, u32[3]:[10, 99, 30], u32[3]:[20, 0, 0], u32[2]:[20, 30], u4:0));
}

struct Element { value: s8, valid: bool }

#[test]
fn structured_and_nested_elements() {
    let a = Element { value: s8:-7, valid: true };
    let b = Element { value: s8:12, valid: false };
    let values = [a, b];
    assert_eq(hls_lists::nth(s8:2, values), (b, false));
    assert_eq(hls_lists::set(u8:1, values, b), ([b, b], false));
    assert_eq(hls_lists::sublist(values, s8:2, u64:1),
        ([b, zero!<Element>()], false));
    let rows = [values, [b, a]];
    assert_eq(hls_lists::nth(u8:2, rows), ([b, a], false));
    assert_eq(hls_lists::slice<u32:1>(rows, u64:2), ([[b, a]], false));
    assert_eq(hls_lists::nth(s64:-1, rows).1, true);
}
