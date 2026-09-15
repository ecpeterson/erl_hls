// XLS defines MIN % -1 as zero, but its x86 JIT can trap on LLVM srem's
// overflowing quotient. Remainder by either -1 or +1 is zero; use +1 so the
// primitive never sees that overflow, including in an unselected branch.
// TODO: remove this guard once our pinned XLS handles signed remainder overflow.
// Standalone upstream reproducer: test_data/xls_srem_overflow_repro.x.
pub fn remainder<S: bool, W: u32>(left: xN[S][W], right: xN[S][W]) -> xN[S][W] {
    let divisor = if S && right == (!xN[S][W]:0) { xN[S][W]:1 } else { right };
    left % divisor
}
