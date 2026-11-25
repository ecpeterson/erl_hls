// Only the positive-edge, fixed-tap 6LUT configuration has a matched XC7Z030-1
// clock-to-Q and input-check reference. The packer puts address bits on A2 up.
static bool xc7FixedSrl(const Arch *ctx, const CellInfo *cell)
{
    if (cell->type != id_SLICE_LUTX || !cell->attrs.count(ctx->id("X_LUT_AS_SRL")) ||
        ctx->getChipName() != "xc7z030sbg485-1" || int_or_default(cell->params, ctx->id("IS_CLK_INVERTED"), 0) ||
        get_net_or_empty(cell, id_CLK) == nullptr || get_net_or_empty(cell, id_O6) == nullptr ||
        str_or_default(cell->attrs, ctx->id("X_ORIG_PORT_O6"), "") != "Q")
        return false;
    const std::string kind = str_or_default(cell->attrs, ctx->id("X_ORIG_TYPE"), "");
    if (kind != "SRL16E" && kind != "SRLC32E")
        return false;
    const int last = kind == "SRL16E" ? 5 : 6;
    for (int i = 2; i <= last; ++i) {
        const NetInfo *net = get_net_or_empty(cell, ctx->id("A" + std::to_string(i)));
        if (net == nullptr || (net->name != ctx->id("$PACKER_VCC_NET") && net->name != ctx->id("$PACKER_GND_NET")))
            return false;
    }
    return true;
}

// Slowest values in the matched four-Phi Vivado SDF. A fixed address does
// not contribute a within-clock data arc. Setup and hold are signed ps.
static TimingPortClass xc7FixedSrlTiming(const Arch *ctx, const CellInfo *cell, IdString port, TimingClockingInfo &info)
{
    info.clock_port = id_CLK;
    info.edge = RISING_EDGE;
    if (port == id_CLK)
        return TMG_CLOCK_INPUT;
    if (port == id_O6) {
        info.clockToQ.delay = str_or_default(cell->attrs, ctx->id("X_ORIG_TYPE"), "") == "SRL16E" ? 1102 : 1109;
        return TMG_REGISTER_OUTPUT;
    }
    const std::string origin = str_or_default(cell->attrs, ctx->id("X_ORIG_PORT_" + port.str(ctx)), "");
    if (origin == "D" || origin == "CE") {
        info.setup.delay = origin == "D" ? 106 : 410;
        info.hold.delay = origin == "D" ? 87 : -17;
        return TMG_REGISTER_INPUT;
    }
    return TMG_IGNORE;
}
