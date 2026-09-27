// Dependency filter for fully combinational DSP48E1 A/B cascade outputs.
// UG479: ACOUT/BCOUT forward the selected A/ACIN or B/BCIN bit unchanged.
// Other outputs retain the caller's existing conservative timing model.
inline bool xc7DspCascadeArcPossible(const std::string &from, const std::string &to,
                                    const std::string &a_input, const std::string &b_input)
{
    // Keep both physical input choices for an unrecognized parameter value.
    auto selected = [&](const std::string &direct, const std::string &cascade,
                        const std::string &mode, size_t prefix_size) {
        const std::string index = to.substr(prefix_size);
        const bool d = from == direct + index;
        const bool c = from == cascade + index;
        return mode == "DIRECT" ? d : mode == "CASCADE" ? c : d || c;
    };
    if (to.compare(0, 5, "ACOUT") == 0)
        return selected("A", "ACIN", a_input, 5);
    if (to.compare(0, 5, "BCOUT") == 0)
        return selected("B", "BCIN", b_input, 5);
    return true;
}
