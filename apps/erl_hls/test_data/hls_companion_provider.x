// Custom provider companion used only by compiler extension fixtures.
import hls_fixed;

// Raw signed Q15.16 value; storage and scaling are owned by the standard codec.
pub type Scalar = s32;

// Three scalar inputs fit in s64 before the final saturating conversion.
pub fn combine(a: Scalar, b: Scalar, c: Scalar) -> Scalar {
    hls_fixed::saturate<u32:32>((a as s64) + (b as s64) + (c as s64))
}
