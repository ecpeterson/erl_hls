// W must be positive. Add an offset modulo 2^W. The caller may cast a signed offset to uN[W].
pub fn add<W: u32>(value: uN[W], offset: uN[W]) -> uN[W] {
    value + offset
}

// Signed left-minus-right for actual separations strictly below half the range.
// The exactly opposite residue is ambiguous and sets failed; other violations
// of the caller's temporal bound cannot be detected from wrapped values alone.
pub fn difference<W: u32>(left: uN[W], right: uN[W]) -> (sN[W], bool) {
    let delta = (left - right) as sN[W];
    let half = (uN[W]:1 << (W - u32:1)) as sN[W];
    (delta, delta == half)
}

// Strict temporal precedence under difference's half-range contract.
pub fn before<W: u32>(left: uN[W], right: uN[W]) -> (bool, bool) {
    let (delta, failed) = difference(left, right);
    (delta < sN[W]:0, failed)
}
