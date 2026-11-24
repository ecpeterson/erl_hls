// Typed operations share XLS's RNE and signed flush-to-zero arithmetic policy.
// Invalid inputs and overflow contribute a selected callback failure. The
// payload of a failed operation is a placeholder and must not be committed.
import apfloat;

// Detects infinity or NaN from an all-ones exponent, independent of fraction bits.
fn nonfinite<E: u32, F: u32>(x: apfloat::APFloat<E, F>) -> bool {
    x.bexp == all_ones!<uN[E]>()
}

// Returns a finite result with false, or a zero placeholder with true on nonfinite data.
fn checked<E: u32, F: u32>(x: apfloat::APFloat<E, F>,
    y: apfloat::APFloat<E, F>, result: apfloat::APFloat<E, F>)
    -> (apfloat::APFloat<E, F>, bool) {
    let failed = nonfinite(x) || nonfinite(y) || nonfinite(result);
    (if failed { zero!<apfloat::APFloat<E, F>>() } else { result }, failed)
}

// Adds finite operands with XLS RNE/flush-to-zero policy and flags nonfinite outcomes.
pub fn add<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (apfloat::APFloat<E, F>, bool) {
    checked(x, y, apfloat::add(x, y))
}

// Subtracts finite operands with XLS RNE/flush-to-zero policy and flags nonfinite outcomes.
pub fn sub<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (apfloat::APFloat<E, F>, bool) {
    checked(x, y, apfloat::sub(x, y))
}

// Multiplies finite operands with XLS RNE/flush-to-zero policy and flags nonfinite outcomes.
pub fn mul<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (apfloat::APFloat<E, F>, bool) {
    checked(x, y, apfloat::mul(x, y))
}

// Compares after flushing subnormals; the predicate is invalid when either input is nonfinite.
pub fn eq<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (bool, bool) {
    (apfloat::eq_2(apfloat::subnormals_to_zero(x), apfloat::subnormals_to_zero(y)),
        nonfinite(x) || nonfinite(y))
}

// Orders after flushing subnormals; the predicate is invalid when either input is nonfinite.
pub fn lt<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (bool, bool) {
    (apfloat::lt_2(apfloat::subnormals_to_zero(x), apfloat::subnormals_to_zero(y)),
        nonfinite(x) || nonfinite(y))
}
