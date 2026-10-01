// Run interpreter_main --compare=jit against this file on x86-64.
// XLS v0.0.0-10601-g9f360fc89 can SIGFPE in EmitMod/CreateSRem, while the
// interpreter and generated RTL return zero. This intentionally uses the raw
// primitive, not our hls_integer::remainder workaround; it is not a CI test.
fn remainder(x: s8, y: s8) -> s8 { x % y }

#[test]
fn signed_minimum_modulo_minus_one() {
    assert_eq(remainder(s8:-128, s8:-1), s8:0);
}
