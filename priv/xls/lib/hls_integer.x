// XLS defines MIN % -1 as zero, but its x86 JIT can trap on LLVM srem's
// overflowing quotient. Remainder by either -1 or +1 is zero; use +1 so the
// primitive never sees that overflow, including in an unselected branch.
// TODO: remove this guard once our pinned XLS handles signed remainder overflow.
// Standalone upstream reproducer: test_data/xls_srem_overflow_repro.x.
pub fn remainder<S: bool, W: u32>(left: xN[S][W], right: xN[S][W]) -> xN[S][W] {
    // s1 cannot represent +1. Its only nonzero divisor is -1 and every valid
    // remainder is zero; clear the dividend so even that primitive is safe.
    let dividend = if S && W == u32:1 { xN[S][W]:0 } else { left };
    let divisor = if S && right == (!xN[S][W]:0) { u1:1 as xN[S][W] } else { right };
    dividend % divisor
}

#[test]
fn one_bit_remainder() {
    assert_eq(remainder(s1:-1, s1:-1), s1:0);
    assert_eq(remainder(s1:0, s1:-1), s1:0);
    assert_eq(remainder(u1:1, u1:1), u1:0);
}

// Erlang reverses the direction for a negative count. Value and count widths
// are independent. Take the magnitude in unsigned arithmetic so MIN_COUNT
// remains representable, and retain all count bits (overshifts never wrap).
// A signed value's >> is arithmetic. LEFT and unsigned-count direction checks
// are compile-time constants; ordinary unsigned shifts need no reverse path.
pub fn shift<LEFT: bool, S: bool, W: u32, CS: bool, CW: u32>(
    value: xN[S][W], count: xN[CS][CW]) -> xN[S][W] {
    let reverse = CS && count < xN[CS][CW]:0;
    let magnitude = if reverse { uN[CW]:0 - (count as uN[CW]) }
                    else { count as uN[CW] };
    if LEFT != reverse { value << magnitude } else { value >> magnitude }
}

#[test]
fn shift_extremes() {
    assert_eq(shift<true>(s8:-8, s16:-2), s8:-2);
    assert_eq(shift<true>(s8:-8, s8:-128), s8:-1);
    assert_eq(shift<false>(s8:-8, s8:-128), s8:0);
    assert_eq(shift<true>(u8:255, s64:-9223372036854775808), u8:0);
    assert_eq(shift<false>(s8:-8, s64:-9223372036854775808), s8:0);
    assert_eq(shift<false>(s8:-8, u64:18446744073709551615), s8:-1);
    assert_eq(shift<true>(u8:1, u64:4294967296), u8:0);
    assert_eq(shift<false>(u64:0x8000000000000000, u8:63), u64:1);
    assert_eq(shift<true>(s1:-1, s1:-1), s1:-1);
    assert_eq(shift<false>(s1:-1, s1:-1), s1:0);
}

// Widen both operands losslessly before comparing mathematical values. An
// unsigned operand needs one extra sign bit; same-type comparisons optimize
// back to their original width. Arithmetic producing the operands is unchanged.
pub fn less<S: bool, W: u32, T: bool, V: u32>(left: xN[S][W], right: xN[T][V]) -> bool {
    const N = if W > V { W + u32:1 } else { V + u32:1 };
    (left as sN[N]) < (right as sN[N])
}

// Include equality without subtracting, so the distance cannot overflow.
pub fn less_equal<S: bool, W: u32, T: bool, V: u32>(left: xN[S][W], right: xN[T][V]) -> bool {
    const N = if W > V { W + u32:1 } else { V + u32:1 };
    (left as sN[N]) <= (right as sN[N])
}

// Equal bit patterns with different signedness need not be equal integers.
pub fn equal<S: bool, W: u32, T: bool, V: u32>(left: xN[S][W], right: xN[T][V]) -> bool {
    const N = if W > V { W + u32:1 } else { V + u32:1 };
    (left as sN[N]) == (right as sN[N])
}
