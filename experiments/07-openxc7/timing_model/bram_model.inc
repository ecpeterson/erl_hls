// Experimental XC7Z030-1 BRAM endpoint model. Only the measured modes below qualify.
// Values are conservative maxima over the captured Vivado 2024.2 SDFs; this
// supplies endpoint arcs, not hold closure or every internal hard-block check.
struct Xc7BramPin { const char *mode; const char *port; const char *clock; bool output; };
static const Xc7BramPin xc7_bram_pins[] = {
    {"SDP", "ADDRARDADDR", "CLKARDCLK", false},
    {"SDP", "ADDRBWRADDR", "CLKBWRCLK", false},
    {"SDP", "DIADI", "CLKBWRCLK", false},
    {"SDP", "DIBDI", "CLKBWRCLK", false},
    {"SDP", "DIPADIP", "CLKBWRCLK", false},
    {"SDP", "DIPBDIP", "CLKBWRCLK", false},
    {"SDP", "DOADO", "CLKARDCLK", true},
    {"SDP", "DOBDO", "CLKARDCLK", true},
    {"SDP", "DOPADOP", "CLKARDCLK", true},
    {"SDP", "DOPBDOP", "CLKARDCLK", true},
    {"SDP", "ENARDEN", "CLKARDCLK", false},
    {"SDP", "ENBWREN", "CLKBWRCLK", false},
    {"SDP", "REGCEAREGCE", "CLKARDCLK", false},
    {"SDP", "REGCEB", "CLKBWRCLK", false},
    {"SDP", "RSTRAMARSTRAM", "CLKARDCLK", false},
    {"SDP", "RSTRAMB", "CLKBWRCLK", false},
    {"SDP", "RSTREGARSTREG", "CLKARDCLK", false},
    {"SDP", "RSTREGB", "CLKBWRCLK", false},
    {"SDP", "WEBWE", "CLKBWRCLK", false},
    {"TDP", "ADDRARDADDR", "CLKARDCLK", false},
    {"TDP", "ADDRBWRADDR", "CLKBWRCLK", false},
    {"TDP", "DIADI", "CLKARDCLK", false},
    {"TDP", "DIBDI", "CLKBWRCLK", false},
    {"TDP", "DIPADIP", "CLKARDCLK", false},
    {"TDP", "DIPBDIP", "CLKBWRCLK", false},
    {"TDP", "DOBDO", "CLKBWRCLK", true},
    {"TDP", "ENARDEN", "CLKARDCLK", false},
    {"TDP", "ENBWREN", "CLKBWRCLK", false},
    {"TDP", "INJECTDBITERR", "CLKBWRCLK", false},
    {"TDP", "INJECTSBITERR", "CLKBWRCLK", false},
    {"TDP", "REGCEB", "CLKBWRCLK", false},
    {"TDP", "RSTRAMARSTRAM", "CLKARDCLK", false},
    {"TDP", "RSTRAMB", "CLKBWRCLK", false},
    {"TDP", "RSTREGB", "CLKBWRCLK", false},
    {"TDP", "WEA", "CLKARDCLK", false},
    {"TDP", "WEBWE", "CLKBWRCLK", false},
};

// Distinguish RAM cells before looking up their explicitly supported modes.
static bool xc7IsBram(const Arch *ctx, const CellInfo *cell)
{
    return cell->type == ctx->id("RAMB18E1_RAMB18E1") || cell->type == ctx->id("RAMB36E1_RAMB36E1");
}

// Supply one connected clock and conservative endpoint costs; unknown modes remain uncovered.
static TimingPortClass xc7BramTiming(const Arch *ctx, const CellInfo *cell, IdString port,
                                    TimingClockingInfo &info)
{
    if (ctx->getChipName() != "xc7z030sbg485-1") return TMG_IGNORE;
    const bool small = cell->type == ctx->id("RAMB18E1_RAMB18E1");
    const std::string mode = str_or_default(cell->params, ctx->id("RAM_MODE"), "");
    auto number = [&](const char *key) { return int_or_default(cell->params, ctx->id(key), -1); };
    const int ra = number("READ_WIDTH_A"), rb = number("READ_WIDTH_B");
    const int wa = number("WRITE_WIDTH_A"), wb = number("WRITE_WIDTH_B");
    const int qa = number("DOA_REG"), qb = number("DOB_REG");
    const bool sdp = mode == "SDP" && ra == (small ? 36 : 72) && rb == 0 && wa == 0 && wb == ra &&
                     qa == qb && (qa == 0 || qa == 1);
    const bool tdp = !small && mode == "TDP" && ra == 0 && rb == 36 && wa == 36 && wb == 0 &&
                     qa == 0 && (qb == 0 || qb == 1);
    if (!sdp && !tdp) return TMG_IGNORE;
    for (const char *key : {"WRITE_MODE_A", "WRITE_MODE_B"})
        if (str_or_default(cell->params, ctx->id(key), "READ_FIRST") != "READ_FIRST") return TMG_IGNORE;
    for (const auto &kv : cell->params) {
        const std::string key = kv.first.str(ctx);
        // Reset/data polarity changes are bounded by the worst rise/fall cost.
        // Inverted clocks need a distinct edge model.
        if (key.find("IS_CLK") == 0 && kv.second.as_bool()) return TMG_IGNORE;
        if (key.find("EN_ECC_") == 0 && kv.second.as_string() == "TRUE") return TMG_IGNORE;
        if (key.find("RAM_EXTENSION_") == 0 && kv.second.as_string() != "NONE") return TMG_IGNORE;
    }
    std::string base = port.str(ctx);
    while (!base.empty() && std::isdigit(base.back())) base.pop_back();
    // 36K BRAM inputs have duplicated lower/upper physical pins.
    if (!base.empty() && (base.back() == 'L' || base.back() == 'U')) base.pop_back();
    if (base == "CLKARDCLK" || base == "CLKBWRCLK") return TMG_CLOCK_INPUT;
    for (const auto &pin : xc7_bram_pins) {
        if (mode != pin.mode || base != pin.port) continue;
        IdString clock = ctx->id(pin.clock);
        if (!cell->ports.count(clock)) {
            IdString lower = ctx->id(std::string(pin.clock) + "L");
            IdString upper = ctx->id(std::string(pin.clock) + "U");
            if (!cell->ports.count(lower) || !cell->ports.count(upper) ||
                cell->ports.at(lower).net != cell->ports.at(upper).net) return TMG_IGNORE;
            clock = lower;
        }
        if (!cell->ports.at(clock).net) return TMG_IGNORE;
        info.clock_port = clock;
        info.edge = RISING_EDGE;
        info.setup = ctx->getDelayFromNS(sdp ? 0.479 : 0.625);
        info.hold = ctx->getDelayFromNS(0.384);
        info.clockToQ = ctx->getDelayFromNS((sdp ? qa : qb) ? 0.748 : 2.080);
        return pin.output ? TMG_REGISTER_OUTPUT : TMG_REGISTER_INPUT;
    }
    return TMG_IGNORE;
}
