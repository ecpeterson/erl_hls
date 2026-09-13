// Typed operations share XLS's RNE and signed flush-to-zero arithmetic policy.
// Invalid inputs and overflow contribute a selected callback failure. The
// payload of a failed operation is a placeholder and must not be committed.
import apfloat;

fn nonfinite<E: u32, F: u32>(x: apfloat::APFloat<E, F>) -> bool {
    x.bexp == all_ones!<uN[E]>()
}

fn checked<E: u32, F: u32>(x: apfloat::APFloat<E, F>,
    y: apfloat::APFloat<E, F>, result: apfloat::APFloat<E, F>)
    -> (apfloat::APFloat<E, F>, bool) {
    let failed = nonfinite(x) || nonfinite(y) || nonfinite(result);
    (if failed { zero!<apfloat::APFloat<E, F>>() } else { result }, failed)
}

pub fn add<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (apfloat::APFloat<E, F>, bool) {
    checked(x, y, apfloat::add(x, y))
}

pub fn sub<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (apfloat::APFloat<E, F>, bool) {
    checked(x, y, apfloat::sub(x, y))
}

pub fn mul<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (apfloat::APFloat<E, F>, bool) {
    checked(x, y, apfloat::mul(x, y))
}

pub fn eq<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (bool, bool) {
    (apfloat::eq_2(apfloat::subnormals_to_zero(x), apfloat::subnormals_to_zero(y)),
        nonfinite(x) || nonfinite(y))
}

pub fn lt<E: u32, F: u32>(x: apfloat::APFloat<E, F>, y: apfloat::APFloat<E, F>)
    -> (bool, bool) {
    (apfloat::lt_2(apfloat::subnormals_to_zero(x), apfloat::subnormals_to_zero(y)),
        nonfinite(x) || nonfinite(y))
}
