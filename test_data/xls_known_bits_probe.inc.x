
// Same-cycle entry observation for every typed cell value. Failure placeholders
// are unobservable; retain the exact failure code and mask only uncommitted data.
pub fn codec_probe(cell_bits: bits[42]) -> bits[338] {
    let cell = Cell { value: cell_bits[0:16], small: cell_bits[16:21],
        signed: cell_bits[21:26] as s5, denominator: cell_bits[26:42] };
    let o = enter(Phase::ACTIVE, Phase::ACTIVE, cell);
    let count = if o.failure == hls_failure::NONE { entry_effect_count(o.effects) } else { u8:0 };
    let data = if o.failure == hls_failure::NONE { o.data } else { cell };
    let a = if count > u8:0 { entry_effect(o.effects, u8:0) } else { zero!<Egress>() };
    let b = if count > u8:1 { entry_effect(o.effects, u8:1) } else { zero!<Egress>() };
    o.failure ++ data.value ++ data.small ++ (data.signed as u5) ++ data.denominator ++ count ++
        (a.port as u8) ++ axis::bits_from_frame(a.frame) ++ (b.port as u8) ++ axis::bits_from_frame(b.frame)
}

// Eight machine steps from initialized entry state with every ready/stall pattern.
// Observe all accepted frames in order plus terminal data, failure and pending state.
pub fn stalled_probe(cell_bits: bits[42], ready: u8) -> bits[339] {
    let cell = Cell { value: cell_bits[0:16], small: cell_bits[16:21],
        signed: cell_bits[21:26] as s5, denominator: cell_bits[26:42] };
    let initial = Machine { data: cell, ..initial_machine() };
    let (m, count, frames) = for (i, state): (u32, (Machine, u8, bits[272])) in u32:0..u32:8 {
        let (m, count, frames) = state;
        let step = machine_step(m, zero!<axis::Frame>(), false, ((ready >> i) as u1) != u1:0);
        let accepted = (step.egress.port as u8) ++ axis::bits_from_frame(step.egress.frame);
        (step.machine, count + (step.egress_valid as u8),
            if step.egress_valid { bit_slice_update(frames, (count as u32) * u32:136, accepted) } else { frames })
    } ((initial, u8:0, bits[272]:0));
    m.failure ++ (m.enter_pending as u1) ++ m.data.value ++ m.data.small ++ (m.data.signed as u5) ++
        m.data.denominator ++ count ++ frames
}
