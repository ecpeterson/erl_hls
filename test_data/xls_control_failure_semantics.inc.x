// Observe the selected failure kind as well as successful values. Failed
// values are intentionally masked: the compiler promises no value on failure.
pub fn control_probe(mode: u32, x: u32, y: u32) -> bits[35] {
    let (value, failure) = hls_local_evaluate__3(mode, x, y);
    (hls_failure::kind(failure) as u3) ++ (if failure == hls_failure::NONE { value } else { u32:0 })
}
