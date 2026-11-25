// XC7Z030-1 maxima in ps from the routed timing_micro DSP48E1. Its signed
// multiplier captures A/B in MREG, then transfers M to PREG on the next edge.
static bool xc7RegisteredMultiply(const Arch *ctx, const CellInfo *cell)
{
    auto number = [&](const std::string &key, int fallback) {
        return int_or_default(cell->params, ctx->id(key), fallback);
    };
    if (number("MREG", -1) != 1 || number("PREG", -1) != 1 ||
        ctx->getChipName() != "xc7z030sbg485-1" || number("IS_CLK_INVERTED", 0) != 0 ||
        get_net_or_empty(cell, ctx->id("CLK")) == nullptr)
        return false;
    for (const char *reg : {"AREG", "BREG", "ACASCREG", "BCASCREG", "ADREG", "DREG", "CREG",
                            "ALUMODEREG", "OPMODEREG", "INMODEREG", "CARRYINREG", "CARRYINSELREG"})
        if (number(reg, -1) != 0)
            return false;
    auto mode = [&](const char *key) { return str_or_default(cell->params, ctx->id(key), ""); };
    if (mode("A_INPUT") != "DIRECT" || mode("B_INPUT") != "DIRECT" || mode("USE_DPORT") != "FALSE" ||
        mode("USE_MULT") != "MULTIPLY" || mode("USE_SIMD") != "ONE48" ||
        str_or_default(cell->params, ctx->id("USE_PATTERN_DETECT"), "NO_PATDET") != "NO_PATDET")
        return false;

    // The packer can implement a low control as an inverted VCC, and move
    // CARRYINSEL2's tie off the routing fabric into a site configuration bit.
    auto tied = [&](const std::string &pin, bool high) {
        const NetInfo *net = get_net_or_empty(cell, ctx->id(pin));
        if (net != nullptr)
            return net->name == ctx->id(high ? "$PACKER_VCC_NET" : "$PACKER_GND_NET");
        const std::string pins = str_or_default(cell->attrs, ctx->id(high ? "DSP_VCC_PINS" : "DSP_GND_PINS"), "");
        return (" " + pins + " ").find(" " + pin + " ") != std::string::npos;
    };
    auto control = [&](const std::string &bus, int width, int value) {
        if (number("IS_" + bus + "_INVERTED", 0) != 0)
            return false;
        for (int i = 0; i < width; ++i) {
            const std::string bit = std::to_string(i);
            bool inverted = number("IS_" + bus + "[" + bit + "]_INVERTED", 0) != 0;
            if (!tied(bus + bit, bool((value >> i) & 1) != inverted))
                return false;
        }
        return true;
    };
    return control("OPMODE", 7, 5) && control("ALUMODE", 4, 0) && control("INMODE", 5, 0) &&
           control("CARRYINSEL", 3, 0) && tied("CARRYIN", number("IS_CARRYIN_INVERTED", 0) != 0);
}

// Only the participating data, enable, reset and P pins have matched timing.
// Setup/hold are signed. The unused C/D paths differ between the two mappings.
static TimingPortClass xc7MultiplyTiming(const Arch *ctx, const CellInfo *cell, IdString port,
                                         TimingClockingInfo &info)
{
    if (!xc7RegisteredMultiply(ctx, cell))
        return TMG_IGNORE;
    info.clock_port = ctx->id("CLK");
    info.edge = RISING_EDGE;
    if (port == info.clock_port)
        return TMG_CLOCK_INPUT;
    const std::string &pin = port.str(ctx);
    const std::string base = pin.substr(0, pin.find_last_not_of("0123456789") + 1);
    if (base == "P") {
        info.clockToQ.delay = 383;
        return TMG_REGISTER_OUTPUT;
    }
    static const struct { const char *pin; int setup, hold; } checks[] = {
        {"A", 1634, -250}, {"B", 1477, -182}, {"CEM", 324, 191},
        {"CEP", 444, 4}, {"RSTM", 229, 232}, {"RSTP", 294, 10},
    };
    for (const auto &check : checks) {
        if (base != check.pin)
            continue;
        info.setup.delay = check.setup;
        info.hold.delay = check.hold;
        return TMG_REGISTER_INPUT;
    }
    return TMG_IGNORE;
}
